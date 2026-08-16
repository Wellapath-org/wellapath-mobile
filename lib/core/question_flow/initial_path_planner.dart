/// Bounded **initial-only** path planner.
///
/// Plans the questions eligible from an immutable initial context, orders them
/// deterministically, and truncates to the ordinary limit with red-flag
/// questions exempt.
///
/// ## What makes this initial-only, and why that matters
///
/// The planner takes one [FlowEvaluationState] and returns one plan. It has no
/// method that accepts an answer, no reference to a mutable state object, and
/// no loop that re-evaluates eligibility. **That is IM-003 being absent by
/// construction, not by discipline** — there is nothing here to call after an
/// answer, so nothing can add, remove or invalidate a question because of one.
///
/// A question's `invalidates_on_change` is loaded and reported, but never
/// acted on: acting on it is dynamic invalidation, which is deferred because
/// it can change scoring inputs.
///
/// The planner does not drive UI, create scoring tokens, invoke scoring, or
/// touch the network.
library;

import 'package:flutter/foundation.dart';

import 'condition_evaluator.dart';
import 'question_flow_models.dart';
import 'question_ordering.dart';

/// Why a question was included or left out. Exposed for tests and evidence.
enum PlanDecision {
  /// Eligible, ordered and within the limit.
  selected,

  /// Trigger condition evaluated false.
  notTriggered,

  /// Eligible but dropped by the ordinary path limit.
  truncated,

  /// Eligible and kept despite the limit, because it can affect a red flag.
  redFlagExempt,

  /// A demographic node. Represented in the graph (IM-006) but not planned as
  /// a follow-up; the live app owns these screens and is not replaced.
  demographicNotPlanned,
}

@immutable
class PlannedQuestion {
  const PlannedQuestion({
    required this.question,
    required this.decision,
    required this.orderKey,
  });

  final FlowQuestion question;
  final PlanDecision decision;
  final String orderKey;

  bool get isPresented =>
      decision == PlanDecision.selected ||
      decision == PlanDecision.redFlagExempt;
}

@immutable
class InitialPathPlan {
  const InitialPathPlan({
    required this.presented,
    required this.truncated,
    required this.notTriggered,
    required this.demographic,
    required this.limit,
  });

  /// Questions to ask, in deterministic order. Red-flag questions first, since
  /// they carry priority 0 in the candidate.
  final List<PlannedQuestion> presented;

  /// Eligible but dropped by the ordinary limit.
  final List<PlannedQuestion> truncated;

  final List<PlannedQuestion> notTriggered;
  final List<PlannedQuestion> demographic;

  final int limit;

  /// True when no question is to be asked.
  bool get isTerminal => presented.isEmpty;

  List<String> get presentedIds =>
      presented.map((PlannedQuestion p) => p.question.id.value).toList();

  List<String> get truncatedIds =>
      truncated.map((PlannedQuestion p) => p.question.id.value).toList();

  /// Ordinary (non-red-flag) questions presented. This is what the limit
  /// applies to.
  int get ordinaryCount => presented
      .where((PlannedQuestion p) => !p.question.isRedFlagQuestion)
      .length;

  int get redFlagCount => presented
      .where((PlannedQuestion p) => p.question.isRedFlagQuestion)
      .length;
}

/// Plans the initially-eligible follow-up questions for [state].
///
/// There is deliberately no counterpart that takes an answer. Re-planning
/// after an answer is IM-003 and is not implemented.
InitialPathPlan planInitialPath(QuestionFlow flow, FlowEvaluationState state) {
  final List<PlannedQuestion> demographic = <PlannedQuestion>[];
  final List<PlannedQuestion> notTriggered = <PlannedQuestion>[];
  final List<FlowQuestion> eligible = <FlowQuestion>[];

  for (final FlowQuestion q in flow.questions) {
    if (q.isDemographic ||
        q.clinicalRole == 'symptom_picker' ||
        q.clinicalRole == 'body_area') {
      // IM-006: represented as graph nodes, not authorised to replace the
      // hardcoded screens, so they are never planned as follow-ups.
      demographic.add(
        PlannedQuestion(
          question: q,
          decision: PlanDecision.demographicNotPlanned,
          orderKey: flowOrderKey(q),
        ),
      );
      continue;
    }

    if (evaluateFlowCondition(q.triggerCondition, state)) {
      eligible.add(q);
    } else {
      notTriggered.add(
        PlannedQuestion(
          question: q,
          decision: PlanDecision.notTriggered,
          orderKey: flowOrderKey(q),
        ),
      );
    }
  }

  final List<FlowQuestion> ordered = orderFlowQuestions(eligible);

  // Truncation: drop the lowest-priority ordinary questions until the ordinary
  // count fits. A red-flag question is never dropped; if red-flag questions
  // alone exceed the limit, the limit yields and all of them are asked.
  final int limit = flow.pathControls.maxFollowupQuestions;
  final List<PlannedQuestion> presented = <PlannedQuestion>[];
  final List<PlannedQuestion> truncated = <PlannedQuestion>[];

  // The limit applies to the TOTAL follow-up count, and red-flag questions are
  // never the ones dropped. So the budget left for ordinary questions is the
  // limit minus however many red-flag questions are eligible — and when
  // red-flag questions alone reach or exceed the limit, the limit yields and
  // all of them are still asked.
  final int redFlagCount = ordered
      .where((FlowQuestion q) => q.isRedFlagQuestion)
      .length;
  final int ordinaryBudget = limit - redFlagCount;

  int ordinaryUsed = 0;
  for (final FlowQuestion q in ordered) {
    if (q.isRedFlagQuestion) {
      presented.add(
        PlannedQuestion(
          question: q,
          decision: PlanDecision.redFlagExempt,
          orderKey: flowOrderKey(q),
        ),
      );
      continue;
    }
    if (ordinaryUsed < ordinaryBudget) {
      ordinaryUsed += 1;
      presented.add(
        PlannedQuestion(
          question: q,
          decision: PlanDecision.selected,
          orderKey: flowOrderKey(q),
        ),
      );
    } else {
      truncated.add(
        PlannedQuestion(
          question: q,
          decision: PlanDecision.truncated,
          orderKey: flowOrderKey(q),
        ),
      );
    }
  }

  return InitialPathPlan(
    presented: List<PlannedQuestion>.unmodifiable(presented),
    truncated: List<PlannedQuestion>.unmodifiable(truncated),
    notTriggered: List<PlannedQuestion>.unmodifiable(notTriggered),
    demographic: List<PlannedQuestion>.unmodifiable(demographic),
    limit: limit,
  );
}
