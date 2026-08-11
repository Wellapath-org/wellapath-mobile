/// Adversarial privacy tests.
///
/// Each case here tries to get prohibited data into telemetry, and asserts
/// two things: that the capture is rejected with the right reason code, and
/// that the value **never reaches the queue or the transport**. The second
/// assertion is the one that matters — a rejection that still persisted the
/// record would be worthless.
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

/// A distinctive marker that must never survive anywhere.
const String marker = 'ZZMARKERZZ';

void main() {
  final now = DateTime.utc(2026, 8, 11, 9, 0, 0);

  Map<String, Object?> validAppOpen() => {
    'event_name': 'app_open',
    'event_id': 'evt_0000000000000001',
    'client_ts': '2026-08-11T09:00:00.000Z',
    'launch_type': 'cold',
  };

  group('the guard accepts what it should', () {
    test('every fixture event passes both validation layers', () {
      for (final event in allEventFixtures()) {
        final verdict = PrivacyGuard.validateEvent(
          serialiseEvent(event, clientTs: now),
          now: now,
        );
        expect(
          verdict.isValid,
          isTrue,
          reason: '${event.eventName} was rejected as ${verdict.reason}',
        );
      }
    });
  });

  group('prohibited fields — clinical', () {
    final cases = <String, Map<String, Object?>>{
      'question_id': {
        'event_name': 'assessment_step_view',
        'question_id': 'q_017',
      },
      'question category': {
        'event_name': 'assessment_step_view',
        'question_category': 'respiratory',
      },
      'answer value': {'event_name': 'assessment_step_view', 'answer': marker},
      'answers list key': {
        'event_name': 'assessment_complete',
        'answers': marker,
      },
      'assessment path': {'event_name': 'assessment_complete', 'path': marker},
      'urgency_category': {
        'event_name': 'assessment_complete',
        'urgency_category': 'EMERGENCY',
      },
      'triage level': {'event_name': 'assessment_complete', 'triage': 'urgent'},
      'condition': {'event_name': 'result_view', 'condition': 'malaria'},
      'differential': {'event_name': 'result_view', 'differential': marker},
      'score': {'event_name': 'result_view', 'score': 87},
      'score contribution': {
        'event_name': 'result_view',
        'score_contribution': 12,
      },
      'red flag': {'event_name': 'emergency_action', 'red_flag': 'rf_006'},
      'rule id': {'event_name': 'emergency_action', 'rule_id': 'rf_006'},
      'symptom token': {'event_name': 'assessment_start', 'symptom': marker},
      'symptom alias': {
        'event_name': 'assessment_start',
        'symptom_alias': marker,
      },
      'complaint text': {'event_name': 'assessment_start', 'complaint': marker},
      'pregnancy status': {'event_name': 'assessment_start', 'pregnancy': true},
      'clinical narrative': {'event_name': 'result_view', 'narrative': marker},
      'free-text feedback': {
        'event_name': 'feedback_submit',
        'free_text': marker,
      },
      'explanation': {'event_name': 'result_view', 'explanation': marker},
    };

    cases.forEach((label, extra) {
      test('$label is rejected as prohibited_field', () {
        final payload = {...validAppOpen(), ...extra};
        final verdict = PrivacyGuard.validateEvent(payload, now: now);
        expect(verdict.isValid, isFalse);
        expect(verdict.reason, 'prohibited_field');
        // The invented key is never echoed back, mirroring the backend.
        expect(verdict.field, isNull);
      });
    });
  });

  group('prohibited fields — identity, credentials, location', () {
    final cases = <String, Map<String, Object?>>{
      'name': {'name': marker},
      'full name': {'full_name': marker},
      'email': {'email': 'a@b.com'},
      'phone number': {'phone_number': '+2348012345678'},
      'account id': {'account_id': marker},
      'user id': {'user_id': marker},
      'patient id': {'patient_id': marker},
      'access token': {'access_token': marker},
      'authorization header': {'authorization': 'Bearer $marker'},
      'cookie': {'cookie': marker},
      'secret': {'client_secret': marker},
      'request headers': {'request_headers': marker},
      'latitude': {'latitude': 6.52},
      'longitude': {'longitude': 3.37},
      'coordinates': {'coordinates': '6.5243793,3.3792057'},
      'address': {'address': marker},
      'raw search query': {'search_query': marker},
      'location history': {'location_history': marker},
      'advertising id': {'advertising_id': marker},
      'device fingerprint': {'device_fingerprint': marker},
      'android id': {'android_id': marker},
      'install id': {'install_id': marker},
    };

    cases.forEach((label, extra) {
      test('$label is rejected as prohibited_field', () {
        final verdict = PrivacyGuard.validateEvent({
          ...validAppOpen(),
          ...extra,
        }, now: now);
        expect(verdict.isValid, isFalse);
        expect(verdict.reason, 'prohibited_field');
      });
    });
  });

  group('containers, unsafe keys and nesting', () {
    for (final key in [
      'metadata',
      'properties',
      'context',
      'extra',
      'data',
      'payload',
      'custom',
      'tags',
    ]) {
      test('$key is rejected as prohibited_container', () {
        final verdict = PrivacyGuard.validateEvent({
          ...validAppOpen(),
          key: {'anything': marker},
        }, now: now);
        expect(verdict.reason, 'prohibited_container');
      });
    }

    for (final key in ['__proto__', 'constructor', 'prototype']) {
      test('$key is rejected as unsafe_key', () {
        final verdict = PrivacyGuard.validateEvent({
          ...validAppOpen(),
          key: {'polluted': true},
        }, now: now);
        expect(verdict.reason, 'unsafe_key');
      });
    }

    test(
      'an object in an allowlisted property is nested_value_not_allowed',
      () {
        final verdict = PrivacyGuard.validateEvent({
          'event_name': 'facility_view',
          'event_id': 'evt_0000000000000001',
          'client_ts': '2026-08-11T09:00:00.000Z',
          'facility_id': {'nested': marker},
        }, now: now);
        expect(verdict.reason, 'nested_value_not_allowed');
      },
    );

    test('an array in an allowlisted property is nested_value_not_allowed', () {
      final verdict = PrivacyGuard.validateEvent({
        'event_name': 'facility_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'facility_id': [marker],
      }, now: now);
      expect(verdict.reason, 'nested_value_not_allowed');
    });

    test('a harmless invented key is unknown_property, not prohibited', () {
      final verdict = PrivacyGuard.validateEvent({
        ...validAppOpen(),
        'my_field': 1,
      }, now: now);
      expect(verdict.reason, 'unknown_property');
    });
  });

  group('prohibited value shapes in allowlisted fields', () {
    test('a coordinate pair smuggled into facility_id', () {
      final verdict = PrivacyGuard.validateEvent({
        'event_name': 'facility_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'facility_id': '6.5243793,3.3792057',
      }, now: now);
      expect(verdict.reason, 'prohibited_value_shape');
      expect(verdict.field, 'facility_id');
    });

    test('a high-precision decimal smuggled into article_id', () {
      final verdict = PrivacyGuard.validateEvent({
        'event_name': 'library_article_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'article_id': '6.5243793',
      }, now: now);
      expect(verdict.reason, 'prohibited_value_shape');
    });

    test('free text smuggled into a session ID', () {
      final verdict = PrivacyGuard.validateEvent({
        'event_name': 'result_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'assessment_session_id': 'severe headache for three days',
      }, now: now);
      expect(verdict.reason, 'prohibited_value_shape');
    });

    test('a phone number smuggled into facility_id', () {
      final verdict = PrivacyGuard.validateEvent({
        'event_name': 'facility_call',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'facility_id': '+2348012345678',
      }, now: now);
      expect(verdict.reason, 'prohibited_value_shape');
    });

    test('a JWT smuggled into an event_id', () {
      final verdict = PrivacyGuard.validateEvent({
        ...validAppOpen(),
        'event_id': 'eyJhbGciOiJIUzI1.eyJzdWIiOiIxMjM0.SflKxwRJSMeKKF2QT4',
      }, now: now);
      expect(verdict.reason, 'prohibited_value_shape');
    });

    test('an ordinary version string is not mistaken for a coordinate', () {
      final verdict = PrivacyGuard.validateEvent({
        'event_name': 'result_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'assessment_session_id': 'ses_00000000000000000001',
        'presentation_contract_version': '1.0',
      }, now: now);
      expect(verdict.isValid, isTrue);
    });
  });

  group('type, enum, range and format enforcement', () {
    test('an unknown event name is unknown_event', () {
      final verdict = PrivacyGuard.validateEvent({
        'event_name': 'symptom_entered',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
      }, now: now);
      expect(verdict.reason, 'unknown_event');
    });

    test('an out-of-enum value is invalid_enum_value', () {
      final verdict = PrivacyGuard.validateEvent({
        ...validAppOpen(),
        'launch_type': 'sideways',
      }, now: now);
      expect(verdict.reason, 'invalid_enum_value');
    });

    test('a missing required property is reported by name', () {
      final verdict = PrivacyGuard.validateEvent({
        'event_name': 'facility_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
      }, now: now);
      expect(verdict.reason, 'missing_required_property');
      // Allowlisted names *are* echoed — only invented ones are withheld.
      expect(verdict.field, 'facility_id');
    });

    test('a wrong type is invalid_type', () {
      final verdict = PrivacyGuard.validateEvent({
        'event_name': 'assessment_step_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'assessment_session_id': 'ses_00000000000000000001',
        'step_index': 'three',
      }, now: now);
      expect(verdict.reason, 'invalid_type');
    });

    test('an out-of-range integer is value_out_of_range', () {
      final verdict = PrivacyGuard.validateEvent({
        'event_name': 'assessment_step_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'assessment_session_id': 'ses_00000000000000000001',
        'step_index': 201,
      }, now: now);
      expect(verdict.reason, 'value_out_of_range');
    });

    test('an over-long value is value_too_long', () {
      final verdict = PrivacyGuard.validateEvent({
        'event_name': 'facility_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'facility_id': 'a' * 65,
      }, now: now);
      expect(verdict.reason, 'value_too_long');
    });

    test('a short session ID fails the 16-character floor', () {
      final verdict = PrivacyGuard.validateEvent({
        'event_name': 'result_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'assessment_session_id': 'short',
      }, now: now);
      expect(verdict.reason, 'invalid_format');
    });

    test('patterns are anchored — a valid prefix is not enough', () {
      // Unanchored, `[A-Za-z0-9_.:-]{1,64}` would match inside this value.
      final verdict = PrivacyGuard.validateEvent({
        'event_name': 'facility_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'facility_id': 'ng_lag_001|$marker',
      }, now: now);
      expect(verdict.isValid, isFalse);
    });
  });

  group('timestamps', () {
    test('an event older than 30 days is timestamp_out_of_range', () {
      final verdict = PrivacyGuard.validateEvent({
        ...validAppOpen(),
        'client_ts': '2026-07-05T09:00:00.000Z',
      }, now: now);
      expect(verdict.reason, 'timestamp_out_of_range');
    });

    test('an event exactly at the 30-day boundary is still accepted', () {
      final boundary = now.subtract(
        Duration(milliseconds: TelemetryContract.maxClientTimestampAgeMs),
      );
      final verdict = PrivacyGuard.validateEvent({
        ...validAppOpen(),
        'client_ts': DefaultTelemetryService.isoUtc(boundary),
      }, now: now);
      expect(verdict.isValid, isTrue);
    });

    test('more than 24 hours in the future is rejected', () {
      final verdict = PrivacyGuard.validateEvent({
        ...validAppOpen(),
        'client_ts': DefaultTelemetryService.isoUtc(
          now.add(const Duration(hours: 25)),
        ),
      }, now: now);
      expect(verdict.reason, 'timestamp_out_of_range');
    });
  });

  group('app context', () {
    test('a valid context passes', () {
      expect(
        PrivacyGuard.validateAppContext(testAppContext.toJson()).isValid,
        isTrue,
      );
    });

    test('a device model is rejected', () {
      final verdict = PrivacyGuard.validateAppContext({
        ...testAppContext.toJson(),
        'device_model': 'Tecno Spark 10',
      });
      expect(verdict.reason, 'prohibited_field');
    });

    test('a full iOS build string is rejected as os_version', () {
      final verdict = PrivacyGuard.validateAppContext({
        'platform': 'ios',
        'app_version': '1.4.2',
        'app_build': '204',
        'os_version': '17.4.1 (21E236)',
      });
      expect(verdict.isValid, isFalse);
    });

    test('the emitted context has no os_version at all', () {
      // The normaliser that used to produce this field has been retired: on
      // Android it read a kernel string and shipped "64" from a device running
      // Android 8.0.0. See os_version_omission_test.dart for the full guard.
      expect(testAppContext.toJson().containsKey('os_version'), isFalse);
      expect(
        PrivacyGuard.validateAppContext(testAppContext.toJson()).isValid,
        isTrue,
        reason: 'os_version is optional, so omitting it must still validate',
      );
    });
  });

  group('prohibited data in the queue never reaches the transport', () {
    // The typed event layer is `sealed`, so no code outside
    // `telemetry_event.dart` can construct an event carrying a prohibited
    // field — that is the first layer, and it is enforced by the compiler
    // (a subclass here fails to compile).
    //
    // These tests exercise the *second* layer by writing hostile records
    // straight into the queue store, which is what a buggy earlier build, a
    // hand-edited box or a tampered device would leave behind. Nothing may
    // escape to the transport.
    late FakeClock clock;
    late TelemetryDiagnostics diagnostics;
    late InMemoryTelemetryQueueStore store;
    late FakeTransport transport;
    late DefaultTelemetryService service;

    setUp(() async {
      clock = FakeClock(now);
      diagnostics = TelemetryDiagnostics();
      store = InMemoryTelemetryQueueStore();
      transport = FakeTransport([accepted]);
      service = DefaultTelemetryService(
        config: const TelemetryConfig(
          enabled: true,
          baseUrl: 'https://example.invalid',
        ),
        queue: memoryQueue(
          clock: clock,
          diagnostics: diagnostics,
          store: store,
        ),
        transport: transport,
        appContext: testAppContext,
        clock: clock,
        idGenerator: FakeIdGenerator(),
        diagnostics: diagnostics,
        jitter: const FixedTelemetryJitter(1),
        sleep: RecordingSleeper().call,
      );
      await service.init();
    });

    tearDown(() => service.dispose());

    Future<void> injectRaw(Map<String, Object?> payload) =>
        store.append(jsonEncode({'v': 1, 'e': payload}));

    /// Everything the queue and the transport hold, as one searchable string.
    String allPersistedAndTransmitted() {
      final persisted = store.keys().map((k) => store.read(k) ?? '').join('\n');
      final transmitted = transport.sent.map(jsonEncode).join('\n');
      return '$persisted\n$transmitted';
    }

    test('a hostile queued record is discarded, never transmitted', () async {
      await injectRaw({
        'event_name': 'assessment_step_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'assessment_session_id': 'ses_00000000000000000001',
        'step_index': 1,
        'question_id': 'q_017',
        'answer': marker,
        'urgency_category': 'EMERGENCY',
      });

      await service.flush();

      expect(transport.sent, isEmpty);
      expect(store.length, 0, reason: 'the hostile record must be removed');
      expect(allPersistedAndTransmitted(), isNot(contains(marker)));
      expect(allPersistedAndTransmitted(), isNot(contains('question_id')));
      expect(diagnostics.rejectedByReason['prohibited_field'], 1);
    });

    test('a valid record queued alongside it still goes through', () async {
      await injectRaw({
        'event_name': 'result_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'assessment_session_id': 'ses_00000000000000000001',
        'condition': 'malaria',
        'score': 87,
      });
      service.capture(
        const AppOpenEvent(launchType: LaunchType.cold, isFirstLaunch: true),
      );
      await Future<void>.delayed(Duration.zero);

      await service.flush();

      final everything = allPersistedAndTransmitted();
      expect(everything, isNot(contains('malaria')));
      expect(everything, isNot(contains('"score"')));
      expect(transport.sent, hasLength(1));
      final events = transport.sent.single['events']! as List;
      expect(events, hasLength(1));
      expect((events.single as Map)['event_name'], 'app_open');
    });

    test('an expired record is dropped and counted as expired', () async {
      await injectRaw({
        'event_name': 'app_open',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-06-01T09:00:00.000Z',
        'launch_type': 'cold',
      });

      await service.flush();

      expect(transport.sent, isEmpty);
      expect(store.length, 0);
      expect(diagnostics.expired, 1);
    });

    test('a corrupted record cannot wedge the queue', () async {
      await store.append('{ not json at all');
      await store.append(
        jsonEncode({
          'v': 99,
          'e': {'from': 'the future'},
        }),
      );
      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await Future<void>.delayed(Duration.zero);

      await service.flush();

      expect(diagnostics.corruptedRecordsDiscarded, 2);
      expect(transport.sent, hasLength(1));
      expect(store.length, 0);
    });

    test('diagnostics record the reason but never the value', () async {
      await injectRaw({
        'event_name': 'assessment_step_view',
        'event_id': 'evt_0000000000000001',
        'client_ts': '2026-08-11T09:00:00.000Z',
        'assessment_session_id': 'ses_00000000000000000001',
        'step_index': 1,
        'answer': marker,
      });
      await service.flush();

      final snapshot = jsonEncode(service.diagnosticsSnapshot());
      expect(snapshot, isNot(contains(marker)));
      expect(snapshot, isNot(contains('answer')));
      expect(snapshot, contains('prohibited_field'));
    });
  });

  group('diagnostics never expose payloads', () {
    test('a snapshot contains no IDs or property values', () async {
      final clock = FakeClock(now);
      final diagnostics = TelemetryDiagnostics();
      final service = DefaultTelemetryService(
        config: const TelemetryConfig(
          enabled: true,
          baseUrl: 'https://example.invalid',
        ),
        queue: memoryQueue(clock: clock, diagnostics: diagnostics),
        transport: FakeTransport([accepted]),
        appContext: testAppContext,
        clock: clock,
        idGenerator: FakeIdGenerator(),
        diagnostics: diagnostics,
      );
      await service.init();
      service.capture(
        const FacilityViewEvent(
          facilityId: 'ng_lag_001',
          source: FacilityViewSource.map,
        ),
      );
      service.capture(
        const ResultViewEvent(assessmentSessionId: 'ses_00000000000000000001'),
      );
      await Future<void>.delayed(Duration.zero);

      final snapshot = jsonEncode(service.diagnosticsSnapshot());
      expect(snapshot, isNot(contains('ng_lag_001')));
      expect(snapshot, isNot(contains('ses_00000000000000000001')));
      expect(snapshot, isNot(contains('evt_')));
      // Event *names* are fixed contract vocabulary and are safe to count by.
      expect(snapshot, contains('facility_view'));
      await service.dispose();
    });
  });
}
