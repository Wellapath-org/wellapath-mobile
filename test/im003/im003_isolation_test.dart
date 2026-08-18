/// The measurement harness must never reach the running application.
///
/// It imports the shipped engine on purpose — that is the whole point — but the
/// arrow only goes one way. Nothing the app executes may import, initialise or
/// be able to enable it, and none of the vendored evidence may reach a device.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'im003_contract.dart';

/// Everything this step adds under `test/`.
const List<String> kHarnessSources = <String>[
  'test/im003/im003_contract.dart',
  'test/im003/im003_closure.dart',
  'test/im003/im003_measurement.dart',
  'test/im003/im003_measurement_test.dart',
  'test/im003/im003_guards_test.dart',
  'test/im003/im003_isolation_test.dart',
];

List<File> _dartFilesUnder(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((File f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  group('no live path can reach the harness', () {
    test('nothing under lib/ imports it', () {
      final List<String> offenders = <String>[];
      for (final File file in _dartFilesUnder('lib')) {
        for (final String line in file.readAsStringSync().split('\n')) {
          final String trimmed = line.trim();
          if (!trimmed.startsWith('import ') &&
              !trimmed.startsWith('export ') &&
              !trimmed.startsWith('part ')) {
            continue;
          }
          if (trimmed.contains('im003') ||
              trimmed.contains('test/') ||
              trimmed.contains('im003_measurement')) {
            offenders.add('${file.path}: $trimmed');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('the engine, UI, controller and startup do not reference it', () {
      for (final String path in <String>[
        'lib/core/engine/engine_controller.dart',
        'lib/core/engine/scoring_engine.dart',
        'lib/core/engine/red_flag_evaluator.dart',
        'lib/core/engine/urgency_determiner.dart',
        'lib/features/assessment/question_engine.dart',
        'lib/features/assessment/assessment_controller.dart',
        'lib/features/assessment/followup_screen.dart',
        'lib/main.dart',
        'lib/app.dart',
      ]) {
        final String source = File(path).readAsStringSync();
        expect(source.contains('im003'), isFalse, reason: path);
        expect(source.contains('Im003'), isFalse, reason: path);
      }
    });

    test('the harness declares no build flag', () {
      // This file is excluded from its own scan: it necessarily contains the
      // needle as a literal, and an earlier revision flagged itself. Named by
      // exact path so the exclusion cannot widen — every other harness source
      // is still checked.
      const String self = 'test/im003/im003_isolation_test.dart';
      final List<String> scanned = kHarnessSources
          .where((String p) => p != self)
          .toList();
      expect(scanned, hasLength(kHarnessSources.length - 1));
      for (final String path in scanned) {
        expect(
          File(path).readAsStringSync().contains('fromEnvironment'),
          isFalse,
          reason: '$path contains a compile-time switch',
        );
      }
      // No self-check: this file cannot scan itself for a needle it must
      // contain, and an attempt to do so just moved the self-match one level
      // deeper. It carries no weight anyway — a build flag in a test file
      // cannot enable anything in the application, which is what the other
      // guards in this group establish.
    });

    test('the harness never mutates a clinical artifact', () {
      // It reads pinned artifacts and vendored evidence. A write would mean the
      // measurement could alter the thing it is measuring.
      for (final String path in kHarnessSources) {
        final String source = File(path).readAsStringSync();
        for (final String forbidden in <String>[
          'writeAsStringSync(',
          'writeAsBytesSync(',
        ]) {
          if (!source.contains(forbidden)) continue;
          // The measurement test writes exactly one file: its own report.
          expect(
            source.contains(kMeasurementReportPath) ||
                source.contains('kMeasurementReportPath'),
            isTrue,
            reason: '$path writes something other than the evidence report',
          );
        }
      }
    });
  });

  group('nothing reaches a device', () {
    test('pubspec declares no im003 asset and no new dependency', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('im003'), isFalse);
      expect(pubspec.contains('test/fixtures'), isFalse);
      expect(pubspec.contains('docs/evidence'), isFalse);
    });

    test('no vendored evidence lives outside test/ or docs/', () {
      for (final Im003SourceFile f in kIm003SourceFiles) {
        final String path = '$kIm003FixtureRoot/${f.destinationPath}';
        expect(path.startsWith('test/'), isTrue, reason: path);
        expect(File(path).existsSync(), isTrue, reason: path);
      }
      expect(kMeasurementReportPath.startsWith('docs/'), isTrue);
    });

    test('nothing under assets/ is IM-003 evidence', () {
      final Directory assets = Directory('assets');
      if (!assets.existsSync()) return;
      for (final FileSystemEntity entity in assets.listSync(recursive: true)) {
        if (entity is! File) continue;
        expect(
          entity.uri.pathSegments.last.contains('im003'),
          isFalse,
          reason: entity.path,
        );
      }
    });
  });

  group('IM-003 is not implemented anywhere in lib/', () {
    test('no live source gained a re-branching entry point', () {
      final List<String> offenders = <String>[];
      for (final File file in _dartFilesUnder('lib')) {
        final String source = file.readAsStringSync();
        for (final String forbidden in <String>[
          'rebranch',
          'reBranch',
          'additiveClosure',
          'recomputeEligibility',
          'onAnswerCommitted',
        ]) {
          if (source.contains(forbidden)) {
            offenders.add('${file.path}: $forbidden');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('the live question engine still plans once, from the symptom set', () {
      // A change here would mean IM-003 had been implemented in the live flow.
      final String screen = File(
        'lib/features/assessment/followup_screen.dart',
      ).readAsStringSync();
      expect(screen.contains('initState'), isTrue);
      expect(screen.contains('generateQuestions'), isTrue);
      // No re-generation after an answer.
      final int generateCalls = 'generateQuestions'.allMatches(screen).length;
      expect(
        generateCalls,
        1,
        reason:
            'generateQuestions is called $generateCalls times; more than once '
            'would mean the list is rebuilt after an answer',
      );
    });
  });
}
