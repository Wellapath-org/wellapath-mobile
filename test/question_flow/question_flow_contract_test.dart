/// Contract-drift, publication and runtime-isolation guards for the vendored
/// Question Flow 1.0 candidate.
///
/// Never skips. A missing fixture is a CI failure, and so is a changed one.
///
/// The publication and isolation assertions are the load-bearing ones: the
/// candidate is clinically unreviewed with unapproved content, so a change to
/// its release status, or its appearance in a runtime asset, is a decision
/// people have to make — not something that arrives in a fixture bump.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'question_flow_contract.dart';

Map<String, dynamic> _candidate() =>
    jsonDecode(File(kFlowCandidatePath).readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('vendored contract integrity', () {
    test('every contract file is present', () {
      final List<String> missing = <String>[
        for (final FlowContractFile f in kFlowContractFiles)
          if (!File('$kFlowFixtureRoot/${f.destinationPath}').existsSync())
            f.destinationPath,
      ];
      expect(
        missing,
        isEmpty,
        reason:
            'Missing vendored contract files: ${missing.join(', ')}. Re-vendor '
            'byte-for-byte from $kFlowSourceRepository@$kFlowSourceCommit.',
      );
    });

    test('every contract file matches its authoritative sha256 and size', () {
      final List<String> drift = <String>[];
      for (final FlowContractFile f in kFlowContractFiles) {
        final File file = File('$kFlowFixtureRoot/${f.destinationPath}');
        if (!file.existsSync()) continue;
        final List<int> bytes = file.readAsBytesSync();
        final String actual = sha256.convert(bytes).toString();
        if (actual != f.sha256 || bytes.length != f.bytes) {
          drift.add(
            '${f.destinationPath}: expected ${f.sha256} (${f.bytes}B), got '
            '$actual (${bytes.length}B)',
          );
        }
      }
      expect(drift, isEmpty, reason: drift.join('\n'));
    });

    test('the five handoff hashes match the published values', () {
      String hashOf(String rel) => sha256
          .convert(File('$kFlowFixtureRoot/$rel').readAsBytesSync())
          .toString();

      expect(
        hashOf('candidate/question_flow.ng.v1.0.json'),
        'c403648f8d4d80184879f4d467d4ae74e63df5be77c461298754b82737024998',
      );
      expect(
        hashOf('schema/question_flow.v1.schema.json'),
        '4b9f09384842968c2c093e2d4a1b246447eaef896980feff84da36d4fdbd4726',
      );
      expect(
        hashOf('handoff/question_flow_types.dart.txt'),
        '4576fb2277d50a2b6bed445a4be4547a615629b8f8bb7b3c82831fc932fba53a',
      );
      expect(
        hashOf('reports/question_baseline_freeze_v1.json'),
        '031f3f8fd830e9ec9a476aab2b7d27634b3d75553e76ded239c5926e936387b3',
      );
      expect(
        hashOf('reports/qb002_evidence_v1.json'),
        '3a82e89571371344271302aaa2a9bcd640fb0582a0dc7c1a54f6270c163b4f8a',
      );
    });

    test('all 23 invalid fixtures named by the index are vendored', () {
      final Map<String, dynamic> index =
          jsonDecode(
                File('$kFlowFixtureRoot/invalid/index.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final List<String> files = (index['fixtures'] as List<dynamic>)
          .map((dynamic f) => (f as Map<String, dynamic>)['file'] as String)
          .toList();

      expect(files, hasLength(23));
      for (final String f in files) {
        expect(
          File('$kFlowFixtureRoot/invalid/$f').existsSync(),
          isTrue,
          reason: 'Invalid fixture $f is not vendored.',
        );
      }
    });
  });

  group('candidate publication state', () {
    late Map<String, dynamic> metadata;

    setUpAll(
      () => metadata = _candidate()['_metadata'] as Map<String, dynamic>,
    );

    test('version and schema version are unchanged', () {
      expect(metadata['version'], kFlowVersion);
      expect(metadata['schema_version'], kFlowSchemaVersion);
    });

    test('release_status is still candidate_unapproved', () {
      expect(
        metadata['release_status'],
        kFlowReleaseStatus,
        reason:
            'Publication is a separately reviewed decision and cannot arrive '
            'through a fixture update.',
      );
    });

    test('may_publish is false', () {
      expect(metadata['may_publish'], isFalse);
    });

    test('clinical review has not become approved', () {
      expect(
        (metadata['clinical_review'] as Map<String, dynamic>)['status'],
        kFlowClinicalReviewStatus,
      );
    });

    test('no question content is marked approved', () {
      final List<String> approved = <String>[
        for (final dynamic q in _candidate()['questions'] as List<dynamic>)
          if (((q as Map<String, dynamic>)['content_ref']
                  as Map<String, dynamic>)['content_approved'] ==
              true)
            q['question_id'] as String,
      ];
      expect(
        approved,
        isEmpty,
        reason:
            'Question content became approved: ${approved.take(5).join(', ')}. '
            'Preserving shipped wording is not the same as approving it.',
      );
    });

    test('question and answer-option counts are unchanged', () {
      final List<dynamic> qs = _candidate()['questions'] as List<dynamic>;
      expect(qs, hasLength(kFlowQuestionCount));
      final int options = qs.fold<int>(
        0,
        (int sum, dynamic q) =>
            sum +
            ((q as Map<String, dynamic>)['answer_options'] as List<dynamic>)
                .length,
      );
      expect(options, kFlowAnswerOptionCount);
    });

    test('the path limit is still 5', () {
      final Map<String, dynamic> controls =
          _candidate()['path_controls'] as Map<String, dynamic>;
      expect(controls['max_followup_questions'], kFlowPathLimit);
      expect(controls['red_flag_questions_exempt_from_truncation'], isTrue);
    });

    test('no optional skip is enabled', () {
      int skippable = 0;
      int sentinels = 0;
      for (final dynamic q in _candidate()['questions'] as List<dynamic>) {
        final Map<String, dynamic> question = q as Map<String, dynamic>;
        if (question['skippable'] == true) skippable++;
        for (final dynamic o in question['answer_options'] as List<dynamic>) {
          if ((o as Map<String, dynamic>)['is_skip_sentinel'] == true) {
            sentinels++;
          }
        }
      }
      expect(skippable, kFlowOptionalSkipCount);
      expect(sentinels, kFlowOptionalSkipCount);
    });

    test('all seven impedance mismatches are disclosed', () {
      final List<String> ids = <String>[
        for (final dynamic im
            in metadata['impedance_mismatches'] as List<dynamic>)
          (im as Map<String, dynamic>)['id'] as String,
      ];
      expect(metadata['impedance_mismatch_count'], 7);
      expect(
        ids,
        containsAll(<String>[
          'IM-001',
          'IM-002',
          'IM-003',
          'IM-004',
          'IM-005',
          'IM-006',
          'IM-007',
        ]),
      );
    });

    test('the dispositions still say what this work relies on', () {
      final Map<String, dynamic> decisions =
          (metadata['engineering_dispositions']
                  as Map<String, dynamic>)['decisions']
              as Map<String, dynamic>;

      expect(
        (decisions['im_001_deterministic_ordering']
            as Map<String, dynamic>)['status'],
        'adopted_for_candidate_and_internal_implementation',
      );
      expect(
        (decisions['im_002_immediate_red_flag_evaluation']
            as Map<String, dynamic>)['status'],
        'adopted_required_safety_correction',
      );
      expect(
        (decisions['skip_behaviour'] as Map<String, dynamic>)['status'],
        'activation_deferred',
      );
      expect(
        (decisions['path_length_limit'] as Map<String, dynamic>)['value'],
        kFlowPathLimit,
      );

      final Map<String, dynamic> dist =
          decisions['distribution_model'] as Map<String, dynamic>;
      expect(dist['backend_distribution'], isFalse);
      expect(dist['config_entry'], isFalse);
      expect(dist['r2_upload'], isFalse);
      expect(dist['live_manifest_entry'], isFalse);

      final Map<String, dynamic> record =
          metadata['engineering_dispositions'] as Map<String, dynamic>;
      expect(record['is_clinical_approval'], isFalse);
      expect(record['is_product_approval'], isFalse);
    });

    test('IM-003 remains deferred in the contract record', () {
      final String blob = jsonEncode(metadata['impedance_mismatches']);
      expect(
        blob.contains('IM-003'),
        isTrue,
        reason: 'IM-003 must remain disclosed.',
      );
    });

    test('Vocabulary 2.0 does not participate in question eligibility', () {
      expect(
        (metadata['vocabulary_2_0'] as Map<String, dynamic>)['used'],
        isFalse,
      );
    });

    test('the frozen clinical inputs are the current live set', () {
      final Map<String, dynamic> frozen =
          metadata['frozen_clinical_inputs'] as Map<String, dynamic>;
      expect(frozen['token_dictionary_v1_1'], kLiveTokenDictionarySha);
      expect(
        frozen['kb_v2_4'],
        '6c00d8257f8417e86bd5e237630bf8a4623ad72e2e46b1b071dd447c067cec2b',
      );
      expect(
        frozen['rules_v2_2'],
        '1d27e854cba95b179577a88f92445400f494a7fe8e6a53a60fcaa98b3870d1c4',
      );
    });
  });

  group('the candidate is not wired into the app', () {
    test('it is not declared as a Flutter asset', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('question_flow'), isFalse);
      expect(pubspec.contains('test/fixtures'), isFalse);
    });

    test('no question flow file lives under assets/', () {
      final Directory assets = Directory('assets');
      if (!assets.existsSync()) return;
      final List<String> offenders = assets
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.contains('question_flow'))
          .map((File f) => f.path)
          .toList();
      expect(offenders, isEmpty);
    });

    test('no live assessment source imports the flow consumer', () {
      // The boundary that keeps this disconnected from the live path.
      const List<String> liveSources = <String>[
        'lib/features/assessment/question_engine.dart',
        'lib/features/assessment/assessment_controller.dart',
        'lib/features/assessment/followup_screen.dart',
        'lib/features/assessment/loading_screen.dart',
        'lib/features/assessment/symptom_selection_screen.dart',
        'lib/features/assessment/body_area_screen.dart',
        'lib/features/assessment/intro_screen.dart',
        'lib/features/assessment/sex_screen.dart',
        'lib/features/assessment/age_screen.dart',
        'lib/features/assessment/pregnancy_screen.dart',
        'lib/features/assessment/medical_conditions_screen.dart',
        'lib/main.dart',
        'lib/app.dart',
      ];
      for (final String path in liveSources) {
        final File f = File(path);
        if (!f.existsSync()) continue;
        // Imports, not raw text: followup_screen.dart legitimately cites the
        // handoff path `mobile_handoff/question_flow_v1/IM002_SAFETY_FIX.md`
        // in a doc comment. What must not exist is a code dependency.
        final List<String> imports = f
            .readAsStringSync()
            .split('\n')
            .where((String l) => l.trimLeft().startsWith('import '))
            .toList();
        expect(
          imports.any((String l) => l.contains('question_flow')),
          isFalse,
          reason: '$path imports the question flow consumer.',
        );
      }
    });

    test('nothing outside lib/core/question_flow imports the consumer', () {
      final List<String> offenders = <String>[];
      for (final FileSystemEntity e in Directory(
        'lib',
      ).listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        if (e.path.contains('lib/core/question_flow/')) continue;
        if (e.readAsStringSync().contains('core/question_flow')) {
          offenders.add(e.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'The W3 consumer is imported by application code: '
            '${offenders.join(', ')}. It must stay reachable from tests only.',
      );
    });

    test('the consumer performs no I/O and no network', () {
      const List<String> consumerFiles = <String>[
        'lib/core/question_flow/question_flow_loader.dart',
        'lib/core/question_flow/condition_evaluator.dart',
        'lib/core/question_flow/question_ordering.dart',
        'lib/core/question_flow/initial_path_planner.dart',
        'lib/core/question_flow/flow_answer_state.dart',
        'lib/core/question_flow/question_flow_models.dart',
      ];
      for (final String path in consumerFiles) {
        // Imports and code, not doc comments: flow_answer_state.dart's header
        // deliberately lists telemetry among the things it is NOT connected
        // to, and that sentence is the point rather than a violation.
        final List<String> code = File(path)
            .readAsStringSync()
            .split('\n')
            .where((String l) => !l.trimLeft().startsWith('///'))
            .where((String l) => !l.trimLeft().startsWith('//'))
            .toList();
        final String src = code.join('\n');
        for (final String forbidden in const <String>[
          'dart:io',
          'package:dio',
          'HttpClient',
          'api_client',
          'staged_artifact_loader',
          'telemetry',
          'rootBundle',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '$path references "$forbidden" in code.',
          );
        }
      }
    });

    test('no build flag can enable the consumer', () {
      for (final FileSystemEntity e in Directory(
        'lib/core/question_flow',
      ).listSync()) {
        if (e is! File) continue;
        final String src = e.readAsStringSync();
        expect(src.contains('fromEnvironment'), isFalse);
        expect(src.contains('Platform.environment'), isFalse);
      }
    });

    test('the consumer never references scoring or the engine', () {
      for (final FileSystemEntity e in Directory(
        'lib/core/question_flow',
      ).listSync()) {
        if (e is! File) continue;
        final List<String> imports = e
            .readAsStringSync()
            .split('\n')
            .where((String l) => l.trimLeft().startsWith('import '))
            .toList();
        for (final String forbidden in const <String>[
          'scoring_engine',
          'engine_controller',
          'red_flag_evaluator',
          'urgency_determiner',
          'assessment_controller',
        ]) {
          expect(
            imports.any((String l) => l.contains(forbidden)),
            isFalse,
            reason: '${e.path} imports $forbidden',
          );
        }
      }
    });
  });
}
