/// Validates what this client actually serialises against the backend's own
/// `telemetry.v1.schema.json`.
///
/// The parity test proves the *mirror* matches the backend. This one proves
/// the *bytes* do — a mirror can be right while a `toProperties()` emits the
/// wrong key, the wrong type, or a timestamp with six fractional digits.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_contract.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_event.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_service.dart';

import 'support/fixtures.dart';
import 'support/json_schema.dart';

void main() {
  late JsonSchemaValidator validator;

  setUpAll(() {
    validator = JsonSchemaValidator(
      loadContractArtifact('telemetry.v1.schema.json'),
    );
  });

  Map<String, Object?> envelope(List<Map<String, Object?>> events) => {
    'contract_version': TelemetryContract.version,
    'sent_at': DefaultTelemetryService.isoUtc(
      DateTime.utc(2026, 8, 11, 9, 1, 14, 639),
    ),
    'app': testAppContext.toJson(),
    'events': events,
  };

  group('the validator itself', () {
    test('implements every keyword the backend schema uses', () {
      expect(
        validator.unsupportedKeywords(),
        isEmpty,
        reason:
            'The backend schema uses a keyword this test validator does not '
            'implement, so conformance here would be under-checked. Extend '
            'test/telemetry/support/json_schema.dart before trusting a pass.',
      );
    });

    test('actually rejects a bad instance', () {
      // A guard on the guard: a validator that always returns [] would make
      // every test below vacuous.
      final errors = validator.validate(
        envelope([
          {
            'event_name': 'app_open',
            'event_id': 'short',
            'client_ts': 'not-a-timestamp',
            'launch_type': 'sideways',
          },
        ]),
      );
      expect(errors, isNotEmpty);
    });
  });

  group('serialised events conform to telemetry.v1.schema.json', () {
    test('every event fixture validates, one per request', () {
      for (final event in allEventFixtures()) {
        final errors = validator.validate(envelope([serialiseEvent(event)]));
        expect(
          errors,
          isEmpty,
          reason: '${event.eventName} failed schema validation: $errors',
        );
      }
    });

    test('all twelve event names are covered by the fixtures', () {
      final covered = allEventFixtures().map((e) => e.eventName).toSet();
      expect(covered, TelemetryContract.eventNames.toSet());
    });

    test('a full 20-event batch validates', () {
      final fixtures = allEventFixtures();
      final events = [
        for (var i = 0; i < 20; i++)
          serialiseEvent(
            fixtures[i % fixtures.length],
            eventId: 'evt_${i.toString().padLeft(16, '0')}',
          ),
      ];
      expect(validator.validate(envelope(events)), isEmpty);
    });

    test('a 21-event batch is rejected by maxItems', () {
      final fixtures = allEventFixtures();
      final events = [
        for (var i = 0; i < 21; i++)
          serialiseEvent(
            fixtures[i % fixtures.length],
            eventId: 'evt_${i.toString().padLeft(16, '0')}',
          ),
      ];
      expect(validator.validate(envelope(events)), isNotEmpty);
    });

    test('an empty batch is rejected by minItems', () {
      expect(validator.validate(envelope([])), isNotEmpty);
    });
  });

  group('timestamps', () {
    test('isoUtc emits at most three fractional digits', () {
      // Dart's own toIso8601String emits six when microseconds are non-zero,
      // which breaks both the 24-character limit and the schema pattern.
      final microsecondPrecision = DateTime.utc(
        2026,
        8,
        11,
        9,
        1,
        14,
        639,
        123,
      );
      expect(
        microsecondPrecision.toIso8601String(),
        '2026-08-11T09:01:14.639123Z',
      );
      final formatted = DefaultTelemetryService.isoUtc(microsecondPrecision);
      expect(formatted, '2026-08-11T09:01:14.639Z');
      expect(formatted.length, lessThanOrEqualTo(24));
    });

    test('a local-time input is converted to UTC', () {
      final local = DateTime.utc(2026, 8, 11, 9, 0, 0).toLocal();
      expect(DefaultTelemetryService.isoUtc(local), '2026-08-11T09:00:00.000Z');
    });

    test('every fixture timestamp matches the contract pattern', () {
      final pattern = RegExp('^(?:${TelemetryContract.tsPattern})\$');
      for (final event in allEventFixtures()) {
        final serialised = serialiseEvent(event);
        expect(pattern.hasMatch(serialised['client_ts']! as String), isTrue);
      }
    });
  });

  group('request size', () {
    test('a full 20-event batch is far inside the 32 768-byte ceiling', () {
      final fixtures = allEventFixtures();
      final events = [
        for (var i = 0; i < 20; i++)
          serialiseEvent(
            fixtures[i % fixtures.length],
            eventId: 'evt_${i.toString().padLeft(16, '0')}',
          ),
      ];
      final bytes = utf8.encode(jsonEncode(envelope(events))).length;
      expect(bytes, lessThan(TelemetryContract.maxBodyBytes));
      // Recorded so a future field addition that inflates events is visible.
      expect(bytes, lessThan(4096));
    });
  });

  group('the fields this step must never send', () {
    test('no serialised event carries question_id or urgency_category', () {
      for (final event in allEventFixtures()) {
        final keys = serialiseEvent(event).keys;
        expect(keys, isNot(contains('question_id')));
        expect(keys, isNot(contains('urgency_category')));
      }
    });

    test('no serialised event carries admin_area_code', () {
      // Optional in the contract, and omitted by this client until the
      // facilities-artifact mapping is confirmed. There is no constructor
      // parameter for it, so this is structural.
      for (final event in allEventFixtures()) {
        expect(serialiseEvent(event).keys, isNot(contains('admin_area_code')));
      }
    });

    test('facility_search exposes no way to send an area code at all', () {
      const event = FacilitySearchEvent(
        searchMode: FacilitySearchMode.nearby,
        resultCount: 3,
      );
      expect(event.toProperties().keys, ['search_mode', 'result_count']);
    });

    test('feedback_submit exposes no free-text field', () {
      const event = FeedbackSubmitEvent(rating: 5);
      expect(event.toProperties().keys, ['rating']);
    });

    test('emergency_action carries the action type and nothing else', () {
      const event = EmergencyActionEvent(
        actionType: EmergencyActionType.callEmergencyNumber,
      );
      expect(event.toProperties(), {'action_type': 'call_emergency_number'});
      expect(
        event.toProperties().keys,
        isNot(contains('assessment_session_id')),
      );
    });

    test('assessment_step_view carries no step_count', () {
      const event = AssessmentStepViewEvent(
        assessmentSessionId: 'ses_00000000000000000001',
        stepIndex: 3,
      );
      expect(event.toProperties().keys, [
        'assessment_session_id',
        'step_index',
      ]);
    });
  });

  group('optional properties are omitted, never nulled', () {
    test('a null optional does not appear as an explicit null', () {
      const event = AppOpenEvent(launchType: LaunchType.warm);
      final properties = event.toProperties();
      expect(properties, {'launch_type': 'warm'});
      expect(properties.containsKey('is_first_launch'), isFalse);
    });

    test('an explicit null would fail the schema, proving the point', () {
      final errors = validator.validate(
        envelope([
          {
            'event_name': 'app_open',
            'event_id': 'evt_0000000000000001',
            'client_ts': '2026-08-11T09:01:14.639Z',
            'launch_type': 'warm',
            'is_first_launch': null,
          },
        ]),
      );
      expect(errors, isNotEmpty);
    });
  });
}
