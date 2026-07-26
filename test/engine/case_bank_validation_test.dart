// ignore_for_file: avoid_print
// print() is intentional in this file only. This is the E8.1 validation run,
// not production code: its console output IS the deliverable summary the
// engineering lead reads, and safety-critical failures must appear on stdout
// the moment they occur rather than being buffered into a final assertion.
// debugPrint() truncates long lines, which would corrupt the failure table.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'case_bank/artifact_fixtures.dart';
import 'case_bank/case_bank_coverage.dart';
import 'case_bank/case_bank_models.dart';
import 'case_bank/case_bank_runner.dart';

/// E8.1 — runs the delivered case bank through the live engine against the
/// pinned production artifacts (kb.ng.v2.3, rules.ng.v2.1,
/// token_dictionary.ng.v1.1) and writes `case_bank_results_v1.json`.
///
/// The case bank is built by the data engineer and delivered to
/// `wellapath-knowledge-base/testing/case_bank_v1.json`. Drop it at
/// `test/fixtures/case_bank_v1.json`, or point CASE_BANK_PATH at it:
///
///   flutter test test/engine/case_bank_validation_test.dart \
///     --dart-define=CASE_BANK_PATH=/path/to/case_bank_v1.json
///
/// Until then this file skips rather than fails — the harness's own behaviour
/// is covered by case_bank_runner_test.dart, which does not need the bank.
///
/// Every case is run twice, under both wirings (see [EngineWiring]):
///
///  * as_shipped  — what loading_screen.dart actually does today. This is the
///                  run the exit criteria are asserted against, because it is
///                  what a real user gets.
///  * as_intended — demographics and season passed through as the engine's
///                  modules expect. Diagnostic only. The gap between the two
///                  is the size of the wiring defect, not a KB problem.

const String _caseBankPathOverride = String.fromEnvironment('CASE_BANK_PATH');
const String _defaultCaseBankPath = 'test/fixtures/case_bank_v1.json';
const String _outputDir = 'build/e8_case_bank';
const String _outputFile = '$_outputDir/case_bank_results_v1.json';

String get _caseBankPath => _caseBankPathOverride.isNotEmpty
    ? _caseBankPathOverride
    : _defaultCaseBankPath;

String _describe(CaseRunResult r) {
  final String expected = r.testCase.expectedUrgency;
  final String actual = r.error != null ? 'ERROR' : (r.actualUrgency ?? 'none');
  final String direction = switch (r.urgencyDirection) {
    TriageDirection.underTriage => 'UNDER-TRIAGE',
    TriageDirection.overTriage => 'over-triage',
    TriageDirection.match => 'urgency ok',
    null => 'no result',
  };
  final String topLine =
      (r.testCase.expectedTopCondition != null && !r.topConditionMatched)
      ? '  top: expected ${r.testCase.expectedTopCondition}, '
            'got ${r.actualTopCondition ?? 'none'}'
      : '';

  return '  ${r.testCase.caseId}  [${r.testCase.conditionTarget}]  '
      '$expected -> $actual  ($direction)\n'
      '    input: ${r.testCase.inputTokens.join(', ')}\n'
      '    demographics: ${r.testCase.demographicTokens.isEmpty ? 'none' : r.testCase.demographicTokens.join(', ')}'
      '${r.testCase.season != null ? '  season: ${r.testCase.season}' : ''}'
      '${topLine.isEmpty ? '' : '\n$topLine'}'
      '${r.error != null ? '\n    error: ${r.error}' : ''}';
}

void _printReport(CaseBankReport report) {
  final String label = wiringName(report.wiring).toUpperCase();
  print('');
  print('=== E8.1 CASE BANK RESULTS — $label ===');
  print('  total cases      : ${report.total}');
  print('  passed           : ${report.passed}');
  print('  failed           : ${report.failed}');
  print('  pass rate        : ${(report.passRate * 100).toStringAsFixed(2)}%');
  print('  under-triage     : ${report.underTriage.length}');
  print('  over-triage      : ${report.overTriage.length}');
  print('  engine errors    : ${report.errored.length}');
  print('  safety-critical failures: ${report.safetyCriticalFailures.length}');
  print(
    '  global red flag rules exercised: '
    '${report.globalRulesTriggered.length}/${report.globalRuleIds.length}',
  );
  if (report.globalRulesNotTriggered.isNotEmpty) {
    print(
      '  global rules NOT exercised: '
      '${(report.globalRulesNotTriggered.toList()..sort()).join(', ')}',
    );
  }

  if (report.safetyCriticalFailures.isNotEmpty) {
    print('');
    print('--- SAFETY-CRITICAL FAILURES ($label) ---');
    for (final CaseRunResult r in report.safetyCriticalFailures) {
      print(_describe(r));
    }
  }

  final List<CaseRunResult> other = report.failures
      .where((CaseRunResult r) => !r.isSafetyCriticalFailure)
      .toList();
  if (other.isNotEmpty) {
    print('');
    print('--- OTHER FAILURES ($label) ---');
    for (final CaseRunResult r in other) {
      print(_describe(r));
    }
  }
}

