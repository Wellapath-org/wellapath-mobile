/// `os_version` must never appear in emitted telemetry.
///
/// ### The defect this pins
///
/// Real payload captured from an emulator running **Android 8.0.0 / API 26**:
///
/// ```json
/// "app": {"platform":"android","app_version":"0.2.0","app_build":"206","os_version":"64"}
/// ```
///
/// Dart's `Platform.operatingSystemVersion` returns a kernel/uname string on
/// Android — `Linux localhost 3.18.94+ #17 SMP … aarch64` — and the normaliser
/// extracted the leading numeric fragment from it. The result matched the
/// contract's `\d{1,3}(\.\d{1,3})?` pattern, so the backend accepted it with a
/// 202 and **no server-side validation could have detected the error**. A
/// silently wrong optional value is worse than an absent one: it corrupts
/// cohorting invisibly.
///
/// The engineering decision is to omit the field entirely in v1.0. It stays
/// declared in the backend contract and in the vendored schema artifacts —
/// this is a client-side emission decision, not a contract change.
///
/// These tests exist so the field cannot come back by accident, and so that
/// nobody reintroduces it from a proxy (kernel version, API level,
/// architecture, user agent) that would recreate the same class of defect.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_contract.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_event.dart';
import 'package:wellapath_mobile/core/telemetry/privacy_guard.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_config.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_queue.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_runtime.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_service.dart';

import 'support/fixtures.dart';
import 'support/json_schema.dart';

