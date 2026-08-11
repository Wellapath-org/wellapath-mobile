/// Service behaviour: capture, batching, retry, backoff, session disablement,
/// configuration gating, concurrency and diagnostics.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_contract.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_event.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_config.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_queue.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_runtime.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_service.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_transport.dart';

import 'support/fixtures.dart';

/// Connectivity that reports offline.
class OfflineConnectivity implements TelemetryConnectivity {
  const OfflineConnectivity();

  @override
  Future<bool> isOnline() async => false;
}

void main() {
  final now = DateTime.utc(2026, 8, 11, 9, 0, 0);

  late FakeClock clock;
  late TelemetryDiagnostics diagnostics;
  late InMemoryTelemetryQueueStore store;
  late RecordingSleeper sleeper;

  setUp(() {
    clock = FakeClock(now);
    diagnostics = TelemetryDiagnostics();
    store = InMemoryTelemetryQueueStore();
    sleeper = RecordingSleeper();
  });

  DefaultTelemetryService build({
    required TelemetryTransport transport,
    bool enabled = true,
    TelemetryConnectivity? connectivity,
    double jitter = 1,
    int flushAtQueueLength = TelemetryContract.maxEventsPerBatch,
  }) => DefaultTelemetryService(
    config: TelemetryConfig(
      enabled: enabled,
      baseUrl: 'https://example.invalid',
      flushInterval: const Duration(hours: 1),
      flushAtQueueLength: flushAtQueueLength,
    ),
    queue: memoryQueue(clock: clock, diagnostics: diagnostics, store: store),
    transport: transport,
    appContext: testAppContext,
    clock: clock,
    idGenerator: FakeIdGenerator(),
    diagnostics: diagnostics,
    jitter: FixedTelemetryJitter(jitter),
    connectivity: connectivity,
    sleep: sleeper.call,
  );

  /// Lets the fire-and-forget enqueue inside `capture` settle.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('capture', () {
    test('stamps event_id and client_ts at occurrence', () async {
      final transport = FakeTransport([accepted]);
      final service = build(transport: transport);
      await service.init();

      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await settle();

      // Time passes between occurrence and flush.
      clock.advance(const Duration(minutes: 42));
      await service.flush();

      final envelope = transport.sent.single;
      final event = (envelope['events']! as List).single as Map;
      expect(event['event_id'], 'evt_0000000000000000');
      expect(
        event['client_ts'],
        '2026-08-11T09:00:00.000Z',
        reason: 'client_ts is when it happened, not when it was flushed',
      );
      expect(
        envelope['sent_at'],
        '2026-08-11T09:42:00.000Z',
        reason: 'sent_at is transmission time',
      );
      await service.dispose();
    });

    test('returns synchronously and never throws', () async {
      final service = build(transport: FakeTransport([accepted]));
      await service.init();
      // No await, no try — this is how every call site uses it.
      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      expect(diagnostics.captureAccepted, 1);
      await service.dispose();
    });

    test('counts accepted captures by event name', () async {
      final service = build(transport: FakeTransport([accepted]));
      await service.init();
      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      service.capture(const AppOpenEvent(launchType: LaunchType.warm));
      service.capture(
        const EmergencyActionEvent(
          actionType: EmergencyActionType.callEmergencyNumber,
        ),
      );
      await settle();
      expect(diagnostics.acceptedByEvent, {
        'app_open': 2,
        'emergency_action': 1,
      });
      await service.dispose();
    });

    test('flushes eagerly once a full batch is queued', () async {
      final transport = FakeTransport([accepted]);
      final service = build(transport: transport, flushAtQueueLength: 5);
      await service.init();
      for (var i = 0; i < 5; i++) {
        service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      }
      await settle();
      await service.flush();
      expect(transport.callCount, greaterThanOrEqualTo(1));
      await service.dispose();
    });
  });

  group('configuration gating', () {
    test('disabled configuration captures nothing at all', () async {
      final transport = FakeTransport([accepted]);
      final service = build(transport: transport, enabled: false);
      await service.init();

      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await settle();
      await service.flush();

      expect(store.length, 0, reason: 'nothing is persisted');
      expect(transport.callCount, 0, reason: 'nothing is transmitted');
      expect(diagnostics.captureAccepted, 0);
      expect(service.isActive, isFalse);
      await service.dispose();
    });

    test('a disabled service still answers diagnostics safely', () async {
      final service = build(
        transport: FakeTransport([accepted]),
        enabled: false,
      );
      final snapshot = service.diagnosticsSnapshot();
      expect(snapshot['enabled'], false);
      expect(snapshot['queue_length'], 0);
      await service.dispose();
    });
  });

  group('batching and size limits', () {
    test('sends 1 event when 1 is queued', () async {
      final transport = FakeTransport([accepted]);
      final service = build(transport: transport);
      await service.init();
      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await settle();
      await service.flush();
      expect((transport.sent.single['events']! as List), hasLength(1));
      await service.dispose();
    });

    for (final size in [1, 2, 19, 20]) {
      test('sends a batch of exactly $size when $size are queued', () async {
        final transport = FakeTransport([accepted]);
        final service = build(transport: transport);
        await service.init();
        for (var i = 0; i < size; i++) {
          service.capture(const AppOpenEvent(launchType: LaunchType.cold));
        }
        await settle();
        await service.flush();
        expect(transport.sent, hasLength(1));
        expect((transport.sent.single['events']! as List), hasLength(size));
        await service.dispose();
      });
    }

    test('21 queued events go out as 20 then 1, never 21', () async {
      final transport = FakeTransport([accepted]);
      final service = build(transport: transport);
      await service.init();
      for (var i = 0; i < 21; i++) {
        service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      }
      await settle();
      await service.flush();

      expect(transport.sent, hasLength(2));
      expect((transport.sent[0]['events']! as List), hasLength(20));
      expect((transport.sent[1]['events']! as List), hasLength(1));
      await service.dispose();
    });

    test('every request stays inside the 32 768-byte ceiling', () async {
      final transport = FakeTransport([accepted]);
      final service = build(transport: transport);
      await service.init();
      for (var i = 0; i < 60; i++) {
        service.capture(
          const AssessmentStartEvent(
            assessmentSessionId: 'ses_00000000000000000001',
            flowVersion: '1.0',
            entryPoint: AssessmentEntryPoint.home,
          ),
        );
      }
      await settle();
      await service.flush();

      for (final envelope in transport.sent) {
        final bytes = utf8.encode(jsonEncode(envelope)).length;
        expect(bytes, lessThanOrEqualTo(TelemetryContract.maxBodyBytes));
      }
      await service.dispose();
    });

    test('the envelope carries the contract version and app context', () async {
      final transport = FakeTransport([accepted]);
      final service = build(transport: transport);
      await service.init();
      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await settle();
      await service.flush();

      final envelope = transport.sent.single;
      expect(envelope['contract_version'], '1.0');
      expect(envelope['app'], testAppContext.toJson());
      expect(envelope.keys.toSet(), {
        'contract_version',
        'sent_at',
        'app',
        'events',
      });
      await service.dispose();
    });
  });

  group('retry classification and backoff', () {
    Future<DefaultTelemetryService> withOneEvent(
      FakeTransport transport, {
      double jitter = 1,
    }) async {
      final service = build(transport: transport, jitter: jitter);
      await service.init();
      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await settle();
      return service;
    }

    test(
      'a 5xx is retried up to three attempts, then the batch is kept',
      () async {
        final transport = FakeTransport([retryable]);
        final service = await withOneEvent(transport);

        await service.flush();

        expect(transport.callCount, 3, reason: 'at most 3 attempts per batch');
        expect(diagnostics.retries, 2, reason: '3 attempts means 2 retries');
        expect(store.length, 1, reason: 'the batch stays queued for later');
        await service.dispose();
      },
    );

    test('a 429 is retried the same way', () async {
      final transport = FakeTransport([rateLimited]);
      final service = await withOneEvent(transport);
      await service.flush();
      expect(transport.callCount, 3);
      expect(store.length, 1);
      await service.dispose();
    });

    test('a network failure is retried', () async {
      final transport = FakeTransport([networkFailure]);
      final service = await withOneEvent(transport);
      await service.flush();
      expect(transport.callCount, 3);
      expect(store.length, 1);
      await service.dispose();
    });

    test('backoff is 2s then 4s with no jitter applied', () async {
      final transport = FakeTransport([retryable]);
      final service = await withOneEvent(transport);
      await service.flush();
      expect(sleeper.delays, [
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      ]);
      await service.dispose();
    });

    test('jitter scales the delay deterministically', () async {
      final transport = FakeTransport([retryable]);
      final service = await withOneEvent(transport, jitter: 0.5);
      await service.flush();
      expect(sleeper.delays, [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
      await service.dispose();
    });

    test('production jitter always lands in [0.5, 1.0]', () {
      final jitter = RandomTelemetryJitter();
      for (var i = 0; i < 2000; i++) {
        final factor = jitter.factor();
        expect(factor, greaterThanOrEqualTo(0.5));
        expect(factor, lessThanOrEqualTo(1.0));
      }
    });

    test('a retry-after longer than the backoff wins', () async {
      final transport = FakeTransport([
        const TelemetryTransportResult(
          disposition: TelemetryDisposition.retryable,
          statusCode: 429,
          retryAfter: Duration(seconds: 30),
        ),
      ]);
      final service = await withOneEvent(transport);
      await service.flush();
      expect(sleeper.delays.first, const Duration(seconds: 30));
      await service.dispose();
    });

    test('event_id is identical across every retry', () async {
      final transport = FakeTransport([retryable]);
      final service = await withOneEvent(transport);
      await service.flush();

      expect(transport.sentEventIds, hasLength(3));
      expect(transport.sentEventIds[0], ['evt_0000000000000000']);
      expect(transport.sentEventIds[1], transport.sentEventIds[0]);
      expect(transport.sentEventIds[2], transport.sentEventIds[0]);
      await service.dispose();
    });

    test('client_ts is identical across every retry', () async {
      final transport = FakeTransport([retryable]);
      final service = await withOneEvent(transport);
      await service.flush();

      final timestamps = transport.sent
          .map((e) => ((e['events']! as List).single as Map)['client_ts'])
          .toSet();
      expect(timestamps, hasLength(1));
      await service.dispose();
    });

    test('a retried batch keeps its IDs across a later flush too', () async {
      final transport = FakeTransport([
        retryable,
        retryable,
        retryable,
        accepted,
      ]);
      final service = await withOneEvent(transport);

      await service.flush();
      expect(store.length, 1);

      await service.flush();

      expect(transport.sentEventIds.last, ['evt_0000000000000000']);
      expect(store.length, 0, reason: 'accepted on the second pass');
      await service.dispose();
    });

    test('400, 413 and 415 are never retried and drop the batch', () async {
      for (final status in [400, 413, 415]) {
        store = InMemoryTelemetryQueueStore();
        diagnostics = TelemetryDiagnostics();
        final transport = FakeTransport([
          TelemetryTransportResult(
            disposition: TelemetryDisposition.nonRetryable,
            statusCode: status,
            reasonCode: 'invalid_envelope',
          ),
        ]);
        final service = await withOneEvent(transport);

        await service.flush();

        expect(transport.callCount, 1, reason: '$status must not be retried');
        expect(store.length, 0, reason: '$status must drop the batch');
        expect(diagnostics.nonRetryableDrops, 1);
        expect(sleeper.delays, isEmpty);
        await service.dispose();
      }
    });

    test('a 202 removes the batch and records per-event rejections', () async {
      final transport = FakeTransport([
        const TelemetryTransportResult(
          disposition: TelemetryDisposition.accepted,
          statusCode: 202,
          accepted: 0,
          rejected: 1,
          rejectionReasons: ['unknown_property'],
        ),
      ]);
      final service = await withOneEvent(transport);
      await service.flush();

      expect(store.length, 0);
      expect(diagnostics.rejectedByReason['unknown_property'], 1);
      await service.dispose();
    });
  });

  group('telemetry_disabled', () {
    test('discards the pending batch and stops for the session', () async {
      final transport = FakeTransport([telemetryDisabled]);
      final service = build(transport: transport);
      await service.init();
      for (var i = 0; i < 5; i++) {
        service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      }
      await settle();
      expect(store.length, 5);

      await service.flush();

      expect(store.length, 0, reason: 'the pending batch is discarded');
      expect(service.isActive, isFalse);
      expect(diagnostics.sessionDisabled, isTrue);
      expect(transport.callCount, 1, reason: 'not retried');
      await service.dispose();
    });

    test('later captures in the same session are no-ops', () async {
      final transport = FakeTransport([telemetryDisabled]);
      final service = build(transport: transport);
      await service.init();
      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await settle();
      await service.flush();

      final callsAfterDisable = transport.callCount;
      service.capture(const AppOpenEvent(launchType: LaunchType.warm));
      await settle();
      await service.flush();

      expect(store.length, 0);
      expect(transport.callCount, callsAfterDisable);
      await service.dispose();
    });

    test('an unsupported contract version also disables the session', () async {
      final transport = FakeTransport([
        const TelemetryTransportResult(
          disposition: TelemetryDisposition.disableSession,
          statusCode: 400,
          reasonCode: 'unsupported_contract_version',
        ),
      ]);
      final service = build(transport: transport);
      await service.init();
      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await settle();
      await service.flush();
      expect(service.isActive, isFalse);
      await service.dispose();
    });
  });

  group('offline behaviour', () {
    test('events queue while offline and flush when back online', () async {
      final transport = FakeTransport([accepted]);
      final offlineService = build(
        transport: transport,
        connectivity: const OfflineConnectivity(),
      );
      await offlineService.init();
      for (var i = 0; i < 3; i++) {
        offlineService.capture(const AppOpenEvent(launchType: LaunchType.cold));
      }
      await settle();
      await offlineService.flush();

      expect(transport.callCount, 0, reason: 'nothing sent while offline');
      expect(store.length, 3, reason: 'everything retained');
      await offlineService.dispose();

      // Same store, now with connectivity — this is also the app-restart case.
      final onlineService = build(transport: transport);
      await onlineService.init();
      await onlineService.flush();

      expect((transport.sent.single['events']! as List), hasLength(3));
      expect(store.length, 0);
      await onlineService.dispose();
    });

    test('a restart re-sends queued events with their original IDs', () async {
      final firstTransport = FakeTransport([networkFailure]);
      final first = build(transport: firstTransport);
      await first.init();
      first.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await settle();
      await first.flush();
      expect(store.length, 1, reason: 'undelivered, so retained');
      await first.dispose();

      // A new service over the same store, as after a process restart.
      final secondTransport = FakeTransport([accepted]);
      final second = build(transport: secondTransport);
      await second.init();
      await second.flush();

      final event =
          (secondTransport.sent.single['events']! as List).single as Map;
      expect(event['event_id'], 'evt_0000000000000000');
      expect(event['client_ts'], '2026-08-11T09:00:00.000Z');
      await second.dispose();
    });

    test(
      'an interrupted flush leaves the batch queued, not half-removed',
      () async {
        // The transport never returns a confirmed outcome — the batch must
        // survive intact, because removal only happens after a response.
        final transport = FakeTransport([networkFailure]);
        final service = build(transport: transport);
        await service.init();
        for (var i = 0; i < 7; i++) {
          service.capture(const AppOpenEvent(launchType: LaunchType.cold));
        }
        await settle();

        await service.flush();

        expect(store.length, 7, reason: 'all seven still queued');
        await service.dispose();
      },
    );
  });

  group('concurrent flush protection', () {
    test('overlapping flushes share one pass', () async {
      final transport = FakeTransport([accepted]);
      final service = build(transport: transport);
      await service.init();
      for (var i = 0; i < 10; i++) {
        service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      }
      await settle();

      await Future.wait([
        service.flush(),
        service.flush(),
        service.flush(),
        service.flush(),
      ]);

      expect(
        transport.callCount,
        1,
        reason: 'four callers, one request — no duplicated queue mutation',
      );
      expect((transport.sent.single['events']! as List), hasLength(10));
      expect(store.length, 0);
      await service.dispose();
    });

    test('no event is sent twice when flushes race', () async {
      final transport = FakeTransport([accepted]);
      final service = build(transport: transport);
      await service.init();
      for (var i = 0; i < 25; i++) {
        service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      }
      await settle();

      await Future.wait([service.flush(), service.flush()]);

      final allIds = transport.sentEventIds.expand((ids) => ids).toList();
      expect(allIds.toSet(), hasLength(allIds.length), reason: 'no duplicates');
      expect(allIds, hasLength(25));
      await service.dispose();
    });

    test('a second flush after the first completes runs normally', () async {
      final transport = FakeTransport([accepted]);
      final service = build(transport: transport);
      await service.init();
      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await settle();
      await service.flush();

      service.capture(const AppOpenEvent(launchType: LaunchType.warm));
      await settle();
      await service.flush();

      expect(transport.callCount, 2);
      await service.dispose();
    });
  });

  group('diagnostics', () {
    test('the snapshot reports every documented counter', () async {
      final service = build(transport: FakeTransport([accepted]));
      await service.init();
      final snapshot = service.diagnosticsSnapshot();
      expect(
        snapshot.keys,
        containsAll(<String>[
          'enabled',
          'queue_length',
          'queue_capacity',
          'capture_accepted',
          'accepted_by_event',
          'rejected_by_reason',
          'dropped_oldest',
          'expired',
          'flush_attempts',
          'retries',
          'non_retryable_drops',
          'corrupted_records_discarded',
          'session_disabled',
        ]),
      );
      await service.dispose();
    });

    test('flush attempts are counted per request, including retries', () async {
      final transport = FakeTransport([retryable]);
      final service = build(transport: transport);
      await service.init();
      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await settle();
      await service.flush();
      expect(diagnostics.flushAttempts, 3);
      await service.dispose();
    });

    test('queue length is reported live', () async {
      final service = build(transport: FakeTransport([retryable]));
      await service.init();
      for (var i = 0; i < 4; i++) {
        service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      }
      await settle();
      expect(service.diagnosticsSnapshot()['queue_length'], 4);
      await service.dispose();
    });
  });

  group('containment', () {
    test('a transport that throws does not surface to the caller', () async {
      final service = build(transport: _ThrowingTransport());
      await service.init();
      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await settle();

      // Must complete rather than propagate.
      await service.flush();

      expect(store.length, 1, reason: 'the event is retained');
      await service.dispose();
    });

    test('a store that throws does not surface to the caller', () async {
      final service = DefaultTelemetryService(
        config: const TelemetryConfig(
          enabled: true,
          baseUrl: 'https://example.invalid',
          flushInterval: Duration(hours: 1),
        ),
        queue: TelemetryQueue(
          store: _ThrowingStore(),
          clock: clock,
          diagnostics: diagnostics,
        ),
        transport: FakeTransport([accepted]),
        appContext: testAppContext,
        clock: clock,
        idGenerator: FakeIdGenerator(),
        diagnostics: diagnostics,
      );
      await service.init();
      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await settle();
      await service.flush();
      await service.dispose();
    });
  });
}

class _ThrowingTransport implements TelemetryTransport {
  @override
  Future<TelemetryTransportResult> send(Map<String, Object?> envelope) async {
    throw StateError('transport exploded');
  }
}

class _ThrowingStore implements TelemetryQueueStore {
  @override
  Future<void> init() async {}

  @override
  Iterable<int> keys() => const [];

  @override
  String? read(int key) => null;

  @override
  Future<int> append(String record) async => throw StateError('disk full');

  @override
  Future<void> delete(Iterable<int> keys) async {}

  @override
  Future<void> clear() async {}

  @override
  int get length => 0;
}
