/// Guards on how telemetry is *enabled*, as opposed to what it sends.
///
/// The `.env.local` defect these tests exist for was not a logic bug — the
/// code was correct and the documentation was wrong, and the two disagreed
/// silently. Following the documented procedure produced a telemetry-off build
/// while the operator believed telemetry was on. Nothing in the unit suite
/// could catch that, because nothing in the unit suite read the documentation.
///
/// So these tests assert across the repository boundary: that the shipped
/// documentation describes a route that actually exists, that the tracked
/// `.env` stays free of secrets, and that turning telemetry on cannot change
/// where it sends or what it is allowed to send.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_contract.dart';
import 'package:wellapath_mobile/core/telemetry/privacy_guard.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_config.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  group('the default build is telemetry-disabled', () {
    test('the tracked .env ships TELEMETRY_ENABLED=false', () {
      final env = read('.env');
      expect(
        RegExp(r'^TELEMETRY_ENABLED=false$', multiLine: true).hasMatch(env),
        isTrue,
        reason: '.env must ship with telemetry off',
      );
      expect(
        RegExp(
          r'^TELEMETRY_PRODUCTION_APPROVED=false$',
          multiLine: true,
        ).hasMatch(env),
        isTrue,
        reason: '.env must ship with the production gate closed',
      );
    });

    test('.env.example ships the same safe defaults', () {
      final example = read('.env.example');
      expect(
        RegExp(r'^TELEMETRY_ENABLED=false$', multiLine: true).hasMatch(example),
        isTrue,
      );
      expect(
        RegExp(
          r'^TELEMETRY_PRODUCTION_APPROVED=false$',
          multiLine: true,
        ).hasMatch(example),
        isTrue,
      );
    });

    test('a build with neither .env flag nor define is disabled', () {
      expect(
        TelemetryConfig.fromEnvironment(
          env: {'API_BASE_URL': 'https://api.example', 'APP_ENV': 'staging'},
          defines: const {},
        ).enabled,
        isFalse,
      );
    });
  });

  group('the tracked .env carries no secret', () {
    /// `.env` is committed by repository policy — `.gitignore` documents it as
    /// placeholder-only for CI asset bundling, with `.env.local` as the
    /// gitignored override. That policy only holds if the file stays boring.
    late Map<String, String> entries;

    setUpAll(() {
      entries = {
        for (final line in read('.env').split('\n'))
          if (line.trim().isNotEmpty && !line.trim().startsWith('#'))
            line.split('=').first.trim(): line
                .substring(line.indexOf('=') + 1)
                .trim(),
      };
    });

    test('every key is a known non-secret configuration key', () {
      const allowed = {
        'API_BASE_URL',
        'ARTIFACT_BASE_URL',
        'APP_ENV',
        'ENABLE_OFFLINE_MODE',
        'API_TIMEOUT_MS',
        'TELEMETRY_ENABLED',
        'TELEMETRY_BASE_URL',
        'TELEMETRY_PRODUCTION_APPROVED',
      };
      expect(
        entries.keys.toSet().difference(allowed),
        isEmpty,
        reason:
            'an unrecognised key appeared in the tracked .env — if it is a '
            'secret it must move to .env.local or a --dart-define, and if it '
            'is not, add it to this allowlist deliberately',
      );
    });

    test('no key name suggests a credential', () {
      final suspicious = RegExp(
        r'secret|password|passwd|token|api[_-]?key|private[_-]?key|'
        r'credential|auth|bearer|cookie|signature|keystore',
        caseSensitive: false,
      );
      for (final key in entries.keys) {
        expect(
          suspicious.hasMatch(key),
          isFalse,
          reason: '$key looks like a credential and must not be committed',
        );
      }
    });

    test('no value looks like a credential', () {
      // Long opaque strings, JWTs, and anything base64-ish and lengthy.
      final jwt = RegExp(r'^[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.');
      final longOpaque = RegExp(r'^[A-Za-z0-9+/_-]{40,}={0,2}$');
      for (final entry in entries.entries) {
        final value = entry.value;
        expect(
          jwt.hasMatch(value),
          isFalse,
          reason: '${entry.key} looks like a JWT',
        );
        expect(
          longOpaque.hasMatch(value),
          isFalse,
          reason: '${entry.key} looks like an opaque credential',
        );
      }
    });

    test('every URL is https and non-local', () {
      for (final entry in entries.entries) {
        if (!entry.key.endsWith('_URL')) continue;
        if (entry.value.isEmpty) continue;
        expect(
          entry.value,
          startsWith('https://'),
          reason: '${entry.key} must not be plaintext or a machine-local host',
        );
        expect(
          RegExp(
            r'localhost|127\.0\.0\.1|192\.168\.|10\.\d+\.',
          ).hasMatch(entry.value),
          isFalse,
          reason: '${entry.key} looks machine-specific',
        );
      }
    });
  });

  group('.env.local is not presented as a working route', () {
    test('no executable code in lib/ tries to load .env.local', () {
      // Comments *about* .env.local are fine and in fact wanted — one of them
      // records why it cannot work. Only a live reference is a defect, so
      // comment lines are excluded rather than the whole file.
      final offenders = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        for (final line in file.readAsStringSync().split('\n')) {
          final trimmed = line.trimLeft();
          final isComment =
              trimmed.startsWith('//') ||
              trimmed.startsWith('///') ||
              trimmed.startsWith('*');
          if (!isComment && line.contains('.env.local')) {
            offenders.add('${file.path}: ${line.trim()}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'no code may load .env.local — flutter_dotenv reads through the '
            'asset bundle, so a gitignored file cannot be loaded. If this '
            'changes, the documentation guard below must change with it.',
      );
    });

    test(
      'the operations doc does not present .env.local as the enable path',
      () {
        final doc = read('docs/TELEMETRY_MOBILE.md');
        if (!doc.contains('.env.local')) return; // Nothing to guard.
        expect(
          doc,
          contains('does not work'),
          reason:
              'docs/TELEMETRY_MOBILE.md mentions .env.local without saying it '
              'does not work. That exact mismatch produced a telemetry-off '
              'build that looked enabled.',
        );
      },
    );

    test('the documented enable route is the one the code implements', () {
      final doc = read('docs/TELEMETRY_MOBILE.md');
      expect(
        doc,
        contains('--dart-define=TELEMETRY_ENABLED=true'),
        reason: 'the doc must show the route that actually works',
      );
      // And that route must actually work.
      expect(
        TelemetryConfig.fromEnvironment(
          env: {'API_BASE_URL': 'https://api.example'},
          defines: {'TELEMETRY_ENABLED': 'true'},
        ).enabled,
        isTrue,
      );
    });
  });

  group('invalid or missing values fail safely to disabled', () {
    // `true` is matched case-insensitively after trimming, so an operator
    // writing `TRUE` or ` true ` gets what they intended. Everything else —
    // including the plausible-looking `1`, `yes` and `on` — fails closed.
    for (final value in ['', ' ', '1', 'yes', 'on', 'enabled', 'null', 'tru']) {
      test('TELEMETRY_ENABLED="$value" does not enable telemetry', () {
        expect(
          TelemetryConfig.fromEnvironment(
            env: {'API_BASE_URL': 'https://api.example'},
            defines: {'TELEMETRY_ENABLED': value},
          ).enabled,
          isFalse,
          reason: '"$value" must not be treated as true',
        );
      });
    }

    for (final value in ['true', 'TRUE', 'True', ' true ']) {
      test('TELEMETRY_ENABLED="$value" does enable telemetry', () {
        expect(
          TelemetryConfig.fromEnvironment(
            env: {'API_BASE_URL': 'https://api.example'},
            defines: {'TELEMETRY_ENABLED': value},
          ).enabled,
          isTrue,
          reason: 'case and surrounding whitespace must not defeat the flag',
        );
      });
    }

    test('an enabled config with no base URL is disabled', () {
      expect(
        TelemetryConfig.fromEnvironment(
          env: const {},
          defines: {'TELEMETRY_ENABLED': 'true'},
        ).enabled,
        isFalse,
      );
    });

    test('the disabled constant has no endpoint to send to', () {
      expect(TelemetryConfig.disabled.enabled, isFalse);
      expect(TelemetryConfig.disabled.baseUrl, isEmpty);
    });
  });

  group('production requires both approval flags', () {
    for (final appEnv in ['production', 'PRODUCTION', 'prod', ' Prod ']) {
      test('APP_ENV="$appEnv" blocks a single enable flag', () {
        expect(
          TelemetryConfig.fromEnvironment(
            env: {'API_BASE_URL': 'https://api.example', 'APP_ENV': appEnv},
            defines: {'TELEMETRY_ENABLED': 'true'},
          ).enabled,
          isFalse,
          reason: 'one flag must never enable production collection',
        );
      });
    }

    test('the approval flag alone, without the enable flag, does nothing', () {
      expect(
        TelemetryConfig.fromEnvironment(
          env: {'API_BASE_URL': 'https://api.example', 'APP_ENV': 'production'},
          defines: {'TELEMETRY_PRODUCTION_APPROVED': 'true'},
        ).enabled,
        isFalse,
      );
    });

    test('both flags together are required, by define or by .env', () {
      // Via defines.
      expect(
        TelemetryConfig.fromEnvironment(
          env: {'API_BASE_URL': 'https://api.example', 'APP_ENV': 'production'},
          defines: {
            'TELEMETRY_ENABLED': 'true',
            'TELEMETRY_PRODUCTION_APPROVED': 'true',
          },
        ).enabled,
        isTrue,
      );
      // Via .env — the define path must not be a weaker gate than the file.
      expect(
        TelemetryConfig.fromEnvironment(
          env: {
            'API_BASE_URL': 'https://api.example',
            'APP_ENV': 'production',
            'TELEMETRY_ENABLED': 'true',
            'TELEMETRY_PRODUCTION_APPROVED': 'true',
          },
          defines: const {},
        ).enabled,
        isTrue,
      );
    });

    test('a mixed source cannot sneak past the gate', () {
      // Enable by define, approval absent everywhere.
      expect(
        TelemetryConfig.fromEnvironment(
          env: {
            'API_BASE_URL': 'https://api.example',
            'APP_ENV': 'production',
            'TELEMETRY_PRODUCTION_APPROVED': 'false',
          },
          defines: {'TELEMETRY_ENABLED': 'true'},
        ).enabled,
        isFalse,
      );
    });
  });

  group('enablement changes nothing about what is sent', () {
    test(
      'the endpoint path is fixed by the contract, not by configuration',
      () {
        // No env key and no define can move the path.
        final configs = [
          TelemetryConfig.fromEnvironment(
            env: {'API_BASE_URL': 'https://a.example'},
            defines: {'TELEMETRY_ENABLED': 'true'},
          ),
          TelemetryConfig.fromEnvironment(
            env: {'API_BASE_URL': 'https://b.example'},
            defines: {
              'TELEMETRY_ENABLED': 'true',
              'TELEMETRY_BASE_URL': 'https://c.example',
            },
          ),
        ];
        for (final config in configs) {
          expect(config.endpoint, endsWith(TelemetryContract.endpointPath));
          expect(config.endpoint, endsWith('/v1/telemetry/events'));
        }
      },
    );

    test('the contract version is a constant, not configuration', () {
      expect(TelemetryContract.version, '1.0');
      // Enabling by any route leaves it untouched.
      TelemetryConfig.fromEnvironment(
        env: {'API_BASE_URL': 'https://a.example'},
        defines: {'TELEMETRY_ENABLED': 'true', 'CONTRACT_VERSION': '2.0'},
      );
      expect(TelemetryContract.version, '1.0');
    });

    test('the event allowlist is unaffected by enablement', () {
      final before = List<String>.from(TelemetryContract.eventNames);
      TelemetryConfig.fromEnvironment(
        env: {'API_BASE_URL': 'https://a.example'},
        defines: {'TELEMETRY_ENABLED': 'true'},
      );
      expect(TelemetryContract.eventNames, before);
      expect(TelemetryContract.eventNames, hasLength(12));
    });

    test('the privacy guard does not consult configuration at all', () {
      // Its signature takes an event and a clock. There is no config
      // parameter, so no enablement flag can relax it.
      final now = DateTime.utc(2026, 8, 11, 9);
      final prohibited = {
        'event_name': 'assessment_step_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'assessment_session_id': 'ses_00000000000000000001',
        'step_index': 1,
        'question_id': 'q_017',
      };
      // Rejected identically whether or not telemetry is enabled anywhere.
      expect(PrivacyGuard.validateEvent(prohibited, now: now).isValid, isFalse);
      TelemetryConfig.fromEnvironment(
        env: {'API_BASE_URL': 'https://a.example'},
        defines: {'TELEMETRY_ENABLED': 'true'},
      );
      expect(PrivacyGuard.validateEvent(prohibited, now: now).isValid, isFalse);
    });

    test('no define name overlaps a contract field name', () {
      // A define called `question_id` must not be able to become a payload
      // field. The config reads a fixed, closed set of keys.
      const configKeys = {
        'TELEMETRY_ENABLED',
        'TELEMETRY_BASE_URL',
        'TELEMETRY_PRODUCTION_APPROVED',
        'APP_ENV',
        'API_BASE_URL',
      };
      for (final event in TelemetryContract.events.values) {
        for (final property in event.properties) {
          expect(
            configKeys.contains(property.field.toUpperCase()),
            isFalse,
            reason: '${property.field} collides with a configuration key',
          );
        }
      }
    });
  });
}
