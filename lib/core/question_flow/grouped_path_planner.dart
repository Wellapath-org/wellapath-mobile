/// Grouped **initial-only** path planner for Question Flow 1.1.
///
/// Plans what a consumer would actually present: groups merge into one
/// question each, then ordering applies, then the limit.
///
/// ## Still initial-only, still IM-003-free
///
/// Like [planInitialPath], this takes one immutable state and returns one
/// plan. There is no method that accepts an answer, no mutable state, and no
/// re-evaluation loop — **IM-003 is absent by construction, not by
/// discipline.** A question's `invalidates_on_change` is loaded and reported
/// and never acted on.
///
/// ## The phase order is the contract
///
///  1. determine triggered sources
///  2. preserve non-groupable questions
///  3. group only explicitly groupable triggered questions
///  4. representative = lowest `source_order_index`
///  5. union options from triggered sources only
///  6. de-duplicate by answer-option id
///  7. deterministic option order
///  8. retain full source provenance
///  9. combine grouped and ungrouped
/// 10. deterministic question ordering
/// 11. total limit of 5, red-flag questions never dropped
///
/// Truncating before grouping is what made candidate 1.0 drop questions the
/// live engine asks on 1,192 paths, so step 11 comes last and is written that
/// way on purpose.
///
/// **Not wired to the assessment.** Nothing here drives UI, writes a token,
/// invokes scoring or touches the network.
library;

import 'package:flutter/foundation.dart';

import 'condition_evaluator.dart';
import 'question_flow_models.dart';
import 'question_grouping_models.dart';
import 'question_ordering.dart';

/// Raised when a plan would violate an invariant the contract guarantees.
///
/// Thrown rather than returned: these are not "this artifact is unusual"
/// conditions, they are "this plan would present something the contract says
/// is impossible". A caller cannot sensibly continue, and a silently degraded
/// plan is how a danger-sign question goes missing.
@immutable
class GroupedPlanViolation implements Exception {
  const GroupedPlanViolation(this.message);

  final String message;

  @override
  String toString() => 'GroupedPlanViolation: $message';
}

/// One question as it would be presented.
@immutable
class PresentedQuestion {
  const PresentedQuestion({
    required this.question,
    required this.questionText,
    required this.optionIds,
    required this.optionLabels,
    required this.producedTokens,
    required this.contributingSourceIds,
    required this.representativeSourceId,
    required this.groupKey,
    required this.wasTruncated,
  });

  final FlowQuestion question;

  /// The wording to render: the representative source's text for a grouped
  /// question, the question's own for an ungrouped one. Never a concatenation.
  final String questionText;

  final List<String> optionIds;
  final List<String> optionLabels;

  /// Tokens any presented answer could produce. Reported, never written.
  final List<String> producedTokens;

  /// Full provenance: every source that contributed to this presentation.
  /// Empty for an ungrouped question, which is its own provenance.
  final List<String> contributingSourceIds;

  final String? representativeSourceId;
  final String? groupKey;
  final bool wasTruncated;

  bool get isRedFlagQuestion => question.isRedFlagQuestion;
  String get clinicalRole => question.clinicalRole;
  String? get redFlagToken => question.clinicalRole == 'red_flag_clarifier'
      ? question.tieBreakKey
      : null;
}

@immutable
class GroupedPathPlan {
  const GroupedPathPlan({
    required this.presented,
    required this.truncated,
    required this.limit,
  });

  final List<PresentedQuestion> presented;
  final List<PresentedQuestion> truncated;
  final int limit;

  List<String> get presentedIds =>
      presented.map((PresentedQuestion p) => p.question.id.value).toList();

  List<String> get truncatedIds =>
      truncated.map((PresentedQuestion p) => p.question.id.value).toList();

  int get redFlagCount =>
      presented.where((PresentedQuestion p) => p.isRedFlagQuestion).length;

  /// Red-flag questions dropped by truncation. Structurally always empty —
  /// reported so a test asserts the outcome rather than trusting the code.
  List<String> get droppedRedFlagIds => truncated
      .where((PresentedQuestion p) => p.isRedFlagQuestion)
      .map((PresentedQuestion p) => p.question.id.value)
      .toList();
}

