/// WP-010: location privacy copy must match what the app actually does.
///
/// Verified behaviour (see the PR for the evidence):
///
///  * coordinates are read on device and used only to compute distances;
///    no telemetry field exists for them and `admin_area_code` is never
///    populated, so WellaPath does not receive the location;
///  * the clinic map is centred on the user at zoom 15 and requests CARTO
///    tiles (`basemaps.cartocdn.com`) for that area. Tile coordinates at that
///    zoom identify roughly a 1 km square, and the request carries the
///    device IP, so the location does leave the device in approximate form;
///  * directions open Google Maps with the facility's coordinates.
///
/// So every "never leaves your device" claim about location was false. These
/// tests stop it coming back and pin the replacement disclosure.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _locationCopySources = <String>[
  'ios/Runner/Info.plist',
  'lib/features/locator/locator_screen.dart',
  'lib/features/more/more_screen.dart',
  'lib/features/help/help_content.dart',
];

/// The two iOS location purpose strings, exactly as they appear in the plist.
Map<String, String> _purposeStrings() {
  final String plist = File('ios/Runner/Info.plist').readAsStringSync();
  final Map<String, String> out = <String, String>{};
  for (final String key in const <String>[
    'NSLocationWhenInUseUsageDescription',
    'NSLocationAlwaysAndWhenInUseUsageDescription',
  ]) {
    final RegExpMatch? m = RegExp(
      '<key>$key</key>\\s*<string>([^<]*)</string>',
    ).firstMatch(plist);
    // Runs while tests are being declared, where `expect` is unavailable.
    if (m == null) throw StateError('$key must be declared in Info.plist');
    out[key] = m.group(1)!;
  }
  return out;
}

void main() {
  group('no source claims location never leaves the device', () {
    for (final String path in _locationCopySources) {
      test(path, () {
        final String lower = File(path).readAsStringSync().toLowerCase();
        for (final String claim in const <String>[
          'never leaves your device',
          'never leaves the device',
          'location stays on your device',
          'location never leaves',
        ]) {
          // Allowed only inside the explanatory code comment recording what
          // the old wording was; never in a user-visible string.
          final Iterable<String> visible = lower
              .split('\n')
              .where((String l) => !l.trimLeft().startsWith('//'));
          expect(
            visible.any((String l) => l.contains(claim)),
            isFalse,
            reason: '$path still claims "$claim"',
          );
        }
      });
    }
  });

  group('iOS location purpose strings disclose the map provider', () {
    for (final MapEntry<String, String> entry in _purposeStrings().entries) {
      test(entry.key, () {
        expect(entry.value, contains('not sent to WellaPath'));
        expect(entry.value, contains('map provider (CARTO)'));
      });
    }
  });

  group('in-app copy discloses the map provider', () {
    test('location permission rationale', () {
      final String src = File(
        'lib/features/locator/locator_screen.dart',
      ).readAsStringSync();
      expect(src, contains('is not sent to WellaPath'));
      expect(src, contains('from the map provider (CARTO)'));
    });

    test('More screen and Help name CARTO and Google Maps', () {
      for (final String path in const <String>[
        'lib/features/more/more_screen.dart',
        'lib/features/help/help_content.dart',
      ]) {
        final String src = File(path).readAsStringSync();
        expect(src, contains('(CARTO)'), reason: path);
        expect(src, contains('Google'), reason: path);
        expect(src, contains('approximate area'), reason: path);
      }
    });
  });

  group('the disclosed provider is the one the code actually calls', () {
    test('tiles come from CARTO and directions from Google Maps', () {
      final String locator = File(
        'lib/features/locator/locator_screen.dart',
      ).readAsStringSync();
      expect(locator, contains('https://basemaps.cartocdn.com/'));
      expect(locator, contains('https://www.google.com/maps/dir/'));
    });
  });
}
