// ignore_for_file: avoid_print
// print() is intentional here, as in case_bank_validation_test.dart: the
// console output is the deliverable the engineering lead reads.

import 'package:flutter_test/flutter_test.dart';

import 'case_bank/artifact_fixtures.dart';
import 'case_bank/case_bank_models.dart';
import 'case_bank/case_bank_runner.dart';

/// E8.2 — the two weight-calibration validation cases, run against
/// kb.ng.v2.4 on the production wiring (`buildEngineInput`, the same function
/// `loading_screen.dart` calls).

final List<CaseBankCase> _cases = <CaseBankCase>[
  const CaseBankCase(
    caseId: 'CB_235',
    conditionTarget: 'malaria',
    description: 'headache alone, no fever, no modifiers',
    inputTokens: <String>['headache'],
    demographicTokens: <String>[],
    expectedUrgency: 'urgent',
    expectedTopCondition: 'malaria',
    safetyCritical: false,
  ),
  const CaseBankCase(
    caseId: 'CB_236',
    conditionTarget: 'malaria',
    description: 'headache + fever + chills',
    inputTokens: <String>['headache', 'fever', 'chills'],
    demographicTokens: <String>[],
    expectedUrgency: 'urgent',
    expectedTopCondition: 'malaria',
    safetyCritical: false,
  ),
];

void main() {
  late PinnedArtifacts artifacts;
  late CaseBankRunner runner;

  setUpAll(() {
    artifacts = loadPinnedArtifacts();
    runner = CaseBankRunner(
      rules: artifacts.rules,
      tokenDictionary: artifacts.tokenDictionary,
      knowledgeBase: artifacts.conditions,
      configMetadata: artifacts.configMetadata,
      wiring: EngineWiring.asShipped,
    );

    print('');
    print(
      '=== E8.2 VALIDATION — kb.ng.v$kKbVersion / '
      'rules.ng.v$kRulesVersion / token_dictionary.ng.v$kTokenDictVersion ===',
    );
  });

  for (final CaseBankCase testCase in _cases) {
    test('${testCase.caseId} — ${testCase.description}', () {
      final CaseRunResult result = runner.runCase(testCase);

      // Re-run through the engine directly to surface the full top-3 with
      // scores, which CaseRunResult intentionally reduces to the top id.
      final List<Map<String, dynamic>> topCauses = runner
          .outputFor(testCase)
          .topCauses;

      print('');
      print('${testCase.caseId} — ${testCase.description}');
      print('  input            : ${testCase.inputTokens.join(', ')}');
      print(
        '  finalUrgency     : ${result.actualUrgency}   '
        '(expected ${testCase.expectedUrgency})',
      );
      print('  urgencySource    : ${result.actualUrgencySource}');
      print(
        '  topCondition     : ${result.actualTopCondition}   '
        '(expected ${testCase.expectedTopCondition})',
      );
      print('  redFlagTriggered : ${result.redFlagTriggered}');
      print('  top 3 by score   :');
      for (final Map<String, dynamic> cause in topCauses) {
        print(
          '      ${cause['score'].toString().padLeft(3)}  '
          '${cause['condition_id']}',
        );
      }
      print('  RESULT           : ${result.passed ? 'PASS' : 'FAIL'}');

      expect(
        result.actualUrgency,
        testCase.expectedUrgency,
        reason: '${testCase.caseId} urgency',
      );
      expect(
        result.actualTopCondition,
        testCase.expectedTopCondition,
        reason: '${testCase.caseId} top condition',
      );
      expect(result.passed, isTrue, reason: '${testCase.caseId} overall');
    });
  }
}