/// Plans the questions a 1.1 consumer would present for [state].
///
/// [state] carries a token **Set**. That is deliberate: the defect this
/// contract corrects is a dependence on selection order, and a set makes
/// reintroducing it impossible rather than merely unlikely.
GroupedPathPlan planGroupedInitialPath(
  QuestionFlow flow,
  FlowEvaluationState state,
) {
  final List<PresentedQuestion> eligible = <PresentedQuestion>[];

  for (final FlowQuestion question in flow.questions) {
    // IM-006: demographic, picker and body-area nodes are represented in the
    // graph but never planned as follow-ups — the live app owns those screens.
    if (question.isDemographic ||
        question.clinicalRole == 'symptom_picker' ||
        question.clinicalRole == 'body_area') {
      continue;
    }

    if (!evaluateFlowCondition(question.triggerCondition, state)) {
      continue;
    }

    final QuestionGrouping? grouping = question.grouping;

    // Step 2: non-groupable questions are preserved exactly as authored.
    if (grouping == null) {
      eligible.add(
        PresentedQuestion(
          question: question,
          questionText: question.sourceText,
          optionIds: <String>[
            for (final AnswerOption o in question.answerOptions) o.id.value,
          ],
          optionLabels: <String>[
            for (final AnswerOption o in question.answerOptions) o.label,
          ],
          producedTokens: _tokensOf(question.answerOptions),
          contributingSourceIds: const <String>[],
          representativeSourceId: null,
          groupKey: null,
          wasTruncated: false,
        ),
      );
      continue;
    }

    // A grouped clarifier would have failed to load; asserted here too,
    // because this is the invariant whose breach deletes a danger sign.
    if (kNonGroupableRoles.contains(question.clinicalRole)) {
      throw GroupedPlanViolation(
        'Question "${question.id.value}" has non-groupable role '
        '"${question.clinicalRole}" and carries a grouping block.',
      );
    }

    // Step 1: which sources actually triggered.
    final List<QuestionGroupSource> triggered = <QuestionGroupSource>[
      for (final QuestionGroupSource s in grouping.sources)
        if (evaluateFlowCondition(s.triggerCondition, state)) s,
    ];
    if (triggered.isEmpty) {
      // The question's own trigger held but no source did. That means the
      // artifact's question trigger is wider than its sources, which load-time
      // containment should have refused.
      throw GroupedPlanViolation(
        'Question "${question.id.value}" triggered but no grouping source '
        'did. The question trigger is wider than its sources.',
      );
    }

    // Steps 3-4: one question per group, representative by lowest index.
    final List<QuestionGroupSource> ordered =
        List<QuestionGroupSource>.of(triggered)..sort(
          (QuestionGroupSource a, QuestionGroupSource b) =>
              a.sourceOrderIndex.compareTo(b.sourceOrderIndex),
        );
    final QuestionGroupSource representative = ordered.first;

    // Steps 5-7: union the TRIGGERED sources' options only, de-duplicated by
    // id, in (source_order_index, position within source).
    final List<String> optionIds = <String>[];
    final List<String> optionLabels = <String>[];
    final List<AnswerOption> presentedOptions = <AnswerOption>[];
    if (grouping.optionUnionRule == OptionUnionRule.staticOptions) {
      for (final AnswerOption o in question.answerOptions) {
        optionIds.add(o.id.value);
        optionLabels.add(o.label);
        presentedOptions.add(o);
      }
    } else {
      final Set<String> seen = <String>{};
      for (final QuestionGroupSource source in ordered) {
        for (final AnswerOption o in source.answerOptions) {
          if (seen.add(o.id.value)) {
            optionIds.add(o.id.value);
            optionLabels.add(o.label);
            presentedOptions.add(o);
          }
        }
      }
    }

    eligible.add(
      PresentedQuestion(
        question: question,
        questionText: representative.sourceText,
        optionIds: List<String>.unmodifiable(optionIds),
        optionLabels: List<String>.unmodifiable(optionLabels),
        producedTokens: _tokensOf(presentedOptions),
        // Step 8: complete provenance, in the same deterministic order.
        contributingSourceIds: List<String>.unmodifiable(<String>[
          for (final QuestionGroupSource s in ordered) s.sourceId,
        ]),
        representativeSourceId: representative.sourceId,
        groupKey: grouping.groupKey,
        wasTruncated: false,
      ),
    );
  }

  // Step 9 + 10: combine, then order deterministically by
  // (priority, tie_break_key, question_id).
  final Map<String, PresentedQuestion> byId = <String, PresentedQuestion>{
    for (final PresentedQuestion p in eligible) p.question.id.value: p,
  };
  final List<FlowQuestion> orderedQuestions = orderFlowQuestions(
    eligible.map((PresentedQuestion p) => p.question),
  );
  final List<PresentedQuestion> combined = <PresentedQuestion>[
    for (final FlowQuestion q in orderedQuestions) byId[q.id.value]!,
  ];

  _assertOneQuestionPerGroup(combined);

  // Step 11: the limit applies to the TOTAL follow-up count, and a red-flag
  // question is never the one dropped. The budget for ordinary questions is
  // what the limit leaves after them; if red-flag questions alone reach the
  // limit, the limit yields.
  final int limit = flow.pathControls.maxFollowupQuestions;
  final int redFlagCount = combined
      .where((PresentedQuestion p) => p.isRedFlagQuestion)
      .length;
  final int ordinaryBudget = limit - redFlagCount;

  final List<PresentedQuestion> presented = <PresentedQuestion>[];
  final List<PresentedQuestion> truncated = <PresentedQuestion>[];
  int ordinaryUsed = 0;
  for (final PresentedQuestion p in combined) {
    if (p.isRedFlagQuestion) {
      presented.add(p);
      continue;
    }
    if (ordinaryUsed < ordinaryBudget) {
      ordinaryUsed += 1;
      presented.add(p);
    } else {
      truncated.add(
        PresentedQuestion(
          question: p.question,
          questionText: p.questionText,
          optionIds: p.optionIds,
          optionLabels: p.optionLabels,
          producedTokens: p.producedTokens,
          contributingSourceIds: p.contributingSourceIds,
          representativeSourceId: p.representativeSourceId,
          groupKey: p.groupKey,
          wasTruncated: true,
        ),
      );
    }
  }

  return GroupedPathPlan(
    presented: List<PresentedQuestion>.unmodifiable(presented),
    truncated: List<PresentedQuestion>.unmodifiable(truncated),
    limit: limit,
  );
}

