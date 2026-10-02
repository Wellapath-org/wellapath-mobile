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
  215:
      'internal-testing build 0.3.0+215 — the first build of the merged '
      'everyday-experience UI. Built 2026-09-25 from develop @ '
      'd84fdac11ead50009f52d01429fc7fe96075e755 (tree 8a6ddc5a…) in the '
      'approved neutral root /Users/Shared/wellapath-build-215 with a '
      'build-local PUB_CACHE and zero dart-defines. Signed Android AAB '
      'sha256 bfc8d401163c838658dcedc34397b18f65cd3ecc9030c77e1c4541f555d6'
      '0917 (62,395,097 B), org.wellapath.app versionCode 215 / '
      'versionName 0.3.0, jar verified, upload certificate SHA-256 '
      '94:E7:C5:74:…:D8:36 — byte-identical fingerprint to build 211, so '
      'the established upload key was used and no signing-ownership or '
      'Play App Signing decision arises. Neutral-path scanner exit 0 (28 '
      'files, 0 findings). No DSN, no Sentry auth token, no staging '
      'configuration; bundled .env byte-identical to the tracked '
      'production file; Feedback and Support Chat control strings absent '
      'from libapp.so (tree-shaken, flags compile-time false). Preserved '
      'at wellapath-release-215/WellaPath-215.aab. INTERNAL TESTING ONLY '
      '— must never be promoted beyond the Play Internal track or the '
      'TestFlight internal group, and must not replace build 211 as the '
      'soft-launch candidate. The number is consumed because a signed '
      'release artifact exists, independently of store processing. iOS, in '
      'sequence: at the first evidence point the IPA had NOT been produced, '
      'because the Apple Distribution (2SCUC2CBBS) private key was absent '
      'from this Mac; the founder then authorised a replacement certificate '
      'on 2026-09-25 and the IPA was produced the same day, which is the '
      'artifact recorded here. iOS IPA sha256 f8cd9d322c6887be'
      '6d6a56d1b571e5e1994bf5622e05ea6975d917cb4928ca74 (26,596,891 B), '
      'org.wellapath.app 0.3.0 (215), min iOS 15.0, signed Apple '
      'Distribution: Pixus Uganda - SMC LTD (2SCUC2CBBS) with the App '
      'Store profile, exported from a neutral-DerivedData archive that '
      'scans clean',
  216:
      'internal-testing build 0.3.0+216 — the COPY-001 disclosure grammar fix '
      'and the UX-002 out-of-region manual area search, plus the facility '
      'attribution footer. Built 2026-10-02 from develop @ '
      '34a331f4b47395df2084250fd6f53b86d30239e1 (tree 1d35237a…, the merge of '
      'PR #94, CI "Flutter Lint & Build Check" success run 36682391970 on that '
      'exact SHA) in the approved neutral root '
      '/Users/Shared/wellapath-build-216 with a build-local PUB_CACHE and zero '
      'dart-defines. Signing material was referenced by symlink and never '
      'copied or read. Signed Android AAB sha256 '
      '2135ecf0f2c7fc53091c71ac4ef697c8f9a4ef6f35d3c1a8c9d5b6248b5d66da '
      '(62,409,495 B), org.wellapath.app versionCode 216 / versionName 0.3.0, '
      'jar verified, upload certificate SHA-256 94:E7:C5:74:…:D8:36 — '
      'byte-identical fingerprint to builds 211 and 215, so the established '
      'upload key was used and no signing-ownership or Play App Signing '
      'decision arises. Signed iOS IPA sha256 '
      '3b433576cf5314afe661d0ba941cb192b5536949554d870dff8abf52155fda85 '
      '(12,619,526 B; 25,255,769 B uncompressed across 117 entries — smaller '
      'than 215 purely from zip compression, with the full Dart AOT '
      'App.framework/App at 7,993,856 B present), org.wellapath.app 0.3.0 '
      '(216), min iOS 15.0, arm64, signed Apple Distribution: Pixus Uganda - '
      'SMC LTD (2SCUC2CBBS) cert SHA-1 '
      '6F191637AA0968B1E1529044D56E93B89AEEF649 with the EXISTING App Store '
      'profile "iOS Team Store Provisioning Profile: org.wellapath.app" (UUID '
      'daebf88b-ed39-45b4-914b-a627cf76831d); no certificate, key, keystore or '
      'profile was created or replaced, and -allowProvisioningUpdates was '
      'deliberately not passed. Exported with destination=export and '
      'testFlightInternalTestingOnly=true, so the build cannot be submitted '
      'for Beta App Review or external testing by construction. Neutral-path '
      'scanner exit 0 on every upload input: 33 files for the AAB set, 99 for '
      'the IPA + archive, 14 for the dSYMs — 0 prohibited findings, 0 input '
      'errors. This specifically clears the build-214 finding: an earlier '
      'unsigned validation build that used the DEFAULT personal DerivedData '
      'failed with personal_home_macos and configured_personal_name in the '
      'Runner binary, and with an explicit neutral -derivedDataPath both '
      'findings are ABSENT from the archive binary and from '
      'dSYMs/Runner.app.dSYM DWARF. Bundled .env byte-identical to the tracked '
      'production file (sha256 71ad44e3…fb96, 1,220 B) in BOTH artifacts; no '
      'DSN, no Sentry auth token; Feedback and Support Chat control strings '
      'absent from libapp.so and from App.framework/App (tree-shaken, flags '
      'compile-time false). INTERNAL TESTING ONLY — must never be promoted '
      'beyond the Play Internal track or the TestFlight internal group. The '
      'number is consumed because signed release artifacts exist, '
      'independently of store processing. UPLOAD STATE, both platforms, '
      '2026-10-02 (an earlier revision of this entry said the Android AAB had '
      'not been uploaded; that was true when written and is superseded by the '
      'founder confirmation recorded in PROGRESS.md, which keeps the earlier '
      'wording verbatim). iOS: ENGINEERING uploaded this build to App Store '
      'Connect from the verified archive via the authenticated Xcode account '
      'flow (xcodebuild -exportArchive, destination=upload); Apple then '
      'PROCESSED it and made it available through the existing TestFlight '
      'internal-testing setup, and the FOUNDER installed the TestFlight update '
      'on an iPhone, launched it and observed that it worked as expected — a '
      'founder observation, not an automated measurement and not a '
      'comprehensive Nigerian geographic validation. Android: the FOUNDER '
      'uploaded the AAB above to the existing Google Play Internal testing '
      'track; recorded as UPLOADED ONLY — no Play processing state, release ID, '
      'timestamp, tester count or availability to testers has been observed or '
      'is claimed. The iOS package App Store Connect received was repackaged by '
      'the upload export, so its bytes are NOT the export-only IPA sha256 '
      'recorded above; both came from this one archive, and the archive, '
      'signing identity, provisioning profile and scanned-content provenance '
      'are established for both. TestFlight Internal Only: not offered to '
      'external testers and not submitted for Beta App Review. No public, '
      'external or production distribution. Builds 211 and 215 remain retained '
      'and available, not promoted, replaced or deleted',
};

/// The build number this candidate ships. Must exceed every known entry.
///
/// 217 has never been attached to anything: it appears in no tag, no CI
/// release identifier, no rollback record, no Sentry release and no
/// registry entry above. 216 was consumed on 2026-10-02 the moment a
/// signed release AAB existed — before any store processing — so rebuilding
/// 216 from different source could produce two artifacts that crash triage
/// and Play both treat as the same build.
const int kCurrentBuildNumber = 217;

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
