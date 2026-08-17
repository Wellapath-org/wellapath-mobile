/// Shared helpers for the Question Flow 1.0 engineering tests.
///
/// Everything here reads local fixtures. Nothing constructs an app, touches
/// `AssessmentController`, or reaches the network.
library;

import 'dart:convert';
import 'dart:io';

import 'package:wellapath_mobile/core/question_flow/question_flow_loader.dart';

import 'question_flow_contract.dart';

const String kLiveTokenDictionaryPath =
    'test/fixtures/artifacts/token_dictionary.ng.v1.1.json';

/// The canonical token set the flow's references must resolve against.
///
/// Token dictionary **1.1** — the live artifact. Vocabulary 2.0 plays no part
/// in question eligibility, and passing 1.1 here is what enforces that.
Set<String> liveTokenDictionaryTokens() {
  final Map<String, dynamic> dict =
      jsonDecode(File(kLiveTokenDictionaryPath).readAsStringSync())
          as Map<String, dynamic>;
  return <String>{
    for (final MapEntry<String, dynamic> e in dict.entries)
      if (e.key.endsWith('_tokens'))
        ...(e.value as List<dynamic>).cast<String>(),
  };
}

/// A fresh mutable copy of the candidate JSON, for mutation tests.
Map<String, dynamic> candidateJson() =>
    jsonDecode(File(kFlowCandidatePath).readAsStringSync())
        as Map<String, dynamic>;

FlowLoadResult loadCandidateFlow() => loadQuestionFlowFromBytes(
  File(kFlowCandidatePath).readAsBytesSync(),
  knownTokens: liveTokenDictionaryTokens(),
);

FlowLoadResult loadFlowFromMap(Map<String, dynamic> doc) =>
    loadQuestionFlowFromString(
      jsonEncode(doc),
      knownTokens: liveTokenDictionaryTokens(),
    );

Map<String, dynamic> _pathFixtureDoc() =>
    jsonDecode(
          File(
            '$kFlowFixtureRoot/paths/path_fixtures_v1.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

/// The 18 authoritative path cases.
List<Map<String, dynamic>> pathFixtures() =>
    (_pathFixtureDoc()['cases'] as List<dynamic>).cast<Map<String, dynamic>>();

/// The 3 authoritative edit cases. Recorded for completeness; answer editing
/// does not exist in the MVP, so they are not executed as behaviour.
List<Map<String, dynamic>> pathEditFixtures() =>
    (_pathFixtureDoc()['edit_cases'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
