/// Runtime isolation for the 1.1 consumer, and the absence of IM-003.
///
/// The 1.0 consumer's isolation is already asserted in
/// `test/question_flow/question_flow_contract_test.dart`. This file extends
/// the same guarantees to everything 1.1 adds — the grouping models, the
/// grouped planner, candidate 1.1 and the 4 MB oracle — and asserts them
/// STRUCTURALLY rather than promising them in a document.
///
/// The oracle matters here in its own right: at 4 MB it is by far the largest
/// file this branch adds, and shipping it in an app bundle would be a
/// user-visible cost for evidence no user needs.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/question_flow/grouped_path_planner.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';

import 'grouping_test_support.dart';
import 'question_grouping_contract.dart';

/// Files added or extended by the 1.1 consumer.
const List<String> kGroupingConsumerSources = <String>[
  'lib/core/question_flow/question_grouping_models.dart',
  'lib/core/question_flow/grouped_path_planner.dart',
  'lib/core/question_flow/question_flow_loader.dart',
  'lib/core/question_flow/question_flow_models.dart',
];

/// The live assessment and engine sources that must not reach the consumer.
List<File> _liveAssessmentSources() => <File>[
  ...Directory('lib/features/assessment')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart')),
  ...Directory('lib/core/engine')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart')),
];

