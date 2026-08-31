/// Build identity — uniqueness and monotonicity of the release build number.
///
/// Android refuses to install an APK whose `versionCode` is not greater than
/// the installed one, and Play refuses a duplicate outright. A build number
/// that regresses or repeats is therefore not a cosmetic mistake: it silently
/// breaks in-place upgrade for every tester holding the previous build.
///
/// `pubspec.yaml` is the single source for all three platforms — Android
/// `versionName`/`versionCode` and iOS `CFBundleShortVersionString`/
/// `CFBundleVersion` all derive from it. Nothing else may set them, so this
/// one file is the only thing that needs guarding.
///
/// The registry below records every build number this project has ever
/// attached to a distributable or distributed artifact. It is append-only:
/// entries are added when a build goes out, never edited or removed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every build number known to have been attached to a build, with where the
/// evidence comes from. Append-only.
///
/// Two numbering namespaces exist and both are recorded, because a future
/// reader who knows only one of them would pick a colliding number:
///
///  * **Platform build number** — `pubspec` `+N`, becoming Android
///    `versionCode` and iOS `CFBundleVersion`. Only ever `1`.
///  * **Crash-release identifier** — `APP_BUILD`, a `--dart-define` used to
///    tag Sentry releases in `.github/workflows/internal-beta-validation.yml`.
///    Reached `208`. It never touched `versionCode`, but it is a build number
///    this project has published against itself, and reusing it would make two
///    different artifacts indistinguishable in crash triage.
const Map<int, String> kKnownDistributedBuilds = <int, String>{
  1:
      'pubspec 1.0.0+1 — all history, all tags (v0.1.0-beta.1, v0.2.0-beta.1, '
      'v0.2.0-beta.2), and the distributed beta recorded in '
      'docs/BETA_ROLLBACK.md (versionName/versionCode 1.0.0/1, '
      'sha256 1f10ee12…d583c)',
  208:
      'internal-beta validation build, CI run 31794343788 (2026-08-14), '
      'crash release identifier wellapath-mobile@0.2.0+208',
};

/// The build number this candidate ships. Must exceed every known entry.
const int kCurrentBuildNumber = 209;

/// The version name this candidate ships.
const String kCurrentVersionName = '0.3.0';

({String name, int build}) _parsePubspecVersion() {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final versionLine = lines.firstWhere(
    (l) => l.startsWith('version:'),
    orElse: () => throw StateError('pubspec.yaml has no version: line'),
  );

  final raw = versionLine.substring('version:'.length).trim();
  final match = RegExp(r'^(\d+\.\d+\.\d+)\+(\d+)$').firstMatch(raw);
  if (match == null) {
    throw StateError(
      'pubspec version "$raw" is not the required <x.y.z>+<build> shape. '
      'A missing build number makes versionCode default to 1 and silently '
      'collides with the first distributed build.',
    );
  }

  return (name: match.group(1)!, build: int.parse(match.group(2)!));
}

void main() {
  group('pubspec version is well-formed', () {
    test('parses as <x.y.z>+<build>', () {
      final version = _parsePubspecVersion();
      expect(version.name, isNotEmpty);
      expect(version.build, greaterThan(0));
    });

    test('exactly one version: line — a second would shadow the first', () {
      final versionLines = File(
        'pubspec.yaml',
      ).readAsLinesSync().where((l) => l.startsWith('version:')).toList();
      expect(versionLines, hasLength(1));
    });
  });

  group('build number is unique and monotonic', () {
    test('matches the declared constant', () {
      expect(_parsePubspecVersion().build, equals(kCurrentBuildNumber));
    });

    test('is greater than every known distributed build number', () {
      final highestKnown = kKnownDistributedBuilds.keys.reduce(
        (a, b) => a > b ? a : b,
      );

      expect(
        kCurrentBuildNumber,
        greaterThan(highestKnown),
        reason:
            'Build $kCurrentBuildNumber does not exceed $highestKnown '
            '(${kKnownDistributedBuilds[highestKnown]}). Android will refuse '
            'the in-place upgrade and Play will reject the upload.',
      );
    });

    test('does not reuse any known build number', () {
      expect(
        kKnownDistributedBuilds.containsKey(kCurrentBuildNumber),
        isFalse,
        reason:
            'Build $kCurrentBuildNumber was already used: '
            '${kKnownDistributedBuilds[kCurrentBuildNumber]}',
      );
    });

    test('every registry entry carries its evidence', () {
      // An entry without provenance cannot be audited, and the next engineer
      // cannot tell whether it is safe to reuse.
      for (final entry in kKnownDistributedBuilds.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: 'build ${entry.key} has no recorded evidence',
        );
        expect(entry.key, greaterThan(0));
      }
    });

    test('the guard actually rejects a regression', () {
      // Mutation check: the assertions above must fail for a bad number, not
      // merely pass for the good one. Without this the guard could be
      // vacuously true and nobody would notice.
      const regressed = 1;
      final highestKnown = kKnownDistributedBuilds.keys.reduce(
        (a, b) => a > b ? a : b,
      );

      expect(regressed > highestKnown, isFalse);
      expect(kKnownDistributedBuilds.containsKey(regressed), isTrue);
    });
  });

  group('version name is coherent', () {
    test('matches the declared constant', () {
      expect(_parsePubspecVersion().name, equals(kCurrentVersionName));
    });

    test('is a plain three-part version with no pre-release suffix', () {
      // Android versionName is free-form, but iOS
      // CFBundleShortVersionString must be one to three dot-separated
      // integers. A suffix like "-beta.1" is rejected at submission, so it
      // cannot live here even though Android would tolerate it.
      expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(kCurrentVersionName), isTrue);
    });
  });

  group('nothing else pins a version', () {
    test(
      'Android reads versionCode/versionName from Flutter, not literals',
      () {
        final gradle = File('android/app/build.gradle.kts').readAsStringSync();

        expect(gradle, contains('versionCode = flutter.versionCode'));
        expect(gradle, contains('versionName = flutter.versionName'));
        expect(
          RegExp(r'versionCode\s*=\s*\d+').hasMatch(gradle),
          isFalse,
          reason: 'a literal versionCode would silently override pubspec',
        );
      },
    );

    test('iOS reads the version from the Flutter-generated values', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, contains(r'$(FLUTTER_BUILD_NAME)'));
      expect(plist, contains(r'$(FLUTTER_BUILD_NUMBER)'));
    });
  });
}