void main() {
  group('the serialized app context omits os_version', () {
    test('toJson emits exactly platform, app_version and app_build', () {
      const context = TelemetryAppContext(
        platform: 'android',
        appVersion: '1.4.2',
        appBuild: '204',
      );
      expect(context.toJson(), {
        'platform': 'android',
        'app_version': '1.4.2',
        'app_build': '204',
      });
      expect(context.toJson().keys, hasLength(3));
    });

    test('the key is absent, not null and not a placeholder', () {
      final json = testAppContext.toJson();
      expect(json.containsKey('os_version'), isFalse);
      final encoded = jsonEncode(json);
      expect(encoded, isNot(contains('os_version')));
      for (final placeholder in [
        'null',
        'unknown',
        'unspecified',
        '""',
        'n/a',
      ]) {
        expect(
          encoded.toLowerCase(),
          isNot(contains('"os_version":$placeholder')),
        );
      }
    });

    test('there is no constructor parameter to populate it', () {
      // Structural: the field cannot be set even deliberately. If this stops
      // compiling, os_version has been reintroduced and every assertion in
      // this file needs re-reading before that is allowed to land.
      const context = TelemetryAppContext(
        platform: 'ios',
        appVersion: '0.2.0',
        appBuild: '206',
      );
      expect(context.toJson().containsKey('os_version'), isFalse);
    });
  });

  group('no host OS string can produce an os_version', () {
    /// Representative `Platform.operatingSystemVersion` values. The Android
    /// entry is the exact string from the device that produced the defect.
    const osStrings = <String, String>{
      'android (kernel/uname — the defect)':
          'Linux localhost 3.18.94+ #17 SMP PREEMPT Mon May 1 07:31:27 PDT 2023 aarch64',
      'android (alternate uname)':
          'Linux localhost 5.10.110-android12 #1 SMP PREEMPT x86_64',
      'ios': 'Version 17.4.1 (Build 21E236)',
      'macos': 'Version 14.4.1 (Build 23E224)',
      'linux': '#58~22.04.1-Ubuntu SMP Fri Jul 26 2024',
      'windows': '"Windows 10 Pro" 10.0 (Build 19045)',
      'empty': '',
      'nonsense': 'no numbers here at all',
    };

    osStrings.forEach((label, raw) {
      test('$label yields no os_version', () {
        // fromPlatform takes no OS-string parameter any more — the value is
        // never read, so no input can reach the payload. This asserts the
        // emitted shape is inert regardless of what the host would report.
        final context = TelemetryAppContext.fromPlatform(
          platformOverride: 'android',
        );
        expect(context.toJson().containsKey('os_version'), isFalse);
        // No fragment of the host string reaches the payload. Skipped for the
        // empty input, where a substring assertion is vacuously false.
        final token = raw.split(' ').first;
        if (token.isNotEmpty) {
          expect(jsonEncode(context.toJson()), isNot(contains(token)));
        }
      });
    });

    test('fromPlatform exposes no OS-string seam at all', () {
      // The old signature accepted `rawOsVersion`. Its removal is what makes
      // the proxy-substitution failure mode unreachable.
      final context = TelemetryAppContext.fromPlatform();
      expect(context.toJson().keys.toSet(), {
        'platform',
        'app_version',
        'app_build',
      });
    });
  });

  group('the retained fields are unchanged', () {
    test('platform is preserved', () {
      expect(
        TelemetryAppContext.fromPlatform(platformOverride: 'ios').platform,
        'ios',
      );
      expect(
        TelemetryAppContext.fromPlatform(platformOverride: 'android').platform,
        'android',
      );
    });

    test('app_version and app_build come from the dart-defines', () {
      // With no --dart-define supplied the documented defaults apply.
      final context = TelemetryAppContext.fromPlatform(
        platformOverride: 'android',
      );
      expect(context.appVersion, '1.0.0');
      expect(context.appBuild, '1');
      expect(
        PrivacyGuard.validateAppContext(context.toJson()).isValid,
        isTrue,
        reason: 'the default context must still be contract-valid',
      );
    });

    test('an explicit context round-trips its three fields', () {
      const context = TelemetryAppContext(
        platform: 'android',
        appVersion: '0.2.0',
        appBuild: '206',
      );
      expect(context.appVersion, '0.2.0');
      expect(context.appBuild, '206');
      expect(context.platform, 'android');
    });
  });

  group('contract compatibility is unaffected', () {
    test('the contract mirror still declares os_version as optional', () {
      // The client omits it; the *contract* still allows it. Removing it from
      // the mirror would break parity with the backend allowlist and would
      // make restoring the field a contract change rather than a client one.
      final spec = TelemetryContract.appContext.firstWhere(
        (f) => f.field == 'os_version',
      );
      expect(spec.required, isFalse);
      expect(spec.maxLength, 8);
    });

    test('the vendored backend schema still declares os_version', () {
      final schema = loadContractArtifact('telemetry.v1.schema.json');
      final defs = schema[r'$defs']! as Map;
      final appContext = defs['AppContext']! as Map;
      final properties = appContext['properties']! as Map;
      expect(
        properties.containsKey('os_version'),
        isTrue,
        reason: 'the backend contract is unchanged by this client decision',
      );
      expect(appContext['required'], ['platform', 'app_version', 'app_build']);
    });

    test('an app context without os_version validates against the schema', () {
      final validator = JsonSchemaValidator(
        loadContractArtifact('telemetry.v1.schema.json'),
      );
      final envelope = {
        'contract_version': TelemetryContract.version,
        'sent_at': DefaultTelemetryService.isoUtc(
          DateTime.utc(2026, 8, 11, 9, 1, 14, 639),
        ),
        'app': testAppContext.toJson(),
        'events': [
          serialiseEvent(const AppOpenEvent(launchType: LaunchType.cold)),
        ],
      };
      expect(validator.validate(envelope), isEmpty);
    });

    test('every event fixture still validates without os_version', () {
      final validator = JsonSchemaValidator(
        loadContractArtifact('telemetry.v1.schema.json'),
      );
      for (final event in allEventFixtures()) {
        final envelope = {
          'contract_version': TelemetryContract.version,
          'sent_at': '2026-08-11T09:01:14.639Z',
          'app': testAppContext.toJson(),
          'events': [serialiseEvent(event)],
        };
        expect(
          validator.validate(envelope),
          isEmpty,
          reason: '${event.eventName} failed without os_version',
        );
      }
    });
  });

  group('nothing reaches the transport with os_version', () {
    test('a real flush emits an app block of exactly three keys', () async {
      final clock = FakeClock(DateTime.utc(2026, 8, 11, 9));
      final diagnostics = TelemetryDiagnostics();
      final transport = FakeTransport([accepted]);
      final service = DefaultTelemetryService(
        config: const TelemetryConfig(
          enabled: true,
          baseUrl: 'https://example.invalid',
          flushInterval: Duration(hours: 1),
        ),
        queue: memoryQueue(
          clock: clock,
          diagnostics: diagnostics,
          store: InMemoryTelemetryQueueStore(),
        ),
        transport: transport,
        appContext: TelemetryAppContext.fromPlatform(
          platformOverride: 'android',
        ),
        clock: clock,
        idGenerator: FakeIdGenerator(),
        diagnostics: diagnostics,
      );
      await service.init();

      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await Future<void>.delayed(Duration.zero);
      await service.flush();

      expect(transport.sent, hasLength(1));
      final app = transport.sent.single['app']! as Map;
      expect(app.keys.toSet(), {'platform', 'app_version', 'app_build'});
      expect(jsonEncode(transport.sent), isNot(contains('os_version')));
      await service.dispose();
    });

    test('no arbitrary property replaced it', () {
      // The removal must not have smuggled a substitute in under another name.
      final keys = testAppContext.toJson().keys.toSet();
      for (final suspect in [
        'os',
        'os_release',
        'sdk',
        'api_level',
        'kernel',
        'arch',
        'abi',
        'device',
        'user_agent',
        'build',
      ]) {
        expect(keys.contains(suspect), isFalse, reason: '$suspect appeared');
      }
    });
  });
}
