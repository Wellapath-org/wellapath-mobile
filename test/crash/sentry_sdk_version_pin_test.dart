/// Pins the resolved Sentry SDK versions to [CrashMonitoring.sdkVersion].
///
/// The crash integration carries implementation imports (integration
/// removal) and behaviour written against SDK 9.27.0 source
/// (`WellaPathTransport`, the debug-image allowlist). A moved file fails
/// the build loudly; a version bump whose paths still resolve would drift
/// SILENTLY — this test turns that drift into a red build, so an SDK
/// upgrade forces a deliberate re-review of every pinned assumption.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/crash/sentry_crash_sink.dart';

void main() {
  test('pubspec.lock resolves sentry and sentry_flutter at the pinned '
      'version', () {
    final String lock = File('pubspec.lock').readAsStringSync();

    String resolved(String package) {
      final RegExp entry = RegExp(
        '\n  $package:\n(?:.*\n)*?    version: "([^"]+)"',
      );
      final Match? match = entry.firstMatch(lock);
      expect(match, isNotNull, reason: '$package missing from pubspec.lock');
      return match!.group(1)!;
    }

    expect(resolved('sentry'), CrashMonitoring.sdkVersion);
    expect(resolved('sentry_flutter'), CrashMonitoring.sdkVersion);
  });
}