void main() {
  group('the 1.1 consumer is not wired into the app', () {
    test('no live assessment or engine source imports it', () {
      final List<String> offenders = <String>[];
      for (final File file in _liveAssessmentSources()) {
        final String source = file.readAsStringSync();
        for (final String line in source.split('\n')) {
          final String trimmed = line.trim();
          if (!trimmed.startsWith('import ') &&
              !trimmed.startsWith('export ') &&
              !trimmed.startsWith('part ')) {
            continue;
          }
          if (trimmed.contains('question_flow/') ||
              trimmed.contains('grouped_path_planner') ||
              trimmed.contains('question_grouping_models')) {
            offenders.add('${file.path}: $trimmed');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('QuestionEngine and AssessmentController do not import it', () {
      for (final String path in <String>[
        'lib/features/assessment/question_engine.dart',
        'lib/features/assessment/assessment_controller.dart',
      ]) {
        final String source = File(path).readAsStringSync();
        expect(source.contains('question_flow/'), isFalse, reason: path);
        expect(source.contains('grouped_path_planner'), isFalse, reason: path);
      }
    });

    test('nothing outside lib/core/question_flow imports the consumer', () {
      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity in Directory(
        'lib',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.startsWith('lib/core/question_flow/')) continue;
        for (final String line in entity.readAsStringSync().split('\n')) {
          final String trimmed = line.trim();
          if ((trimmed.startsWith('import ') ||
                  trimmed.startsWith('export ')) &&
              trimmed.contains('question_flow')) {
            offenders.add('${entity.path}: $trimmed');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('app startup does not initialise it', () {
      for (final String path in <String>['lib/main.dart', 'lib/app.dart']) {
        final String source = File(path).readAsStringSync();
        expect(source.contains('question_flow'), isFalse, reason: path);
        expect(source.contains('planGrouped'), isFalse, reason: path);
      }
    });

    test('no build flag can enable it', () {
      for (final String path in kGroupingConsumerSources) {
        final String source = File(path).readAsStringSync();
        expect(
          source.contains('fromEnvironment'),
          isFalse,
          reason: '$path contains a compile-time switch',
        );
      }
    });

    test('it imports no networking, telemetry, scoring or controller', () {
      const List<String> forbidden = <String>[
        'dart:io',
        'dio',
        'http',
        'shared_preferences',
        'hive',
        'telemetry',
        'scoring_engine',
        'red_flag_evaluator',
        'engine_controller',
        'assessment_controller',
        'api_client',
      ];
      for (final String path in kGroupingConsumerSources) {
        for (final String line in File(path).readAsStringSync().split('\n')) {
          final String trimmed = line.trim();
          if (!trimmed.startsWith('import ') &&
              !trimmed.startsWith('export ')) {
            continue;
          }
          for (final String needle in forbidden) {
            expect(
              trimmed.contains(needle),
              isFalse,
              reason: '$path imports $needle: $trimmed',
            );
          }
        }
      }
    });

    test('it never constructs a widget', () {
      for (final String path in kGroupingConsumerSources) {
        final String source = File(path).readAsStringSync();
        expect(source.contains('package:flutter/material.dart'), isFalse);
        expect(source.contains('package:flutter/widgets.dart'), isFalse);
        expect(source.contains('extends StatelessWidget'), isFalse);
        expect(source.contains('extends StatefulWidget'), isFalse);
      }
    });
  });

  group('candidate 1.1 and the oracle are not runtime assets', () {
    test('pubspec declares no question-flow asset', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('question_flow'), isFalse);
      expect(pubspec.contains('live_question_oracle'), isFalse);
      expect(pubspec.contains('test/fixtures'), isFalse);
    });

    test('nothing under assets/ is a question-flow artifact', () {
      final Directory assets = Directory('assets');
      if (!assets.existsSync()) return;
      for (final FileSystemEntity entity in assets.listSync(recursive: true)) {
        if (entity is! File) continue;
        final String name = entity.uri.pathSegments.last;
        expect(name.contains('question_flow'), isFalse, reason: entity.path);
        expect(name.contains('oracle'), isFalse, reason: entity.path);
      }
    });

    test('every 1.1 fixture lives under test/, never lib/ or assets/', () {
      for (final GroupingContractFile f in kGroupingContractFiles) {
        final String path = '$kGroupingFixtureRoot/${f.destinationPath}';
        expect(path.startsWith('test/'), isTrue, reason: path);
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    });

    test('the 4 MB oracle is a test fixture only', () {
      // Bundling it would add ~4 MB to every install for evidence no user
      // needs. Asserted by location and by pubspec absence, not assumed.
      final File oracleFile = File(kOraclePath);
      expect(oracleFile.path.startsWith('test/'), isTrue);
      expect(oracleFile.lengthSync(), kOracleBytes);
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains(oracleFile.uri.pathSegments.last), isFalse);
    });

    test('the vendored Dart types are inert .txt, not compiled source', () {
      // Same convention as the 1.0 handoff: the reference types file would
      // otherwise be analysed as project source.
      final File types = File(
        '$kGroupingFixtureRoot/handoff/question_grouping_types.dart.txt',
      );
      expect(types.existsSync(), isTrue);
      expect(
        File(
          '$kGroupingFixtureRoot/handoff/question_grouping_types.dart',
        ).existsSync(),
        isFalse,
      );
      final File harness = File(
        '$kGroupingFixtureRoot/oracle/'
        'live_question_oracle_v1.harness.dart.txt',
      );
      expect(harness.existsSync(), isTrue);
    });
  });

  group('IM-003 remains absent by construction', () {
    test('the grouped planner exposes no answer-driven replanning API', () {
      final String source = File(
        'lib/core/question_flow/grouped_path_planner.dart',
      ).readAsStringSync();
      for (final String forbidden in <String>[
        'replan',
        'onAnswer',
        'recordAnswer',
        'afterAnswer',
        'reevaluate',
        'reEvaluate',
        'invalidateDependents',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: 'grouped planner exposes "$forbidden"',
        );
      }
    });

    test(
      'planning takes state and returns a plan, with no answer parameter',
      () {
        // There is nothing to call after an answer, so nothing can add, remove
        // or invalidate a question because of one.
        final QuestionFlow flow = groupedFlow();
        final GroupedPathPlan first = planTokens(flow, <String>[
          'headache',
          'fever',
        ]);
        final GroupedPathPlan second = planTokens(flow, <String>[
          'headache',
          'fever',
        ]);
        expect(second.presentedIds, first.presentedIds);
        expect(second.truncatedIds, first.truncatedIds);
      },
    );

    test('invalidates_on_change is read and never acted on', () {
      final QuestionFlow flow = groupedFlow();
      final Iterable<FlowQuestion> withInvalidation = flow.questions.where(
        (FlowQuestion q) => q.invalidatesOnChange.isNotEmpty,
      );
      expect(withInvalidation, isNotEmpty);
      // Recorded on the model...
      for (final FlowQuestion q in withInvalidation) {
        expect(q.invalidatesOnChange, isNotEmpty);
      }
      // ...and absent from the planner, which never consults it.
      final String source = File(
        'lib/core/question_flow/grouped_path_planner.dart',
      ).readAsStringSync();
      expect(source.contains('invalidatesOnChange'), isFalse);
    });

    test('no restoration, editing or skip API exists', () {
      for (final String path in kGroupingConsumerSources) {
        final String source = File(path).readAsStringSync();
        for (final String forbidden in <String>[
          'restoreFrom',
          'resumeAssessment',
          'editAnswer',
          'skipQuestion',
        ]) {
          expect(
            source.contains(forbidden),
            isFalse,
            reason: '$path $forbidden',
          );
        }
      }
    });

    test('the candidate itself still declares IM-003 deferred', () {
      final Map<String, dynamic> meta =
          groupedCandidateJson()['_metadata'] as Map<String, dynamic>;
      final List<dynamic> mismatches =
          meta['impedance_mismatches'] as List<dynamic>;
      final Map<String, dynamic> im003 = mismatches
          .cast<Map<String, dynamic>>()
          .firstWhere((Map<String, dynamic> m) => m['id'] == 'IM-003');
      expect(im003['status'], contains('deferred'));
      expect(im003['activation_blocker'], isTrue);
    });

    test('no question declares a branch condition', () {
      // Branch conditions are the data IM-003 would act on. The candidate
      // declares none, so there is nothing to re-branch on even in principle.
      final Map<String, dynamic> doc = groupedCandidateJson();
      for (final Object? q in doc['questions'] as List<dynamic>) {
        final Map<String, dynamic> question = q as Map<String, dynamic>;
        expect(
          (question['branch_conditions'] as List<dynamic>?) ??
              const <dynamic>[],
          isEmpty,
          reason: question['question_id'] as String,
        );
      }
    });
  });

  group('grouping safety invariants hold on every plan', () {
    late QuestionFlow flow;

    setUpAll(() => flow = groupedFlow());

    test('grouping happens before truncation, never after', () {
      // If truncation ran first, a path with three clarifiers plus three
      // un-merged follow-ups would drop a question the live engine asks.
      // Asserted through behaviour: with 3 clarifiers eligible, the merged
      // follow-ups still fit and exactly one question is dropped.
      final GroupedPathPlan plan = planTokens(flow, <String>[
        'difficulty_breathing',
        'poor_feeding',
        'bleeding',
        'headache',
        'fever',
      ]);
      expect(plan.presented, hasLength(5));
      expect(plan.redFlagCount, 3);
      expect(plan.droppedRedFlagIds, isEmpty);
      // Exactly one ordinary question is beyond the limit.
      expect(plan.truncatedIds, hasLength(1));
    });

    test('ordinary questions can never absorb a red-flag question', () {
      final Map<String, dynamic> doc = oracle();
      for (final OracleCase c in oracleCases(doc, 'forward')) {
        final GroupedPathPlan plan = planTokens(flow, c.inputTokens);
        expect(plan.droppedRedFlagIds, isEmpty, reason: '${c.inputTokens}');
        final int liveFlags = c.questions
            .where((OracleQuestion q) => q.role == 'red_flag_clarifier')
            .length;
        expect(plan.redFlagCount, liveFlags, reason: '${c.inputTokens}');
      }
    });

    test('a group never presents two questions on any captured path', () {
      final Map<String, dynamic> doc = oracle();
      for (final OracleCase c in oracleCases(doc, 'forward')) {
        final GroupedPathPlan plan = planTokens(flow, c.inputTokens);
        final Set<String> groupKeys = <String>{};
        final Set<String> roles = <String>{};
        for (final PresentedQuestion p in plan.presented) {
          if (p.groupKey != null) {
            expect(
              groupKeys.add(p.groupKey!),
              isTrue,
              reason: '${c.inputTokens}',
            );
          }
          if (p.clinicalRole == 'red_flag_clarifier') continue;
          expect(roles.add(p.clinicalRole), isTrue, reason: '${c.inputTokens}');
        }
      }
    });

    test('every grouped presentation retains its source provenance', () {
      final Map<String, dynamic> doc = oracle();
      for (final OracleCase c in oracleCases(doc, 'forward')) {
        for (final PresentedQuestion p in planTokens(
          flow,
          c.inputTokens,
        ).presented) {
          if (p.groupKey == null) continue;
          expect(
            p.contributingSourceIds,
            isNotEmpty,
            reason: '${c.inputTokens} ${p.question.id.value}',
          );
          expect(p.representativeSourceId, isNotNull);
          expect(
            p.contributingSourceIds.contains(p.representativeSourceId),
            isTrue,
          );
        }
      }
    });
  });
}