void main() {
  final File caseBankFile = File(_caseBankPath);
  final bool caseBankPresent = caseBankFile.existsSync();

  group(
    'E8.1 case bank validation',
    () {
      late PinnedArtifacts artifacts;
      late List<CaseBankCase> cases;
      late CaseBankReport shipped;
      late CaseBankReport intended;
      late CaseBankCoverage coverage;

      setUpAll(() {
        artifacts = loadPinnedArtifacts();
        cases = parseCaseBank(jsonDecode(caseBankFile.readAsStringSync()));

        coverage = CaseBankCoverage(
          cases: cases,
          knownConditionIds: artifacts.conditionIds,
          emergencyConditionIds: artifacts.emergencyConditionIds,
        );

        CaseBankRunner runnerFor(EngineWiring wiring) => CaseBankRunner(
          rules: artifacts.rules,
          tokenDictionary: artifacts.tokenDictionary,
          knowledgeBase: artifacts.conditions,
          configMetadata: artifacts.configMetadata,
          wiring: wiring,
          // Exit criterion: safety-critical failures surface immediately,
          // mid-run, not after all 200+ cases have finished.
          onSafetyCriticalFailure: (CaseRunResult r) => print(
            '!! SAFETY-CRITICAL (${wiringName(wiring)}) ${r.testCase.caseId}: '
            'expected ${r.testCase.expectedUrgency}, '
            'got ${r.error != null ? 'ERROR' : r.actualUrgency}',
          ),
        );

        shipped = runnerFor(EngineWiring.asShipped).runAll(cases);
        intended = runnerFor(EngineWiring.asIntended).runAll(cases);

        _printReport(shipped);
        _printReport(intended);

        final Map<String, dynamic> payload = <String, dynamic>{
          'run_metadata': <String, dynamic>{
            'phase': 'E8.1',
            'case_bank_path': _caseBankPath,
            'artifacts': <String, String>{
              'knowledge_base': 'kb.ng.v$kKbVersion.json',
              'rules': 'rules.ng.v$kRulesVersion.json',
              'token_dictionary':
                  'token_dictionary.ng.v$kTokenDictVersion.json',
            },
            'wirings_run': <String>['as_shipped', 'as_intended'],
            'assertions_applied_to': 'as_shipped',
          },
          'coverage': coverage.toJson(),
          'as_shipped': shipped.toJson(),
          'as_intended': intended.toJson(),
        };

        Directory(_outputDir).createSync(recursive: true);
        File(_outputFile).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(payload),
        );
        print('');
        print('Results written to $_outputFile');
        print(
          'Commit to wellapath-knowledge-base/testing/case_bank_results_v1.json',
        );
      });

      test('exit criterion 1 — bank holds at least 200 cases', () {
        expect(
          coverage.meetsMinimumCases,
          isTrue,
          reason: 'Case bank has ${cases.length} cases, minimum is 200',
        );
      });

      test('exit criterion 2 — every condition has at least 3 cases', () {
        expect(
          coverage.conditionsBelowMinimum,
          isEmpty,
          reason:
              'Conditions with fewer than 3 cases: '
              '${(coverage.conditionsBelowMinimum.toList()..sort()).join(', ')}',
        );
      });

      test(
        'exit criterion 3 — every emergency condition has at least 5 cases',
        () {
          expect(
            coverage.emergencyConditionsBelowMinimum,
            isEmpty,
            reason:
                'Emergency conditions with fewer than 5 cases: '
                '${(coverage.emergencyConditionsBelowMinimum.toList()..sort()).join(', ')}',
          );
        },
      );

      test('exit criterion 4 — all global red flag rules exercised', () {
        expect(
          shipped.globalRulesNotTriggered,
          isEmpty,
          reason:
              'Global red flag rules never triggered by any case: '
              '${(shipped.globalRulesNotTriggered.toList()..sort()).join(', ')}',
        );
      });

      test(
        'exit criterion 5 — zero safety-critical under-triage (as shipped)',
        () {
          expect(
            shipped.safetyCriticalFailures,
            isEmpty,
            reason:
                '${shipped.safetyCriticalFailures.length} safety-critical '
                'failure(s) under the shipping wiring. See $_outputFile. '
                'The as_intended run had '
                '${intended.safetyCriticalFailures.length} — a gap between the '
                'two is the loading_screen.dart wiring defect, not a KB defect.',
          );
        },
      );
    },
    skip: caseBankPresent
        ? null
        : 'Case bank not found at $_caseBankPath — '
              'awaiting wellapath-knowledge-base/testing/case_bank_v1.json from the '
              'data engineer. Harness behaviour is covered by case_bank_runner_test.dart.',
  );
}
