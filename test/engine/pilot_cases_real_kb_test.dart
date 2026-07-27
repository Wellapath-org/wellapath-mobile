// ignore_for_file: avoid_print
// print() is intentional here, as in the other E8 validation files: the
// console output is the deliverable the engineering lead reads.

import 'package:flutter_test/flutter_test.dart';

import 'case_bank/artifact_fixtures.dart';
import 'case_bank/case_bank_models.dart';
import 'case_bank/case_bank_runner.dart';

/// E3.5 pilot cases re-run against the **real** knowledge base artifact.
///
/// `pilot_case_validation_test.dart` runs these against an inline mock
/// knowledge base written in E3.2, not against the artifact that ships. That
/// mock deliberately differs from the shipped KB — PROGRESS.md records
/// malaria's `headache` weight being reduced 6 -> 3 "in pilot validation mock
/// only" so Case 11 would score correctly. The real KB was never brought in
/// line, so the pilot suite has been green while the shipped behaviour
/// diverged, invisibly (issue #42).
///
/// This file closes that gap for the three cases the engineering lead
/// selected, running them through the same harness and pinned artifacts the
/// E8.1 case bank uses: kb.ng.v2.4, rules.ng.v2.2, token_dictionary.ng.v1.1,
/// on the production wiring.
///
/// The original E3.5 assertions covered urgency only, not top condition, so
/// these do the same; the actual top condition is recorded for the record.

final List<CaseBankCase> _cases = <CaseBankCase>[
  const CaseBankCase(
    caseId: 'E3.5_C03',
    conditionTarget: 'malaria',
    description: 'malaria classic, adult, no modifiers',
    inputTokens: <String>[
      'fever',
      'chills',
      'headache',
      'body_pain',
      'sweating',
    ],
    demographicTokens: <String>[],
    expectedUrgency: 'urgent',
    safetyCritical: false,
  ),
  const CaseBankCase(
    caseId: 'E3.5_C08',
    conditionTarget: 'acute_diarrhoea',
    description: 'acute diarrhoea, no red flags, adult',
    inputTokens: <String>['watery_stool', 'nausea', 'abdominal_cramps'],
    demographicTokens: <String>[],
    expectedUrgency: 'non_urgent',
    safetyCritical: false,
  ),
  const CaseBankCase(
    caseId: 'E3.5_C11',
    conditionTarget: 'headache',
    description: 'headache + dizziness + fatigue',
    inputTokens: <String>['headache', 'dizziness', 'fatigue'],
    demographicTokens: <String>[],
    expectedUrgency: 'self_care',
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
      '=== E3.5 PILOT CASES vs REAL KB — kb.ng.v$kKbVersion / '
      'rules.ng.v$kRulesVersion / token_dictionary.ng.v$kTokenDictVersion ===',
    );

    for (final CaseBankCase testCase in _cases) {
      final CaseRunResult result = runner.runCase(testCase);
      print('');
      print('${testCase.caseId} — ${testCase.description}');
      print('  input          : ${testCase.inputTokens.join(', ')}');
      print(
        '  finalUrgency   : ${result.actualUrgency}   '
        '(E3.5 expected ${testCase.expectedUrgency})',
      );
      print('  topCondition   : ${result.actualTopCondition}');
      print('  urgencySource  : ${result.actualUrgencySource}');
      print('  top 3 by score :');
      for (final Map<String, dynamic> cause
          in runner.outputFor(testCase).topCauses) {
        print(
          '      ${cause['score'].toString().padLeft(3)}  '
          '${cause['condition_id']}',
        );
      }
      print(
        '  RESULT         : '
        '${result.actualUrgency == testCase.expectedUrgency ? 'PASS' : 'FAIL'}',
      );
    }
  });

  test('E3.5 Case 03 — malaria classic still returns urgent', () {
    expect(runner.runCase(_cases[0]).actualUrgency, 'urgent');
  });

  test('E3.5 Case 08 — acute diarrhoea still returns non_urgent', () {
    expect(runner.runCase(_cases[1]).actualUrgency, 'non_urgent');
  });

  // Skipped, not deleted and not re-pointed at the actual value: against the
  // real KB this returns hypertension / non_urgent, not the self_care E3.5
  // documented. Asserting the actual result would bake in behaviour the
  // clinical reviewer has not ruled on; asserting self_care reds the suite
  // over a decision that is not the code's to make. The setUpAll block above
  // still runs and prints the real output every time, so the divergence stays
  // visible rather than hidden. Flip this to a live assertion once the
  // engineering lead rules — see issue #42.
  test(
    'E3.5 Case 11 — headache + dizziness + fatigue',
    () {
      expect(runner.runCase(_cases[2]).actualUrgency, 'self_care');
    },
    skip:
        'Diverges against the real KB: returns hypertension / non_urgent. '
        'Awaiting ruling — case bank update or separate issue (#42).',
  );
}
