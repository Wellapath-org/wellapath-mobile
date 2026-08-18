/// Immutable domain model for a Question Flow 1.0 candidate.
///
/// **This is an engineering consumer. It is not wired to the assessment.**
/// Nothing in `lib/core/question_flow/` is imported by any screen, by
/// `AssessmentController` or by `QuestionEngine`; the live flow continues to
/// use its compiled Dart questions and is untouched by this package.
///
/// Contract: `wellapath-knowledge-base` @ aa7a2f13,
/// `docs/W3_QUESTION_FLOW_CONTRACT.md`, candidate
/// `candidate/question_flow.ng.v1.0.json`
/// (sha256 c403648f…37024998), `candidate_unapproved`, `may_publish: false`.
library;

import 'package:flutter/foundation.dart';

import 'question_grouping_models.dart';

/// A question id that is known to exist in a loaded flow.
///
/// Private constructor, so no raw string becomes a question identity without
/// going through a flow that contains it — the same discipline the Vocabulary
/// 2.0 consumer uses for canonical tokens.
@immutable
class QuestionId {
  const QuestionId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) => other is QuestionId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// An answer-option id known to exist on its question.
@immutable
class AnswerOptionId {
  const AnswerOptionId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is AnswerOptionId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Mints ids for the loader, which has already proved membership. Kept
/// library-private in spirit: the only call sites are in this library's
/// loader, and no public API accepts a bare string as an identity.
QuestionId internalMintQuestionId(String value) => QuestionId._(value);
AnswerOptionId internalMintAnswerOptionId(String value) =>
    AnswerOptionId._(value);

/// The 13 operators the contract defines. Anything else is a typed failure —
/// never "false".
enum ConditionOperator {
  all,
  any,
  not,
  equals,
  oneOf,
  tokenPresent,
  tokenAbsent,
  priorAnswerEquals,
  ageRange,
  sex,
  pregnancy,
  always,
  never,
}

const Map<String, ConditionOperator> kConditionOperators =
    <String, ConditionOperator>{
      'all': ConditionOperator.all,
      'any': ConditionOperator.any,
      'not': ConditionOperator.not,
      'equals': ConditionOperator.equals,
      'one_of': ConditionOperator.oneOf,
      'token_present': ConditionOperator.tokenPresent,
      'token_absent': ConditionOperator.tokenAbsent,
      'prior_answer_equals': ConditionOperator.priorAnswerEquals,
      'age_range': ConditionOperator.ageRange,
      'sex': ConditionOperator.sex,
      'pregnancy': ConditionOperator.pregnancy,
      'always': ConditionOperator.always,
      'never': ConditionOperator.never,
    };

/// The four fields a condition may read. Anything else is a typed failure.
const Set<String> kConditionFields = <String>{
  'age_token',
  'assessment_phase',
  'body_area',
  'sex',
};

/// A parsed condition node. Structure is validated at load; evaluation cannot
/// encounter an unknown operator because one would not have loaded.
@immutable
class FlowCondition {
  const FlowCondition({
    required this.operator,
    this.children = const <FlowCondition>[],
    this.field,
    this.value,
    this.values = const <Object?>[],
    this.questionId,
    this.token,
  });

  final ConditionOperator operator;
  final List<FlowCondition> children;
  final String? field;
  final Object? value;
  final List<Object?> values;
  final String? questionId;
  final String? token;
}

@immutable
class AnswerOption {
  const AnswerOption({
    required this.id,
    required this.label,
    required this.producesTokens,
    required this.isSkipSentinel,
    required this.value,
  });

  final AnswerOptionId id;
  final String label;

  /// Canonical token ids this answer contributes. Read-only here; nothing in
  /// this package writes a token into clinical state.
  final List<String> producesTokens;

  final bool isSkipSentinel;
  final Object? value;
}

@immutable
class RedFlagEvaluation {
  const RedFlagEvaluation({
    required this.canAffectRedFlag,
    required this.evaluateAfterAnswer,
    required this.blocksNextQuestion,
  });

  final bool canAffectRedFlag;
  final bool evaluateAfterAnswer;
  final bool blocksNextQuestion;
}

@immutable
class QuestionEffects {
  const QuestionEffects({
    required this.producesTokens,
    required this.affectsScoring,
    required this.affectsRedFlags,
  });

