/// Strict, offline loader for a Question Flow 1.0 candidate.
///
/// Reads local bytes only. No URL, no client, no import of the networking
/// layer — a flow cannot be fetched, so a question can never be selected as a
/// result of a network call.
///
/// ## Fails closed
///
/// Every failure returns a typed [FlowLoadFailure]. The loader never returns
/// partially-populated data and never treats a malformed condition as `false`.
/// The live compiled Dart flow is untouched and continues to serve the
/// application, because this consumer never replaces it.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'question_flow_models.dart';
import 'condition_evaluator.dart';
import 'question_grouping_models.dart';

/// The schema major version this loader was written and reviewed against.
const int kSupportedFlowSchemaMajor = 1;

/// The EXACT schema versions this consumer implements.
///
/// Major-version gating is not enough here and was a real hazard: this loader
/// previously accepted any `1.x`, so a 1.1 artifact would have parsed without
/// error — the grouping block being merely an unknown field to it — and then
/// been planned as if every question stood alone. It would have presented the
/// full option union instead of the triggered union, offering the user
/// symptoms no selected token contributed. Silent partial understanding is the
/// failure mode; an exact set is the fix.
const Set<String> kSupportedFlowSchemaVersions = <String>{'1.0', '1.1'};

/// Schema versions whose grouping block this consumer applies.
const Set<String> kGroupingSchemaVersions = <String>{'1.1'};

/// The seven disclosed impedance mismatches. All must be present.
const List<String> kRequiredImpedanceMismatches = <String>[
  'IM-001',
  'IM-002',
  'IM-003',
  'IM-004',
  'IM-005',
  'IM-006',
  'IM-007',
];

/// The documented wildcard in `invalidates_on_change`. Recorded, never acted
/// on: acting on it would be dynamic invalidation (IM-003), which is deferred.
const String kInvalidatesAllFollowupsSentinel = '<all follow-up questions>';

/// Operator names that would indicate free-text, fuzzy or scored matching.
/// The contract forbids all of them; a flow naming one is refused.
const List<String> kForbiddenOperatorSubstrings = <String>[
  'regex',
  'matches',
  'contains',
  'like',
  'similarity',
  'score',
];

enum FlowLoadError {
  malformedJson,
  notAnObject,
  missingMetadata,
  unsupportedSchemaVersion,
  missingQuestions,
  malformedQuestion,
  duplicateQuestionId,
  duplicateAnswerOptionId,
  malformedId,
  invalidQuestionType,
  invalidAnswerValueType,
  invalidCondition,
  unknownOperator,
  unknownField,
  conditionTypeMismatch,
  unknownTokenReference,
  unknownQuestionReference,
  invalidRedFlagMetadata,
  invalidReviewOrPublication,
  invalidPathControls,
  duplicateOrderKey,
  missingImpedanceRecord,
  vocabularyActivated,
  skipSentinelProducesToken,
  requiredQuestionSkippable,
  unreachableQuestion,
  contradictoryCondition,
  branchCycle,
  redFlagOrderedBehindOrdinary,

  // ── schema 1.1 grouping ───────────────────────────────────────────────
  missingGroupingSemantics,
  invalidGroupingSemantics,
  invalidGrouping,
  duplicateGroupKey,
  unresolvedTieBreakTie,
  groupedRedFlagQuestion,
  ungroupedGroupableQuestion,
  duplicateGroupSource,
  missingSourceProvenance,
  conflictingOptionMeaning,
  sourceTriggerEscapesQuestion,
}

@immutable
class FlowLoadFailure implements Exception {
  const FlowLoadFailure(this.error, this.message, {this.questionId});

  final FlowLoadError error;
  final String message;
  final String? questionId;

  @override
  String toString() =>
      'FlowLoadFailure(${error.name}'
      '${questionId == null ? '' : ', $questionId'}): $message';
}

@immutable
class FlowLoadResult {
  const FlowLoadResult._(this.flow, this.failure);

  factory FlowLoadResult.success(QuestionFlow flow) =>
      FlowLoadResult._(flow, null);
  factory FlowLoadResult.failure(FlowLoadFailure failure) =>
      FlowLoadResult._(null, failure);

  final QuestionFlow? flow;
  final FlowLoadFailure? failure;

  bool get isSuccess => flow != null;
}

const Set<String> _validQuestionTypes = <String>{
  'single_select',
  'multi_select',
  'scale_select',
  'yes_no',
};

/// From the schema's own enum, not guessed.
const Set<String> _validAnswerValueTypes = <String>{
  'option_id',
  'option_id_set',
  'boolean',
};

/// From the schema's own enum.
const Set<String> _validClinicalRoles = <String>{
  'red_flag_clarifier',
  'severity',
  'duration',
  'additional_symptoms',
  'demographic',
  'body_area',
  'symptom_picker',
};

final RegExp _questionIdPattern = RegExp(r'^Q-[A-Za-z0-9_.-]+$');

FlowLoadResult _fail(FlowLoadError e, String m, {String? questionId}) =>
    FlowLoadResult.failure(FlowLoadFailure(e, m, questionId: questionId));

