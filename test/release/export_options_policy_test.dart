/// iOS distribution export options must upload symbols.
///
/// Build 216 was exported and uploaded with `uploadSymbols` set to `false`, so
/// no dSYMs reached App Store Connect and automatic Apple-side symbolication is
/// unavailable for that build. The cause was structural: the
/// `ExportOptions.plist` was hand-authored in an untracked build directory, so
/// no source-controlled rule existed for it to violate.
///
/// These tests pin the rule. The important ones are not the happy paths — they
/// are the mutation checks: each asserts the guard **rejects** a bad file, so
/// the guard cannot be vacuously true. A policy test that only passes for good
/// input proves nothing about the regression it exists to prevent.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/export_options_policy.dart';

const String _teamId = '2SCUC2CBBS';

void main() {
  group('generation cannot produce a symbols-disabled file', () {
    test('internal-testing export sets uploadSymbols true', () {
      final plist = buildExportOptionsPlist(
        mode: DistributionMode.internalTesting,
        destination: ExportDestination.upload,
        teamId: _teamId,
      );

      expect(rawValueForKey(plist, 'uploadSymbols'), '<true/>');
      expect(verifyExportOptions(plist), isEmpty);
    });

    test('app-store export sets uploadSymbols true', () {
      final plist = buildExportOptionsPlist(
        mode: DistributionMode.appStore,
        destination: ExportDestination.upload,
        teamId: _teamId,
      );

      expect(rawValueForKey(plist, 'uploadSymbols'), '<true/>');
      expect(verifyExportOptions(plist), isEmpty);
    });

    test('an export-only run still uploads symbols', () {
      // The verification export is the artifact that gets hashed and scanned.
      // If it lacks symbols it is not the thing that later gets uploaded.
      final plist = buildExportOptionsPlist(
        mode: DistributionMode.internalTesting,
        destination: ExportDestination.export,
        teamId: _teamId,
      );

      expect(rawValueForKey(plist, 'uploadSymbols'), '<true/>');
      expect(rawValueForKey(plist, 'destination'), '<string>export</string>');
    });

    test('the required value is true and is not a parameter', () {
      // If someone makes uploadSymbols configurable, this fails and they have
      // to come and read the comment explaining why it is not.
      expect(kRequiredUploadSymbols, isTrue);
    });
  });

  group('distribution mode stays explicit', () {
    test('internal testing is marked internal-only', () {
      final plist = buildExportOptionsPlist(
        mode: DistributionMode.internalTesting,
        destination: ExportDestination.upload,
        teamId: _teamId,
      );

      expect(rawValueForKey(plist, 'testFlightInternalTestingOnly'), '<true/>');
    });

    test('app-store distribution carries NO internal-only marker', () {
      // An external or public candidate must not inherit an internal-only
      // marker: it would bar the external testing the release is for.
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
        reason:
            'if the modes diverge in any other key, that difference is '
            'undocumented and will surprise whoever ships the next build',
      );
    });
  });

  group('the guard rejects a bad file — mutation checks', () {
    late String good;

    setUp(() {
      good = buildExportOptionsPlist(
        mode: DistributionMode.internalTesting,
        destination: ExportDestination.upload,
        teamId: _teamId,
      );
      // Guard the guard: the fixture must start clean, or the mutations below
      // would pass for the wrong reason.
      expect(verifyExportOptions(good), isEmpty);
    });

    test('uploadSymbols false is REJECTED — the build-216 regression', () {
      final disabled = good.replaceFirst(
        '<key>uploadSymbols</key>\n\t<true/>',
        '<key>uploadSymbols</key>\n\t<false/>',
      );
      // Prove the mutation actually landed, so a silent no-op replace cannot
      // make this test pass vacuously.
      expect(disabled, isNot(equals(good)));
      expect(rawValueForKey(disabled, 'uploadSymbols'), '<false/>');

      final violations = verifyExportOptions(disabled);
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('uploadSymbols is DISABLED'));
    });

    test('uploadSymbols omitted entirely is REJECTED', () {
      final omitted = good.replaceFirst(
        '\t<key>uploadSymbols</key>\n\t<true/>\n',
        '',
      );
      expect(omitted, isNot(equals(good)));
      expect(rawValueForKey(omitted, 'uploadSymbols'), isNull);

      final violations = verifyExportOptions(omitted);
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('uploadSymbols is OMITTED'));
    });

    test('a missing method is REJECTED', () {
      final broken = good.replaceFirst(
        '\t<key>method</key>\n\t<string>app-store-connect</string>\n',
        '',
      );
      expect(broken, isNot(equals(good)));
      expect(verifyExportOptions(broken).join('\n'), contains('method'));
    });

    test('a missing destination is REJECTED', () {
      final broken = good.replaceFirst(
        RegExp(r'\t<key>destination</key>\n\t<string>\w+</string>\n'),
        '',
      );
      expect(broken, isNot(equals(good)));
      expect(verifyExportOptions(broken).join('\n'), contains('destination'));
    });

    test('a missing teamID is REJECTED', () {
      final broken = good.replaceFirst(
        '\t<key>teamID</key>\n\t<string>$_teamId</string>\n',
        '',
      );
      expect(broken, isNot(equals(good)));
      expect(verifyExportOptions(broken).join('\n'), contains('teamID'));
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
  });

  group('no credential material', () {
    test('a generated file carries none of the forbidden keys', () {
      for (final mode in DistributionMode.values) {
        final plist = buildExportOptionsPlist(
          mode: mode,
          destination: ExportDestination.upload,
          teamId: _teamId,
        );
        for (final key in kForbiddenCredentialKeys) {
          expect(
            plist,
            isNot(contains('<key>$key</key>')),
            reason: '$mode must not carry $key',
          );
        }
      }
    });

    test('a smuggled credential key is REJECTED', () {
      final good = buildExportOptionsPlist(
        mode: DistributionMode.appStore,
        destination: ExportDestination.upload,
        teamId: _teamId,
      );
      final leaky = good.replaceFirst(
        '</dict>',
        '\t<key>storePassword</key>\n\t<string>hunter2</string>\n</dict>',
      );
      expect(leaky, isNot(equals(good)));

      final violations = verifyExportOptions(leaky);
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('storePassword'));
    });
  });

  group('the verifier agrees with the parser that matters', () {
    // Found by independent review. An earlier version read the FIRST occurrence
    // of a key while Apple's plist parser resolves the LAST, so a hand-edited
    // file that `plutil -p` reports as `uploadSymbols => false` was reported
    // CLEAN — precisely the outcome this library exists to prevent. Both shapes
    // below also pass `plutil -lint`, so they look legitimate.
    late String good;

    setUp(() {
      good = buildExportOptionsPlist(
        mode: DistributionMode.appStore,
        destination: ExportDestination.upload,
        teamId: _teamId,
      );
      expect(verifyExportOptions(good), isEmpty);
    });

    test('a duplicated uploadSymbols key is REJECTED', () {
      final dup = good.replaceFirst(
        '</dict>',
        '\t<key>uploadSymbols</key>\n\t<false/>\n</dict>',
      );
      expect(dup, isNot(equals(good)));
      expect(countKeyOccurrences(dup, 'uploadSymbols'), 2);

      final violations = verifyExportOptions(dup);
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('appears 2 times'));
    });

    test('the LAST value wins, as Apple resolves it', () {
      final dup = good.replaceFirst(
        '</dict>',
        '\t<key>uploadSymbols</key>\n\t<false/>\n</dict>',
      );
      // true first, false last. Apple reads false, so this must too.
      expect(rawValueForKey(dup, 'uploadSymbols'), '<false/>');
      expect(
        verifyExportOptions(dup).join('\n'),
        contains('uploadSymbols is DISABLED'),
      );
    });

    test('a commented-out key then overridden false is REJECTED', () {
      final commented = good.replaceFirst(
        '\t<key>uploadSymbols</key>\n\t<true/>',
        '\t<!-- <key>uploadSymbols</key><true/> -->\n'
            '\t<key>uploadSymbols</key>\n\t<false/>',
      );
      expect(commented, isNot(equals(good)));
      // The commented copy must not count as a live key.
      expect(countKeyOccurrences(commented, 'uploadSymbols'), 1);
      expect(rawValueForKey(commented, 'uploadSymbols'), '<false/>');

      expect(
        verifyExportOptions(commented).join('\n'),
        contains('uploadSymbols is DISABLED'),
      );
    });

    test('a key present ONLY in a comment counts as omitted', () {
      final onlyComment = good.replaceFirst(
        '\t<key>uploadSymbols</key>\n\t<true/>',
        '\t<!-- <key>uploadSymbols</key><true/> -->',
      );
      expect(onlyComment, isNot(equals(good)));
      expect(countKeyOccurrences(onlyComment, 'uploadSymbols'), 0);
      expect(
        verifyExportOptions(onlyComment).join('\n'),
        contains('uploadSymbols is OMITTED'),
      );
    });

    test('stripXmlComments removes comments and keeps live markup', () {
      expect(stripXmlComments('a<!-- x -->b'), 'ab');
      expect(
        stripXmlComments('<!--\nmulti\nline\n--><key>k</key>'),
        '<key>k</key>',
      );
    });

    test('a generated file has exactly one of every policy key', () {
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

  group('the rule is written down where a release engineer will look', () {
    test('the neutral build policy requires uploadSymbols true', () {
      final policy = File('docs/NEUTRAL_BUILD_POLICY.md').readAsStringSync();

      expect(policy, contains('uploadSymbols'));
      expect(
        policy,
        contains('export_options_tool.dart'),
        reason: 'a guard nobody is told to run is not a control',
      );
    });

    test('the archive-and-dSYM scan requirement survives', () {
      // The export-options check is additional to the neutral-path scan, never
      // a replacement for it.
      final policy = File('docs/NEUTRAL_BUILD_POLICY.md').readAsStringSync();

      expect(policy, contains('scan_symbol_artifacts.dart'));
      expect(policy, contains('dSYM'));
    });

    test('archive retention for every distributed build is documented', () {
      final policy = File('docs/NEUTRAL_BUILD_POLICY.md').readAsStringSync();

      expect(policy.toLowerCase(), contains('retain'));
      expect(policy, contains('.xcarchive'));
    });
  });
}