/// One presented question per group key, and per groupable role.
///
/// Checked on every plan rather than only at load: the load-time backstop can
/// only probe the shapes it knows about, whereas this sees the actual result.
void _assertOneQuestionPerGroup(List<PresentedQuestion> questions) {
  final Map<String, String> byGroupKey = <String, String>{};
  final Map<String, String> byRole = <String, String>{};
  for (final PresentedQuestion p in questions) {
    final String? key = p.groupKey;
    if (key != null) {
      final String? owner = byGroupKey[key];
      if (owner != null) {
        throw GroupedPlanViolation(
          'Group "$key" would present two questions: "$owner" and '
          '"${p.question.id.value}".',
        );
      }
      byGroupKey[key] = p.question.id.value;
    }
    if (!kGroupableRoles.contains(p.clinicalRole)) continue;
    final String? roleOwner = byRole[p.clinicalRole];
    if (roleOwner != null) {
      throw GroupedPlanViolation(
        'Role "${p.clinicalRole}" would present two questions: "$roleOwner" '
        'and "${p.question.id.value}". The live engine asks one.',
      );
    }
    byRole[p.clinicalRole] = p.question.id.value;
  }
}

List<String> _tokensOf(List<AnswerOption> options) {
  final Set<String> tokens = <String>{};
  for (final AnswerOption o in options) {
    tokens.addAll(o.producesTokens);
  }
  final List<String> sorted = tokens.toList()..sort();
  return List<String>.unmodifiable(sorted);
}
