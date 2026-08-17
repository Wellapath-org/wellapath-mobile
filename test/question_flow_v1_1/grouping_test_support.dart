/// Shared helpers for the Question Flow 1.1 grouping tests.
///
/// Everything here reads local fixtures. Nothing constructs an app, touches
/// `AssessmentController`, or reaches the network.
library;

import 'dart:convert';
import 'dart:io';

import 'package:wellapath_mobile/core/question_flow/condition_evaluator.dart';
import 'package:wellapath_mobile/core/question_flow/grouped_path_planner.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_loader.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';

import '../question_flow/question_flow_test_support.dart';
import 'question_grouping_contract.dart';

/// Loads candidate 1.1 against the live token dictionary.
///
/// Token dictionary **1.1** — the live artifact. Vocabulary 2.0 plays no part
/// in question eligibility, and passing 1.1 here is what enforces that.
FlowLoadResult loadGroupedCandidate() => loadQuestionFlowFromBytes(
  File(kGroupingCandidatePath).readAsBytesSync(),
  knownTokens: liveTokenDictionaryTokens(),
);

/// The loaded 1.1 flow, or a hard failure with the reason.
QuestionFlow groupedFlow() {
  final FlowLoadResult result = loadGroupedCandidate();
  if (!result.isSuccess) {
    throw StateError('candidate 1.1 failed to load: ${result.failure}');
  }
  return result.flow!;
}

/// A fresh mutable copy of the 1.1 candidate JSON, for mutation tests.
Map<String, dynamic> groupedCandidateJson() =>
    jsonDecode(File(kGroupingCandidatePath).readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// The captured oracle. Real Dart output, not a reimplementation.
Map<String, dynamic> oracle() => readJson(kOraclePath);

/// Plans a path from a token **set**. Order cannot be expressed here, which is
/// the point: the corrected model must not depend on it.
GroupedPathPlan planTokens(QuestionFlow flow, Iterable<String> tokens) =>
    planGroupedInitialPath(
      flow,
      FlowEvaluationState(tokens: tokens.toSet(), assessmentPhase: 'followup'),
    );

/// One live question as the oracle recorded it.
class OracleQuestion {
  OracleQuestion(Map<String, dynamic> raw)
    : role = raw['role'] as String,
      questionText = raw['question_text'] as String,
      options = ((raw['options'] as List<dynamic>?) ?? const <dynamic>[])
          .cast<String>(),
      redFlagToken = raw['red_flag_token'] as String?;

  final String role;
  final String questionText;
  final List<String> options;
  final String? redFlagToken;
}

class OracleCase {
  OracleCase(Map<String, dynamic> raw)
    : inputTokens = (raw['input_tokens'] as List<dynamic>).cast<String>(),
      questions = <OracleQuestion>[
        for (final Object? q in raw['questions'] as List<dynamic>)
          OracleQuestion(q as Map<String, dynamic>),
      ];

  final List<String> inputTokens;
  final List<OracleQuestion> questions;

  /// Sorted tokens, used to pair a reversed case with its forward counterpart.
  String get key => (List<String>.of(inputTokens)..sort()).join('|');
}

List<OracleCase> oracleCases(Map<String, dynamic> doc, String direction) =>
    <OracleCase>[
      for (final Object? c in doc[direction] as List<dynamic>)
        OracleCase(c as Map<String, dynamic>),
    ];

/// The roles whose live `FollowupQuestion` actually carries options.
///
/// Severity and duration carry an empty list in the live Dart model — their
/// answers come from the severity slider and duration chips — so there is
/// nothing to compare and no match is claimed for them.
const Set<String> kRolesWithComparableOptions = <String>{
  'additional_symptoms',
  'red_flag_clarifier',
};

/// WHICH question is asked, independent of how it is worded.
String identityKey(String role, String? redFlagToken) =>
    '$role|${redFlagToken ?? ''}';

/// Tokens the live model says a question's answers could produce.
///
/// Returns null where the live `FollowupQuestion` does not carry them —
/// severity and duration produce tokens through the slider and chips, which
/// the captured model has no field for. Comparing there would be inventing a
/// match.
Set<String>? liveProducedTokens(OracleQuestion q) {
  if (q.role == 'red_flag_clarifier') {
    return <String>{q.redFlagToken!};
  }
  if (q.role == 'additional_symptoms') {
    return q.options.toSet();
  }
  return null;
}