/// Parses and validates a flow from raw bytes. Performs no I/O.
///
/// [knownTokens] is the canonical token set the flow's token references must
/// resolve against — token dictionary 1.1 in every current build. Passing it
/// in keeps the loader from reaching for a clinical artifact itself.
FlowLoadResult loadQuestionFlowFromBytes(
  List<int> bytes, {
  required Set<String> knownTokens,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object catch (e) {
    return _fail(FlowLoadError.malformedJson, 'Flow is not valid JSON: $e');
  }
  if (decoded is! Map<String, dynamic>) {
    return _fail(FlowLoadError.notAnObject, 'Flow must be a JSON object.');
  }
  return _validate(decoded, knownTokens);
}

FlowLoadResult loadQuestionFlowFromString(
  String raw, {
  required Set<String> knownTokens,
}) => loadQuestionFlowFromBytes(utf8.encode(raw), knownTokens: knownTokens);

FlowLoadResult _validate(Map<String, dynamic> json, Set<String> knownTokens) {
  // ── metadata ──────────────────────────────────────────────────────────
  final Object? rawMeta = json['_metadata'];
  if (rawMeta is! Map<String, dynamic>) {
    return _fail(FlowLoadError.missingMetadata, 'Flow is missing "_metadata".');
  }

  final String schemaVersion = rawMeta['schema_version'] as String? ?? '';
  if (!kSupportedFlowSchemaVersions.contains(schemaVersion)) {
    return _fail(
      FlowLoadError.unsupportedSchemaVersion,
      'Unsupported schema version "$schemaVersion". This consumer implements '
      'exactly ${kSupportedFlowSchemaVersions.toList()..sort()}. A version is '
      'refused rather than best-effort parsed: partially understanding a '
      'schema changes which questions are asked.',
    );
  }
  final int? major = int.tryParse(schemaVersion.split('.').first);
  if (major != kSupportedFlowSchemaMajor) {
    return _fail(
      FlowLoadError.unsupportedSchemaVersion,
      'Unsupported schema version "$schemaVersion". This consumer was reviewed '
      'against major version $kSupportedFlowSchemaMajor.',
    );
  }

  final String releaseStatus = rawMeta['release_status'] as String? ?? '';
  final bool mayPublish = rawMeta['may_publish'] as bool? ?? false;
  final Object? review = rawMeta['clinical_review'];
  final String reviewStatus = review is Map<String, dynamic>
      ? (review['status'] as String? ?? 'not_reviewed')
      : 'not_reviewed';

  // "Ship me" plus "nobody checked" is the one combination that must not load.
  if ((mayPublish || releaseStatus == 'published') &&
      reviewStatus != 'approved') {
    return _fail(
      FlowLoadError.invalidReviewOrPublication,
      'Flow claims publication (release_status="$releaseStatus", '
      'may_publish=$mayPublish) without an approved clinical review '
      '(status="$reviewStatus").',
    );
  }

  // Content approved without a recorded review is the same defect one level
  // down, and has its own authoritative invalid fixture.
  final Object? rawQuestions = json['questions'];
  if (rawQuestions is! List) {
    return _fail(
      FlowLoadError.missingQuestions,
      'Flow is missing "questions".',
    );
  }

  final List<String> impedanceIds = <String>[
    for (final Object? im
        in (rawMeta['impedance_mismatches'] as List<dynamic>?) ??
            const <dynamic>[])
      if (im is Map<String, dynamic> && im['id'] is String) im['id'] as String,
  ];
  for (final String required in kRequiredImpedanceMismatches) {
    if (!impedanceIds.contains(required)) {
      return _fail(
        FlowLoadError.missingImpedanceRecord,
        'Flow does not disclose $required. All seven impedance mismatches must '
        'be present; a missing one is an undisclosed behavioural difference.',
      );
    }
  }

  // ── grouping semantics (schema 1.1) ───────────────────────────────────
  // Required for 1.1 and forbidden for 1.0. Enforced by ARTIFACT VERSION, not
  // by whether questions happen to carry grouping blocks: a 1.0 artifact must
  // never be implicitly grouped, and a 1.1 artifact must never group without
  // declaring how.
  QuestionGroupingSemantics? groupingSemantics;
  final Object? rawSemantics = rawMeta['grouping_semantics'];
  if (kGroupingSchemaVersions.contains(schemaVersion)) {
    if (rawSemantics is! Map<String, dynamic>) {
      return _fail(
        FlowLoadError.missingGroupingSemantics,
        'Schema $schemaVersion artifact declares no _metadata.'
        'grouping_semantics. A consumer cannot know whether questions merge, '
        'and guessing would change which questions are asked.',
      );
    }
    if (rawSemantics['one_question_per_group_key'] != true) {
      return _fail(
        FlowLoadError.invalidGroupingSemantics,
        'one_question_per_group_key must be true. A group that can present '
        'twice is not a group, and would re-inflate the question count.',
      );
    }
    final Object? declaredPhase = rawSemantics['grouping_phase'];
    if (declaredPhase != kGroupingPhaseBeforeTruncation) {
      return _fail(
        FlowLoadError.invalidGroupingSemantics,
        'grouping_phase is "$declaredPhase", not '
        '"$kGroupingPhaseBeforeTruncation". Grouping after truncation lets '
        'un-merged questions consume the follow-up budget and drops questions '
        'the live engine asks.',
      );
    }
    final List<String> nonGroupable = <String>[
      for (final Object? r
          in (rawSemantics['non_groupable_roles'] as List<dynamic>?) ??
              const <dynamic>[])
        if (r is String) r,
    ];
    for (final String role in kNonGroupableRoles) {
      if (!nonGroupable.contains(role)) {
        return _fail(
          FlowLoadError.invalidGroupingSemantics,
          'non_groupable_roles omits "$role". That declaration is the only '
          'thing standing between a merge rule and a deleted danger-sign '
          'question.',
        );
      }
    }
    final List<String> groupable = <String>[
      for (final Object? r
          in (rawSemantics['groupable_roles'] as List<dynamic>?) ??
              const <dynamic>[])
        if (r is String) r,
    ];
    for (final String role in groupable) {
      if (kNonGroupableRoles.contains(role)) {
        return _fail(
          FlowLoadError.invalidGroupingSemantics,
          'Role "$role" is declared both groupable and non-groupable.',
        );
      }
    }
    groupingSemantics = QuestionGroupingSemantics(
      enabled: rawSemantics['enabled'] as bool? ?? false,
      groupableRoles: List<String>.unmodifiable(groupable),
      nonGroupableRoles: List<String>.unmodifiable(nonGroupable),
      groupingPhase: declaredPhase as String,
      oneQuestionPerGroupKey: true,
    );
  } else if (rawSemantics != null) {
    return _fail(
      FlowLoadError.invalidGroupingSemantics,
      'Schema $schemaVersion artifact declares grouping_semantics, but that '
      'schema has no grouping. Honouring it would apply semantics the '
      'artifact version does not define.',
    );
  }

  final Object? vocab = rawMeta['vocabulary_2_0'];
  final bool vocabUsed = vocab is Map<String, dynamic>
      ? (vocab['used'] as bool? ?? false)
      : false;
  if (vocabUsed) {
    return _fail(
      FlowLoadError.vocabularyActivated,
      'Flow declares Vocabulary 2.0 participates in question eligibility. '
      'Question branching must resolve canonical tokens from token dictionary '
      '1.1 only.',
    );
  }

  // ── condition language ────────────────────────────────────────────────
  final Object? rawLang = json['condition_language'];
  if (rawLang is! Map<String, dynamic>) {
    return _fail(
      FlowLoadError.invalidCondition,
      'Flow is missing "condition_language".',
    );
  }
  final List<String> declaredOperators = <String>[
    for (final Object? o
        in (rawLang['operators'] as List<dynamic>?) ?? const <dynamic>[])
      if (o is String) o,
  ];
  for (final String op in declaredOperators) {
    if (!kConditionOperators.containsKey(op)) {
      return _fail(
        FlowLoadError.unknownOperator,
        'Condition language declares unsupported operator "$op".',
      );
    }
    for (final String banned in kForbiddenOperatorSubstrings) {
      if (op.toLowerCase().contains(banned)) {
        return _fail(
          FlowLoadError.unknownOperator,
          'Operator "$op" suggests free-text, fuzzy or scored matching, which '
          'the contract forbids.',
        );
      }
    }
  }

  // ── path controls ─────────────────────────────────────────────────────
  final Object? rawControls = json['path_controls'];
  if (rawControls is! Map<String, dynamic>) {
    return _fail(
      FlowLoadError.invalidPathControls,
      'Flow is missing "path_controls".',
    );
  }
  final int maxFollowups = rawControls['max_followup_questions'] as int? ?? -1;
  if (maxFollowups != 5) {
    return _fail(
      FlowLoadError.invalidPathControls,
      'max_followup_questions is $maxFollowups; the adopted limit is 5 and '
      'raising or lowering it is not authorised.',
    );
  }
  if (rawControls['red_flag_questions_exempt_from_truncation'] != true) {
    return _fail(
      FlowLoadError.invalidPathControls,
      'Red-flag questions must be exempt from truncation (IM-005).',
    );
  }

  final PathControls pathControls = PathControls(
    maxQuestionsPerAssessment:
        rawControls['max_questions_per_assessment'] as int? ?? 0,
    maxFollowupQuestions: maxFollowups,
    redFlagQuestionsExemptFromTruncation: true,
    truncationAllowed: rawControls['truncation_allowed'] as bool? ?? false,
  );

  // ── questions ─────────────────────────────────────────────────────────
  final List<FlowQuestion> questions = <FlowQuestion>[];

  /// group_key -> owning question id. One question per group key, enforced
  /// as questions are read rather than in a later pass, so the first
  /// collision names both sides.
  final Map<String, String> groupKeyOwners = <String, String>{};
  final Set<String> seenQuestionIds = <String>{};
  final Set<String> seenOptionIds = <String>{};
  final Set<String> seenOrderKeys = <String>{};
  final List<_PendingCondition> pending = <_PendingCondition>[];
  final Map<String, List<String>> branchGraph = <String, List<String>>{};

  for (final Object? entry in rawQuestions) {
    if (entry is! Map<String, dynamic>) {
      return _fail(
        FlowLoadError.malformedQuestion,
        'A question entry is not an object.',
      );
    }

    final Object? rawId = entry['question_id'];
    if (rawId is! String || !_questionIdPattern.hasMatch(rawId)) {
      return _fail(
        FlowLoadError.malformedId,
        'Question id ${jsonEncode(rawId)} is missing or malformed.',
      );
    }
    if (!seenQuestionIds.add(rawId)) {
      return _fail(
        FlowLoadError.duplicateQuestionId,
        'Question id "$rawId" appears more than once.',
        questionId: rawId,
      );
    }

    final String questionType = entry['question_type'] as String? ?? '';
    if (!_validQuestionTypes.contains(questionType)) {
      return _fail(
        FlowLoadError.invalidQuestionType,
        'Question "$rawId" has type "$questionType".',
        questionId: rawId,
      );
    }

    final String answerValueType = entry['answer_value_type'] as String? ?? '';
    if (!_validAnswerValueTypes.contains(answerValueType)) {
      return _fail(
        FlowLoadError.invalidAnswerValueType,
        'Question "$rawId" has answer_value_type "$answerValueType".',
        questionId: rawId,
      );
    }

    final String clinicalRole = entry['clinical_role'] as String? ?? '';
    if (!_validClinicalRoles.contains(clinicalRole)) {
      return _fail(
        FlowLoadError.invalidQuestionType,
        'Question "$rawId" has clinical_role "$clinicalRole".',
        questionId: rawId,
      );
    }

    final bool required = entry['required'] as bool? ?? false;
    final bool skippable = entry['skippable'] as bool? ?? false;
    if (required && skippable) {
      return _fail(
        FlowLoadError.requiredQuestionSkippable,
        'Question "$rawId" is required and skippable. A required clinical '
        'question must not be silently skippable.',
        questionId: rawId,
      );
    }

    // ── answer options ──────────────────────────────────────────────────
    final Object? rawOptions = entry['answer_options'];
    if (rawOptions is! List) {
      return _fail(
        FlowLoadError.malformedQuestion,
        'Question "$rawId" has no answer_options list.',
        questionId: rawId,
      );
    }
    final List<AnswerOption> options = <AnswerOption>[];
    for (final Object? o in rawOptions) {
      if (o is! Map<String, dynamic>) {
        return _fail(
          FlowLoadError.malformedQuestion,
          'Question "$rawId" has a non-object answer option.',
          questionId: rawId,
        );
      }
      final Object? oid = o['answer_option_id'];
      if (oid is! String || oid.isEmpty) {
        return _fail(
          FlowLoadError.malformedId,
          'Question "$rawId" has an answer option with no id.',
          questionId: rawId,
        );
      }
      if (!seenOptionIds.add(oid)) {
        return _fail(
          FlowLoadError.duplicateAnswerOptionId,
          'Answer option id "$oid" is not globally unique.',
          questionId: rawId,
        );
      }

      final List<String> produces = <String>[
        for (final Object? t
            in (o['produces_tokens'] as List<dynamic>?) ?? const <dynamic>[])
          if (t is String) t,
      ];
      for (final String t in produces) {
        if (!knownTokens.contains(t)) {
          return _fail(
            FlowLoadError.unknownTokenReference,
            'Answer option "$oid" produces token "$t", which is not in the '
            'canonical token dictionary.',
            questionId: rawId,
          );
        }
      }

      final bool isSkip = o['is_skip_sentinel'] as bool? ?? false;
      if (isSkip && produces.isNotEmpty) {
        return _fail(
          FlowLoadError.skipSentinelProducesToken,
          'Answer option "$oid" is a skip sentinel yet produces tokens. '
          'Skipping must contribute no clinical content.',
          questionId: rawId,
        );
      }

      options.add(
        AnswerOption(
          id: internalMintAnswerOptionId(oid),
          label: o['label'] as String? ?? '',
          producesTokens: List<String>.unmodifiable(produces),
          isSkipSentinel: isSkip,
          value: o['value'],
        ),
      );
    }

    // ── condition ───────────────────────────────────────────────────────
    final Object? rawCondition = entry['trigger_condition'];
    final _ConditionParse parsed = _parseCondition(rawCondition, knownTokens);
    if (parsed.failure != null) {
      return _fail(
        parsed.failure!.error,
        '${parsed.failure!.message} (question "$rawId")',
        questionId: rawId,
      );
    }
    pending.addAll(
      parsed.questionRefs.map((String q) => _PendingCondition(rawId, q)),
    );

    // Branch conditions: every `next_question_id` must resolve, and each
    // `when` must itself be a valid condition. These edges also form the
    // graph the cycle check walks.
    final Object? rawBranches = entry['branch_conditions'];
    if (rawBranches is! List) {
      return _fail(
        FlowLoadError.malformedQuestion,
        'Question "$rawId" has a non-list branch_conditions.',
        questionId: rawId,
      );
    }
    for (final Object? b in rawBranches) {
      if (b is! Map<String, dynamic>) {
        return _fail(
          FlowLoadError.malformedQuestion,
          'Question "$rawId" has a non-object branch condition.',
          questionId: rawId,
        );
      }
      final _ConditionParse when = _parseCondition(b['when'], knownTokens);
      if (when.failure != null) {
        return _fail(
          when.failure!.error,
          '${when.failure!.message} (branch of "$rawId")',
          questionId: rawId,
        );
      }
      final Object? next = b['next_question_id'];
      if (next is! String || next.isEmpty) {
        return _fail(
          FlowLoadError.unknownQuestionReference,
          'Question "$rawId" has a branch with no next_question_id.',
          questionId: rawId,
        );
      }
      pending.add(_PendingCondition(rawId, next));
      (branchGraph[rawId] ??= <String>[]).add(next);
    }

    // A trigger that can never be true makes the question unreachable, and a
    // self-contradictory one is the same defect written differently. Both are
    // authored mistakes, not intentional configuration.
    if (_isNeverSatisfiable(parsed.condition!)) {
      return _fail(
        FlowLoadError.unreachableQuestion,
        'Question "$rawId" has a trigger that can never be satisfied.',
        questionId: rawId,
      );
    }
    if (_isContradictory(parsed.condition!)) {
      return _fail(
        FlowLoadError.contradictoryCondition,
        'Question "$rawId" requires a token to be both present and absent.',
        questionId: rawId,
      );
    }

    // ── red flag metadata ───────────────────────────────────────────────
    final Object? rawRedFlag = entry['red_flag_evaluation'];
    if (rawRedFlag is! Map<String, dynamic>) {
      return _fail(
        FlowLoadError.invalidRedFlagMetadata,
        'Question "$rawId" is missing red_flag_evaluation.',
        questionId: rawId,
      );
    }
    final bool canAffect = rawRedFlag['can_affect_red_flag'] as bool? ?? false;
    final bool evaluateAfter =
        rawRedFlag['evaluate_after_answer'] as bool? ?? false;
    if (canAffect && !evaluateAfter) {
      return _fail(
        FlowLoadError.invalidRedFlagMetadata,
        'Question "$rawId" can affect a red flag but is not marked for '
        'immediate evaluation (IM-002).',
        questionId: rawId,
      );
    }

    final Object? rawEffects = entry['effects'];
    final Map<String, dynamic> effects = rawEffects is Map<String, dynamic>
        ? rawEffects
        : const <String, dynamic>{};
    final bool affectsRedFlags = effects['affects_red_flags'] as bool? ?? false;
    // Effect and hook must agree in BOTH directions. Declaring the effect
    // while denying the hook understates the impact just as much as the
    // reverse, and is the shape the authoritative fixture uses.
    if (canAffect != affectsRedFlags) {
      return _fail(
        FlowLoadError.invalidRedFlagMetadata,
        'Question "$rawId" disagrees with itself about red-flag impact: '
        'can_affect_red_flag=$canAffect but effects.affects_red_flags='
        '$affectsRedFlags.',
        questionId: rawId,
      );
    }

    // ── ordering key ────────────────────────────────────────────────────
    final int priority = entry['priority'] as int? ?? -1;
    final String tieBreak = entry['tie_break_key'] as String? ?? '';
    if (tieBreak.isEmpty) {
      return _fail(
        FlowLoadError.duplicateOrderKey,
        'Question "$rawId" declares no tie_break_key; a priority tie would '
        'have no declared resolution.',
        questionId: rawId,
      );
    }
    final String orderKey = '$priority $tieBreak $rawId';
    if (!seenOrderKeys.add(orderKey)) {
      return _fail(
        FlowLoadError.duplicateOrderKey,
        'Order key ($priority, $tieBreak, $rawId) is not unique.',
        questionId: rawId,
      );
    }

    final Object? contentRef = entry['content_ref'];
    final Map<String, dynamic> content = contentRef is Map<String, dynamic>
        ? contentRef
        : const <String, dynamic>{};

    // ── grouping (schema 1.1) ───────────────────────────────────────────
    QuestionGrouping? grouping;
    final Object? rawGrouping = entry['grouping'];
    if (rawGrouping != null) {
      if (!kGroupingSchemaVersions.contains(schemaVersion)) {
        return _fail(
          FlowLoadError.invalidGrouping,
          'Question "$rawId" declares grouping, but schema version '
          '"$schemaVersion" has no grouping semantics. A grouping block under '
          'a schema that cannot express it would be silently ignored.',
          questionId: rawId,
        );
      }
      final _GroupingParse parsedGroup = _parseGrouping(
        rawGrouping,
        rawId,
        clinicalRole,
        options,
        knownTokens,
      );
      if (parsedGroup.failure != null) {
        return FlowLoadResult.failure(parsedGroup.failure!);
      }
      grouping = parsedGroup.grouping;
      final String key = grouping!.groupKey;
      final String? owner = groupKeyOwners[key];
      if (owner != null) {
        return _fail(
          FlowLoadError.duplicateGroupKey,
          'group_key "$key" is claimed by both "$owner" and "$rawId". A path '
          'could then present two questions for one group.',
          questionId: rawId,
        );
      }
      groupKeyOwners[key] = rawId;
    }

    questions.add(
      FlowQuestion(
        id: internalMintQuestionId(rawId),
        questionType: questionType,
        clinicalRole: clinicalRole,
        answerValueType: answerValueType,
        required: required,
        skippable: skippable,
        answerOptions: List<AnswerOption>.unmodifiable(options),
        triggerCondition: parsed.condition!,
        priority: priority,
        tieBreakKey: tieBreak,
        pathLengthContribution: entry['path_length_contribution'] as int? ?? 1,
        invalidatesOnChange: List<String>.unmodifiable(<String>[
          for (final Object? v
              in (entry['invalidates_on_change'] as List<dynamic>?) ??
                  const <dynamic>[])
            if (v is String) v,
        ]),
        effects: QuestionEffects(
          producesTokens: List<String>.unmodifiable(<String>[
            for (final Object? t
                in (effects['produces_tokens'] as List<dynamic>?) ??
                    const <dynamic>[])
              if (t is String) t,
          ]),
          affectsScoring: effects['affects_scoring'] as bool? ?? false,
          affectsRedFlags: affectsRedFlags,
        ),
        redFlagEvaluation: RedFlagEvaluation(
          canAffectRedFlag: canAffect,
          evaluateAfterAnswer: evaluateAfter,
          blocksNextQuestion:
              rawRedFlag['blocks_next_question'] as bool? ?? false,
        ),
        terminal: entry['terminal'] as bool? ?? false,
        sourceText: content['source_text'] as String? ?? '',
        contentApproved: content['content_approved'] as bool? ?? false,
        grouping: grouping,
      ),
    );
  }

  // ── cross-references resolve ──────────────────────────────────────────
  for (final _PendingCondition p in pending) {
    if (!seenQuestionIds.contains(p.referencedQuestionId)) {
      return _fail(
        FlowLoadError.unknownQuestionReference,
        'Question "${p.owner}" references unknown question '
        '"${p.referencedQuestionId}".',
        questionId: p.owner,
      );
    }
  }
  for (final FlowQuestion q in questions) {
    for (final String target in q.invalidatesOnChange) {
      // The candidate uses a documented wildcard sentinel where an answer
      // would invalidate the whole follow-up set. It is a declaration, not a
      // reference — and it is never acted on here, because acting on it is
      // IM-003.
      if (target == kInvalidatesAllFollowupsSentinel) continue;
      if (!seenQuestionIds.contains(target)) {
        return _fail(
          FlowLoadError.unknownQuestionReference,
          'Question "${q.id}" invalidates unknown question "$target".',
          questionId: q.id.value,
        );
      }
      if (target == q.id.value) {
        return _fail(
          FlowLoadError.unknownQuestionReference,
          'Question "${q.id}" invalidates itself.',
          questionId: q.id.value,
        );
      }
    }
  }

  // A red-flag question must never be ordered behind an ordinary one: it
  // would be asked late, which is exactly the QB-002 harm in a new place.
  //
  // Scoped to follow-up-phase questions. `Q-symptom-selection` can affect a
  // red flag and carries priority 150, but it belongs to the demographic
  // phase that precedes follow-ups entirely — comparing it against follow-up
  // priorities compares two different orderings.
  bool isFollowupPhase(FlowQuestion q) =>
      !q.isDemographic &&
      q.clinicalRole != 'symptom_picker' &&
      q.clinicalRole != 'body_area';

  final int worstRedFlagPriority = questions
      .where((FlowQuestion q) => q.isRedFlagQuestion && isFollowupPhase(q))
      .fold<int>(
        -1,
        (int m, FlowQuestion q) => q.priority > m ? q.priority : m,
      );
  if (worstRedFlagPriority >= 0) {
    for (final FlowQuestion q in questions) {
      if (q.isRedFlagQuestion || !isFollowupPhase(q)) continue;
      if (q.priority < worstRedFlagPriority) {
        return _fail(
          FlowLoadError.redFlagOrderedBehindOrdinary,
          'Ordinary question "${q.id}" (priority ${q.priority}) is ordered '
          'ahead of a red-flag question (priority $worstRedFlagPriority).',
          questionId: q.id.value,
        );
      }
    }
  }

  // Branch cycles would let the flow loop forever.
  final FlowLoadResult? cycle = _detectBranchCycle(branchGraph);
  if (cycle != null) return cycle;

  // Content approval requires a recorded review, per question.
  for (final FlowQuestion q in questions) {
    if (q.contentApproved && reviewStatus != 'approved') {
      return _fail(
        FlowLoadError.invalidReviewOrPublication,
        'Question "${q.id}" is marked content_approved while the artifact has '
        'no completed clinical review.',
        questionId: q.id.value,
      );
    }
  }

  // ── tie_break_key is an ordering key, never a grouping key ────────────
  //
  // Two ungrouped questions sharing one is an UNRESOLVED ORDER TIE. It must
  // never be read as an implied merge: doing so would group questions the
  // artifact never declared groupable, and the whole point of `group_key` is
  // that grouping is declared rather than inferred.
  //
  // Scoped to schema 1.1. Candidate 1.0 legitimately reuses a tie-break key
  // across roles — `Q-followup-headache-severity`, `-duration` and
  // `-additional_symptoms` all carry "headache" and are separated by priority
  // — because 1.0 had no group key and used the key as a token label. An
  // earlier revision applied this to every version and stopped 1.0 loading,
  // which is a compatibility break, not a safety gain.
  if (kGroupingSchemaVersions.contains(schemaVersion)) {
    final Map<String, String> tieBreakOwners = <String, String>{};
    for (final FlowQuestion q in questions) {
      if (q.isGrouped) continue;
      final String? owner = tieBreakOwners[q.tieBreakKey];
      if (owner != null) {
        return _fail(
          FlowLoadError.unresolvedTieBreakTie,
          'Questions "$owner" and "${q.id.value}" share tie_break_key '
          '"${q.tieBreakKey}" with no grouping block. tie_break_key orders '
          'questions and never groups them, so this is an unresolved order '
          'tie, not an implied merge.',
          questionId: q.id.value,
        );
      }
      tieBreakOwners[q.tieBreakKey] = q.id.value;
    }
  }

  // ── every source trigger implies its question trigger ─────────────────
  //
  // A source that can fire where its question cannot would need a question
  // that is never presented, so its wording and options could never be shown.
  //
  // Decided EXACTLY by enumerating the token subsets the two conditions can
  // depend on — not approximated. Only the assignments where the QUESTION
  // trigger is false have to be examined, because those are the only ones a
  // source could escape into. Above the token cap the answer is UNDECIDED and
  // the artifact is refused, never assumed fine.
  for (final FlowQuestion q in questions) {
    if (!q.isGrouped) continue;

    // Fast path, exact for the shape the contract actually uses: a question
    // whose trigger is `any([token_present ...])` contains a source whose
    // trigger is `token_present t` exactly when t is one of those tokens. No
    // enumeration needed, and the answer is the same one enumeration gives.
    //
    // This matters: the general path below enumerates 2^n subsets, and the
    // widest group references 18 tokens. Measured at 87 ms of load time before
    // this fast path existed, against 1.5 ms for the whole of candidate 1.0.
    final Set<String>? questionTokens = _anyTokenPresentSet(q.triggerCondition);
    if (questionTokens != null) {
      bool decidedStructurally = true;
      for (final QuestionGroupSource s in q.grouping!.sources) {
        final String? sourceToken = _singleTokenPresent(s.triggerCondition);
        if (sourceToken == null) {
          decidedStructurally = false;
          break;
        }
        if (!questionTokens.contains(sourceToken)) {
          return _fail(
            FlowLoadError.sourceTriggerEscapesQuestion,
            'Question "${q.id.value}" source "${s.sourceId}" triggers on '
            '"$sourceToken", which the question trigger does not cover. The '
            'union would need a question that is never presented.',
            questionId: q.id.value,
          );
        }
      }
      if (decidedStructurally) continue;
    }

    final Set<String> universe = <String>{
      ..._referencedTokens(q.triggerCondition),
      for (final QuestionGroupSource s in q.grouping!.sources)
        ..._referencedTokens(s.triggerCondition),
    };
    if (universe.length > kContainmentTokenLimit) {
      return _fail(
        FlowLoadError.sourceTriggerEscapesQuestion,
        'Question "${q.id.value}" references ${universe.length} tokens, above '
        'the $kContainmentTokenLimit-token limit for an exact containment '
        'decision. Containment is UNDECIDED and must not be assumed.',
        questionId: q.id.value,
      );
    }
    final List<String> tokens = universe.toList()..sort();
    final List<Set<String>> outside = <Set<String>>[];
    for (int mask = 0; mask < (1 << tokens.length); mask++) {
      final Set<String> selection = <String>{
        for (int i = 0; i < tokens.length; i++)
          if ((mask & (1 << i)) != 0) tokens[i],
      };
      if (!evaluateFlowCondition(
        q.triggerCondition,
        FlowEvaluationState(tokens: selection),
      )) {
        outside.add(selection);
      }
    }
    for (final QuestionGroupSource s in q.grouping!.sources) {
      for (final Set<String> selection in outside) {
        if (evaluateFlowCondition(
          s.triggerCondition,
          FlowEvaluationState(tokens: selection),
        )) {
          return _fail(
            FlowLoadError.sourceTriggerEscapesQuestion,
            'Question "${q.id.value}" source "${s.sourceId}" can trigger on '
            '$selection while the question does not. The union would need a '
            'question that is never presented.',
            questionId: q.id.value,
          );
        }
      }
    }
  }

  // ── grouping is not silently bypassed (schema 1.1) ────────────────────
  //
  // An ungrouped question in a groupable role is exactly the candidate 1.0
  // shape: it consumes its own slot against the limit of 5, which is what made
  // 1.0 drop questions the live engine asks. One such question is legitimate —
  // the default-duration fallback — because its trigger cannot hold at the
  // same time as the group's. The difference is whether the two can CO-FIRE.
  //
  // Decided by probing each grouped source token on its own. That is sound for
  // the shapes the contract uses (a per-token follow-up fires on a single
  // token) and deliberately narrow: it is a load-time backstop, not a general
  // satisfiability decision. The stronger guarantee is enforced on every plan
  // by `planGroupedInitialPath`, which refuses to present two questions for
  // one group key or one groupable role.
  if (kGroupingSchemaVersions.contains(schemaVersion)) {
    for (final FlowQuestion ungrouped in questions) {
      if (ungrouped.isGrouped ||
          !kGroupableRoles.contains(ungrouped.clinicalRole)) {
        continue;
      }
      for (final FlowQuestion grouped in questions) {
        if (!grouped.isGrouped ||
            grouped.clinicalRole != ungrouped.clinicalRole) {
          continue;
        }
        for (final QuestionGroupSource source in grouped.grouping!.sources) {
          final FlowEvaluationState probe = FlowEvaluationState(
            tokens: <String>{source.sourceToken},
          );
          if (evaluateFlowCondition(ungrouped.triggerCondition, probe) &&
              evaluateFlowCondition(grouped.triggerCondition, probe)) {
            return _fail(
              FlowLoadError.ungroupedGroupableQuestion,
              'Question "${ungrouped.id.value}" is in groupable role '
              '"${ungrouped.clinicalRole}" with no grouping block, and fires '
              'alongside grouped question "${grouped.id.value}" when token '
              '"${source.sourceToken}" is selected. Two questions would be '
              'presented for one role, each consuming a slot against the '
              'follow-up limit.',
              questionId: ungrouped.id.value,
            );
          }
        }
      }
    }
  }

  return FlowLoadResult.success(
    QuestionFlow(
      metadata: FlowMetadata(
        artifactId: rawMeta['artifact_id'] as String? ?? '',
        version: rawMeta['version'] as String? ?? '',
        schemaVersion: schemaVersion,
        releaseStatus: releaseStatus,
        mayPublish: mayPublish,
        clinicalReviewStatus: reviewStatus,
        impedanceMismatchIds: List<String>.unmodifiable(impedanceIds),
        groupingSemantics: groupingSemantics,
        vocabulary20Used: vocabUsed,
      ),
      pathControls: pathControls,
      questions: List<FlowQuestion>.unmodifiable(questions),
      conditionLanguageVersion: rawLang['version'] as String? ?? '',
    ),
  );
}

/// True when a condition can never be satisfied by any state.
bool _isNeverSatisfiable(FlowCondition c) {
  switch (c.operator) {
    case ConditionOperator.never:
      return true;
    case ConditionOperator.all:
      return c.children.any(_isNeverSatisfiable);
    case ConditionOperator.any:
      return c.children.isNotEmpty && c.children.every(_isNeverSatisfiable);
    case ConditionOperator.not:
      return c.children.length == 1 &&
          c.children.first.operator == ConditionOperator.always;
    default:
      return false;
  }
}

/// True when an `all` requires the same token both present and absent.
bool _isContradictory(FlowCondition c) {
  if (c.operator == ConditionOperator.all) {
    final Set<String> present = <String>{};
    final Set<String> absent = <String>{};
    for (final FlowCondition child in c.children) {
      if (child.operator == ConditionOperator.tokenPresent &&
          child.token != null) {
        present.add(child.token!);
      }
      if (child.operator == ConditionOperator.tokenAbsent &&
          child.token != null) {
        absent.add(child.token!);
      }
    }
    if (present.intersection(absent).isNotEmpty) return true;
  }
  return c.children.any(_isContradictory);
}

FlowLoadResult? _detectBranchCycle(Map<String, List<String>> graph) {
  final Set<String> visiting = <String>{};
  final Set<String> done = <String>{};

  bool walk(String node, List<String> path) {
    if (visiting.contains(node)) return true;
    if (done.contains(node)) return false;
    visiting.add(node);
    for (final String next in graph[node] ?? const <String>[]) {
      if (walk(next, <String>[...path, next])) return true;
    }
    visiting.remove(node);
    done.add(node);
    return false;
  }

  for (final String start in (graph.keys.toList()..sort())) {
    if (walk(start, <String>[start])) {
      return _fail(
        FlowLoadError.branchCycle,
        'Branch conditions form a cycle reachable from "$start".',
        questionId: start,
      );
    }
  }
  return null;
}

class _PendingCondition {
  const _PendingCondition(this.owner, this.referencedQuestionId);
  final String owner;
  final String referencedQuestionId;
}

class _ConditionParse {
  const _ConditionParse(this.condition, this.failure, this.questionRefs);
  final FlowCondition? condition;
  final FlowLoadFailure? failure;
  final List<String> questionRefs;
}

/// Parses one condition node.
///
/// Exactly one operator key. An unknown operator, an unknown field, more than
/// one key, or a payload of the wrong type is an **error**, never `false`.
/// Every field a grouping block may carry. Anything else is refused.
const Set<String> kGroupingFields = <String>{
  'group_key',
  'merge_strategy',
  'representative_selection',
  'option_union_rule',
  'option_order',
  'conflict_resolution',
  'sources',
};

/// Every field a grouping source may carry.
const Set<String> kGroupingSourceFields = <String>{
  'source_id',
  'source_token',
  'source_order_index',
  'trigger_condition',
  'source_text',
  'answer_options',
  'provenance',
};

/// Above this many distinct referenced tokens, source-trigger containment is
/// refused rather than approximated. 20 covers every group in the candidate
/// (the largest references 18) with headroom.
const int kContainmentTokenLimit = 20;

/// The token set of an `any([token_present ...])` condition, or null when the
/// condition is not exactly that shape.
Set<String>? _anyTokenPresentSet(FlowCondition condition) {
  if (condition.operator != ConditionOperator.any) return null;
  final Set<String> tokens = <String>{};
  for (final FlowCondition child in condition.children) {
    if (child.operator != ConditionOperator.tokenPresent) return null;
    tokens.add(child.token!);
  }
  return tokens.isEmpty ? null : tokens;
}

/// The token of a bare `token_present` condition, or null.
String? _singleTokenPresent(FlowCondition condition) =>
    condition.operator == ConditionOperator.tokenPresent
    ? condition.token
    : null;

/// Every token a condition's truth can depend on.
///
/// Throws on an operator this walk cannot interpret, so an unrecognised
/// condition can never be silently treated as depending on nothing.
Set<String> _referencedTokens(FlowCondition condition) {
  switch (condition.operator) {
    case ConditionOperator.tokenPresent:
    case ConditionOperator.tokenAbsent:
      return <String>{condition.token!};
    case ConditionOperator.all:
    case ConditionOperator.any:
    case ConditionOperator.not:
      return <String>{
        for (final FlowCondition c in condition.children)
          ..._referencedTokens(c),
      };
    case ConditionOperator.always:
    case ConditionOperator.never:
    case ConditionOperator.equals:
    case ConditionOperator.oneOf:
    case ConditionOperator.priorAnswerEquals:
    case ConditionOperator.ageRange:
    case ConditionOperator.sex:
    case ConditionOperator.pregnancy:
      return const <String>{};
  }
}

@immutable
class _GroupingParse {
  const _GroupingParse.success(this.grouping) : failure = null;
  const _GroupingParse.error(this.failure) : grouping = null;

  final QuestionGrouping? grouping;
  final FlowLoadFailure? failure;
}

FlowLoadFailure _groupFail(FlowLoadError e, String m, String qid) =>
    FlowLoadFailure(e, m, questionId: qid);

/// Parses and validates one question's grouping block.
///
/// Every branch fails closed. A grouping rule this consumer cannot execute is
/// an error, never a shrug: silently ignoring a merge rule would present a
/// different question set than the one that was reviewed.
_GroupingParse _parseGrouping(
  Object? raw,
  String qid,
  String clinicalRole,
  List<AnswerOption> questionOptions,
  Set<String> knownTokens,
) {
  if (raw is! Map<String, dynamic>) {
    return _GroupingParse.error(
      _groupFail(
        FlowLoadError.invalidGrouping,
        'Question "$qid" has a non-object grouping block.',
        qid,
      ),
    );
  }

  // An unknown field in a grouping block is a merge directive this consumer
  // does not implement. Ignoring it is the precise failure this contract
  // exists to prevent: the artifact would be describing behaviour the app
  // silently does not perform.
  final Set<String> unknownKeys = raw.keys.toSet().difference(kGroupingFields);
  if (unknownKeys.isNotEmpty) {
    return _GroupingParse.error(
      _groupFail(
        FlowLoadError.invalidGrouping,
        'Question "$qid" grouping block carries unknown field(s) '
        '${unknownKeys.toList()..sort()}. This consumer refuses a merge '
        'directive it cannot execute rather than ignoring it.',
        qid,
      ),
    );
  }

  // A clarifier carries its own red-flag token; merging two would delete a
  // danger-sign question. Refused before anything else is even read.
  if (kNonGroupableRoles.contains(clinicalRole)) {
    return _GroupingParse.error(
      _groupFail(
        FlowLoadError.groupedRedFlagQuestion,
        'Question "$qid" has clinical role "$clinicalRole" and declares '
        'grouping. A red-flag clarifier must never be grouped: each carries '
        'its own red-flag token, so merging two deletes a danger sign.',
        qid,
      ),
    );
  }
  if (!kGroupableRoles.contains(clinicalRole)) {
    return _GroupingParse.error(
      _groupFail(
        FlowLoadError.invalidGrouping,
        'Question "$qid" has clinical role "$clinicalRole", which is not a '
        'groupable role.',
        qid,
      ),
    );
  }

  final Object? groupKey = raw['group_key'];
  if (groupKey is! String || groupKey.isEmpty) {
    return _GroupingParse.error(
      _groupFail(
        FlowLoadError.invalidGrouping,
        'Question "$qid" declares grouping with no group_key.',
        qid,
      ),
    );
  }

  final QuestionMergeStrategy? strategy =
      kQuestionMergeStrategies[raw['merge_strategy']];
  if (strategy == null) {
    return _GroupingParse.error(
      _groupFail(
        FlowLoadError.invalidGrouping,
        'Question "$qid" declares merge_strategy '
        '"${raw['merge_strategy']}", which this consumer cannot execute.',
        qid,
      ),
    );
  }

  final RepresentativeSelection? selection =
      kRepresentativeSelections[raw['representative_selection']];
  if (selection == null) {
    return _GroupingParse.error(
      _groupFail(
        FlowLoadError.invalidGrouping,
        'Question "$qid" declares representative_selection '
        '"${raw['representative_selection']}". An undeclared selection rule '
        'would reintroduce the selection-order dependence this contract '
        'exists to remove.',
        qid,
      ),
    );
  }

  final OptionUnionRule? unionRule =
      kOptionUnionRules[raw['option_union_rule']];
  if (unionRule == null) {
    return _GroupingParse.error(
      _groupFail(
        FlowLoadError.invalidGrouping,
        'Question "$qid" declares option_union_rule '
        '"${raw['option_union_rule']}", which this consumer cannot execute.',
        qid,
      ),
    );
  }

  final Object? optionOrder = raw['option_order'];
  if (optionOrder != null && optionOrder != kSourceOrderThenDeclaredOrder) {
    return _GroupingParse.error(
      _groupFail(
        FlowLoadError.invalidGrouping,
        'Question "$qid" declares option_order "$optionOrder", which is not a '
        'declared total order.',
        qid,
      ),
    );
  }

  GroupConflictResolution? conflict;
  final Object? rawConflict = raw['conflict_resolution'];
  if (rawConflict != null) {
    if (rawConflict is! Map<String, dynamic>) {
      return _GroupingParse.error(
        _groupFail(
          FlowLoadError.invalidGrouping,
          'Question "$qid" has a non-object conflict_resolution.',
          qid,
        ),
      );
    }
    if (rawConflict['on_value_type_conflict'] != 'reject') {
      return _GroupingParse.error(
        _groupFail(
          FlowLoadError.conflictingOptionMeaning,
          'Question "$qid" does not reject answer-value-type conflicts. '
          'Merging two answer shapes changes what an answer MEANS, which no '
          'grouping rule may do.',
          qid,
        ),
      );
    }
    if (unionRule == OptionUnionRule.unionOfTriggeredSources &&
        rawConflict['on_option_conflict'] != 'union_preserving_all_sources') {
      return _GroupingParse.error(
        _groupFail(
          FlowLoadError.conflictingOptionMeaning,
          'Question "$qid" unions options but does not promise to preserve '
          "every triggered source's options.",
          qid,
        ),
      );
    }
    conflict = GroupConflictResolution(
      onTextConflict: rawConflict['on_text_conflict'] as String? ?? '',
      onOptionConflict: rawConflict['on_option_conflict'] as String? ?? '',
      onValueTypeConflict:
          rawConflict['on_value_type_conflict'] as String? ?? '',
    );
  }

  final Object? rawSources = raw['sources'];
  if (rawSources is! List || rawSources.isEmpty) {
    return _GroupingParse.error(
      _groupFail(
        FlowLoadError.invalidGrouping,
        'Question "$qid" declares a group with no sources. There is nothing '
        'to merge and the question could never be presented.',
        qid,
      ),
    );
  }

  final Map<String, AnswerOption> declaredById = <String, AnswerOption>{
    for (final AnswerOption o in questionOptions) o.id.value: o,
  };
  final Set<String> seenSourceIds = <String>{};
  final Set<int> seenOrderIndexes = <int>{};
  final Set<String> contributed = <String>{};
  final List<QuestionGroupSource> sources = <QuestionGroupSource>[];

  for (final Object? rawSource in rawSources) {
    if (rawSource is! Map<String, dynamic>) {
      return _GroupingParse.error(
        _groupFail(
          FlowLoadError.invalidGrouping,
          'Question "$qid" has a non-object grouping source.',
          qid,
        ),
      );
    }
    final Set<String> unknownSourceKeys = rawSource.keys.toSet().difference(
      kGroupingSourceFields,
    );
    if (unknownSourceKeys.isNotEmpty) {
      return _GroupingParse.error(
        _groupFail(
          FlowLoadError.invalidGrouping,
          'Question "$qid" has a grouping source with unknown field(s) '
          '${unknownSourceKeys.toList()..sort()}.',
          qid,
        ),
      );
    }

    final Object? sourceId = rawSource['source_id'];
    if (sourceId is! String || sourceId.isEmpty) {
      return _GroupingParse.error(
        _groupFail(
          FlowLoadError.invalidGrouping,
          'Question "$qid" has a grouping source with no source_id.',
          qid,
        ),
      );
    }
    if (!seenSourceIds.add(sourceId)) {
      return _GroupingParse.error(
        _groupFail(
          FlowLoadError.duplicateGroupSource,
          'Question "$qid" has duplicate source_id "$sourceId", so the '
          'provenance of the presented wording is ambiguous.',
          qid,
        ),
      );
    }

    final Object? orderIndex = rawSource['source_order_index'];
    if (orderIndex is! int || orderIndex < 0) {
      return _GroupingParse.error(
        _groupFail(
          FlowLoadError.invalidGrouping,
          'Question "$qid" source "$sourceId" has a non-integer '
          'source_order_index. Representative selection would fall back to '
          'declaration order in the JSON, which is not a declared rule.',
          qid,
        ),
      );
    }
    if (!seenOrderIndexes.add(orderIndex)) {
      return _GroupingParse.error(
        _groupFail(
          FlowLoadError.duplicateGroupSource,
          'Question "$qid" has two sources at source_order_index '
          '$orderIndex, so representative selection is a tie with no '
          'declared resolution.',
          qid,
        ),
      );
    }

    final Object? sourceToken = rawSource['source_token'];
    if (sourceToken is! String || !knownTokens.contains(sourceToken)) {
      return _GroupingParse.error(
        _groupFail(
          FlowLoadError.unknownTokenReference,
          'Question "$qid" source "$sourceId" names token "$sourceToken", '
          'which is not in the canonical token dictionary.',
          qid,
        ),
      );
    }

    final Object? sourceText = rawSource['source_text'];
    if (sourceText is! String || sourceText.isEmpty) {
      return _GroupingParse.error(
        _groupFail(
          FlowLoadError.invalidGrouping,
          'Question "$qid" source "$sourceId" carries no source_text.',
          qid,
        ),
      );
    }

    // Provenance is never synthesised. An unattributable question cannot be
    // clinically reviewed, so a source without it is refused rather than
    // given a placeholder.
    final Object? provenance = rawSource['provenance'];
    if (provenance is! String || provenance.isEmpty) {
      return _GroupingParse.error(
        _groupFail(
          FlowLoadError.missingSourceProvenance,
          'Question "$qid" source "$sourceId" carries no provenance. This '
          'consumer never invents provenance for a question it would present.',
          qid,
        ),
      );
    }

    final _ConditionParse trigger = _parseCondition(
      rawSource['trigger_condition'],
      knownTokens,
    );
    if (trigger.failure != null) {
      return _GroupingParse.error(
        _groupFail(
          trigger.failure!.error,
          '${trigger.failure!.message} (question "$qid" source "$sourceId")',
          qid,
        ),
      );
    }

    final Object? rawSourceOptions = rawSource['answer_options'];
    final List<AnswerOption> sourceOptions = <AnswerOption>[];
    if (unionRule == OptionUnionRule.staticOptions) {
      if (rawSourceOptions is List && rawSourceOptions.isNotEmpty) {
        return _GroupingParse.error(
          _groupFail(
            FlowLoadError.conflictingOptionMeaning,
            'Question "$qid" source "$sourceId" carries answer_options under '
            'the static rule, so the artifact declares two different option '
            'sets for one question.',
            qid,
          ),
        );
      }
    } else {
      if (rawSourceOptions is! List || rawSourceOptions.isEmpty) {
        return _GroupingParse.error(
          _groupFail(
            FlowLoadError.invalidGrouping,
            'Question "$qid" source "$sourceId" contributes no answer_options '
            'under union_of_triggered_sources. If it triggered alone the '
            'question would have no answers.',
            qid,
          ),
        );
      }
      for (final Object? rawOption in rawSourceOptions) {
        if (rawOption is! Map<String, dynamic>) {
          return _GroupingParse.error(
            _groupFail(
              FlowLoadError.invalidGrouping,
              'Question "$qid" source "$sourceId" has a non-object option.',
              qid,
            ),
          );
        }
        final Object? optionId = rawOption['answer_option_id'];
        final AnswerOption? declared = optionId is String
            ? declaredById[optionId]
            : null;
        if (declared == null) {
          return _GroupingParse.error(
            _groupFail(
              FlowLoadError.invalidGrouping,
              'Question "$qid" source "$sourceId" would present option '
              '"$optionId", which the question does not declare.',
              qid,
            ),
          );
        }
        // Identity must agree exactly. A source that relabels a shared option
        // makes the presented text depend on which source triggered.
        final List<String> produces = <String>[
          for (final Object? t
              in (rawOption['produces_tokens'] as List<dynamic>?) ??
                  const <dynamic>[])
            if (t is String) t,
        ];
        final bool sameLabel = rawOption['label'] == declared.label;
        final bool sameValue = rawOption['value'] == declared.value;
        final bool sameTokens =
            produces.join('\u0000') == declared.producesTokens.join('\u0000');
        if (!sameLabel || !sameValue || !sameTokens) {
          return _GroupingParse.error(
            _groupFail(
              FlowLoadError.conflictingOptionMeaning,
              'Question "$qid" source "$sourceId" declares option '
              '"$optionId" with a different label, value or produced tokens '
              'than the question. An answer must not change meaning with the '
              'source that contributed it.',
              qid,
            ),
          );
        }
        contributed.add(declared.id.value);
        sourceOptions.add(declared);
      }
    }

    sources.add(
      QuestionGroupSource(
        sourceId: sourceId,
        sourceToken: sourceToken,
        sourceOrderIndex: orderIndex,
        triggerCondition: trigger.condition!,
        sourceText: sourceText,
        provenance: provenance,
        answerOptions: List<AnswerOption>.unmodifiable(sourceOptions),
      ),
    );
  }

  if (unionRule == OptionUnionRule.unionOfTriggeredSources) {
    final List<String> orphaned = <String>[
      for (final AnswerOption o in questionOptions)
        if (!contributed.contains(o.id.value)) o.id.value,
    ];
    if (orphaned.isNotEmpty) {
      return _GroupingParse.error(
        _groupFail(
          FlowLoadError.invalidGrouping,
          'Question "$qid" declares options no source contributes '
          '($orphaned). They can never be presented, so review would approve '
          'content no user sees.',
          qid,
        ),
      );
    }
  }

  return _GroupingParse.success(
    QuestionGrouping(
      groupKey: groupKey,
      mergeStrategy: strategy,
      representativeSelection: selection,
      optionUnionRule: unionRule,
      optionOrder: optionOrder as String?,
      conflictResolution: conflict,
      sources: List<QuestionGroupSource>.unmodifiable(sources),
    ),
  );
}

_ConditionParse _parseCondition(Object? raw, Set<String> knownTokens) {
  final List<String> refs = <String>[];

  _ConditionParse err(FlowLoadError e, String m) =>
      _ConditionParse(null, FlowLoadFailure(e, m), refs);

  if (raw is! Map<String, dynamic>) {
    return err(
      FlowLoadError.invalidCondition,
      'Condition must be an object, got ${raw.runtimeType}.',
    );
  }
  if (raw.length != 1) {
    return err(
      FlowLoadError.invalidCondition,
      'Condition must carry exactly one operator key, got ${raw.length}.',
    );
  }

  final String opName = raw.keys.first;
  final ConditionOperator? op = kConditionOperators[opName];
  if (op == null) {
    return err(
      FlowLoadError.unknownOperator,
      'Unknown condition operator "$opName".',
    );
  }

  final Object? payload = raw.values.first;

  List<FlowCondition>? parseChildren(Object? p) {
    if (p is! List) return null;
    final List<FlowCondition> out = <FlowCondition>[];
    for (final Object? c in p) {
      final _ConditionParse sub = _parseCondition(c, knownTokens);
      if (sub.failure != null) return null;
      refs.addAll(sub.questionRefs);
      out.add(sub.condition!);
    }
    return out;
  }

  switch (op) {
    case ConditionOperator.all:
    case ConditionOperator.any:
      final List<FlowCondition>? children = parseChildren(payload);
      if (children == null) {
        // Re-parse to surface the child's own failure rather than a generic one.
        if (payload is List) {
          for (final Object? c in payload) {
            final _ConditionParse sub = _parseCondition(c, knownTokens);
            if (sub.failure != null) {
              return _ConditionParse(null, sub.failure, refs);
            }
          }
        }
        return err(
          FlowLoadError.conditionTypeMismatch,
          '"$opName" expects a list of conditions.',
        );
      }
      return _ConditionParse(
        FlowCondition(operator: op, children: children),
        null,
        refs,
      );

    case ConditionOperator.not:
      final _ConditionParse sub = _parseCondition(payload, knownTokens);
      if (sub.failure != null) return _ConditionParse(null, sub.failure, refs);
      refs.addAll(sub.questionRefs);
      return _ConditionParse(
        FlowCondition(operator: op, children: <FlowCondition>[sub.condition!]),
        null,
        refs,
      );

    case ConditionOperator.always:
    case ConditionOperator.never:
      if (payload is! bool) {
        return err(
          FlowLoadError.conditionTypeMismatch,
          '"$opName" expects a boolean.',
        );
      }
      return _ConditionParse(
        FlowCondition(operator: op, value: payload),
        null,
        refs,
      );

    case ConditionOperator.tokenPresent:
    case ConditionOperator.tokenAbsent:
      if (payload is! String) {
        return err(
          FlowLoadError.conditionTypeMismatch,
          '"$opName" expects a token id string, got ${payload.runtimeType}.',
        );
      }
      if (!knownTokens.contains(payload)) {
        return err(
          FlowLoadError.unknownTokenReference,
          '"$opName" names token "$payload", which is not in the canonical '
          'token dictionary.',
        );
      }
      return _ConditionParse(
        FlowCondition(operator: op, token: payload),
        null,
        refs,
      );

    case ConditionOperator.sex:
    case ConditionOperator.pregnancy:
      if (op == ConditionOperator.sex && payload is! String) {
        return err(
          FlowLoadError.conditionTypeMismatch,
          '"sex" expects a string.',
        );
      }
      if (op == ConditionOperator.pregnancy && payload is! bool) {
        return err(
          FlowLoadError.conditionTypeMismatch,
          '"pregnancy" expects a boolean.',
        );
      }
      return _ConditionParse(
        FlowCondition(operator: op, value: payload),
        null,
        refs,
      );

    case ConditionOperator.ageRange:
      if (payload is! List) {
        return err(
          FlowLoadError.conditionTypeMismatch,
          '"age_range" expects a list of age tokens.',
        );
      }
      return _ConditionParse(
        FlowCondition(
          operator: op,
          values: List<Object?>.unmodifiable(payload),
        ),
        null,
        refs,
      );

    case ConditionOperator.equals:
    case ConditionOperator.oneOf:
      if (payload is! Map<String, dynamic>) {
        return err(
          FlowLoadError.conditionTypeMismatch,
          '"$opName" expects an object with a field.',
        );
      }
      final Object? field = payload['field'];
      if (field is! String || !kConditionFields.contains(field)) {
        return err(
          FlowLoadError.unknownField,
          '"$opName" reads unknown field ${jsonEncode(field)}. Readable '
          'fields: ${kConditionFields.join(', ')}.',
        );
      }
      if (op == ConditionOperator.equals) {
        return _ConditionParse(
          FlowCondition(operator: op, field: field, value: payload['value']),
          null,
          refs,
        );
      }
      final Object? values = payload['values'];
      if (values is! List) {
        return err(
          FlowLoadError.conditionTypeMismatch,
          '"one_of" expects a "values" list.',
        );
      }
      return _ConditionParse(
        FlowCondition(
          operator: op,
          field: field,
          values: List<Object?>.unmodifiable(values),
        ),
        null,
        refs,
      );

    case ConditionOperator.priorAnswerEquals:
      if (payload is! Map<String, dynamic>) {
        return err(
          FlowLoadError.conditionTypeMismatch,
          '"prior_answer_equals" expects an object.',
        );
      }
      final Object? qid = payload['question_id'];
      if (qid is! String || qid.isEmpty) {
        return err(
          FlowLoadError.invalidCondition,
          '"prior_answer_equals" needs a question_id.',
        );
      }
      refs.add(qid);
      return _ConditionParse(
        FlowCondition(
          operator: op,
          questionId: qid,
          value: payload['answer_option_id'] ?? payload['value'],
        ),
        null,
        refs,
      );
  }
}
