// ignore_for_file: avoid_print
// print() is intentional in this file only. This is the E8.1 validation run,
// not production code: its console output IS the deliverable summary the
// engineering lead reads, and safety-critical failures must appear on stdout
// the moment they occur rather than being buffered into a final assertion.
// debugPrint() truncates long lines, which would corrupt the failure table.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_bank/artifact_fixtures.dart';
import 'case_bank/case_bank_coverage.dart';
import 'case_bank/case_bank_models.dart';
import 'case_bank/case_bank_runner.dart';
import 'case_bank/known_findings.dart';
import 'case_bank/known_findings_fixture.dart';

/// E8.1 — runs the delivered case bank through the live engine against the
/// pinned production artifacts (kb.ng.v2.4, rules.ng.v2.2,
/// token_dictionary.ng.v1.1) and writes `case_bank_results_v1.json`.
///
/// The versions above track the constants in `case_bank/artifact_fixtures.dart`,
/// which are the ones actually loaded — keep them in step.
///
/// The case bank is built by the data engineer and delivered to
/// `wellapath-knowledge-base/testing/case_bank_v1.json`. It is now vendored at
/// `test/fixtures/case_bank_v1.json` and hash-pinned by
/// `case_bank_provenance_test.dart` (see `docs/CASE_BANK_PROVENANCE.md`);
/// CASE_BANK_PATH still points the run at a different copy:
///
///   flutter test test/engine/case_bank_validation_test.dart \
///     --dart-define=CASE_BANK_PATH=/path/to/case_bank_v1.json
///
/// The skip below now only fires if the vendored fixture is deleted, and it is
/// no longer the safety net it once was: `case_bank_provenance_test.dart` fails
/// outright on a missing bank, so absence turns CI red there rather than
/// passing quietly here.
///
/// Every case runs once, under [EngineWiring.asShipped] — the production path
/// through `buildEngineInput`, the same function `loading_screen.dart` calls.
/// Since the E8 engine wiring fix (PR #37) that path carries demographics,
/// season and derived candidate conditions, so there is no longer a second
/// wiring worth reporting. [EngineWiring.preFix] survives only as a
/// regression fixture in case_bank_runner_test.dart.

const String _caseBankPathOverride = String.fromEnvironment('CASE_BANK_PATH');
const String _defaultCaseBankPath = 'test/fixtures/case_bank_v1.json';
const String _outputDir = 'build/e8_case_bank';
const String _outputFile = '$_outputDir/case_bank_results_v1.json';

/// The immutable known-findings registry. Its integrity constants live in
/// `known_findings_fixture.dart` so the validation run and the provenance
/// guard assert the same values.
const String _registryPath = kKnownFindingsPath;

String get _caseBankPath => _caseBankPathOverride.isNotEmpty
    ? _caseBankPathOverride
    : _defaultCaseBankPath;

String _describe(CaseRunResult r) {
  final String expected = r.testCase.expectedUrgency ?? '(observe)';
  final String actual = r.error != null ? 'ERROR' : (r.actualUrgency ?? 'none');
  final String direction = switch (r.urgencyDirection) {
    TriageDirection.underTriage => 'UNDER-TRIAGE',
    TriageDirection.overTriage => 'over-triage',
    TriageDirection.match => 'urgency ok',
    null => r.testCase.isObserveCase ? 'observed' : 'no result',
  };
  final String sourceLine =
      (r.testCase.expectedUrgencySource != null && !r.urgencySourceMatched)
      ? '    source: expected ${r.testCase.expectedUrgencySource}, '
            'got ${r.actualUrgencySource ?? 'none'}'
      : '';
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
      '${sourceLine.isEmpty ? '' : '\n$sourceLine'}'
      '${topLine.isEmpty ? '' : '\n$topLine'}'
      '${r.error != null ? '\n    error: ${r.error}' : ''}';
}

