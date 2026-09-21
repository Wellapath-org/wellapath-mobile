/// Permissions inventory and privacy-manifest presence.
///
/// Store declarations are written against exactly this permission set
/// (`docs/store/PLAY_DECLARATIONS.md`, `docs/store/PLAY_DATA_SAFETY.md`).
/// A permission appearing or disappearing silently would make the published
/// declarations false, so the set is pinned exactly.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String androidManifest;
  late String iosPlist;

  setUpAll(() {
    androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    iosPlist = File('ios/Runner/Info.plist').readAsStringSync();
  });

  group('Android permissions are exactly the declared inventory', () {
    test('exactly INTERNET + FINE/COARSE location, nothing else', () {
      final permissions = RegExp(
        r'<uses-permission android:name="([^"]+)"',
      ).allMatches(androidManifest).map((m) => m.group(1)!).toSet();

      expect(
        permissions,
        equals({
          'android.permission.INTERNET',
          'android.permission.ACCESS_FINE_LOCATION',
          'android.permission.ACCESS_COARSE_LOCATION',
        }),
        reason:
            'The permission set is pinned to what the store declarations '
            'describe. Changing it requires updating docs/store/ first.',
      );
    });

    test('no background location', () {
      expect(androidManifest.contains('ACCESS_BACKGROUND_LOCATION'), isFalse);
    });
  });

  group('iOS purpose strings', () {
    test('location purpose string exists and explains the on-device use', () {
      expect(iosPlist, contains('NSLocationWhenInUseUsageDescription'));
      expect(
        iosPlist,
        contains(
          'WellaPath uses your location to show nearby health '
          'facilities.',
        ),
      );
    });

    test('no other sensitive-capability purpose strings are declared', () {
      // NSLocationAlwaysAndWhenInUseUsageDescription was deliberately moved
      // OFF this denylist for build 211 (ITMS-90683): geolocator_apple
      // compiles the always-authorization API in and Apple's static scan
      // demands the key. The app still never requests always-level access —
      // the plugin's if/else-if requests when-in-use whenever that key
      // exists — and the declared wording explicitly denies background
      // tracking. Pinned by test/release/ios_production_readiness_test.dart.
      for (final key in const [
        'NSCameraUsageDescription',
        'NSMicrophoneUsageDescription',
        'NSContactsUsageDescription',
        'NSPhotoLibraryUsageDescription',
        'NSHealthShareUsageDescription',
        'NSHealthUpdateUsageDescription',
        'NSUserTrackingUsageDescription',
      ]) {
        expect(
          iosPlist.contains(key),
          isFalse,
          reason:
              '$key implies a capability the app does not use and the '
              'declarations do not cover',
        );
      }
    });
  });

  group('iOS app-target privacy manifest', () {
    late String manifest;

    setUpAll(() {
      manifest = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
    });

    test('exists and declares no tracking', () {
      expect(manifest, contains('NSPrivacyTracking'));
      expect(manifest, contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
    });

    test('declares crash, product-interaction and coarse-location data', () {
      // Telemetry and crash reporting are off by default but enable-able in
      // internal builds; declaring them uncollected would be false.
      expect(manifest, contains('NSPrivacyCollectedDataTypeCrashData'));
      expect(
        manifest,
        contains('NSPrivacyCollectedDataTypeProductInteraction'),
      );
      expect(manifest, contains('NSPrivacyCollectedDataTypeCoarseLocation'));
    });

    test(
      'declares no data linked to identity and no data used for tracking',
      () {
        expect(
          manifest.contains(
            '<key>NSPrivacyCollectedDataTypeLinked</key>\n'
            '\t\t\t<true/>',
          ),
          isFalse,
        );
        expect(
          manifest.contains(
            '<key>NSPrivacyCollectedDataTypeTracking</key>\n'
            '\t\t\t<true/>',
          ),
          isFalse,
        );
      },
    );

    test('declares the UserDefaults required-reason API with CA92.1', () {
      expect(manifest, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
      expect(manifest, contains('CA92.1'));
    });

    test('is registered in the Xcode project as a bundled resource', () {
      final pbxproj = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(pbxproj, contains('PrivacyInfo.xcprivacy in Resources'));
    });

    test('does not declare precise location or health data as collected', () {
      // Symptom answers and precise location never leave the device
      // (LOCKED PRINCIPLES #2/#3). If either ever appears here, that claim
      // has been broken somewhere and this file is the tripwire.
      expect(
        manifest.contains('NSPrivacyCollectedDataTypePreciseLocation'),
        isFalse,
      );
      expect(manifest.contains('NSPrivacyCollectedDataTypeHealth'), isFalse);
    });
  });
}
