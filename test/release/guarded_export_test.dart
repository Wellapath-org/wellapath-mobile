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
  late _FakeXcodebuild xcodebuild;

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
    xcodebuild = _FakeXcodebuild();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  GuardedExportResult run({
    required PlutilRunner plutil,
    List<String> extraArguments = const [],
  }) => runGuardedExport(
    archivePath: '${dir.path}/Runner.xcarchive',
    exportOptionsPath: optionsPath,
    exportPath: '${dir.path}/out',
    xcodebuild: xcodebuild,
    plutil: plutil,
    extraArguments: extraArguments,
  );

  group('the export command is NEVER invoked when verification fails', () {
    test('not for uploadSymbols false', () {
      final result = run(
        plutil: FakePlutilRunner(
          rootObject: compliantRoot()..['uploadSymbols'] = false,
        ),
      );

      expect(result.exportInvoked, isFalse);
      expect(
        xcodebuild.invocations,
        isEmpty,
        reason: 'xcodebuild must not be reached',
      );
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
      expect(xcodebuild.invocations, isEmpty);
      expect(result.exitCode, 1);
    });

    test('not for a nested-only uploadSymbols', () {
      final root = compliantRoot()
        ..remove('uploadSymbols')
        ..['provisioningProfiles'] = <String, Object?>{'uploadSymbols': true};
      final result = run(plutil: FakePlutilRunner(rootObject: root));
      expect(result.exportInvoked, isFalse);
      expect(xcodebuild.invocations, isEmpty);
    });

    test('not for a wrong type', () {
      final result = run(
        plutil: FakePlutilRunner(
          rootObject: compliantRoot()..['uploadSymbols'] = 'true',
        ),
      );
      expect(result.exportInvoked, isFalse);
      expect(xcodebuild.invocations, isEmpty);
    });

    test('not when plutil is MISSING — exit 2, nothing exported', () {
      final result = run(plutil: FakePlutilRunner(available: false));

      expect(result.exportInvoked, isFalse);
      expect(xcodebuild.invocations, isEmpty);
      expect(
        result.exitCode,
        2,
        reason: 'an unanswerable check must not become a pass',
      );
    });

    test('not when the plist is malformed', () {
      final result = run(plutil: FakePlutilRunner(lintExitCode: 1));
      expect(result.exportInvoked, isFalse);
      expect(xcodebuild.invocations, isEmpty);
      expect(result.exitCode, 2);
    });

    test('not when plutil fails unexpectedly', () {
      final result = run(plutil: FakePlutilRunner(convertExitCode: 70));
      expect(result.exportInvoked, isFalse);
      expect(xcodebuild.invocations, isEmpty);
      expect(result.exitCode, 2);
    });

    test('not when the file is missing', () {
      final result = runGuardedExport(
        archivePath: '${dir.path}/Runner.xcarchive',
        exportOptionsPath: '${dir.path}/absent.plist',
        exportPath: '${dir.path}/out',
        xcodebuild: xcodebuild,
        plutil: FakePlutilRunner(rootObject: compliantRoot()),
      );
      expect(result.exportInvoked, isFalse);
      expect(xcodebuild.invocations, isEmpty);
      expect(result.exitCode, 2);
    });
  });

  group('extraArguments may not override the verified plist path', () {
    // The wrapper is authoritative for which plist is exported. xcodebuild takes
    // the LATER value of a repeated flag, so a smuggled second
    // -exportOptionsPlist would make the verification meaningless.
    PlutilRunner good() => FakePlutilRunner(rootObject: compliantRoot());

    test('the bare flag followed by another path is REJECTED', () {
      final result = run(
        plutil: good(),
        extraArguments: ['-exportOptionsPlist', '/tmp/other.plist'],
      );

      expect(result.exportInvoked, isFalse);
      expect(
        xcodebuild.invocations,
        isEmpty,
        reason: 'must be rejected before invocation',
      );
      expect(result.exitCode, 2);
      expect(
        result.verdict.messages.join('\n'),
        contains('may not supply or override'),
      );
    });

    test('the inline -exportOptionsPlist=PATH form is REJECTED', () {
      final result = run(
        plutil: good(),
        extraArguments: ['-exportOptionsPlist=/tmp/other.plist'],
      );
      expect(result.exportInvoked, isFalse);
      expect(xcodebuild.invocations, isEmpty);
      expect(result.exitCode, 2);
    });

    test('a double-dashed or odd-case spelling is REJECTED', () {
      for (final spelling in [
        '--exportOptionsPlist',
        '-ExportOptionsPlist',
        '--EXPORTOPTIONSPLIST=/tmp/x.plist',
      ]) {
        final result = run(plutil: good(), extraArguments: [spelling]);
        expect(
          result.exportInvoked,
          isFalse,
          reason: '$spelling must be rejected',
        );
        expect(
          xcodebuild.invocations,
          isEmpty,
          reason: '$spelling reached xcodebuild',
        );
      }
    });

    test('rejection happens BEFORE verification, so nothing is exported even '
        'when the plist itself is fine', () {
      final result = run(
        plutil: good(),
        extraArguments: ['-exportOptionsPlist', '/tmp/other.plist'],
      );
      // The plist on disk is compliant; the refusal is about the arguments.
      expect(result.exitCode, 2);
      expect(xcodebuild.invocations, isEmpty);
    });

    test('a normal unrelated extra argument IS allowed and passed through', () {
      final result = run(
        plutil: good(),
        extraArguments: ['-allowProvisioningUpdates'],
      );

      expect(result.exportInvoked, isTrue);
      expect(xcodebuild.invocations, hasLength(1));
      expect(
        xcodebuild.invocations.single,
        contains('-allowProvisioningUpdates'),
      );
      // And the verified path is still the one that went through.
      final args = xcodebuild.invocations.single;
      expect(args[args.indexOf('-exportOptionsPlist') + 1], optionsPath);
    });

    test('overridesExportOptions matches the forms it must and no others', () {
      for (final smuggled in [
        '-exportOptionsPlist',
        '--exportOptionsPlist',
        '-exportoptionsplist=/x',
        '-ExportOptionsPlist=/x',
      ]) {
        expect(overridesExportOptions(smuggled), isTrue, reason: smuggled);
      }
      for (final benign in [
        '-allowProvisioningUpdates',
        '-exportPath',
        '-archivePath',
        '-exportOptionsPlistExtra',
        'exportOptionsPlistish',
      ]) {
        expect(overridesExportOptions(benign), isFalse, reason: benign);
      }
    });
  });

  group('a missing or unusable xcodebuild fails closed', () {
    test('an unavailable xcodebuild is exit 2 and exports nothing', () {
      final result = runGuardedExport(
        archivePath: '${dir.path}/Runner.xcarchive',
        exportOptionsPath: optionsPath,
        exportPath: '${dir.path}/out',
        xcodebuild: _FakeXcodebuild(available: false),
        plutil: FakePlutilRunner(rootObject: compliantRoot()),
      );

      expect(result.exportInvoked, isFalse);
      expect(result.exitCode, 2);
      expect(
        result.verdict.messages.join('\n'),
        contains(kXcodebuildPath),
        reason: 'the message must name the fixed path it looked for',
      );
    });

    test('the production runner uses a fixed absolute path, not PATH', () {
      // The asymmetry a review exploited: plutil was absolute, xcodebuild was
      // not, so a fake earlier on PATH was invoked. Both are fixed now.
      expect(kXcodebuildPath, '/usr/bin/xcodebuild');
      expect(kXcodebuildPath.startsWith('/'), isTrue);
    });
  });

  group('on a pass, the VERIFIED pathname is what gets exported', () {
    test('the export command is invoked exactly once', () {
      final result = run(plutil: FakePlutilRunner(rootObject: compliantRoot()));
      expect(result.exportInvoked, isTrue);
      expect(xcodebuild.invocations, hasLength(1));
      expect(result.exitCode, 0);
    });

    test('-exportOptionsPlist receives the SAME path that was verified', () {
      // The substitution guard. If the wrapper ever regenerated or swapped the
      // plist after verifying, this is what catches it.
      run(plutil: FakePlutilRunner(rootObject: compliantRoot()));

      final args = xcodebuild.invocations.single;
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
      final args = xcodebuild.invocations.single;

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
        xcodebuild: _FakeXcodebuild(exitCode: 65),
        plutil: FakePlutilRunner(rootObject: compliantRoot()),
      );
      expect(result.exportInvoked, isTrue);
      expect(result.exitCode, 65);
    });
  });
}

/// An injected stand-in for `/usr/bin/xcodebuild`.
///
/// Testability comes from this seam on purpose. The previous design resolved
/// `xcodebuild` through `PATH`, which a review demonstrated was substitutable by
/// putting a fake first on `PATH` — exactly what the fixed [kXcodebuildPath] now
/// prevents. A fake injected here cannot be mistaken for the real tool at
/// release time.
class _FakeXcodebuild implements XcodebuildRunner {
  _FakeXcodebuild({this.available = true, this.exitCode = 0});

  final bool available;
  final int exitCode;

  /// Every argument list this fake was asked to run, in order. Must stay empty
  /// whenever the wrapper refuses.
  final List<List<String>> invocations = [];

  @override
  bool get isAvailable => available;

  @override
  int run(List<String> arguments) {
    invocations.add(arguments);
    return exitCode;
  }
}
