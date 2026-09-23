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
/// consumed — attached to a distributable or distributed artifact, or to a
/// Sentry release from a local-only verification build. It is append-only:
/// entries are added when a number is consumed, never edited or removed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every build number this project has ever CONSUMED, with where the
/// evidence comes from. Append-only. Consumption means the number was
/// attached to any artifact or external record — a distributed or
/// distributable binary, OR a Sentry release created during a local-only
/// verification. Burned local-only numbers (212–214) are recorded here
/// even though they were never distributed and never may be, because a
/// Sentry release bearing them exists and reuse would make two different
/// artifacts indistinguishable in crash triage. The map keeps its
/// historical name; read "Distributed" as "consumed".
///
/// Two numbering namespaces exist and both are recorded, because a future
/// reader who knows only one of them would pick a colliding number:
///
///  * **Platform build number** — `pubspec` `+N`, becoming Android
///    `versionCode` and iOS `CFBundleVersion`. Stayed `1` until the 0.3.0
///    line; real versionCodes then advanced through 209–214 (see the
///    entries below).
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
  209:
      'release candidate 0.3.0+209 (PR #77, merge 7961883) — signed '
      'internal-testing AABs sha256 cfa41692…166e (62,078,226 B) and '
      '096b45bc…cd54 (62,077,759 B) plus a release-signed APK were built '
      'under org.wellapath.wellapath_mobile. Never uploaded to any store or '
      'tester track, but the number was attached to distributable signed '
      'artifacts and must not be reused — especially since the application '
      'identifier changed to org.wellapath.app afterwards',
  210:
      'internal-testing build 0.3.0+210 (commit 5a1930b) — the first build '
      'UPLOADED to any store console: iOS IPA sha256 bd1f378b…9f46 '
      '(27,085,109 B) uploaded to App Store Connect / TestFlight internal '
      'on 2026-09-21 (team 2SCUC2CBBS, org.wellapath.app). The signed '
      'Android AAB sha256 818d60b1…129d4 (62,090,832 B) was built but not '
      'uploaded. The number is burned on both platforms',
  211:
      'internal-testing build 0.3.0+211 (distributed 2026-09-21): iOS IPA '
      'sha256 7c39f4f8… uploaded to TestFlight internal; signed Android AAB '
      'sha256 690249ae… built. The number is burned',
  212:
      'LOCAL VERIFICATION ONLY — consumed/burned, never distributed, never '
      'to be distributed. Release APKs built 2026-09-22 on the abandoned '
      'local-only branch build/212-internal-verification for the '
      'crash-transport investigation; release wellapath-mobile@0.3.0+212 '
      'exists in Sentry, so the number is burned',
  213:
      'LOCAL VERIFICATION ONLY — consumed/burned, never distributed, never '
      'to be distributed. One release APK built 2026-09-22 on the abandoned '
      'local-only branch build/213-transport-verification; its one '
      'controlled event was received and audited (transport/privacy/'
      'identity passed; geo scrub, debug_meta and symbolication failed — '
      'all three causes fixed by PR #83); release '
      'wellapath-mobile@0.3.0+213 exists in Sentry, so the number is '
      'burned',
  214:
      'LOCAL VERIFICATION ONLY — consumed/burned, never distributed and '
      'never distributable. One release APK built 2026-09-23 on the '
      'abandoned local-only branch build/214-transport-verification, '
      'sha256 f45be13bc4f1564657e8142b1154c57e6c024d5824fefa19230adc7104a2'
      'd86f, release-signed, org.wellapath.app versionCode 214, installed '
      'only on the wellapath_lowend emulator; uploaded arm64 symbols debug '
      'ID 098518b7-57d7-7fd7-1ab8-0642754b65d3. Its ONE permitted '
      'synthetic event was sent 2026-09-23T08:48:04Z, received and audited '
      'fields-only: final verdict PASS 5/5 with two qualified '
      'representations (a null-valued user.geo scrub shell retained by '
      'Sentry; four server-added debug-image keys beyond the five '
      'client-transmitted fields) and one build-path finding (symbolicated '
      'abs_path exposed the build engineer\'s username — neutral-path '
      'remediation required before any distribution). See '
      'docs/CRASH_VERIFICATION_214_REPORT.md. Release '
      'wellapath-mobile@0.3.0+214 exists in Sentry, so the number is '
      'burned',
};

/// The build number this candidate ships. Must exceed every known entry.
///
/// 215 has never been attached to anything: it appears in no tag, no CI
/// release identifier, no rollback record, no Sentry release and no
/// registry entry above. It is the earliest potentially distributable
/// Sentry-enabled candidate, contingent on the build-path remediation and
/// the store privacy-declaration update recorded in
/// docs/CRASH_VERIFICATION_214_REPORT.md.
const int kCurrentBuildNumber = 215;

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
