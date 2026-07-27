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
/// Cases 03 and 08 pass against the real KB unchanged. Case 11 did not: E3.5
/// documented `self_care`, the real KB returns `non_urgent` / hypertension.
/// Per engineering lead ruling that expectation encoded the mock rather than
/// clinical intent, and has been updated here — headache + dizziness in an
/// adult reading as hypertension at `non_urgent` is clinically defensible.
///
/// Cases 03 and 08 keep E3.5's urgency-only assertions; Case 11 additionally
/// asserts top condition and urgency source, which the ruling fixed.

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
  // Expectation updated per engineering lead ruling: E3.5's `self_care`
  // encoded the inline mock (malaria headache weight lowered 6 -> 3 for the
  // pilot only), not clinical intent. non_urgent / hypertension for headache
  // + dizziness in an adult is the correct real-KB result and is clinically
  // defensible. Root cause of the wider ranking question stays on #42.
  const CaseBankCase(
    caseId: 'E3.5_C11',
    conditionTarget: 'hypertension',
    description: 'headache + dizziness + fatigue',
    inputTokens: <String>['headache', 'dizziness', 'fatigue'],
    demographicTokens: <String>[],
    expectedUrgency: 'non_urgent',
    expectedTopCondition: 'hypertension',
    expectedUrgencySource: 'urgency_default',
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

  // Asserts urgency, top condition and urgency source together — the full
  // CaseRunResult.passed — since the ruling fixed all three.
  test('E3.5 Case 11 — headache + dizziness returns non_urgent', () {
    final CaseRunResult result = runner.runCase(_cases[2]);

    expect(result.actualUrgency, 'non_urgent');
    expect(result.actualTopCondition, 'hypertension');
    expect(result.actualUrgencySource, 'urgency_default');
    expect(result.passed, isTrue);
  });
}
