/// The guard must sit in front of the real export, not beside it.
///
/// A standalone verifier is only as good as someone's memory of running it.
/// Build 216's `ExportOptions.plist` was hand-authored and nothing stood between
/// it and `xcodebuild`. These tests pin the two properties that make
/// [runGuardedExport] a control rather than a suggestion:
///
///  1. **The export command is never invoked when verification fails.** Asserted
///     by a fake invoker that records every call and fails the test if it is
///     reached.
///  2. **The exact pathname that was verified is the one handed to the export.**
///     A wrapper that verified one file and exported another would satisfy every
///     verifier test while shipping an unverified plist.
///
/// These use a fake parser so they run on every platform; the real-parser cases
/// live in `export_options_plutil_test.dart`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/export_options_policy.dart';
import '../../scripts/guarded_export.dart';
import 'fake_plutil.dart';

const String _teamId = '2SCUC2CBBS';

void main() {
  late Directory dir;
  late String optionsPath;
  late List<List<String>> invocations;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('guarded_export_');
    optionsPath = '${dir.path}/ExportOptions.plist';
    File(optionsPath).writeAsStringSync(
      buildExportOptionsPlist(
        mode: DistributionMode.appStore,
        destination: ExportDestination.upload,
        teamId: _teamId,
      ),
    );
    invocations = [];
  });

  tearDown(() => dir.deleteSync(recursive: true));

  int recordingInvoker(List<String> args) {
    invocations.add(args);
    return 0;
  }

  GuardedExportResult run({required PlutilRunner plutil}) => runGuardedExport(
    archivePath: '${dir.path}/Runner.xcarchive',
    exportOptionsPath: optionsPath,
    exportPath: '${dir.path}/out',
    exportInvoker: recordingInvoker,
    plutil: plutil,
  );

  group('the export command is NEVER invoked when verification fails', () {
    test('not for uploadSymbols false', () {
      final result = run(
        plutil: FakePlutilRunner(
          rootObject: compliantRoot()..['uploadSymbols'] = false,
        ),
      );

      expect(result.exportInvoked, isFalse);
      expect(invocations, isEmpty, reason: 'xcodebuild must not be reached');
      expect(result.exitCode, 1);
      expect(result.exportArguments, isNull);
    });

    test('not for uploadSymbols omitted at the root', () {
      final result = run(
        plutil: FakePlutilRunner(
          rootObject: compliantRoot()..remove('uploadSymbols'),
        ),
      );
      expect(result.exportInvoked, isFalse);
      expect(invocations, isEmpty);
      expect(result.exitCode, 1);
    });

    test('not for a nested-only uploadSymbols', () {
      final root = compliantRoot()
        ..remove('uploadSymbols')
        ..['provisioningProfiles'] = <String, Object?>{'uploadSymbols': true};
      final result = run(plutil: FakePlutilRunner(rootObject: root));
      expect(result.exportInvoked, isFalse);
      expect(invocations, isEmpty);
    });

    test('not for a wrong type', () {
      final result = run(
        plutil: FakePlutilRunner(
          rootObject: compliantRoot()..['uploadSymbols'] = 'true',
        ),
      );
      expect(result.exportInvoked, isFalse);
      expect(invocations, isEmpty);
    });

    test('not when plutil is MISSING — exit 2, nothing exported', () {
      final result = run(plutil: FakePlutilRunner(available: false));

      expect(result.exportInvoked, isFalse);
      expect(invocations, isEmpty);
      expect(
        result.exitCode,
        2,
        reason: 'an unanswerable check must not become a pass',
      );
    });

    test('not when the plist is malformed', () {
      final result = run(plutil: FakePlutilRunner(lintExitCode: 1));
      expect(result.exportInvoked, isFalse);
      expect(invocations, isEmpty);
      expect(result.exitCode, 2);
    });

    test('not when plutil fails unexpectedly', () {
      final result = run(plutil: FakePlutilRunner(convertExitCode: 70));
      expect(result.exportInvoked, isFalse);
      expect(invocations, isEmpty);
      expect(result.exitCode, 2);
    });

    test('not when the file is missing', () {
      final result = runGuardedExport(
        archivePath: '${dir.path}/Runner.xcarchive',
        exportOptionsPath: '${dir.path}/absent.plist',
        exportPath: '${dir.path}/out',
        exportInvoker: recordingInvoker,
        plutil: FakePlutilRunner(rootObject: compliantRoot()),
      );
      expect(result.exportInvoked, isFalse);
      expect(invocations, isEmpty);
      expect(result.exitCode, 2);
    });
  });

  group('on a pass, the VERIFIED pathname is what gets exported', () {
    test('the export command is invoked exactly once', () {
      final result = run(plutil: FakePlutilRunner(rootObject: compliantRoot()));
      expect(result.exportInvoked, isTrue);
      expect(invocations, hasLength(1));
      expect(result.exitCode, 0);
    });

    test('-exportOptionsPlist receives the SAME path that was verified', () {
      // The substitution guard. If the wrapper ever regenerated or swapped the
      // plist after verifying, this is what catches it.
      run(plutil: FakePlutilRunner(rootObject: compliantRoot()));

      final args = invocations.single;
      final index = args.indexOf('-exportOptionsPlist');
      expect(index, isNot(-1), reason: '-exportOptionsPlist must be passed');
      expect(
        args[index + 1],
        equals(optionsPath),
        reason:
            'the exported plist must be byte-for-byte the pathname that was '
            'verified, not a regenerated or substituted one',
      );
    });

    test('the archive and export paths are passed through unchanged', () {
      run(plutil: FakePlutilRunner(rootObject: compliantRoot()));
      final args = invocations.single;

      expect(args.first, '-exportArchive');
      expect(
        args[args.indexOf('-archivePath') + 1],
        '${dir.path}/Runner.xcarchive',
      );
      expect(args[args.indexOf('-exportPath') + 1], '${dir.path}/out');
    });

    test('a failing export surfaces its exit code', () {
      final result = runGuardedExport(
        archivePath: '${dir.path}/Runner.xcarchive',
        exportOptionsPath: optionsPath,
        exportPath: '${dir.path}/out',
        exportInvoker: (args) {
          invocations.add(args);
          return 65; // xcodebuild's generic failure
        },
        plutil: FakePlutilRunner(rootObject: compliantRoot()),
      );
      expect(result.exportInvoked, isTrue);
      expect(result.exitCode, 65);
    });
  });
}
