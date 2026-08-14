/// Crash-monitoring configuration gates.
///
/// Collection requires two independent build-time gates. These tests exist
/// because the failure mode is silent in both directions: a build that
/// collects when it should not, and a build that quietly collects nothing
/// while everyone believes it is reporting.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/crash/crash_config.dart';

void main() {
  /// A structurally valid DSN shape. Not a real project — no secret is
  /// committed anywhere in this repository, including in tests.
  const validDsn = 'https://abc123def456@o0.ingest.de.sentry.io/1234567';

  Map<String, String> defines({
    String? enabled,
    String? dsn,
    String? appEnv,
    String? productionApproved,
    String? version,
    String? build,
  }) {
    final map = <String, String>{};
    void put(String key, String? value) {
      if (value != null) map[key] = value;
    }

    put('CRASH_REPORTING_ENABLED', enabled);
    put('SENTRY_DSN', dsn);
    put('APP_ENV', appEnv);
    put('CRASH_REPORTING_PRODUCTION_APPROVED', productionApproved);
    put('APP_VERSION', version);
    put('APP_BUILD', build);
    return map;
  }

  group('disabled by default', () {
    test('no defines at all resolves to disabled', () {
      final config = CrashConfig.fromEnvironment(defines: const {});
      expect(config.enabled, isFalse);
      expect(config.dsn, isEmpty);
    });

    test('the real build path with no defines is disabled', () {
      // Exercises the compile-time constants, which are empty in every
      // ordinary build and in every test run.
      expect(CrashConfig.fromEnvironment().enabled, isFalse);
    });

    test('the disabled constant carries no destination', () {
      expect(CrashConfig.disabled.enabled, isFalse);
      expect(CrashConfig.disabled.dsn, isEmpty);
      expect(CrashConfig.disabled.release, isEmpty);
    });
  });

  group('both gates are required', () {
    test('flag alone, without a DSN, is disabled', () {
      expect(
        CrashConfig.fromEnvironment(defines: defines(enabled: 'true')).enabled,
        isFalse,
      );
    });

    test('DSN alone, without the flag, is disabled', () {
      expect(
        CrashConfig.fromEnvironment(defines: defines(dsn: validDsn)).enabled,
        isFalse,
      );
    });

    test('both together enable collection', () {
      final config = CrashConfig.fromEnvironment(
        defines: defines(enabled: 'true', dsn: validDsn),
      );
      expect(config.enabled, isTrue);
      expect(config.dsn, validDsn);
      expect(config.environment, 'internal-beta');
    });

    for (final value in [
      '',
      ' ',
      '1',
      'yes',
      'on',
      'enabled',
      'tru',
      'false',
    ]) {
      test('CRASH_REPORTING_ENABLED="$value" does not enable', () {
        expect(
          CrashConfig.fromEnvironment(
            defines: defines(enabled: value, dsn: validDsn),
          ).enabled,
          isFalse,
        );
      });
    }

    for (final value in ['true', 'TRUE', 'True', ' true ']) {
      test('CRASH_REPORTING_ENABLED="$value" does enable', () {
        expect(
          CrashConfig.fromEnvironment(
            defines: defines(enabled: value, dsn: validDsn),
          ).enabled,
          isTrue,
        );
      });
    }
  });

  group('DSN validation fails closed', () {
    final invalid = <String, String>{
      'empty': '',
      'whitespace': '   ',
      'not a url': 'not-a-dsn',
      'http not https': 'http://abc@o0.ingest.de.sentry.io/1234567',
      'missing public key': 'https://o0.ingest.de.sentry.io/1234567',
      'missing project id': 'https://abc@o0.ingest.de.sentry.io/',
      'non-numeric project id': 'https://abc@o0.ingest.de.sentry.io/project',
      'unexpanded shell variable': r'https://abc@${SENTRY_HOST}/1234567',
      'documentation placeholder': 'https://<key>@<host>/<project>',
      'literal your-dsn': 'https://your-dsn@o0.ingest.de.sentry.io/1234567',
      'example host': 'https://abc@example.com/1234567',
      'truncated secret': 'https://abc@',
    };

    invalid.forEach((label, dsn) {
      test('$label is rejected', () {
        expect(CrashConfig.isValidDsn(dsn), isFalse, reason: label);
        expect(
          CrashConfig.fromEnvironment(
            defines: defines(enabled: 'true', dsn: dsn),
          ).enabled,
          isFalse,
          reason: 'a malformed DSN must disable collection, not half-enable it',
        );
      });
    });

    test('a well-formed EU DSN is accepted', () {
      expect(CrashConfig.isValidDsn(validDsn), isTrue);
    });
  });

  group('production stays disabled', () {
    for (final env in ['production', 'PRODUCTION', 'prod', ' Prod ']) {
      test('APP_ENV="$env" blocks collection even with both gates', () {
        expect(
          CrashConfig.fromEnvironment(
            defines: defines(enabled: 'true', dsn: validDsn, appEnv: env),
          ).enabled,
          isFalse,
        );
      });
    }

    test('production needs a third, separate approval key', () {
      final config = CrashConfig.fromEnvironment(
        defines: defines(
          enabled: 'true',
          dsn: validDsn,
          appEnv: 'production',
          productionApproved: 'true',
        ),
      );
      expect(config.enabled, isTrue);
    });

    test('the approval key alone enables nothing', () {
      expect(
        CrashConfig.fromEnvironment(
          defines: defines(
            dsn: validDsn,
            appEnv: 'production',
            productionApproved: 'true',
          ),
        ).enabled,
        isFalse,
      );
    });
  });

  group('release identity carries no identifier', () {
    test('release is version and build only', () {
      final config = CrashConfig.fromEnvironment(
        defines: defines(
          enabled: 'true',
          dsn: validDsn,
          version: '0.2.0',
          build: '208',
        ),
      );
      expect(config.release, 'wellapath-mobile@0.2.0+208');
    });

    test('release contains no user, device or session identifier', () {
      final config = CrashConfig.fromEnvironment(
        defines: defines(enabled: 'true', dsn: validDsn),
      );
      for (final forbidden in [
        'user',
        'device',
        'install',
        'session',
        'account',
        'uuid',
      ]) {
        expect(config.release.toLowerCase(), isNot(contains(forbidden)));
      }
    });
  });

  group('the DSN never leaks through diagnostics', () {
    test('diagnostics report configuration without the DSN', () {
      final config = CrashConfig.fromEnvironment(
        defines: defines(enabled: 'true', dsn: validDsn),
      );
      final diagnostics = config.toDiagnostics().toString();
      expect(diagnostics, isNot(contains('abc123def456')));
      expect(diagnostics, isNot(contains(validDsn)));
      expect(config.toDiagnostics()['dsn_configured'], isTrue);
    });

    test('a disabled config reports no destination configured', () {
      expect(CrashConfig.disabled.toDiagnostics()['dsn_configured'], isFalse);
    });
  });
}