void _printReport(CaseBankReport report) {
  final String label = wiringName(report.wiring).toUpperCase();
  print('');
  print('=== E8.1 CASE BANK RESULTS — $label ===');
  print('  total cases      : ${report.total}');
  print('  graded cases     : ${report.gradedTotal}');
  print('  observe cases    : ${report.observeResults.length}');
  print('  passed           : ${report.passed}');
  print('  failed           : ${report.failed}');
  print('  pass rate        : ${(report.passRate * 100).toStringAsFixed(2)}%');
  print('  under-triage     : ${report.underTriage.length}');
  print('  over-triage      : ${report.overTriage.length}');
  print('  engine errors    : ${report.errored.length}');
  print('  urgency-source mismatches: ${report.sourceMismatches.length}');
  print(
    '  right answer, wrong reason: ${report.rightAnswerWrongReason.length}',
  );
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

  if (report.observeResults.isNotEmpty) {
    print('');
    print('--- OBSERVE CASES (recorded, not graded) ---');
    for (final CaseRunResult r in report.observeResults) {
      print(
        '  ${r.testCase.caseId}  ${r.testCase.description}\n'
        '    input: ${r.testCase.inputTokens.join(', ')}\n'
        '    actual: urgency=${r.actualUrgency ?? 'none'}  '
        'top=${r.actualTopCondition ?? 'none'}  '
        'red_flag=${r.redFlagTriggered}'
        '${r.matchedRuleId != null ? ' rule=${r.matchedRuleId}' : ''}'
        '${r.error != null ? '\n    error: ${r.error}' : ''}',
      );
    }
  }

  if (report.sourceMismatches.isNotEmpty) {
    print('');
    print('--- URGENCY SOURCE MISMATCHES ($label) ---');
    for (final CaseRunResult r in report.sourceMismatches) {
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

List<String> _sourceMismatchIds(CaseBankReport report) => report
    .sourceMismatches
    .map((CaseRunResult r) => r.testCase.caseId)
    .toList();

/// The authoritative result line. Known findings are printed loudly and are
/// never folded into the pass count.
void _printClassification(KnownFindingsClassification c) {
  print('');
  print('=== AUTHORITATIVE RESULT ===');
  print('  ${c.headline}');
  print(
    '  registry: v${c.registry.version} '
    '(schema ${c.registry.schemaVersion}), '
    'disposition ${c.registry.disposition}',
  );
  print('  registry bound to case bank: ${c.registry.boundFixtureSha256}');
  print('  engineering disposition only — NOT clinical approval, NOT external');
  print('  beta approval, NOT production approval.');

  if (c.knownFindings.isNotEmpty) {
    print('');
    print(
      '*** KNOWN FINDINGS — REGISTERED, UNRESOLVED, NOT COUNTED AS PASSED ***',
    );
    for (final ClassifiedCase e in c.knownFindings) {
      final KnownFinding f = e.finding!;
      print('');
      print('  ${e.caseId}  ${f.classification}');
      print('    decision status : ${f.decisionStatus}');
      print('    must resolve by : ${f.expiresAtMilestone}');
      print(
        '    triage direction: ${f.triageDirection} '
        '(safety_critical=${f.safetyCritical})',
      );
      print(
        '    case bank expects: ${f.expectedUrgency} / '
        '${f.expectedUrgencySource} / ${f.expectedTopCondition}',
      );
      print(
        '    pinned observed  : ${e.result.actualUrgency} / '
        '${e.result.actualUrgencySource} / ${e.result.actualTopCondition} '
        '/ red_flag=${e.result.redFlagTriggered}',
      );
      print('    counted as passed: NO');
    }
    print('');
    print('*** END KNOWN FINDINGS ***');
  }

  if (c.unexpectedFailures.isNotEmpty) {
    print('');
    print('--- UNEXPECTED FAILURES (not registered) ---');
    for (final ClassifiedCase e in c.unexpectedFailures) {
      print('  ${e.caseId}: ${e.reason}');
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
      late CaseBankCoverage coverage;
      late KnownFindingsRegistry registry;
      late KnownFindingsClassification classified;

      setUpAll(() {
        artifacts = loadPinnedArtifacts();
        final List<int> caseBankBytes = caseBankFile.readAsBytesSync();
        cases = parseCaseBank(jsonDecode(utf8.decode(caseBankBytes)));

        // The registry is bound to the exact bytes just loaded, not to a
        // hash restated from documentation — so a swapped fixture cannot
        // quietly inherit an adjudication made against a different one.
        registry = KnownFindingsRegistry.load(
          path: _registryPath,
          expectedSha256: kKnownFindingsSha256,
          expectedBytes: kKnownFindingsBytes,
          expectedVersion: kKnownFindingsVersion,
          expectedSchemaVersion: kKnownFindingsSchemaVersion,
          caseBankSha256: sha256.convert(caseBankBytes).toString(),
          cases: cases,
        );

        coverage = CaseBankCoverage(
          cases: cases,
          knownConditionIds: artifacts.conditionIds,
          emergencyConditionIds: artifacts.emergencyConditionIds,
        );

        final CaseBankRunner runner = CaseBankRunner(
          rules: artifacts.rules,
          tokenDictionary: artifacts.tokenDictionary,
          knowledgeBase: artifacts.conditions,
          configMetadata: artifacts.configMetadata,
          wiring: EngineWiring.asShipped,
          // Exit criterion: safety-critical failures surface immediately,
          // mid-run, not after all 200+ cases have finished.
          onSafetyCriticalFailure: (CaseRunResult r) => print(
            '!! SAFETY-CRITICAL ${r.testCase.caseId}: '
            'expected ${r.testCase.expectedUrgency}, '
            'got ${r.error != null ? 'ERROR' : r.actualUrgency}',
          ),
        );

        shipped = runner.runAll(cases);
        classified = KnownFindingsClassification(
          report: shipped,
          registry: registry,
        );

        _printReport(shipped);
        _printClassification(classified);

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
            'wiring': 'as_shipped',
            'engine_wiring_fix':
                'PR #37 — demographics, season and derived '
                'candidate conditions reach the engine',
          },
          'coverage': coverage.toJson(),
          'classification': classified.toJson(),
          'as_shipped': shipped.toJson(),
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
        'exit criterion 4b — every source mismatch is registered or fails',
        () {
          // The bank's own expectation is unchanged; what the registry buys is
          // that an *unregistered* mismatch still fails. CB_211's mismatch is
          // asserted exactly, in the pin test below.
          final Set<String> registered = registry.caseIds;
          final List<String> unregistered = _sourceMismatchIds(
            shipped,
          ).where((String id) => !registered.contains(id)).toList();

          expect(
            unregistered,
            isEmpty,
            reason:
                '${unregistered.length} unregistered case(s) reached their '
                'answer for a different reason than the bank expected. A new '
                'mismatch is never absorbed by the registry — it must be '
                'adjudicated in wellapath-knowledge-base first. '
                'See $_outputFile.',
          );
        },
      );

      test(
        'exit criterion 5 — zero safety-critical under-triage (as shipped)',
        () {
          expect(
            shipped.safetyCriticalFailures,
            isEmpty,
            reason:
                '${shipped.safetyCriticalFailures.length} safety-critical '
                'failure(s) under the shipping wiring. See $_outputFile.',
          );
        },
      );

      test(
        'every one of the 239 cases executed — none skipped or filtered',
        () {
          expect(shipped.total, cases.length);
          expect(cases, hasLength(239));
          expect(
            classified.executed,
            239,
            reason:
                'Classification must cover every case that ran. A registered '
                'finding that silently drops out of the run would look like a '
                'clean sweep.',
          );
          expect(
            classified.registeredButNotExecuted,
            isEmpty,
            reason:
                'Registered case(s) never executed: '
                '${classified.registeredButNotExecuted.join(', ')}',
          );
        },
      );

      test('no unexpected failures', () {
        expect(
          classified.unexpectedFailures
              .map((ClassifiedCase e) => '${e.caseId}: ${e.reason}')
              .toList(),
          isEmpty,
        );
      });

      test('counts reconcile exactly — 239 = 238 passed + 1 known finding', () {
        expect(classified.reconciles, isTrue);
        expect(classified.passed, hasLength(238));
        expect(classified.knownFindings, hasLength(1));
        expect(classified.unexpectedFailures, isEmpty);
        expect(classified.headline, contains('239 executed'));
      });

      test('registered findings are never counted as passed', () {
        final Set<String> passedIds = classified.passed
            .map((ClassifiedCase e) => e.caseId)
            .toSet();
        for (final String id in registry.caseIds) {
          expect(
            passedIds,
            isNot(contains(id)),
            reason:
                '$id is registered as a known finding and must never appear '
                'in the pass total.',
          );
        }
      });

      test('every registered finding is pinned exactly to its observation', () {
        // Deliberately driven from the registry, not from a hardcoded case id:
        // adding a finding upstream extends this assertion automatically.
        expect(classified.knownFindings, isNotEmpty);

        for (final ClassifiedCase e in classified.knownFindings) {
          final KnownFinding f = e.finding!;
          final CaseRunResult r = e.result;

          expect(r.error, isNull, reason: '${e.caseId} threw');
          expect(r.actualUrgency, f.observedUrgency, reason: e.caseId);
          expect(
            r.actualUrgencySource,
            f.observedUrgencySource,
            reason: e.caseId,
          );
          expect(
            r.actualTopCondition,
            f.observedTopCondition,
            reason: e.caseId,
          );
          expect(
            r.redFlagTriggered,
            f.observedRedFlagTriggered,
            reason: e.caseId,
          );

          // Still genuinely mismatching the unchanged bank expectation.
          expect(
            r.passed,
            isFalse,
            reason:
                '${e.caseId} now matches its case-bank expectation. That is '
                'not an automatic pass: the registry has gone stale and the '
                'entry must be reviewed.',
          );
          expect(f.isOpen, isTrue, reason: '${e.caseId} decision is not open');
        }
      });

      test('red flag precedence — emergency, and never a ranked cause', () {
        final List<CaseRunResult> redFlagged = shipped.results
            .where((CaseRunResult r) => r.redFlagTriggered)
            .toList();

        expect(redFlagged, isNotEmpty);
        for (final CaseRunResult r in redFlagged) {
          expect(
            r.actualUrgency,
            'emergency',
            reason:
                '${r.testCase.caseId} triggered a red flag but returned '
                '${r.actualUrgency}',
          );
          expect(
            r.actualTopCondition,
            isNull,
            reason:
                '${r.testCase.caseId} triggered a red flag and still produced '
                'a ranked cause — scoring must be skipped entirely '
                '(LOCKED PRINCIPLE #5).',
          );
        }
      });

      test('the registry claims no approval it does not hold', () {
        final Map<String, dynamic> json = classified.toJson();
        final Map<String, dynamic> reg =
            json['registry'] as Map<String, dynamic>;
        expect(reg['is_clinical_approval'], isFalse);
        expect(reg['engineering_disposition'], 'option_d_adopted');
      });
    },
    skip: caseBankPresent
        ? null
        : 'Case bank not found at $_caseBankPath — '
              'awaiting wellapath-knowledge-base/testing/case_bank_v1.json from the '
              'data engineer. Harness behaviour is covered by case_bank_runner_test.dart.',
  );
}
