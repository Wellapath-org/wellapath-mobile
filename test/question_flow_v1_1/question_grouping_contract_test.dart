/// Handoff integrity: every vendored 1.1 file is byte-identical to the
/// knowledge base, and the artifact is what it claims to be.
///
/// A hash recorded in a commit message is a claim. A hash asserted in a test
/// is a fact, re-established on every run.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';

import '../question_flow/question_flow_contract.dart';
import 'grouping_test_support.dart';
import 'question_grouping_contract.dart';

String _sha256(File file) => sha256.convert(file.readAsBytesSync()).toString();

void main() {
  group('vendored 1.1 contract integrity', () {
    test('every file matches its knowledge-base hash and byte count', () {
      expect(kGroupingContractFiles, hasLength(36));
      final List<String> problems = <String>[];
      for (final GroupingContractFile f in kGroupingContractFiles) {
        final File file = File('$kGroupingFixtureRoot/${f.destinationPath}');
        if (!file.existsSync()) {
          problems.add('${f.destinationPath}: missing');
          continue;
        }
        final int bytes = file.lengthSync();
        final String digest = _sha256(file);
        if (bytes != f.bytes) {
          problems.add('${f.destinationPath}: ${f.bytes} B expected, $bytes B');
        }
        if (digest != f.sha256) {
          problems.add('${f.destinationPath}: sha256 ${f.sha256} -> $digest');
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('every recorded hash is a full sha256, not an abbreviation', () {
      for (final GroupingContractFile f in kGroupingContractFiles) {
        expect(
          f.sha256,
          matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: '${f.destinationPath} carries a non-full hash',
        );
      }
    });

    test('no vendored file is empty', () {
      for (final GroupingContractFile f in kGroupingContractFiles) {
        expect(f.bytes, greaterThan(0), reason: f.destinationPath);
      }
    });
  });

  group('authoritative controls', () {
    test('candidate 1.1 byte count', () {
      expect(File(kGroupingCandidatePath).lengthSync(), kCandidate11Bytes);
    });

    test('oracle byte count and case counts', () {
      expect(File(kOraclePath).lengthSync(), kOracleBytes);
      final Map<String, dynamic> doc = oracle();
      final int forward = (doc['forward'] as List<dynamic>).length;
      final int reversed = (doc['reversed'] as List<dynamic>).length;
      expect(forward, kOracleForwardCases);
      expect(reversed, kOracleReversedCases);
      expect(forward + reversed, kOracleTotalCases);
    });

    test('22 invalid grouping fixtures, index agrees with the directory', () {
      final Map<String, dynamic> index = readJson(
        '$kInvalidGroupingDir/index.json',
      );
      final List<dynamic> fixtures = index['fixtures'] as List<dynamic>;
      expect(fixtures, hasLength(kInvalidGroupingFixtureCount));

      final Set<String> onDisk = Directory(kInvalidGroupingDir)
          .listSync()
          .whereType<File>()
          .map((File f) => f.uri.pathSegments.last)
          .where((String n) => n != 'index.json')
          .toSet();
      final Set<String> declared = <String>{
        for (final Object? f in fixtures)
          (f as Map<String, dynamic>)['file'] as String,
      };
      expect(onDisk, declared);
    });

    test('16 grouped path fixtures', () {
      final Map<String, dynamic> doc = readJson(kGroupingPathFixturesPath);
      final Map<String, dynamic> meta =
          doc['_metadata'] as Map<String, dynamic>;
      expect(meta['case_count'], kGroupedPathFixtureCount);
      expect((doc['cases'] as List<dynamic>).length, kGroupedPathFixtureCount);
    });

    test('135 Product wording decisions, every one still pending', () {
      final Map<String, dynamic> report = readJson(kIm001ReviewReportPath);
      final Map<String, dynamic> scope =
          report['scope'] as Map<String, dynamic>;
      expect(scope['distinct_wording_decisions'], kPendingProductDecisions);

      final List<dynamic> decisions = report['decisions'] as List<dynamic>;
      expect(decisions, hasLength(kPendingProductDecisions));
      for (final Object? d in decisions) {
        final Map<String, dynamic> decision = d as Map<String, dynamic>;
        expect(
          decision['product_verdict'],
          'PENDING',
          reason:
              '${decision['decision_id']} is no longer pending. This consumer '
              'must never mark a Product decision resolved.',
        );
        expect(decision['product_reviewer'], isNull);
        expect(decision['review_date'], isNull);
      }
      final Map<String, dynamic> signOff =
          report['sign_off'] as Map<String, dynamic>;
      expect(signOff['status'], 'PENDING');
      expect(signOff['blocks_activation'], isTrue);
    });
  });

  group('oracle provenance', () {
    test('names the Mobile commit and symbol this consumer expects', () {
      final Map<String, dynamic> meta =
          oracle()['_metadata'] as Map<String, dynamic>;
      expect(meta['source_commit'], kOracleMobileSourceCommit);
      expect(meta['source_symbol'], kOracleSourceSymbol);
      expect(meta['source_repository'], 'Wellapath-org/wellapath-mobile');
    });

    test('the sidecar pins the exact fixture bytes on disk', () {
      final Map<String, dynamic> provenance = readJson(kOracleProvenancePath);
      final Map<String, dynamic> fixture =
          provenance['fixture'] as Map<String, dynamic>;
      expect(fixture['sha256'], _sha256(File(kOraclePath)));
      expect(fixture['bytes'], File(kOraclePath).lengthSync());
      expect(fixture['total_cases'], kOracleTotalCases);

      final Map<String, dynamic> capture =
          provenance['capture'] as Map<String, dynamic>;
      expect(capture['evidence_class'], 'CAPTURED_DART');
      expect(capture['source_commit'], kOracleMobileSourceCommit);
    });

    test(
      'forward inputs are sorted; reversed inputs are their exact reverse',
      () {
        final Map<String, dynamic> doc = oracle();
        final Map<String, List<String>> forwardByKey = <String, List<String>>{};
        for (final OracleCase c in oracleCases(doc, 'forward')) {
          final List<String> sorted = List<String>.of(c.inputTokens)..sort();
          expect(
            c.inputTokens,
            sorted,
            reason: 'forward case ${c.inputTokens} is not in sorted order',
          );
          forwardByKey[c.key] = c.inputTokens;
        }
        for (final OracleCase c in oracleCases(doc, 'reversed')) {
          final List<String>? forward = forwardByKey[c.key];
          expect(
            forward,
            isNotNull,
            reason: 'reversed case has no counterpart',
          );
          expect(c.inputTokens, forward!.reversed.toList());
          expect(
            c.inputTokens.length,
            greaterThan(1),
            reason: 'a 0- or 1-token reversal would duplicate a forward case',
          );
        }
      },
    );

    test('records no demographic state, because the engine reads none', () {
      // `generateQuestions` takes only the selected token list. A fixture
      // carrying sex, age or pregnancy would mean the capture recorded state
      // the function never reads — and would be PHI-shaped besides.
      const Set<String> forbidden = <String>{
        'sex',
        'age',
        'age_token',
        'pregnancy',
        'body_area',
        'medical_conditions',
        'patient_id',
        'device_id',
        'session_id',
      };
      final String raw = File(kOraclePath).readAsStringSync();
      final Map<String, dynamic> doc = jsonDecode(raw) as Map<String, dynamic>;
      for (final String direction in <String>['forward', 'reversed']) {
        for (final Object? c in doc[direction] as List<dynamic>) {
          final Map<String, dynamic> caseMap = c as Map<String, dynamic>;
          expect(caseMap.keys.toSet(), <String>{'input_tokens', 'questions'});
          for (final Object? q in caseMap['questions'] as List<dynamic>) {
            final Map<String, dynamic> question = q as Map<String, dynamic>;
            expect(question.keys.toSet(), <String>{
              'role',
              'question_text',
              'options',
              'red_flag_token',
            });
            for (final String key in question.keys) {
              expect(forbidden.contains(key), isFalse);
            }
          }
        }
      }
    });
  });

  group('candidate 1.1 identity and publication state', () {
    test('is the version and schema this consumer implements', () {
      final FlowMetadata meta = groupedFlow().metadata;
      expect(meta.version, kGroupingVersion);
      expect(meta.schemaVersion, kGroupingSchemaVersion);
      expect(meta.artifactId, 'question_flow');
    });

    test('remains unpublished, unreviewed and inactive', () {
      final FlowMetadata meta = groupedFlow().metadata;
      expect(meta.releaseStatus, kGroupingReleaseStatus);
      expect(meta.mayPublish, isFalse);
      expect(meta.clinicalReviewStatus, kGroupingClinicalReviewStatus);
      expect(meta.vocabulary20Used, isFalse);
    });

    test('no question content is marked approved', () {
      for (final FlowQuestion q in groupedFlow().questions) {
        expect(q.contentApproved, isFalse, reason: q.id.value);
      }
    });

    test('supersession names 1.0 as a retained engineering candidate', () {
      final Map<String, dynamic> meta =
          groupedCandidateJson()['_metadata'] as Map<String, dynamic>;
      final Map<String, dynamic> supersedes =
          meta['supersedes'] as Map<String, dynamic>;
      expect(supersedes['version'], '1.0');
      expect(supersedes['sha256'], kCandidate10Sha);
      expect(supersedes['status'], 'superseded_retained');
      expect(supersedes['migration'], isNotEmpty);
    });
  });

  group('candidate 1.0 remains immutable', () {
    test('candidate and schema 1.0 still match their frozen hashes', () {
      expect(_sha256(File(kFlowCandidatePath)), kCandidate10Sha);
      expect(
        _sha256(File('$kFlowFixtureRoot/schema/question_flow.v1.schema.json')),
        kSchema10Sha,
      );
    });
  });
}