  final List<String> producesTokens;
  final bool affectsScoring;
  final bool affectsRedFlags;
}

@immutable
class FlowQuestion {
  const FlowQuestion({
    required this.id,
    required this.questionType,
    required this.clinicalRole,
    required this.answerValueType,
    required this.required,
    required this.skippable,
    required this.answerOptions,
    required this.triggerCondition,
    required this.priority,
    required this.tieBreakKey,
    required this.pathLengthContribution,
    required this.invalidatesOnChange,
    required this.effects,
    required this.redFlagEvaluation,
    required this.terminal,
    required this.sourceText,
    required this.contentApproved,
    this.grouping,
  });

  final QuestionId id;
  final String questionType;
  final String clinicalRole;
  final String answerValueType;
  final bool required;
  final bool skippable;
  final List<AnswerOption> answerOptions;
  final FlowCondition triggerCondition;

  final int priority;
  final String tieBreakKey;
  final int pathLengthContribution;

  /// Declared for IM-004/IM-003 completeness. **Read but never acted on** —
  /// acting on it would be dynamic invalidation, which is deferred.
  final List<String> invalidatesOnChange;

  final QuestionEffects effects;
  final RedFlagEvaluation redFlagEvaluation;
  final bool terminal;

  /// Existing shipped wording, preserved byte-for-byte. `contentApproved` is
  /// false throughout the candidate.
  final String sourceText;
  final bool contentApproved;

  /// Present only on questions that merge (schema 1.1). Absent means this
  /// question is always presented alone — the correct reading of every 1.0
  /// question, which is why it is nullable rather than defaulted.
  final QuestionGrouping? grouping;

  bool get isDemographic => clinicalRole == 'demographic';
  bool get isRedFlagQuestion => redFlagEvaluation.canAffectRedFlag;

  /// True when this question merges several baseline sources.
  ///
  /// Deliberately keyed on the grouping block's presence, never on the
  /// clinical role or the tie-break key: inferring grouping from either would
  /// merge questions the artifact never declared groupable.
  bool get isGrouped => grouping != null;
}

/// Path controls as declared by the candidate.
@immutable
class PathControls {
  const PathControls({
    required this.maxQuestionsPerAssessment,
    required this.maxFollowupQuestions,
    required this.redFlagQuestionsExemptFromTruncation,
    required this.truncationAllowed,
  });

  final int maxQuestionsPerAssessment;
  final int maxFollowupQuestions;
  final bool redFlagQuestionsExemptFromTruncation;
  final bool truncationAllowed;
}

@immutable
class FlowMetadata {
  const FlowMetadata({
    required this.artifactId,
    required this.version,
    required this.schemaVersion,
    required this.releaseStatus,
    required this.mayPublish,
    required this.clinicalReviewStatus,
    required this.impedanceMismatchIds,
    required this.vocabulary20Used,
    this.groupingSemantics,
  });

  final String artifactId;
  final String version;
  final String schemaVersion;
  final String releaseStatus;
  final bool mayPublish;
  final String clinicalReviewStatus;
  final List<String> impedanceMismatchIds;

  /// The candidate's own assertion that Vocabulary 2.0 plays no part in
  /// question eligibility. The loader refuses a candidate that claims
  /// otherwise.
  final bool vocabulary20Used;

  /// Declared grouping semantics. Null for a 1.0 artifact, which does not
  /// group; required for 1.1, enforced at load.
  final QuestionGroupingSemantics? groupingSemantics;

  bool get isCandidateUnapproved => releaseStatus == 'candidate_unapproved';
  bool get claimsPublishable => mayPublish;

  /// True when this artifact declares grouping. A 1.0 artifact is never
  /// implicitly grouped, whatever its questions look like.
  bool get groupsQuestions => groupingSemantics?.enabled ?? false;
}

/// A fully validated, immutable question flow.
@immutable
class QuestionFlow {
  QuestionFlow({
    required this.metadata,
    required this.pathControls,
    required this.questions,
    required this.conditionLanguageVersion,
  }) : _byId = <String, FlowQuestion>{
         for (final FlowQuestion q in questions) q.id.value: q,
       };

  final FlowMetadata metadata;
  final PathControls pathControls;
  final List<FlowQuestion> questions;
  final String conditionLanguageVersion;

  final Map<String, FlowQuestion> _byId;

  Set<String> get questionIds => _byId.keys.toSet();

  FlowQuestion? question(String id) => _byId[id];

  /// The only way to obtain a [QuestionId] from a string.
  QuestionId? questionId(String candidate) =>
      _byId.containsKey(candidate) ? internalMintQuestionId(candidate) : null;
}
