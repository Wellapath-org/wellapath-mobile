/// Contract-drift guard.
///
/// The Dart contract mirror in `lib/core/telemetry/contract/telemetry_contract
/// .dart` is hand-written. This file is what makes that safe: it compares the
/// mirror against the vendored backend allowlist artifact in both directions,
/// so a field the backend added, removed, renamed, retyped, re-bounded or
/// re-enumerated fails CI.
///
/// **If this test fails, do not edit the mirror to match a stale artifact.**
/// Re-vendor `telemetry.v1.allowlist.json` (and its siblings) from the backend
/// repository, then mirror the change deliberately and re-read
/// `docs/TELEMETRY_CONTRACT.md` §8 for anything newly excluded.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_contract.dart';

import 'support/fixtures.dart';

void main() {
  late Map<String, Object?> allowlist;

  setUpAll(() {
    allowlist = loadContractArtifact('telemetry.v1.allowlist.json');
  });

  /// Renders a backend field descriptor into a comparable, order-independent
  /// map. Both sides go through the same shape so a diff is readable.
  Map<String, Object?> normaliseBackend(Map<String, Object?> field) => {
    'field': field['field'],
    'type': field['type'],
    'required': field['required'],
    'allowed_values': (field['allowed_values'] as List?)?.cast<String>(),
    'max_length': field['max_length'],
    'pattern': field['pattern'],
    'minimum': field['minimum'],
    'maximum': field['maximum'],
  };

  Map<String, Object?> normaliseMirror(TelemetryFieldSpec spec) => {
    'field': spec.field,
    'type': switch (spec.type) {
      TelemetryFieldType.string => 'string',
      TelemetryFieldType.integer => 'integer',
      TelemetryFieldType.boolean => 'boolean',
      TelemetryFieldType.enumeration => 'enum',
    },
    'required': spec.required,
    'allowed_values': spec.allowedValues,
    'max_length': spec.maxLength,
    'pattern': spec.pattern,
    'minimum': spec.minimum,
    'maximum': spec.maximum,
  };

  void expectFieldListsMatch(
    List<Object?> backendFields,
    List<TelemetryFieldSpec> mirrorFields,
    String label,
  ) {
    final backend = {
      for (final f in backendFields.cast<Map<String, Object?>>())
        f['field'] as String: normaliseBackend(f),
    };
    final mirror = {for (final s in mirrorFields) s.field: normaliseMirror(s)};

    expect(
      mirror.keys.toSet(),
      backend.keys.toSet(),
      reason: '$label: field names drifted from the backend allowlist',
    );
    for (final name in backend.keys) {
      expect(
        mirror[name],
        backend[name],
        reason: '$label.$name: constraint drifted from the backend allowlist',
      );
    }
  }

  group('contract parity — backend allowlist vs Dart mirror', () {
    test('vendored artifact is the expected contract version', () {
      expect(allowlist['contract_version'], TelemetryContract.version);
      expect(TelemetryContract.version, '1.0');
    });

    test('limits match', () {
      final limits = allowlist['limits']! as Map<String, Object?>;
      expect(limits['maxBodyBytes'], TelemetryContract.maxBodyBytes);
      expect(limits['maxEventsPerBatch'], TelemetryContract.maxEventsPerBatch);
      expect(limits['minEventsPerBatch'], TelemetryContract.minEventsPerBatch);
      expect(
        limits['maxClientTimestampAgeMs'],
        TelemetryContract.maxClientTimestampAgeMs,
      );
      expect(
        limits['maxClientTimestampSkewMs'],
        TelemetryContract.maxClientTimestampSkewMs,
      );
    });

    test('envelope fields match', () {
      expectFieldListsMatch(
        allowlist['envelope']! as List,
        TelemetryContract.envelope,
        'envelope',
      );
    });

    test('app context fields match', () {
      expectFieldListsMatch(
        allowlist['app_context']! as List,
        TelemetryContract.appContext,
        'app_context',
      );
    });

    test('common event fields match', () {
      expectFieldListsMatch(
        allowlist['common_event_fields']! as List,
        TelemetryContract.commonEventFields,
        'common_event_fields',
      );
    });

    test('the event name set matches exactly, in order', () {
      final backendNames = (allowlist['events']! as List)
          .cast<Map<String, Object?>>()
          .map((e) => e['event_name'] as String)
          .toList();
      expect(TelemetryContract.eventNames, backendNames);
      expect(TelemetryContract.events.keys.toList(), backendNames);
      expect(backendNames, hasLength(12));
    });

    test('every event property matches', () {
      for (final event
          in (allowlist['events']! as List).cast<Map<String, Object?>>()) {
        final name = event['event_name'] as String;
        final mirror = TelemetryContract.events[name];
        expect(mirror, isNotNull, reason: 'mirror is missing event $name');
        expectFieldListsMatch(
          event['properties']! as List,
          mirror!.properties,
          name,
        );
      }
    });

    test('rejection reason codes match', () {
      expect(
        TelemetryContract.rejectionReasonCodes,
        (allowlist['rejection_reason_codes']! as List).cast<String>(),
      );
    });

    test('admin area codes match, all 37 of them', () {
      final backendCodes =
          (allowlist['events']! as List)
                  .cast<Map<String, Object?>>()
                  .firstWhere(
                    (e) => e['event_name'] == 'facility_search',
                  )['properties']!
              as List;
      final adminArea = backendCodes.cast<Map<String, Object?>>().firstWhere(
        (p) => p['field'] == 'admin_area_code',
      );
      expect(
        TelemetryContract.adminAreaCodes,
        (adminArea['allowed_values']! as List).cast<String>(),
      );
      expect(TelemetryContract.adminAreaCodes, hasLength(37));
    });
  });

  group('client-side constants the contract document fixes', () {
    test('endpoint path, timeout, attempt budget and backoff', () {
      expect(TelemetryContract.endpointPath, '/v1/telemetry/events');
      expect(TelemetryContract.requestTimeout, const Duration(seconds: 10));
      expect(TelemetryContract.maxAttemptsPerBatch, 3);
      expect(TelemetryContract.backoff, const [
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
      ]);
      expect(TelemetryContract.maxQueuedEvents, 500);
    });

    test('30 days and 24 hours, spelled out', () {
      expect(
        TelemetryContract.maxClientTimestampAgeMs,
        const Duration(days: 30).inMilliseconds,
      );
      expect(
        TelemetryContract.maxClientTimestampSkewMs,
        const Duration(hours: 24).inMilliseconds,
      );
    });
  });
}
