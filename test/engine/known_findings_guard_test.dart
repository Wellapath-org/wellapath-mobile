/// Negative guards for the known-findings registry.
///
/// The registry's whole value is that it fails closed. A guard that has never
/// been seen to fail is an assumption, not a control, so every rejection path
/// is exercised here against a deliberately broken copy of the real registry.
///
/// Each test mutates the authoritative JSON in memory, writes it to a temp
/// file, and passes *that file's own* hash and byte count so the mutation
/// reaches the semantic check under test rather than being stopped at the
/// integrity gate. The integrity gate itself is covered by its own tests.
///
/// The vendored registry is never modified by this file.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_bank/case_bank_models.dart';
import 'case_bank/case_bank_runner.dart';
import 'case_bank/known_findings.dart';
import 'case_bank/known_findings_fixture.dart';

const String _caseBankPath = 'test/fixtures/case_bank_v1.json';

late Directory _tempDir;
late List<CaseBankCase> _cases;
late String _caseBankSha;
late Map<String, dynamic> _authoritative;

/// Writes [registry] to a temp file and loads it, passing that file's real hash
/// and size so the test targets the check it means to.
KnownFindingsRegistry _loadMutated(
  Map<String, dynamic> registry, {
  String? caseBankSha,
  String currentMilestone = 'internal_beta',
  String? version,
  String? schemaVersion,
}) {
  final File file = File(
    '${_tempDir.path}/known_findings_${DateTime.now().microsecondsSinceEpoch}.json',
  );
  final List<int> bytes = utf8.encode(jsonEncode(registry));
  file.writeAsBytesSync(bytes);

  return KnownFindingsRegistry.load(
    path: file.path,
    expectedSha256: sha256.convert(bytes).toString(),
    expectedBytes: bytes.length,
    expectedVersion: version ?? kKnownFindingsVersion,
    expectedSchemaVersion: schemaVersion ?? kKnownFindingsSchemaVersion,
    caseBankSha256: caseBankSha ?? _caseBankSha,
    cases: _cases,
    currentMilestone: currentMilestone,
  );
}

/// A deep copy, so one test's mutation cannot leak into another's.
Map<String, dynamic> _copy() =>
    jsonDecode(jsonEncode(_authoritative)) as Map<String, dynamic>;

Map<String, dynamic> _finding(Map<String, dynamic> registry) =>
    (registry['findings'] as List<dynamic>).first as Map<String, dynamic>;

/// Builds a run result for [caseId] with the given engine output, so drift can
/// be simulated without touching the engine.
CaseRunResult _resultFor(
  String caseId, {
  required String? urgency,
  required String? urgencySource,
  required String? topCondition,
  bool redFlagTriggered = false,
  String? error,
}) {
  final CaseBankCase testCase = _cases.firstWhere(
    (CaseBankCase c) => c.caseId == caseId,
  );

  TriageDirection? direction;
  if (urgency != null && testCase.expectedUrgency != null) {
    final int expected = urgencyRank(testCase.expectedUrgency!);
    final int actual = urgencyRank(urgency);
    direction = actual == expected
        ? TriageDirection.match
        : (actual < expected
              ? TriageDirection.underTriage
              : TriageDirection.overTriage);
  }

  return CaseRunResult(
    testCase: testCase,
    wiring: EngineWiring.asShipped,
    actualUrgency: urgency,
    actualUrgencySource: urgencySource,
    actualTopCondition: topCondition,
    urgencyDirection: direction,
    topConditionMatched:
        testCase.expectedTopCondition == null ||
        testCase.expectedTopCondition == topCondition,
    redFlagTriggered: redFlagTriggered,
    error: error,
  );
}

KnownFindingsClassification _classify(List<CaseRunResult> results) {
  return KnownFindingsClassification(
    report: CaseBankReport(
      wiring: EngineWiring.asShipped,
      results: results,
      globalRuleIds: const <String>{},
    ),
    registry: _loadMutated(_copy()),
  );
}

