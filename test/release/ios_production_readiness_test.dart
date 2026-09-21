/// iOS production-readiness pins for build 211 (Apple warning remediation).
///
/// ITMS-90683: the binary references always-location APIs because
/// `geolocator_apple` compiles `requestAlwaysAuthorization` in and SPM
/// integration offers no way to set its `BYPASS_PERMISSION_LOCATION_ALWAYS`
/// define without forking. Apple's static scan therefore requires
/// `NSLocationAlwaysAndWhenInUseUsageDescription`. Runtime behaviour is
/// unchanged and When-In-Use only, structurally: the plugin's
/// PermissionHandler is an if/ELSE-if that calls
/// `requestWhenInUseAuthorization` whenever
/// `NSLocationWhenInUseUsageDescription` exists, so the always branch is
/// unreachable while that key is present — which this suite pins.
///
/// ITMS-90068: deployment target raised to iOS 15.0 (same hardware floor
/// as 13.0 — iPhone 6s and later — ahead of Apple's Spring 2027 rule).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
  final pbxproj = File(
    'ios/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();

  group('location purpose strings (ITMS-90683)', () {
    test('when-in-use description is present with the approved wording', () {
      expect(infoPlist, contains('NSLocationWhenInUseUsageDescription'));
      expect(
        infoPlist,
        contains(
          'WellaPath uses your location to show nearby health facilities. '
          'Your location never leaves your device.',
        ),
      );
    });

    test('always-and-when-in-use description is present, accurate and '
        'explicitly denies background tracking', () {
      expect(
        infoPlist,
        contains('NSLocationAlwaysAndWhenInUseUsageDescription'),
      );
      expect(
        infoPlist,
        contains(
          'WellaPath does not track your location in the background and '
          'never requests always-on access.',
        ),
      );
    });

    test('the always key never appears without the when-in-use key that '
        'keeps its branch unreachable', () {
      // geolocator_apple PermissionHandler.m: `if (WhenInUse key) request
      // when-in-use; else if (always key) request always`. The always key
      // alone would therefore flip runtime requests to always-level — the
      // implication pinned here is the actual safety property.
      final hasAlwaysKey = infoPlist.contains(
        'NSLocationAlwaysAndWhenInUseUsageDescription',
      );
      final hasWhenInUseKey = infoPlist.contains(
        'NSLocationWhenInUseUsageDescription',
      );
      expect(
        !hasAlwaysKey || hasWhenInUseKey,
        isTrue,
        reason:
            'NSLocationAlwaysAndWhenInUseUsageDescription without '
            'NSLocationWhenInUseUsageDescription makes geolocator request '
            'always-level authorization',
      );
    });

    test('no standalone legacy always key and no background location mode', () {
      expect(
        infoPlist.contains('NSLocationAlwaysUsageDescription</key>'),
        isFalse,
        reason: 'the deprecated standalone always key must not appear',
      );
      expect(
        infoPlist.contains('UIBackgroundModes'),
        isFalse,
        reason: 'no background execution modes are approved',
      );
    });
  });

  group('export compliance', () {
    test('ITSAppUsesNonExemptEncryption is declared false', () {
      // Audited 2026-09-16: the app uses only SHA-256 hashing (artifact
      // integrity) and platform TLS — exempt standard encryption.
      final keyIndex = infoPlist.indexOf('ITSAppUsesNonExemptEncryption');
      expect(keyIndex, greaterThanOrEqualTo(0));
      final end = keyIndex + 120 > infoPlist.length
          ? infoPlist.length
          : keyIndex + 120;
      final after = infoPlist.substring(keyIndex, end);
      expect(after, contains('<false/>'));
    });
  });

  group('deployment target (ITMS-90068)', () {
    test('every configuration targets iOS 15.0', () {
      final matches = RegExp(
        r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);',
      ).allMatches(pbxproj).map((m) => m.group(1)).toSet();
      expect(matches, {'15.0'});
    });
  });
}
