/// Immutable domain model for Question Flow **1.1** grouping.
///
/// **This is an engineering consumer. It is not wired to the assessment.**
/// Nothing in `lib/core/question_flow/` is imported by any screen, by
/// `AssessmentController` or by `QuestionEngine`; the live flow continues to
/// use its compiled Dart questions and is untouched by this package.
///
/// Contract: `wellapath-knowledge-base` @ cffbe8a6,
/// `docs/W3_QUESTION_GROUPING_CONTRACT.md`, candidate
/// `candidate/question_flow.ng.v1.1.json`
/// (sha256 3ea534b0…888c02b), `candidate_unapproved`, `may_publish: false`.
///
/// ## Why this exists
///
/// The live `QuestionEngine` asks **one** severity question, **one** duration
/// question and **one** additional-symptoms question, however many symptoms
/// were selected. Candidate 1.0 modelled one question per token per role, and
/// therefore planned a different question SET on 1,930 of 2,325 paths. 1.1
/// models the de-duplication the engine actually performs.
///
/// ## Four rules this model exists to make unbreakable
///
/// 1. A group presents **exactly one** question.
/// 2. A red-flag clarifier is **never** grouped — each carries its own
///    red-flag token, so merging two deletes a danger-sign question.
/// 3. Grouping happens **before** truncation.
/// 4. [QuestionGrouping.groupKey] groups; `tieBreakKey` orders. Neither ever
///    does the other's job.
library;

import 'package:flutter/foundation.dart';

import 'question_flow_models.dart';

/// How a group turns several sources into one presented question.
enum QuestionMergeStrategy {
  /// Exactly one question: wording from the representative, options from the
  /// option-union rule.
  singleRepresentative,
}

const Map<String, QuestionMergeStrategy> kQuestionMergeStrategies =
    <String, QuestionMergeStrategy>{
      'single_representative': QuestionMergeStrategy.singleRepresentative,
    };

/// Which triggered source supplies the wording.
enum RepresentativeSelection {
  /// The triggered source with the smallest `source_order_index`.
  ///
  /// The index is assigned from the sorted canonical token id, so it is a
  /// property of the artifact and never of a run, a map iteration or the order
  /// the user tapped. This is the declared replacement for the live engine's
  /// first-tapped-wins.
  lowestSourceOrderIndex,
}

const Map<String, RepresentativeSelection> kRepresentativeSelections =
    <String, RepresentativeSelection>{
      'lowest_source_order_index':
          RepresentativeSelection.lowestSourceOrderIndex,
    };

/// Which options the merged question presents.
enum OptionUnionRule {
  /// The question's own answer options, unchanged, whichever sources fired.
  /// Used where every source offers identical answers (severity, duration).
  staticOptions,

  /// The union of the answer options of the **triggered** sources only,
  /// de-duplicated by answer-option id, ordered by
  /// (`source_order_index`, position within that source).
  ///
  /// "Triggered only" is the part that is easy to get wrong: presenting the
  /// full union would offer the user symptoms no selected token contributed.
  unionOfTriggeredSources,
}

const Map<String, OptionUnionRule> kOptionUnionRules =
    <String, OptionUnionRule>{
      'static': OptionUnionRule.staticOptions,
      'union_of_triggered_sources': OptionUnionRule.unionOfTriggeredSources,
    };

/// The only declared option ordering. Stated so two consumers cannot present
/// the same option set in a different order.
const String kSourceOrderThenDeclaredOrder = 'source_order_then_declared_order';

/// Roles that may carry a grouping block.
const Set<String> kGroupableRoles = <String>{
  'severity',
  'duration',
  'additional_symptoms',
};

/// Roles that must never be grouped, whatever an artifact declares.
const Set<String> kNonGroupableRoles = <String>{'red_flag_clarifier'};

/// The only phase in which grouping may occur.
const String kGroupingPhaseBeforeTruncation = 'before_truncation';

/// What happens when triggered sources disagree on a presented property.
@immutable
class GroupConflictResolution {
  const GroupConflictResolution({
    required this.onTextConflict,
    required this.onOptionConflict,
    required this.onValueTypeConflict,
  });

  /// `representative_wins` — the baseline shows the first-visited wording and
  /// never the others.
  final String onTextConflict;

  /// `union_preserving_all_sources`, or `reject` under the static rule.
  final String onOptionConflict;

  /// Always `reject`. Merging two answer shapes changes what an answer
  /// *means*, which no grouping rule is permitted to do.
  final String onValueTypeConflict;
}

/// One baseline authoring site that can feed a merged question.
///
/// In the live engine these are the per-token entries of
/// `kFollowupQuestionMap`. The engine visits them in user-selection order and
/// keeps the first; here they are declared explicitly so selection is resolved
/// by a stated rule instead of by tap order.
@immutable
class QuestionGroupSource {
  const QuestionGroupSource({
    required this.sourceId,
    required this.sourceToken,
    required this.sourceOrderIndex,
    required this.triggerCondition,
    required this.sourceText,
    required this.provenance,
    required this.answerOptions,
  });

  /// Unique within a grouping block.
  final String sourceId;

  /// The canonical token whose selection makes this source contribute.
  final String sourceToken;

  /// Total order over the group's sources. Unique within a grouping block.
  final int sourceOrderIndex;

  /// Must imply the owning question's trigger — enforced at load.
  final FlowCondition triggerCondition;

  /// Verbatim baseline wording. Rendered **only** if this source is the
  /// representative, never concatenated with another source's text.
  final String sourceText;

  /// Where this wording lives in the live Dart. Never synthesised: a source
  /// without provenance is a load failure, because an unattributable question
  /// cannot be reviewed.
  final String provenance;

  /// Options this source contributes under
  /// [OptionUnionRule.unionOfTriggeredSources]. Empty under the static rule.
  final List<AnswerOption> answerOptions;
}

/// Declares that several baseline sites collapse into ONE presented question.
///
/// Absent from a question means that question never merges — the correct
/// reading of every question schema 1.0 could express.
@immutable
class QuestionGrouping {
  const QuestionGrouping({
    required this.groupKey,
    required this.mergeStrategy,
    required this.representativeSelection,
    required this.optionUnionRule,
    required this.optionOrder,
    required this.conflictResolution,
    required this.sources,
  });

  /// Identity of the merged question. At most one question may be presented
  /// per group key on any path.
  ///
  /// Deliberately **not** `tieBreakKey`. Two questions sharing a tie-break key
  /// is an unresolved order tie, never an implied merge.
  final String groupKey;

  final QuestionMergeStrategy mergeStrategy;
  final RepresentativeSelection representativeSelection;
  final OptionUnionRule optionUnionRule;
  final String? optionOrder;
  final GroupConflictResolution? conflictResolution;

  final List<QuestionGroupSource> sources;
}

/// `_metadata.grouping_semantics`.
///
/// A consumer that cannot honour this must **refuse** the artifact. Ignoring
/// it silently changes which questions get asked.
@immutable
class QuestionGroupingSemantics {
  const QuestionGroupingSemantics({
    required this.enabled,
    required this.groupableRoles,
    required this.nonGroupableRoles,
    required this.groupingPhase,
    required this.oneQuestionPerGroupKey,
  });

  final bool enabled;
  final List<String> groupableRoles;

  /// Always contains `red_flag_clarifier`. If it does not, the artifact is
  /// refused: the one declaration standing between a merge rule and a deleted
  /// danger-sign question has gone missing.
  final List<String> nonGroupableRoles;

  /// Always [kGroupingPhaseBeforeTruncation].
  final String groupingPhase;

  /// Always true.
  final bool oneQuestionPerGroupKey;
}
