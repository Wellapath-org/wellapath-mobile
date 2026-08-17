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

/// The schema major version this loader was written and reviewed against.
const int kSupportedFlowSchemaMajor = 1;

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
