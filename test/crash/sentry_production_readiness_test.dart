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

  group(
    'the environment label cannot be spoofed by a stale APP_ENV define',
    () {
      test(
        'bundled production + approval + APP_ENV=staging → still production',
        () {
          // A leftover CI define must not tag production data as staging.
          final config = CrashConfig.fromEnvironment(
            defines: {
              ...bothGates(),
              'CRASH_REPORTING_PRODUCTION_APPROVED': 'true',
              'APP_ENV': 'staging',
            },
            bundledIsProduction: true,
          );
          expect(config.enabled, isTrue);
          expect(config.environment, 'production');
        },
      );

      test('CRASH_REPORTING_CONTEXT=internal-testing labels the 212 test', () {
        final config = CrashConfig.fromEnvironment(
          defines: {
            ...bothGates(),
            'CRASH_REPORTING_PRODUCTION_APPROVED': 'true',
            'CRASH_REPORTING_CONTEXT': 'internal-testing',
          },
          bundledIsProduction: true,
        );
        expect(config.enabled, isTrue);
        expect(config.environment, 'internal-testing');
      });

      test('an unknown context value falls back to the derived label', () {
        final config = CrashConfig.fromEnvironment(
          defines: {
            ...bothGates(),
            'CRASH_REPORTING_PRODUCTION_APPROVED': 'true',
            'CRASH_REPORTING_CONTEXT': 'my-custom-env',
          },
          bundledIsProduction: true,
        );
        expect(config.environment, 'production');
      });

      test('the context define never affects the gates themselves', () {
        final config = CrashConfig.fromEnvironment(
          defines: {
            ...bothGates(),
            'CRASH_REPORTING_CONTEXT': 'internal-testing',
          },
          bundledIsProduction: true,
        );
        // No approval key: still blocked, whatever the label says.
        expect(config.enabled, isFalse);
      });
    },
  );

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

    test('adversarial corpus from the PR #81 review never survives', () {
      final cases = <String, List<String>>{
        'NoSuchMethodError: severeHeadache on null': ['severeHeadache'],
        'failed at 6.52, 3.37 near user': ['6.52', '3.37'],
        'GET /facilities?q=malaria&lat=6.52 timed out': [
          'q=malaria',
          'lat=6.52',
          '6.52',
        ],
        'state feverScore=high chestPain=true': ['feverScore', 'chestPain'],
        'patient reported chest pain since Tuesday': ['chest', 'pain'],
        'token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig rejected': [
          'eyJhbGciOiJIUzI1NiJ9',
        ],
        'call 0801 234 5678 failed': ['0801 234 5678'],
        'X-Auth-Token: tok_live_1234 refused': ['tok_live_1234'],
        // Second cookie in a chained header (PR #81 review finding).
        'Cookie: locale=en; sid=tok9xyz1 expired': ['sid=tok9xyz1', 'tok9xyz1'],
        'Authorization: Bearer abc123x, Basic dXNlcg== retry': [
          'abc123x',
          'dXNlcg',
        ],
        // Short credential assignment outside any header context.
        'refresh failed sid=tok9xyz1 retrying': ['tok9xyz1'],
        // Header name outside the curated list, short non-snake value.
        'X-Auth-Token: k9f3a2b1 rejected': ['k9f3a2b1'],
        // Relative redirect path with encoded free text and 4-decimal coords.
        'Redirect location: /search?q=chest+pain&lat=6.5244&lng=3.3792': [
          'chest+pain',
          '6.5244',
          '3.3792',
        ],
        // Quote-eating interaction: the URL scrub must not consume the
        // closing quote and re-pair later quotes past the free text.
        "Invalid response for 'https://api.wellapath.org/cfg?t=1' with body "
            "'severe pain in chest'": [
          'severe pain',
          'chest',
        ],
      };
      cases.forEach((input, needles) {
        final out = CrashSanitiser.sanitise(Exception(input));
        for (final needle in needles) {
          expect(out, isNot(contains(needle)), reason: 'in: $input');
        }
      });
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
