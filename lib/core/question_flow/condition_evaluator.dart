/// The declarative condition evaluator for Question Flow 1.0.
///
/// Deterministic, finite, type-safe. No arbitrary code, no regex over clinical
/// text, no free-text interpretation, no fuzzy matching, no network.
///
/// ## Two rules that look similar and are not
///
/// * An **unknown operator or field** is a *contract failure*. It cannot be
///   reached at evaluation time, because the loader refuses such a flow — but
///   the evaluator throws rather than returning `false` if one ever arrives,
///   so a malformed condition can never be silently read as "not eligible".
/// * An **unknown demographic value** — sex not stated, age not stated,
///   pregnancy not stated — makes a gated condition **false**. An unanswered
///   question is not the same as "no", so an age-gated question is *not asked*
///   rather than wrongly asked.
///
/// `{"all": []}` is **true**; `{"any": []}` is **false**. Stated by the
/// contract so two implementations cannot silently disagree.
///
/// The evaluator takes an explicitly supplied immutable [FlowEvaluationState].
/// It is **not** wired to re-evaluate the live question list after answers —
/// that is IM-003, which is deferred.
library;

import 'package:flutter/foundation.dart';

import 'question_flow_models.dart';

/// Thrown when a condition names something the contract does not define.
///
/// Never caught and converted to `false` anywhere in this package.
@immutable
class ConditionContractFailure implements Exception {
  const ConditionContractFailure(this.message);

  final String message;

  @override
  String toString() => 'ConditionContractFailure: $message';
}

/// Immutable state a condition may read.
///
/// Deliberately a value object rather than a live controller: the evaluator
/// must not be able to observe a mutating assessment.
@immutable
class FlowEvaluationState {
  const FlowEvaluationState({
    this.tokens = const <String>{},
    this.sex,
    this.ageToken,
    this.pregnancy,
    this.bodyArea,
    this.assessmentPhase,
    this.priorAnswers = const <String, String>{},
  });

  /// Canonical token ids already selected.
  final Set<String> tokens;

  /// Null means *not stated*, which is not the same as "no".
  final String? sex;
  final String? ageToken;
  final bool? pregnancy;
  final String? bodyArea;
  final String? assessmentPhase;

  /// question_id -> answer_option_id. A missing entry is never an affirmative
  /// match.
  final Map<String, String> priorAnswers;

  Object? readField(String field) {
    switch (field) {
      case 'sex':
        return sex;
      case 'age_token':
        return ageToken;
      case 'body_area':
        return bodyArea;
      case 'assessment_phase':
        return assessmentPhase;
      default:
        throw ConditionContractFailure(
          'Condition reads unknown field "$field". Readable fields: '
          '${kConditionFields.join(', ')}.',
        );
    }
  }
}

/// Evaluates [condition] against [state].
///
/// Pure and deterministic: the same condition and state always yield the same
/// answer, on every run and every platform.
bool evaluateFlowCondition(FlowCondition condition, FlowEvaluationState state) {
  switch (condition.operator) {
    case ConditionOperator.always:
      return true;

    case ConditionOperator.never:
      return false;

    // An empty `all` is true; an empty `any` is false.
    case ConditionOperator.all:
      for (final FlowCondition c in condition.children) {
        if (!evaluateFlowCondition(c, state)) return false;
      }
      return true;

    case ConditionOperator.any:
      for (final FlowCondition c in condition.children) {
        if (evaluateFlowCondition(c, state)) return true;
      }
      return false;

    case ConditionOperator.not:
      if (condition.children.length != 1) {
        throw const ConditionContractFailure(
          '"not" takes exactly one child condition.',
        );
      }
      return !evaluateFlowCondition(condition.children.first, state);

    case ConditionOperator.tokenPresent:
      final String? token = condition.token;
      if (token == null) {
        throw const ConditionContractFailure('"token_present" has no token.');
      }
      return state.tokens.contains(token);

    case ConditionOperator.tokenAbsent:
      final String? token = condition.token;
      if (token == null) {
        throw const ConditionContractFailure('"token_absent" has no token.');
      }
      return !state.tokens.contains(token);

    case ConditionOperator.sex:
      // Not stated -> false. The question is not asked rather than wrongly
      // asked.
      if (state.sex == null) return false;
      return state.sex == condition.value;

    case ConditionOperator.pregnancy:
      if (state.pregnancy == null) return false;
      return state.pregnancy == condition.value;

    case ConditionOperator.ageRange:
      if (state.ageToken == null) return false;
      return condition.values.contains(state.ageToken);

    case ConditionOperator.equals:
      final String? field = condition.field;
      if (field == null) {
        throw const ConditionContractFailure('"equals" has no field.');
      }
      final Object? actual = state.readField(field);
      if (actual == null) return false;
      return actual == condition.value;

    case ConditionOperator.oneOf:
      final String? field = condition.field;
      if (field == null) {
        throw const ConditionContractFailure('"one_of" has no field.');
      }
      final Object? actual = state.readField(field);
      if (actual == null) return false;
      return condition.values.contains(actual);

    case ConditionOperator.priorAnswerEquals:
      final String? questionId = condition.questionId;
      if (questionId == null) {
        throw const ConditionContractFailure(
          '"prior_answer_equals" has no question_id.',
        );
      }
      final String? given = state.priorAnswers[questionId];
      // A missing prior answer is never an affirmative match.
      if (given == null) return false;
      return given == condition.value;
  }
}
