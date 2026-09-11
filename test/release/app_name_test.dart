/// Displayed application name.
///
/// The Android launcher showed `wellapath_mobile` and iOS showed
/// `Wellapath Mobile` — an internal identifier and a mis-cased variant, neither
/// of which is the product's name. A tester installing the beta saw a package
/// name on their home screen.
///
/// The brand is **WellaPath**: one word, capital W, capital P.
///
/// The application identifier was resolved to **org.wellapath.app** on both
/// platforms before any store record exists (closes RC-BLK-010). Once a Play
/// or App Store listing is created against it, it can never change again, so
/// the tests below pin it hard: the same identifier on both platforms, and
/// the retired identifiers gone.
///
/// Verification recorded 2026-09-11, before the change was made:
///  * wellapath.org is WellaPath's own live site ("Join the waitlist ·
///    WellaPath", en-NG) and CLAUDE.md names api-staging.wellapath.org as the
///    project backend — the org.wellapath reverse-DNS identity is legitimately
///    WellaPath's.
///  * org.wellapath.app has never been registered or distributed: Play returns
///    HTTP 404 for it, the iTunes lookup API returns resultCount 0, the full
///    git history (`git log --all -S`) contains no prior use, and the
///    append-only build registry records every distributable build under the
///    old identifiers only.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one correct spelling. Capital W, capital P, no space, no suffix.
const String kBrandName = 'WellaPath';

/// The permanent store identity — identical on both platforms. Never change
/// this once a store record exists.
const String kApplicationId = 'org.wellapath.app';

/// The Android code namespace (R classes, MainActivity package). Deliberately
/// NOT the store identifier: namespace has no store meaning and changing it
/// would churn Kotlin sources for zero product effect.
const String kAndroidNamespace = 'org.wellapath.wellapath_mobile';

/// Retired identifiers that must never reappear as an applicationId or
/// PRODUCT_BUNDLE_IDENTIFIER value.
const List<String> kRetiredIds = ['org.wellapath.wellapathMobile'];

void main() {
  late String androidManifest;
  late String iosPlist;
  late String gradle;
  late String pbxproj;

  setUpAll(() {
    androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    iosPlist = File('ios/Runner/Info.plist').readAsStringSync();
    gradle = File('android/app/build.gradle.kts').readAsStringSync();
    pbxproj = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
  });

  group('Android launcher label', () {
    test('is the brand name', () {
      expect(androidManifest, contains('android:label="$kBrandName"'));
    });

    test('is not the internal identifier', () {
      expect(
        androidManifest,
        isNot(contains('android:label="wellapath_mobile"')),
        reason: 'the launcher must not show a package-style identifier',
      );
    });

    test('exactly one label is declared on the application element', () {
      final labels = RegExp(
        r'android:label="[^"]*"',
      ).allMatches(androidManifest).map((m) => m.group(0)).toList();

      expect(
        labels,
        hasLength(1),
        reason: 'a second label would make the displayed name ambiguous',
      );
    });
  });

  group('iOS display name', () {
    /// Returns the string value following [key] in the plist.
    String? plistValue(String key) {
      final match = RegExp(
        '<key>$key</key>\\s*<string>([^<]*)</string>',
      ).firstMatch(iosPlist);
      return match?.group(1);
    }

    test('CFBundleDisplayName is the brand name', () {
      // This is what the home screen shows.
      expect(plistValue('CFBundleDisplayName'), equals(kBrandName));
    });

    test('CFBundleName is the brand name', () {
      // The fallback when CFBundleDisplayName is absent, and what several
      // system surfaces (Settings, storage) use.
      expect(plistValue('CFBundleName'), equals(kBrandName));
    });

    test('neither shows the old value', () {
      expect(iosPlist, isNot(contains('Wellapath Mobile')));
      expect(iosPlist, isNot(contains('wellapath_mobile')));
    });

    test('CFBundleName fits the 15-character limit', () {
      // Longer values are truncated by iOS, and rejected by some review
      // tooling. "WellaPath" is 9.
      expect(plistValue('CFBundleName')!.length, lessThanOrEqualTo(15));
    });
  });

  group('brand spelling is exact', () {
    test('capital W and capital P, one word', () {
      expect(kBrandName, equals('WellaPath'));
      expect(kBrandName, isNot(contains(' ')));
      expect(RegExp(r'^[A-Z][a-z]+[A-Z][a-z]+$').hasMatch(kBrandName), isTrue);
    });

    test('no platform shows a differently-cased variant', () {
      for (final wrong in const [
        'Wellapath Mobile',
        'wellapath_mobile',
        'WellaPath Mobile',
        'wellapathMobile',
      ]) {
        expect(
          androidManifest.contains('android:label="$wrong"'),
          isFalse,
          reason: 'Android label must not be "$wrong"',
        );
        expect(
          iosPlist.contains('<string>$wrong</string>'),
          isFalse,
          reason: 'iOS name keys must not be "$wrong"',
        );
      }
    });
  });

  group('application identity — one identifier, both platforms', () {
    // Changing any of these after a store record exists is impossible.
    // RC-BLK-010 is closed by this parity; do not reopen it silently.
    test('Android applicationId is the permanent identifier', () {
      expect(gradle, contains('applicationId = "$kApplicationId"'));
    });

    test('iOS bundle identifier is the permanent identifier', () {
      expect(pbxproj, contains('PRODUCT_BUNDLE_IDENTIFIER = $kApplicationId;'));
    });

    test('every Runner build configuration uses the permanent identifier', () {
      // Debug, Release and Profile must all agree — a Profile build with a
      // stale identifier would install as a different app.
      final ids = RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);',
      ).allMatches(pbxproj).map((m) => m.group(1)!).toSet();
      expect(ids, equals({kApplicationId, '$kApplicationId.RunnerTests'}));
    });

    test('Android namespace stays the code-only package', () {
      expect(gradle, contains('namespace = "$kAndroidNamespace"'));
    });

    test('no retired identifier remains as a platform identity', () {
      for (final retired in kRetiredIds) {
        expect(
          gradle.contains('applicationId = "$retired"'),
          isFalse,
          reason: 'Android applicationId must not be the retired "$retired"',
        );
        expect(
          pbxproj.contains('= $retired;'),
          isFalse,
          reason: 'iOS bundle identifier must not be the retired "$retired"',
        );
      }
    });

    test('the identifier is a well-formed reverse-DNS id on both stores', () {
      // Play: two or more segments, each starting with a letter, only
      // [a-zA-Z0-9_]. Apple: RFC-1035-ish, alphanumerics and hyphens.
      // org.wellapath.app satisfies the intersection.
      expect(
        RegExp(
          r'^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*)+$',
        ).hasMatch(kApplicationId),
        isTrue,
      );
    });
  });
}
