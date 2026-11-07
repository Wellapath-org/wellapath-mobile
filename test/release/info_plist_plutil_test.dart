@Tags(['plutil'])
/// WP-010: the app Info.plist, judged by Apple's real `/usr/bin/plutil`.
///
/// The string-level checks in `location_privacy_copy_test.dart` read the XML
/// as text. This confirms Apple's parser accepts the file and resolves each
/// location purpose string to exactly the corrected wording, so an escaping
/// or structure mistake cannot ship a different string than the one reviewed.
/// Tagged `plutil`: runs in the mandatory macOS CI job.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/export_options_policy.dart';

const String _plist = 'ios/Runner/Info.plist';

const String _whenInUse =
    'WellaPath uses your location to show nearby health facilities. '
    'Distances are worked out on your device and your location is not sent '
    'to WellaPath. Showing the map requests map images of your area from the '
    'map provider (CARTO).';

const String _alwaysAndWhenInUse =
    'WellaPath does not track your location in the background and never '
    'requests always-on access. Location is used only while you are using '
    'the app, to show nearby health facilities. Distances are worked out on '
    'your device and your location is not sent to WellaPath. Showing the map '
    'requests map images of your area from the map provider (CARTO).';

String _extractRaw(String key) {
  final ProcessResult r = Process.runSync(kPlutilPath, <String>[
    '-extract',
    key,
    'raw',
    '-o',
    '-',
    _plist,
  ]);
  expect(r.exitCode, 0, reason: 'plutil could not extract $key: ${r.stderr}');
  return (r.stdout as String).trimRight();
}

void main() {
  test('Info.plist passes plutil -lint', () {
    final ProcessResult r = Process.runSync(kPlutilPath, <String>[
      '-lint',
      _plist,
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test(
    'NSLocationWhenInUseUsageDescription resolves to the corrected copy',
    () {
      expect(_extractRaw('NSLocationWhenInUseUsageDescription'), _whenInUse);
    },
  );

  test('NSLocationAlwaysAndWhenInUseUsageDescription resolves to the '
      'corrected copy', () {
    expect(
      _extractRaw('NSLocationAlwaysAndWhenInUseUsageDescription'),
      _alwaysAndWhenInUse,
    );
  });
}
