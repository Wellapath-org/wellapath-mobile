/// Build-environment configuration gates.
///
/// Since build 211 the bundled `.env` is the PRODUCTION configuration
/// (api.wellapath.org, verified 2026-09-21; RC-BLK-005 closed). These tests
/// pin the two directions of the cross-environment gate — an internal build
/// must fail if it points at production, and a production build must fail
/// if it points at staging — plus the bundled `.env` itself and the
/// internal-build marker, which production builds never show. Staging work
/// uses `.env.local` overrides, never edits to the tracked file.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/config/build_environment.dart';

const Map<String, String> _stagingEnv = {
  'APP_ENV': 'staging',
  'API_BASE_URL': 'https://wellapath-backend-staging.onrender.com',
  'ARTIFACT_BASE_URL': 'https://pub-8bc2ba0d7e7647799d89662d70f23c45.r2.dev',
  'TELEMETRY_BASE_URL': 'https://wellapath-backend-staging.onrender.com',
  'TELEMETRY_PRODUCTION_APPROVED': 'false',
};

void main() {
  group('cross-environment gate', () {
    test('the shipped staging configuration validates', () {
      expect(
        () => BuildEnvironment.validate(env: _stagingEnv),
        returnsNormally,
      );
    });

    test('an internal build pointing at a non-staging API host fails', () {
      final env = Map.of(_stagingEnv)
        ..['API_BASE_URL'] = 'https://api.wellapath.org';
      expect(
        () => BuildEnvironment.validate(env: env),
        throwsA(isA<StateError>()),
      );
    });

    test('an internal build pointing at a non-staging artifact host fails', () {
      final env = Map.of(_stagingEnv)
        ..['ARTIFACT_BASE_URL'] = 'https://artifacts.wellapath.org';
      expect(
        () => BuildEnvironment.validate(env: env),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'an internal build pointing telemetry at a non-staging host fails',
      () {
        final env = Map.of(_stagingEnv)
          ..['TELEMETRY_BASE_URL'] = 'https://telemetry.example.com';
        expect(
          () => BuildEnvironment.validate(env: env),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('a production build pointing at the staging backend fails', () {
      final env = Map.of(_stagingEnv)..['APP_ENV'] = 'production';
      expect(
        () => BuildEnvironment.validate(env: env),
        throwsA(isA<StateError>()),
      );
    });

    test('a production build without an API base URL still fails', () {
      // RC-BLK-005 closed 2026-09-21: api.wellapath.org exists and is the
      // shipped production API. Configuration must still be explicit — a
      // production declaration with no API_BASE_URL never falls back.
      expect(
        () => BuildEnvironment.validate(env: const {'APP_ENV': 'production'}),
        throwsA(isA<StateError>()),
      );
    });

    test('the shipped production configuration validates', () {
      expect(
        () => BuildEnvironment.validate(
          env: const {
            'APP_ENV': 'production',
            'API_BASE_URL': 'https://api.wellapath.org',
            'TELEMETRY_ENABLED': 'false',
            'TELEMETRY_PRODUCTION_APPROVED': 'false',
          },
        ),
        returnsNormally,
      );
    });

    test('an unknown APP_ENV fails rather than falling back', () {
      final env = Map.of(_stagingEnv)..['APP_ENV'] = 'dev';
      expect(
        () => BuildEnvironment.validate(env: env),
        throwsA(isA<StateError>()),
      );
    });

    test('the production-approval flag cannot travel in an internal build', () {
      final env = Map.of(_stagingEnv)
        ..['TELEMETRY_PRODUCTION_APPROVED'] = 'true';
      expect(
        () => BuildEnvironment.validate(env: env),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('the bundled .env is the production configuration (build 211+)', () {
    late Map<String, String> bundled;

    setUpAll(() {
      // Parsed directly from the repository file — the same bytes the asset
      // bundle ships — so the gate is exercised against what testers get.
      bundled = {};
      for (final line in File('.env').readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final eq = trimmed.indexOf('=');
        if (eq <= 0) continue;
        bundled[trimmed.substring(0, eq)] = trimmed.substring(eq + 1);
      }
    });

    test('declares APP_ENV=production with the verified production API', () {
      expect(bundled['APP_ENV'], equals('production'));
      expect(bundled['API_BASE_URL'], equals('https://api.wellapath.org'));
    });

    test('references no staging host and constructs no artifact URL', () {
      for (final entry in bundled.entries) {
        for (final stagingHost in BuildEnvironment.kStagingHosts) {
          expect(
            entry.value.contains(stagingHost),
            isFalse,
            reason:
                '.env ${entry.key} references staging host $stagingHost — '
                'a production build must never depend on staging',
          );
        }
      }
      // Artifact URLs come from GET /config only; an env-level base would
      // reintroduce constructed URLs.
      expect(bundled.containsKey('ARTIFACT_BASE_URL'), isFalse);
    });

    test('passes the cross-environment gate', () {
      expect(() => BuildEnvironment.validate(env: bundled), returnsNormally);
    });

    test('telemetry is disabled and production approval is off', () {
      // Telemetry may be switched on for a specific internal build only via
      // --dart-define, never by editing the tracked .env.
      expect(bundled['TELEMETRY_ENABLED'], equals('false'));
      expect(bundled['TELEMETRY_PRODUCTION_APPROVED'], equals('false'));
    });

    test('contains no secret-shaped value', () {
      for (final entry in bundled.entries) {
        expect(
          RegExp(
            'secret|password|private|token|dsn',
            caseSensitive: false,
          ).hasMatch(entry.key),
          isFalse,
          reason: '.env key "${entry.key}" looks like a secret',
        );
      }
    });
  });

  group('internal-build marker', () {
    test('the marker names internal testing and staging', () {
      expect(
        BuildEnvironment.kInternalBuildMarker,
        equals('Internal testing — staging'),
      );
    });

    test('a staging environment is internal; production is not', () {
      expect(BuildEnvironment.isInternal(env: _stagingEnv), isTrue);
      expect(
        BuildEnvironment.isInternal(env: const {'APP_ENV': 'production'}),
        isFalse,
      );
    });

    test('an ambiguous environment shows the marker rather than hiding it', () {
      expect(BuildEnvironment.isInternal(env: const {}), isTrue);
    });

    test('the release notes carry the same wording', () {
      final notes = File(
        'docs/release/INTERNAL_TESTING_0.3.0_210.md',
      ).readAsStringSync();
      expect(notes, contains(BuildEnvironment.kInternalBuildMarker));
    });
  });
}
