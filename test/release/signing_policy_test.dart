/// Release signing must fail closed.
///
/// The Gradle config used to fall back from release signing to the **debug**
/// keystore whenever `android/key.properties` was absent, emitting only a
/// `logger.warn`. That produced an APK named `app-release.apk`, signed with a
/// shared well-known per-machine key, indistinguishable at a glance from a
/// real release build — and not upgradable in place, which silently breaks the
/// APK rollback lever in docs/BETA_ROLLBACK.md.
///
/// These tests read the committed Gradle config as text. They cannot run
/// Gradle, so they do not prove the build fails; they prove the *fallback is
/// not written down anywhere*, which is the regression that actually happened
/// and the one a reviewer is most likely to reintroduce. The three runtime
/// outcomes are exercised by hand and recorded in
/// docs/release/RELEASE_CHECKLIST.md.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Credential material that must never appear in a tracked file.
const List<String> _credentialKeys = [
  'storePassword',
  'keyPassword',
  'keyAlias',
  'storeFile',
];

void main() {
  late String gradle;

  setUpAll(() {
    gradle = File('android/app/build.gradle.kts').readAsStringSync();
  });

  group('no debug fallback for release builds', () {
    test('the release build type never selects the debug signing config', () {
      // The exact shape of the removed fallback.
      expect(
        gradle,
        isNot(contains('signingConfigs.getByName("debug")')),
        reason:
            'a release build must never be signed with the debug keystore — '
            'it is a shared well-known key and is per-machine, so testers '
            'cannot upgrade in place',
      );
    });

    test('a missing keystore raises a GradleException, not a warning', () {
      expect(gradle, contains('throw GradleException'));
      expect(gradle, contains('Release build refused'));
    });

    test('the failure names how to fix it', () {
      // A fail-closed control that does not say what to do gets worked around.
      expect(gradle, contains('key.properties'));
      expect(gradle, contains('WELLAPATH_ALLOW_UNSIGNED_RELEASE'));
    });

    test('logger.warn is not used to wave a signing problem through', () {
      expect(
        gradle.contains('logger.warn'),
        isFalse,
        reason:
            'the previous fallback warned and continued; a warning in a long '
            'Gradle log is not a control',
      );
    });
  });

  group('the unsigned path is explicit and cannot be reached by accident', () {
    test('it requires an opt-in flag', () {
      expect(gradle, contains('WELLAPATH_ALLOW_UNSIGNED_RELEASE'));
      expect(gradle, contains('wellapath.allowUnsignedRelease'));
    });

    test('opting in yields no signing config at all, not a debug one', () {
      // `signingConfig = null` is what makes apksigner report no signer, so a
      // downstream distributability check cannot be fooled by the filename.
      expect(gradle, contains('allowUnsignedRelease ->'));
      expect(gradle, contains('NOT installable'));
    });

    test('debug builds are left alone', () {
      // The fail-closed rule is about release builds. Removing debug signing
      // would break every developer's `flutter run`.
      expect(
        gradle,
        contains('Debug keeps debug signing'),
        reason: 'the debug path must remain intact and its intent recorded',
      );
    });
  });

  group('the refusal applies to release tasks only (RC-BLK-013 / WP-016)', () {
    // Before this, the refusal was thrown while configuring the `release`
    // build type. Gradle configures every build type on every build, so
    // `flutter build apk --debug` and `flutter run` also failed without
    // key.properties. Verified by hand (see PROGRESS.md, 2026-11-07): debug
    // builds without key.properties; release without it is refused with no
    // artifact; release with WELLAPATH_ALLOW_UNSIGNED_RELEASE=true builds.

    test('the release build type does not throw while being configured', () {
      expect(
        RegExp(r'else\s*->\s*throw').hasMatch(gradle),
        isFalse,
        reason:
            'a throw inside buildTypes.release runs on every build, '
            'including debug',
      );
    });

    test(
      'the refusal is enforced at task-graph time, before any task runs',
      () {
        final int gate = gradle.indexOf('if (releaseSigningRefused)');
        final int whenReady = gradle.indexOf('gradle.taskGraph.whenReady');
        final int refusal = gradle.indexOf('Release build refused');
        expect(gate, greaterThan(-1));
        expect(whenReady, greaterThan(gate));
        expect(
          refusal,
          greaterThan(whenReady),
          reason: 'the refusal must live inside the task-graph check',
        );
      },
    );

    test('the gate is exactly "no keystore and no explicit opt-in"', () {
      // Keeps the fail-closed rule from being weakened: any build without
      // signing material that did not opt in is still refused.
      expect(
        gradle,
        contains(
          'val releaseSigningRefused = !hasKeystoreFile && !allowUnsignedRelease',
        ),
      );
    });

    test('it triggers on any release task of the app module', () {
      expect(
        gradle,
        contains('task.project == project && task.name.contains("Release")'),
      );
      // A task-name allowlist (e.g. only assembleRelease) would let
      // bundleRelease through unsigned.
      expect(gradle, isNot(contains('name == "assembleRelease"')));
    });

    test('a refused release has no signing config, never the debug one', () {
      expect(gradle, contains('else -> null'));
      expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    });
  });

  group('required signing keys are validated, not assumed', () {
    test('an incomplete key.properties fails with a named list', () {
      expect(gradle, contains('requiredSigningKeys'));
      expect(gradle, contains('present but incomplete'));
    });

    test('a keystore path that does not resolve fails early', () {
      expect(gradle, contains('points at a keystore that does not exist'));
    });

    test('every required key is named in the config', () {
      for (final key in _credentialKeys) {
        expect(
          gradle,
          contains(key),
          reason: '$key must be named so the failure message can list it',
        );
      }
    });
  });

  group('no credential value reaches Git', () {
    test('key.properties is not tracked', () {
      // The file exists on the signing machine; it must never be committed.
      final tracked = Process.runSync('git', [
        'ls-files',
        'android/key.properties',
      ]).stdout.toString().trim();

      expect(
        tracked,
        isEmpty,
        reason: 'android/key.properties must stay gitignored (principle #6)',
      );
    });

    test('.gitignore covers key.properties and keystore files', () {
      final ignore = File('.gitignore').readAsStringSync();
      expect(ignore, contains('android/key.properties'));
      expect(ignore, contains('*.keystore'));
      expect(ignore, contains('*.jks'));
    });

    test('no keystore or credential file is tracked anywhere', () {
      final tracked = Process.runSync('git', [
        'ls-files',
      ]).stdout.toString().split('\n');

      final offenders = tracked.where((path) {
        final lower = path.toLowerCase();
        return lower.endsWith('.keystore') ||
            lower.endsWith('.jks') ||
            lower.endsWith('key.properties');
      }).toList();

      expect(offenders, isEmpty, reason: 'signing material in Git: $offenders');
    });

    test('the Gradle config names keys but embeds no values', () {
      // Guards the shape `keyPassword = "hunter2"` — a literal assignment to a
      // credential key. Reading them from the Properties object is required
      // and must keep passing.
      for (final key in ['storePassword', 'keyPassword', 'keyAlias']) {
        final literalAssignment = RegExp('$key\\s*=\\s*"[^"]+"');
        expect(
          literalAssignment.hasMatch(gradle),
          isFalse,
          reason: '$key must be read from key.properties, never inlined',
        );
      }
    });

    test('the config does not echo the keystore path into build output', () {
      // The path can carry a username and directory layout. The
      // does-not-exist failure deliberately withholds it.
      expect(gradle, contains('Path not echoed here'));
    });
  });
}
