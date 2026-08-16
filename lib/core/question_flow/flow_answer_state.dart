/// ID-keyed engineering answer state (IM-004, at contract level only).
///
/// Answers are keyed by stable question id and answer-option id rather than by
/// list index, which is what a future restoration model would need to
/// re-attribute an answer safely.
///
/// ## What this is NOT
///
/// **Restoration is not implemented, and this class does not provide it.** The
/// MVP persists no in-flight assessment and has no answer editing. This state
/// is an isolated engineering model used by tests. It is deliberately
/// unconnected to:
///
/// * `AssessmentController` — the live clinical state;
/// * persistence of any kind;
/// * restoration or answer-editing UI;
/// * dynamic invalidation (IM-003);
/// * telemetry;
/// * scoring;
/// * production state.
///
/// Recording an answer here changes nothing a user would see and contributes
/// no scoring token to any assessment.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'question_flow_models.dart';

enum AnswerRejection { unknownQuestion, unknownAnswerOption, alreadyAnswered }

@immutable
class AnswerResult {
  const AnswerResult._(this.state, this.rejection);

  factory AnswerResult.accepted(FlowAnswerState state) =>
      AnswerResult._(state, null);
  factory AnswerResult.rejected(AnswerRejection rejection) =>
      AnswerResult._(null, rejection);

  final FlowAnswerState? state;
  final AnswerRejection? rejection;

  bool get accepted => state != null;
}

/// Immutable, ID-keyed answer state. Every mutation returns a new instance.
@immutable
class FlowAnswerState {
  const FlowAnswerState._(this._answers);

  const FlowAnswerState.empty() : _answers = const <String, String>{};

  final Map<String, String> _answers;

  /// question_id -> answer_option_id, in insertion-independent sorted order.
  Map<String, String> get answers => Map<String, String>.unmodifiable(
    Map<String, String>.fromEntries(
      _answers.entries.toList()..sort(
        (MapEntry<String, String> a, MapEntry<String, String> b) =>
            a.key.compareTo(b.key),
      ),
    ),
  );

  bool get isEmpty => _answers.isEmpty;
  int get length => _answers.length;

  String? answerFor(QuestionId id) => _answers[id.value];

  /// Records an answer.
  ///
  /// Rejects an unknown question id, an option that does not belong to that
  /// question, and — unless [replace] is set — a second answer to a question
  /// that already has one.
  AnswerResult record(
    QuestionFlow flow,
    String questionId,
    String answerOptionId, {
    bool replace = false,
  }) {
    final FlowQuestion? question = flow.question(questionId);
    if (question == null) {
      return AnswerResult.rejected(AnswerRejection.unknownQuestion);
    }

    final bool optionBelongs = question.answerOptions.any(
      (AnswerOption o) => o.id.value == answerOptionId,
    );
    if (!optionBelongs) {
      return AnswerResult.rejected(AnswerRejection.unknownAnswerOption);
    }

    if (_answers.containsKey(questionId) && !replace) {
      return AnswerResult.rejected(AnswerRejection.alreadyAnswered);
    }

    final Map<String, String> next = Map<String, String>.of(_answers)
      ..[questionId] = answerOptionId;
    return AnswerResult.accepted(FlowAnswerState._(next));
  }

  /// The tokens the recorded answers would derive, in sorted order.
  ///
  /// **Reporting only.** Nothing here writes a token into clinical state; the
  /// live assessment does not read this class.
  List<String> derivedTokens(QuestionFlow flow) {
    final Set<String> tokens = <String>{};
    for (final MapEntry<String, String> e in _answers.entries) {
      final FlowQuestion? q = flow.question(e.key);
      if (q == null) continue;
      for (final AnswerOption o in q.answerOptions) {
        if (o.id.value == e.value) tokens.addAll(o.producesTokens);
      }
    }
    return (tokens.toList()..sort());
  }

  /// Questions whose answers can affect a red flag and are therefore marked
  /// for immediate evaluation (IM-002).
  List<String> questionsRequiringImmediateEvaluation(QuestionFlow flow) {
    final List<String> out = <String>[
      for (final String id in _answers.keys)
        if (flow.question(id)?.redFlagEvaluation.evaluateAfterAnswer ?? false)
          id,
    ];
    return out..sort();
  }

  /// Deterministic serialization for local test inspection. Not persisted.
  String toDeterministicJson() =>
      const JsonEncoder.withIndent('  ').convert(answers);

  /// Clears the entire isolated test state.
  FlowAnswerState cleared() => const FlowAnswerState.empty();
}
