/// iOS distribution export options — generation, and the fail-closed paths.
///
/// Verification now runs through Apple's `/usr/bin/plutil`, because two earlier
/// string-scanning versions were defeated by independent review: first by
/// comments and duplicate keys, then by a key nested inside the legitimate
/// `provisioningProfiles` sub-dictionary. A text scanner has no model of plist
/// structure, so each patch closed one shape and left the class open.
///
/// This file covers what does not need Apple's parser: generation, and the
/// fail-closed behaviour when the parser cannot answer. The cases that must go
/// through the real parser are in `export_options_plutil_test.dart`, tagged
/// `plutil` and run in a mandatory macOS CI job.
///
/// The load-bearing tests here are the ones proving the guard **refuses**. A
/// policy test that only passes for good input proves nothing about the
/// regression it exists to prevent.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/export_options_policy.dart';
import 'fake_plutil.dart';

const String _teamId = '2SCUC2CBBS';

void main() {
  group('generation cannot produce a symbols-disabled file', () {
    test('internal-testing export sets uploadSymbols true', () {
      final plist = buildExportOptionsPlist(
        mode: DistributionMode.internalTesting,
        destination: ExportDestination.upload,
        teamId: _teamId,
      );
      expect(plist, contains('<key>uploadSymbols</key>\n\t<true/>'));
    });

    test('app-store export sets uploadSymbols true', () {
      final plist = buildExportOptionsPlist(
        mode: DistributionMode.appStore,
        destination: ExportDestination.upload,
        teamId: _teamId,
      );
      expect(plist, contains('<key>uploadSymbols</key>\n\t<true/>'));
    });

    test('an export-only run still uploads symbols', () {
      // The verification export is the artifact that gets hashed and scanned.
      // If it lacks symbols it is not the thing that later gets uploaded.
      final plist = buildExportOptionsPlist(
        mode: DistributionMode.internalTesting,
        destination: ExportDestination.export,
        teamId: _teamId,
      );
      expect(plist, contains('<key>uploadSymbols</key>\n\t<true/>'));
      expect(
        plist,
        contains('<key>destination</key>\n\t<string>export</string>'),
      );
    });

    test('the required value is true and is not a parameter', () {
      expect(kRequiredUploadSymbols, isTrue);
    });

    test('an empty team id is refused at generation', () {
      expect(
        () => buildExportOptionsPlist(
          mode: DistributionMode.appStore,
          destination: ExportDestination.upload,
          teamId: '   ',
        ),
        throwsArgumentError,
      );
    });

    test('a generated file never emits a policy key twice', () {
      for (final mode in DistributionMode.values) {
        final plist = buildExportOptionsPlist(
          mode: mode,
          destination: ExportDestination.upload,
          teamId: _teamId,
        );
        for (final key in kPolicyKeys) {
          expect(
            countKeyOccurrences(plist, key),
            lessThanOrEqualTo(1),
            reason: '$mode emits $key more than once',
          );
        }
      }
    });
  });

  group('distribution mode stays explicit', () {
    test('internal testing is marked internal-only', () {
      final plist = buildExportOptionsPlist(
        mode: DistributionMode.internalTesting,
        destination: ExportDestination.upload,
        teamId: _teamId,
      );
      expect(plist, contains('testFlightInternalTestingOnly'));
    });

    test('app-store distribution carries NO internal-only marker', () {
      // An external candidate must not inherit an internal-only marker: it
      // would bar the external testing the release is for.
      final plist = buildExportOptionsPlist(
        mode: DistributionMode.appStore,
        destination: ExportDestination.upload,
        teamId: _teamId,
      );
      expect(plist, isNot(contains('testFlightInternalTestingOnly')));
    });

    test('the two modes differ only in the internal-only marker', () {
      final internal = buildExportOptionsPlist(
        mode: DistributionMode.internalTesting,
        destination: ExportDestination.upload,
        teamId: _teamId,
      );
      final appStore = buildExportOptionsPlist(
        mode: DistributionMode.appStore,
        destination: ExportDestination.upload,
        teamId: _teamId,
      );
      expect(
        internal.replaceAll(
          RegExp(r'\t<key>testFlightInternalTestingOnly</key>\n\t<true/>\n'),
          '',
        ),
        equals(appStore),
      );
    });
  });

  group('fail closed when Apple\'s parser cannot answer', () {
    late String path;

    setUpAll(() {
      // A real, compliant file on disk. The fake controls what "plutil" says
      // about it, so these tests isolate the failure handling rather than the
      // parsing.
      final dir = Directory.systemTemp.createTempSync('export_opts_');
      path = '${dir.path}/ExportOptions.plist';
      File(path).writeAsStringSync(
        buildExportOptionsPlist(
          mode: DistributionMode.appStore,
          destination: ExportDestination.upload,
          teamId: _teamId,
        ),
      );
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    test('a missing plutil is UNUSABLE (exit 2), never a pass', () {
      final verdict = verifyExportOptionsFile(
        path: path,
        plutil: FakePlutilRunner(available: false),
      );
      expect(verdict.outcome, VerificationOutcome.unusable);
      expect(verdict.exitCode, 2);
      expect(verdict.messages.join('\n'), contains('NOTHING IS CERTIFIED'));
    });

    test('a missing plutil does NOT fall back to a string scanner', () {
      // The file on disk is fully compliant. If a fallback scanner existed it
      // would pass here, which is exactly the behaviour being refused.
      final verdict = verifyExportOptionsFile(
        path: path,
        plutil: FakePlutilRunner(available: false),
      );
      expect(verdict.isPass, isFalse);
    });

    test('lint rejecting the file is UNUSABLE (exit 2)', () {
      final verdict = verifyExportOptionsFile(
        path: path,
        plutil: FakePlutilRunner(
          lintExitCode: 1,
          stderrText: 'Unexpected character at line 3',
        ),
      );
      expect(verdict.exitCode, 2);
      expect(
        verdict.messages.join('\n'),
        contains('not a valid property list'),
      );
    });

    test('an unexpected plutil failure is UNUSABLE (exit 2)', () {
      final verdict = verifyExportOptionsFile(
        path: path,
        plutil: FakePlutilRunner(
          convertExitCode: 70,
          stderrText: 'internal error',
        ),
      );
      expect(verdict.exitCode, 2);
      expect(verdict.messages.join('\n'), contains('could not convert'));
    });

    test('output plutil returns that is not JSON is UNUSABLE (exit 2)', () {
      final verdict = verifyExportOptionsFile(
        path: path,
        plutil: FakePlutilRunner(convertStdout: 'not json at all'),
      );
      expect(verdict.exitCode, 2);
      expect(verdict.messages.join('\n'), contains('could not read as JSON'));
    });

    test('a non-dictionary root is UNUSABLE (exit 2)', () {
      final verdict = verifyExportOptionsFile(
        path: path,
        plutil: FakePlutilRunner(convertStdout: '[1,2,3]'),
      );
      expect(verdict.exitCode, 2);
      expect(verdict.messages.join('\n'), contains('not a dictionary'));
    });

    test('a missing file is UNUSABLE (exit 2)', () {
      final verdict = verifyExportOptionsFile(
        path: '${path}_does_not_exist',
        plutil: FakePlutilRunner(rootObject: compliantRoot()),
      );
      expect(verdict.exitCode, 2);
      expect(verdict.messages.join('\n'), contains('no such file'));
    });

    test('unusable dominates: nothing is certified', () {
      // All three outcomes are distinct and 2 is reserved for "did not check".
      expect(
        const ExportOptionsVerdict(VerificationOutcome.unusable, []).exitCode,
        2,
      );
      expect(
        const ExportOptionsVerdict(VerificationOutcome.violation, []).exitCode,
        1,
      );
      expect(
        const ExportOptionsVerdict(VerificationOutcome.pass, []).exitCode,
        0,
      );
    });
  });

  group('the value verdict comes from the parsed ROOT object', () {
    late String path;

    setUpAll(() {
      final dir = Directory.systemTemp.createTempSync('export_opts_root_');
      path = '${dir.path}/ExportOptions.plist';
      File(path).writeAsStringSync(
        buildExportOptionsPlist(
          mode: DistributionMode.appStore,
          destination: ExportDestination.upload,
          teamId: _teamId,
        ),
      );
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    ExportOptionsVerdict verdictFor(Map<String, Object?> root) =>
        verifyExportOptionsFile(
          path: path,
          plutil: FakePlutilRunner(rootObject: root),
        );

    test('root boolean true passes', () {
      expect(verdictFor(compliantRoot()).exitCode, 0);
    });

    test('root boolean false is a VIOLATION (exit 1)', () {
      final verdict = verdictFor(compliantRoot()..['uploadSymbols'] = false);
      expect(verdict.exitCode, 1);
      expect(verdict.messages.join('\n'), contains('DISABLED'));
    });

    test('root key omitted is a VIOLATION (exit 1)', () {
      final root = compliantRoot()..remove('uploadSymbols');
      final verdict = verdictFor(root);
      expect(verdict.exitCode, 1);
      expect(verdict.messages.join('\n'), contains('OMITTED at the root'));
    });

    test('a string "true" is a VIOLATION — wrong type', () {
      final verdict = verdictFor(compliantRoot()..['uploadSymbols'] = 'true');
      expect(verdict.exitCode, 1);
      expect(verdict.messages.join('\n'), contains('must be a boolean'));
      expect(verdict.messages.join('\n'), contains('a string'));
    });

    test('an integer 1 is a VIOLATION — wrong type', () {
      final verdict = verdictFor(compliantRoot()..['uploadSymbols'] = 1);
      expect(verdict.exitCode, 1);
      expect(verdict.messages.join('\n'), contains('must be a boolean'));
      expect(verdict.messages.join('\n'), contains('an integer'));
    });

    test('a nested-only key reads as omitted — nesting does not count', () {
      // This is the evasion that defeated the previous version. The parsed root
      // object simply has no uploadSymbols, which is what Apple sees too.
      final root = compliantRoot()
        ..remove('uploadSymbols')
        ..['provisioningProfiles'] = <String, Object?>{
          'org.wellapath.app': 'WellaPath Distribution',
          'uploadSymbols': true,
        };
      final verdict = verdictFor(root);
      expect(verdict.exitCode, 1);
      expect(verdict.messages.join('\n'), contains('OMITTED at the root'));
    });

    test('a key inside an array reads as omitted', () {
      final root = compliantRoot()
        ..remove('uploadSymbols')
        ..['notes'] = <Object?>['uploadSymbols', true];
      expect(verdictFor(root).exitCode, 1);
    });

    test('root false beats a nested true', () {
      final root = compliantRoot()
        ..['uploadSymbols'] = false
        ..['provisioningProfiles'] = <String, Object?>{'uploadSymbols': true};
      final verdict = verdictFor(root);
      expect(verdict.exitCode, 1);
      expect(verdict.messages.join('\n'), contains('DISABLED'));
    });

    test('root true is not spoiled by a nested false', () {
      final root = compliantRoot()
        ..['provisioningProfiles'] = <String, Object?>{'uploadSymbols': false};
      expect(verdictFor(root).exitCode, 0);
    });

    test('a missing method, destination or teamID is a VIOLATION', () {
      for (final key in ['method', 'destination', 'teamID']) {
        final root = compliantRoot()..remove(key);
        final verdict = verdictFor(root);
        expect(verdict.exitCode, 1, reason: 'removing $key should fail');
        expect(verdict.messages.join('\n'), contains(key));
      }
    });

    test('a credential key in the parsed root is a VIOLATION', () {
      final verdict = verdictFor(
        compliantRoot()..['storePassword'] = 'hunter2',
      );
      expect(verdict.exitCode, 1);
      expect(verdict.messages.join('\n'), contains('storePassword'));
    });
  });
}