void main() {
  setUpAll(() {
    _tempDir = Directory.systemTemp.createTempSync('known_findings_guard');
    final List<int> bankBytes = File(_caseBankPath).readAsBytesSync();
    _caseBankSha = sha256.convert(bankBytes).toString();
    _cases = parseCaseBank(jsonDecode(utf8.decode(bankBytes)));
    _authoritative =
        jsonDecode(File(kKnownFindingsPath).readAsStringSync())
            as Map<String, dynamic>;
  });

  tearDownAll(() {
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });

  group('registry integrity', () {
    test('the authoritative registry loads cleanly', () {
      final KnownFindingsRegistry registry = KnownFindingsRegistry.load(
        path: kKnownFindingsPath,
        expectedSha256: kKnownFindingsSha256,
        expectedBytes: kKnownFindingsBytes,
        expectedVersion: kKnownFindingsVersion,
        expectedSchemaVersion: kKnownFindingsSchemaVersion,
        caseBankSha256: _caseBankSha,
        cases: _cases,
      );

      expect(registry.version, '1.0');
      expect(registry.schemaVersion, '1.0');
      expect(registry.disposition, 'option_d_adopted');
      expect(registry.boundFixtureSha256, kCaseBankSha256);
      expect(registry.findings, hasLength(1));
      expect(registry.caseIds, <String>{'CB_211'});
    });

    test('a missing registry fails — absence is not permission', () {
      expect(
        () => KnownFindingsRegistry.load(
          path: '${_tempDir.path}/does_not_exist.json',
          expectedSha256: kKnownFindingsSha256,
          expectedBytes: kKnownFindingsBytes,
          expectedVersion: kKnownFindingsVersion,
          expectedSchemaVersion: kKnownFindingsSchemaVersion,
          caseBankSha256: _caseBankSha,
          cases: _cases,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('missing'), contains('not permission')),
          ),
        ),
      );
    });

    test('a different sha256 fails', () {
      expect(
        () => KnownFindingsRegistry.load(
          path: kKnownFindingsPath,
          expectedSha256: 'deadbeef' * 8,
          expectedBytes: kKnownFindingsBytes,
          expectedVersion: kKnownFindingsVersion,
          expectedSchemaVersion: kKnownFindingsSchemaVersion,
          caseBankSha256: _caseBankSha,
          cases: _cases,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('hash drifted'),
          ),
        ),
      );
    });

    test('a different byte count fails', () {
      expect(
        () => KnownFindingsRegistry.load(
          path: kKnownFindingsPath,
          expectedSha256: kKnownFindingsSha256,
          expectedBytes: kKnownFindingsBytes + 1,
          expectedVersion: kKnownFindingsVersion,
          expectedSchemaVersion: kKnownFindingsSchemaVersion,
          caseBankSha256: _caseBankSha,
          cases: _cases,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('byte count drifted'),
          ),
        ),
      );
    });

    test('a malformed registry fails', () {
      final File broken = File('${_tempDir.path}/malformed.json');
      final List<int> bytes = utf8.encode('{"_metadata": {broken');
      broken.writeAsBytesSync(bytes);

      expect(
        () => KnownFindingsRegistry.load(
          path: broken.path,
          expectedSha256: sha256.convert(bytes).toString(),
          expectedBytes: bytes.length,
          expectedVersion: kKnownFindingsVersion,
          expectedSchemaVersion: kKnownFindingsSchemaVersion,
          caseBankSha256: _caseBankSha,
          cases: _cases,
        ),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
    });

    test('a wrong version fails', () {
      expect(
        () => _loadMutated(_copy(), version: '2.0'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('version'),
          ),
        ),
      );
    });

    test('a wrong schema_version fails', () {
      expect(
        () => _loadMutated(_copy(), schemaVersion: '2.0'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('schema_version'),
          ),
        ),
      );
    });
  });

  group('registry-to-fixture binding', () {
    test('a registry bound to a different case bank fails', () {
      expect(
        () => _loadMutated(_copy(), caseBankSha: 'abc123' * 10),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('bound to case bank'), contains('re-adjudicated')),
          ),
        ),
      );
    });

    test('an entry adjudicated against another fixture fails', () {
      final Map<String, dynamic> r = _copy();
      _finding(r)['fixture_sha256'] = 'f' * 64;

      expect(
        () => _loadMutated(r),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('adjudicated against fixture'),
          ),
        ),
      );
    });

    test('a case id absent from the case bank fails', () {
      final Map<String, dynamic> r = _copy();
      _finding(r)['case_id'] = 'CB_999';

      expect(
        () => _loadMutated(r),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('does not exist in the loaded case bank'),
          ),
        ),
      );
    });

    test('duplicate case ids fail', () {
      final Map<String, dynamic> r = _copy();
      final List<dynamic> findings = r['findings'] as List<dynamic>;
      findings.add(jsonDecode(jsonEncode(findings.first)));

      expect(
        () => _loadMutated(r),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('more than once'),
          ),
        ),
      );
    });

    test('an expectation disagreeing with the case bank fails', () {
      final Map<String, dynamic> r = _copy();
      (_finding(r)['expected_output'] as Map<String, dynamic>)['urgency'] =
          'emergency';

      expect(
        () => _loadMutated(r),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('disagrees with the case bank'),
          ),
        ),
      );
    });
  });

  group('authority and staleness', () {
    test('a non-option_d disposition fails', () {
      final Map<String, dynamic> r = _copy();
      (r['_metadata'] as Map<String, dynamic>)['engineering_disposition'] =
          'option_a_preserve';

      expect(
        () => _loadMutated(r),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('disposition'),
          ),
        ),
      );
    });

    test('a closed decision status fails — it must stay open', () {
      final Map<String, dynamic> r = _copy();
      _finding(r)['decision_status'] = 'resolved_option_b_applied';

      expect(
        () => _loadMutated(r),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('no longer reads as open'),
          ),
        ),
      );
    });

    test('a claimed clinical approval fails', () {
      final Map<String, dynamic> r = _copy();
      _finding(r)['classification_is_clinical_approval'] = true;

      expect(
        () => _loadMutated(r),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('engineering authority only'),
          ),
        ),
      );
    });

    test('a claimed external-beta approval in the record fails', () {
      final Map<String, dynamic> r = _copy();
      final Map<String, dynamic> record =
          (r['_metadata']
                  as Map<String, dynamic>)['engineering_disposition_record']
              as Map<String, dynamic>;
      record['is_external_beta_approval'] = true;

      expect(
        () => _loadMutated(r),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('engineering authority only'),
          ),
        ),
      );
    });

    test('an expired registry fails at the milestone it defers to', () {
      // The entry expires at external_beta; running an external-beta build
      // must force the deferred decision rather than carry it further.
      expect(
        () => _loadMutated(_copy(), currentMilestone: 'external_beta'),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('expires at milestone'), contains('now due')),
          ),
        ),
      );
    });

    test('it is still valid at the current internal-beta milestone', () {
      expect(
        _loadMutated(_copy(), currentMilestone: 'internal_beta').findings,
        hasLength(1),
      );
    });
  });

  group('classification fails closed', () {
    test('the pinned observation classifies as one known finding', () {
      final KnownFindingsClassification c = _classify(<CaseRunResult>[
        _resultFor(
          'CB_211',
          urgency: 'urgent',
          urgencySource: 'urgency_default',
          topCondition: 'malaria',
        ),
      ]);

      expect(c.knownFindings, hasLength(1));
      expect(c.passed, isEmpty);
      expect(c.unexpectedFailures, isEmpty);
    });

    test('a drifted urgency fails rather than re-pinning', () {
      final KnownFindingsClassification c = _classify(<CaseRunResult>[
        _resultFor(
          'CB_211',
          urgency: 'emergency',
          urgencySource: 'urgency_default',
          topCondition: 'malaria',
        ),
      ]);

      expect(c.knownFindings, isEmpty);
      expect(c.unexpectedFailures, hasLength(1));
      expect(c.unexpectedFailures.single.reason, contains('urgency pinned'));
    });

    test('a drifted urgency source fails', () {
      final KnownFindingsClassification c = _classify(<CaseRunResult>[
        _resultFor(
          'CB_211',
          urgency: 'urgent',
          urgencySource: 'demographic_escalation',
          topCondition: 'malaria',
        ),
      ]);

      expect(c.unexpectedFailures, hasLength(1));
      expect(
        c.unexpectedFailures.single.reason,
        contains('urgency_source pinned'),
      );
    });

    test('a drifted top condition fails', () {
      final KnownFindingsClassification c = _classify(<CaseRunResult>[
        _resultFor(
          'CB_211',
          urgency: 'urgent',
          urgencySource: 'urgency_default',
          topCondition: 'cholera',
        ),
      ]);

      expect(c.unexpectedFailures, hasLength(1));
      expect(
        c.unexpectedFailures.single.reason,
        contains('top_condition pinned'),
      );
    });

    test('a drifted red flag flag fails', () {
      final KnownFindingsClassification c = _classify(<CaseRunResult>[
        _resultFor(
          'CB_211',
          urgency: 'urgent',
          urgencySource: 'urgency_default',
          topCondition: 'malaria',
          redFlagTriggered: true,
        ),
      ]);

      expect(c.unexpectedFailures, hasLength(1));
      expect(
        c.unexpectedFailures.single.reason,
        contains('red_flag_triggered pinned'),
      );
    });

    test(
      'an apparent improvement is NOT an automatic pass — the registry is stale',
      () {
        // The case now matches the bank expectation the registry says it
        // misses. That is a real change and must be reviewed, not celebrated.
        final KnownFindingsClassification c = _classify(<CaseRunResult>[
          _resultFor(
            'CB_211',
            urgency: 'non_urgent',
            urgencySource: 'empty_default',
            topCondition: null,
          ),
        ]);

        expect(c.passed, isEmpty);
        expect(c.knownFindings, isEmpty);
        expect(c.unexpectedFailures, hasLength(1));
        expect(
          c.unexpectedFailures.single.reason,
          allOf(contains('stale'), contains('not an automatic pass')),
        );
      },
    );

    test('a registered finding that throws fails', () {
      final KnownFindingsClassification c = _classify(<CaseRunResult>[
        _resultFor(
          'CB_211',
          urgency: null,
          urgencySource: null,
          topCondition: null,
          error: 'ArgumentError: unknown token',
        ),
      ]);

      expect(c.unexpectedFailures, hasLength(1));
      expect(c.unexpectedFailures.single.reason, contains('now throws'));
    });

    test('an additional unregistered mismatch fails', () {
      // CB_001 expects urgent/urgency_default/malaria. Returning something
      // else must fail: the registry covers CB_211 and nothing more.
      final KnownFindingsClassification c = _classify(<CaseRunResult>[
        _resultFor(
          'CB_211',
          urgency: 'urgent',
          urgencySource: 'urgency_default',
          topCondition: 'malaria',
        ),
        _resultFor(
          'CB_001',
          urgency: 'self_care',
          urgencySource: 'urgency_default',
          topCondition: 'malaria',
        ),
      ]);

      expect(c.knownFindings, hasLength(1));
      expect(c.unexpectedFailures, hasLength(1));
      expect(c.unexpectedFailures.single.caseId, 'CB_001');
      expect(
        c.unexpectedFailures.single.reason,
        contains('unregistered mismatch'),
      );
    });

    test('a registered case dropped from the run is detected', () {
      final KnownFindingsClassification c = _classify(<CaseRunResult>[
        _resultFor(
          'CB_001',
          urgency: 'urgent',
          urgencySource: 'urgency_default',
          topCondition: 'malaria',
        ),
      ]);

      expect(c.registeredButNotExecuted, <String>{'CB_211'});
      expect(
        c.reconciles,
        isFalse,
        reason: 'A registered case that never ran must break reconciliation.',
      );
    });

    test('a known finding is never reported as passed', () {
      final KnownFindingsClassification c = _classify(<CaseRunResult>[
        _resultFor(
          'CB_211',
          urgency: 'urgent',
          urgencySource: 'urgency_default',
          topCondition: 'malaria',
        ),
      ]);

      final Map<String, dynamic> json = c.toJson();
      expect(json['passed'], 0);
      expect(json['known_findings'], 1);
      expect(
        (json['known_finding_detail'] as List<dynamic>).first,
        containsPair('counted_as_passed', false),
      );
    });
  });
}
