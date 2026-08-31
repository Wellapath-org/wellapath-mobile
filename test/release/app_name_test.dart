/// Displayed application name.
///
/// The Android launcher showed `wellapath_mobile` and iOS showed
/// `Wellapath Mobile` — an internal identifier and a mis-cased variant, neither
/// of which is the product's name. A tester installing the beta saw a package
/// name on their home screen.
///
/// The brand is **WellaPath**: one word, capital W, capital P.
///
/// This step changes display labels **only**. The Android application ID and
/// the iOS bundle ID are deliberately untouched — they are store-record
/// identity and cannot be changed once a listing exists, so they are a separate
/// decision (RC-BLK-010). The tests below pin both facts: the labels must be
/// correct, and the IDs must not have moved.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one correct spelling. Capital W, capital P, no space, no suffix.
const String kBrandName = 'WellaPath';

/// Identifiers that must NOT change in this step.
const String kAndroidApplicationId = 'org.wellapath.wellapath_mobile';
const String kIosBundleId = 'org.wellapath.wellapathMobile';

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

  group('application identity is NOT changed by this step', () {
    // Changing either of these after a store record exists is impossible.
    // They are tracked as RC-BLK-010 and decided separately.
    test('Android applicationId is unchanged', () {
      expect(gradle, contains('applicationId = "$kAndroidApplicationId"'));
    });

    test('Android namespace is unchanged', () {
      expect(gradle, contains('namespace = "$kAndroidApplicationId"'));
    });

    test('iOS bundle identifier is unchanged', () {
      expect(pbxproj, contains('PRODUCT_BUNDLE_IDENTIFIER = $kIosBundleId;'));
    });

    test('the two platform IDs still differ — the open decision stands', () {
      // Asserted so that if someone reconciles them, this test fails and
      // forces the blocker to be closed deliberately rather than silently.
      expect(kAndroidApplicationId, isNot(equals(kIosBundleId)));
    });
  });
}
