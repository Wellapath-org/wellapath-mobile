/// Production-readiness gates added for the build-212 activation line.
///
/// Three properties are pinned here on top of the PR #65–#68 suite:
///
///  1. the production block engages from the **bundled** environment, not
///     only from an `APP_ENV` define — since build 211 the tracked `.env`
///     declares production, so a define-only check would wave through the
///     common case (crash defines set, `APP_ENV` define omitted);
///  2. session replay is explicitly off, in both sample rates;
///  3. the newest scrubbing rules: URL query strings and credential headers
///     never survive an exception message.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wellapath_mobile/core/crash/crash_config.dart';
import 'package:wellapath_mobile/core/crash/crash_reporter.dart';
import 'package:wellapath_mobile/core/crash/sentry_crash_sink.dart';

const String validDsn = 'https://abc123@o447951.ingest.de.sentry.io/1234567';

Map<String, String> bothGates() => const {
  'CRASH_REPORTING_ENABLED': 'true',
  'SENTRY_DSN': validDsn,
};

void main() {
  group('the production block reads the bundled environment', () {
    test('bundled production + both gates, no APP_ENV define → disabled', () {
      final config = CrashConfig.fromEnvironment(
        defines: bothGates(),
        bundledIsProduction: true,
      );
      expect(config.enabled, isFalse);
    });

    test(
      'bundled production + approval key → enabled, labelled production',
      () {
        final config = CrashConfig.fromEnvironment(
          defines: {
            ...bothGates(),
            'CRASH_REPORTING_PRODUCTION_APPROVED': 'true',
          },
          bundledIsProduction: true,
        );
        expect(config.enabled, isTrue);
        expect(config.environment, 'production');
      },
    );

    test('an unreadable bundled environment fails closed to the block', () {
      // No dotenv is initialised in tests, so the default resolution models
      // exactly the ambiguous case: it must land on the production block.
      final config = CrashConfig.fromEnvironment(defines: bothGates());
      expect(config.enabled, isFalse);
    });

    test('bundled staging with both gates remains the internal path', () {
      final config = CrashConfig.fromEnvironment(
        defines: bothGates(),
        bundledIsProduction: false,
      );
      expect(config.enabled, isTrue);
      expect(config.environment, 'internal-beta');
    });
  });

  group('session replay is explicitly off', () {
    test('both replay sample rates are pinned to null', () {
      // applyPrivacyOptions is asserted directly — CrashMonitoring.init is
      // deliberately NOT called with an enabled config here, so no SDK
      // client can start inside the test run.
      final options = SentryFlutterOptions();
      // ignore: invalid_use_of_visible_for_testing_member
      CrashMonitoring.applyPrivacyOptions(options);
      expect(options.replay.sessionSampleRate, isNull);
      expect(options.replay.onErrorSampleRate, isNull);
      expect(options.attachScreenshot, isFalse);
      // ignore: experimental_member_use
      expect(options.attachViewHierarchy, isFalse);
      expect(options.tracesSampleRate, isNull);
      expect(options.sendDefaultPii, isFalse);
    });
  });

  group('URL queries and credential headers are scrubbed', () {
    test('a query string never survives; scheme, host and path do', () {
      final out = CrashSanitiser.sanitise(
        Exception(
          'GET https://api.wellapath.org/facilities?q=fever&lat=6.5244&lng=3.3792 failed',
        ),
      );
      expect(out, contains('https://api.wellapath.org/facilities'));
      expect(out, isNot(contains('q=')));
      expect(out, isNot(contains('6.5244')));
      expect(out, isNot(contains('3.3792')));
      expect(out, isNot(contains('fever')));
    });

    test('a fragment never survives', () {
      final out = CrashSanitiser.sanitise(
        Exception('https://api.wellapath.org/config#section-token-abc failed'),
      );
      expect(out, isNot(contains('section-token-abc')));
    });

    test('authorization and cookie headers never survive', () {
      for (final message in [
        'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig rejected',
        'authorization=Basic dXNlcjpwYXNz failed',
        'Cookie: session=abcdef123456 expired',
        'Set-Cookie: sid=xyz; HttpOnly',
        'X-Api-Key: k-12345678 invalid',
      ]) {
        final out = CrashSanitiser.sanitise(Exception(message));
        expect(out, isNot(contains('eyJ')), reason: message);
        expect(out, isNot(contains('dXNlcjpwYXNz')), reason: message);
        expect(out, isNot(contains('abcdef123456')), reason: message);
        expect(out, isNot(contains('sid=xyz')), reason: message);
        expect(out, isNot(contains('k-12345678')), reason: message);
      }
    });

    test(
      'the existing identity patterns still hold alongside the new ones',
      () {
        final out = CrashSanitiser.sanitise(
          Exception(
            'user jane@example.com (+2348012345678) at 6.5244, 3.3792 '
            'searched severe_headache with urgency URGENT',
          ),
        );
        expect(out, isNot(contains('jane@example.com')));
        expect(out, isNot(contains('2348012345678')));
        expect(out, isNot(contains('6.5244')));
        expect(out, isNot(contains('severe_headache')));
        expect(out, isNot(contains('URGENT')));
      },
    );
  });
}
