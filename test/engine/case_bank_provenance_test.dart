/// Deterministic provenance and drift guard for the vendored case bank.
///
/// The case bank is authored in `wellapath-knowledge-base` and vendored here
/// byte-for-byte so the clinical regression is reproducible from this commit
/// alone — no network call, no dependence on whatever that repo happens to
/// serve later. This file is what makes "byte-for-byte" enforceable rather
/// than a claim in a commit message.
///
/// Authoritative source:
///   repository : Wellapath-org/wellapath-knowledge-base
///   commit     : dceecde2ee7545664bf45ea5edfa137a52acdebd
///   path       : testing/case_bank_v1.json
///   version    : 1.0
///   bytes      : 138,988
///   sha256     : c7bdc434…d998834 (full value in [_expectedSha256])
///   cases      : 239 (CB_001 … CB_239)
///
/// Supported artifact combination: kb.ng.v2.4 / rules.ng.v2.2 /
/// token_dictionary.ng.v1.1 — pinned and hash-verified separately by
/// `case_bank/artifact_fixtures.dart`.
///
/// Unlike `case_bank_validation_test.dart`, this file never skips. A missing
/// fixture is a CI failure here by design: a silently skipped clinical
/// regression is indistinguishable from a passing one, which is the exact
/// failure mode this guard exists to prevent.
///
/// If the knowledge base publishes a new bank, update every constant below
/// *and* re-run the full 239-case regression. Refreshing the hash on its own
/// converts a real drift signal into a rubber stamp.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const String _fixturePath = 'test/fixtures/case_bank_v1.json';

const String _sourceRepository = 'Wellapath-org/wellapath-knowledge-base';
const String _sourceCommit = 'dceecde2ee7545664bf45ea5edfa137a52acdebd';
const String _sourcePath = 'testing/case_bank_v1.json';

const String _expectedSha256 =
    'c7bdc434a33d341e21e015f0defe567274d7f6271c332352b19ba21e7d998834';
const int _expectedBytes = 138988;
const String _expectedVersion = '1.0';
const int _expectedCaseCount = 239;
const String _caseIdPrefix = 'CB_';

/// The three cases the bank ships with `expected_urgency_source: "observe"`.
/// Pinned because the harness grades every other case, and an observe case
/// quietly turning into a graded one (or vice versa) would move the pass rate
/// without any expected value having visibly changed.
const List<String> _observeCaseIds = <String>['CB_225', 'CB_232', 'CB_233'];

File get _fixture => File(_fixturePath);

void main() {
  group('case bank provenance', () {
    test('fixture is present', () {
      expect(
        _fixture.existsSync(),
        isTrue,
        reason:
            'Missing $_fixturePath. Vendor it byte-for-byte from '
            '$_sourceRepository at $_sourceCommit ($_sourcePath). '
            'The clinical regression must never skip for want of its fixture.',
      );
    });

    test('byte count matches the authoritative source', () {
      expect(
        _fixture.readAsBytesSync().length,
        _expectedBytes,
        reason:
            'Case bank byte count drifted. Expected $_expectedBytes bytes '
            'from $_sourceRepository@$_sourceCommit. Any reformat, '
            'reserialise or line-ending change breaks byte identity.',
      );
    });

    test('sha256 matches the authoritative source', () {
      final String actual = sha256
          .convert(_fixture.readAsBytesSync())
          .toString();
      expect(
        actual,
        _expectedSha256,
        reason:
            'Case bank content drifted from $_sourceRepository@$_sourceCommit '
            '($_sourcePath). Expected $_expectedSha256, got $actual. Do not '
            'refresh this hash without re-running the full 239-case '
            'regression — the hash is the evidence, not the formality.',
      );
    });

    group('structure', () {
      late Map<String, dynamic> decoded;
      late List<Map<String, dynamic>> cases;

      setUpAll(() {
        decoded =
            jsonDecode(_fixture.readAsStringSync()) as Map<String, dynamic>;
        cases = (decoded['cases'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
      });

      test('declared version matches', () {
        final Map<String, dynamic> metadata =
            decoded['_metadata'] as Map<String, dynamic>;
        expect(metadata['version'], _expectedVersion);
      });

      test('declared case count matches', () {
        final Map<String, dynamic> metadata =
            decoded['_metadata'] as Map<String, dynamic>;
        expect(
          metadata['total_cases'],
          _expectedCaseCount,
          reason:
              'The bank\'s own _metadata.total_cases disagrees with the '
              'handoff contract.',
        );
      });

      test('actual case count matches the declared count', () {
        expect(
          cases.length,
          _expectedCaseCount,
          reason:
              'Declared ${decoded['_metadata']['total_cases']} cases but the '
              '"cases" list holds ${cases.length}. A bank that miscounts '
              'itself cannot be graded.',
        );
      });

      test('case ids are unique', () {
        final List<String> ids = cases
            .map((Map<String, dynamic> c) => c['case_id'] as String)
            .toList();
        final Set<String> unique = ids.toSet();
        expect(
          unique.length,
          ids.length,
          reason:
              'Duplicate case ids: '
              '${(ids.toSet().where((String id) => ids.where((String i) => i == id).length > 1).toList()..sort()).join(', ')}',
        );
      });

      test('case ids span CB_001 through CB_239 with no gaps', () {
        final Set<String> actual = cases
            .map((Map<String, dynamic> c) => c['case_id'] as String)
            .toSet();
        final Set<String> expected = <String>{
          for (int i = 1; i <= _expectedCaseCount; i++)
            '$_caseIdPrefix${i.toString().padLeft(3, '0')}',
        };

        expect(
          actual.difference(expected).toList()..sort(),
          isEmpty,
          reason: 'Unexpected case ids outside the CB_001..CB_239 range.',
        );
        expect(
          expected.difference(actual).toList()..sort(),
          isEmpty,
          reason: 'Missing case ids from the CB_001..CB_239 range.',
        );
      });

      test('observe cases are exactly the three the handoff names', () {
        final List<String> observed =
            cases
                .where(
                  (Map<String, dynamic> c) =>
                      c['expected_urgency_source'] == 'observe',
                )
                .map((Map<String, dynamic> c) => c['case_id'] as String)
                .toList()
              ..sort();

        expect(
          observed,
          _observeCaseIds,
          reason:
              'The set of ungraded observe cases changed. These are excluded '
              'from the pass rate, so a change here moves the reported number '
              'without any expected value appearing to change.',
        );
      });

      test('every case carries the fields the harness grades on', () {
        final List<String> malformed = <String>[];
        for (final Map<String, dynamic> c in cases) {
          final bool ok =
              c['case_id'] is String &&
              c['input_tokens'] is List &&
              c['demographic_tokens'] is List &&
              c['safety_critical'] is bool &&
              // Null on observe cases by design; any other type is malformed.
              (c['expected_urgency'] == null ||
                  c['expected_urgency'] is String);
          if (!ok) malformed.add(c['case_id']?.toString() ?? '(no case_id)');
        }

        expect(
          malformed,
          isEmpty,
          reason:
              'Cases missing or mistyping graded fields: '
              '${malformed.join(', ')}',
        );
      });
    });
  });
}
