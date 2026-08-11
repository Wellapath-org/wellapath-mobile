/// Offline-queue behaviour: capacity, drop-oldest, expiry, corruption
/// recovery and schema migration.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_contract.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_queue.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_runtime.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_service.dart';

import 'support/fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 8, 11, 9, 0, 0);

  late FakeClock clock;
  late TelemetryDiagnostics diagnostics;
  late InMemoryTelemetryQueueStore store;

  setUp(() {
    clock = FakeClock(now);
    diagnostics = TelemetryDiagnostics();
    store = InMemoryTelemetryQueueStore();
  });

  TelemetryQueue build({int capacity = 500}) => memoryQueue(
    clock: clock,
    diagnostics: diagnostics,
    capacity: capacity,
    store: store,
  );

  Map<String, Object?> event(int index, {DateTime? at}) => {
    'event_name': 'app_open',
    'event_id': 'evt_${index.toString().padLeft(16, '0')}',
    'client_ts': DefaultTelemetryService.isoUtc(at ?? now),
    'launch_type': 'cold',
  };

  group('capacity and overflow', () {
    test('holds up to 500 events', () async {
      final queue = build();
      await queue.init();
      for (var i = 0; i < 500; i++) {
        await queue.add(event(i));
      }
      expect(queue.length, 500);
      expect(diagnostics.droppedOldest, 0);
    });

    test('the 501st event drops the oldest, not the newest', () async {
      final queue = build();
      await queue.init();
      for (var i = 0; i < 501; i++) {
        await queue.add(event(i));
      }
      expect(queue.length, 500);
      expect(diagnostics.droppedOldest, 1);

      final head = await queue.peek(max: 1);
      // Event 0 is gone; the queue now starts at 1 and still ends at 500.
      expect(head.single.eventId, 'evt_0000000000000001');

      final all = await queue.peek(max: 500);
      expect(all.last.eventId, 'evt_0000000000000500');
    });

    test('a large overflow drops exactly the excess', () async {
      final queue = build();
      await queue.init();
      for (var i = 0; i < 560; i++) {
        await queue.add(event(i));
      }
      expect(queue.length, 500);
      expect(diagnostics.droppedOldest, 60);
      final head = await queue.peek(max: 1);
      expect(head.single.eventId, 'evt_0000000000000060');
    });

    test('the capacity default is the contract-documented 500', () {
      expect(build().capacity, TelemetryContract.maxQueuedEvents);
    });
  });

  group('FIFO order and identity preservation', () {
    test('peek returns oldest first', () async {
      final queue = build();
      await queue.init();
      for (var i = 0; i < 5; i++) {
        await queue.add(event(i));
      }
      final batch = await queue.peek(max: 5);
      expect(batch.map((e) => e.eventId), [
        for (var i = 0; i < 5; i++) 'evt_${i.toString().padLeft(16, '0')}',
      ]);
    });

    test('event_id and client_ts survive a round trip unchanged', () async {
      final queue = build();
      await queue.init();
      final occurred = now.subtract(const Duration(hours: 3, minutes: 7));
      await queue.add(event(1, at: occurred));

      clock.advance(const Duration(hours: 2));
      final batch = await queue.peek();

      expect(batch.single.eventId, 'evt_0000000000000001');
      expect(
        batch.single.payload['client_ts'],
        DefaultTelemetryService.isoUtc(occurred),
        reason: 'client_ts must be occurrence time, not flush time',
      );
    });

    test('peek is bounded by the batch maximum', () async {
      final queue = build();
      await queue.init();
      for (var i = 0; i < 50; i++) {
        await queue.add(event(i));
      }
      expect(
        await queue.peek(),
        hasLength(TelemetryContract.maxEventsPerBatch),
      );
    });

    test('remove deletes only the named records', () async {
      final queue = build();
      await queue.init();
      for (var i = 0; i < 5; i++) {
        await queue.add(event(i));
      }
      final batch = await queue.peek(max: 2);
      await queue.remove(batch);
      expect(queue.length, 3);
      final remaining = await queue.peek(max: 5);
      expect(remaining.first.eventId, 'evt_0000000000000002');
    });
  });

  group('expiry', () {
    test('an event older than 30 days is dropped, not sent', () async {
      final queue = build();
      await queue.init();
      await queue.add(event(1, at: now.subtract(const Duration(days: 31))));
      await queue.add(event(2));

      final batch = await queue.peek();

      expect(batch, hasLength(1));
      expect(batch.single.eventId, 'evt_0000000000000002');
      expect(diagnostics.expired, 1);
      expect(queue.length, 1, reason: 'the expired record is removed');
    });

    test('an event ageing past 30 days while queued is dropped', () async {
      final queue = build();
      await queue.init();
      await queue.add(event(1));
      expect(await queue.peek(), hasLength(1));

      clock.advance(const Duration(days: 31));

      expect(await queue.peek(), isEmpty);
      expect(diagnostics.expired, 1);
    });

    test('29 days old is still deliverable', () async {
      final queue = build();
      await queue.init();
      await queue.add(event(1, at: now.subtract(const Duration(days: 29))));
      expect(await queue.peek(), hasLength(1));
      expect(diagnostics.expired, 0);
    });
  });

  group('corruption and migration', () {
    test('unparseable JSON is discarded without throwing', () async {
      final queue = build();
      await queue.init();
      await store.append('}{ not json');
      await queue.add(event(1));

      final batch = await queue.peek();

      expect(batch, hasLength(1));
      expect(diagnostics.corruptedRecordsDiscarded, 1);
      expect(queue.length, 1);
    });

    test('a record from a different schema version is discarded', () async {
      final queue = build();
      await queue.init();
      await store.append(jsonEncode({'v': 0, 'e': event(99)}));
      await store.append(jsonEncode({'v': 2, 'e': event(98)}));
      await queue.add(event(1));

      final batch = await queue.peek();

      expect(batch, hasLength(1));
      expect(batch.single.eventId, 'evt_0000000000000001');
      expect(diagnostics.corruptedRecordsDiscarded, 2);
    });

    test('a record with a missing envelope is discarded', () async {
      final queue = build();
      await queue.init();
      await store.append(jsonEncode({'v': 1}));
      await store.append(jsonEncode({'e': event(97)}));
      await store.append(jsonEncode('a bare string'));

      expect(await queue.peek(), isEmpty);
      expect(diagnostics.corruptedRecordsDiscarded, 3);
      expect(queue.length, 0, reason: 'corrupt records must not accumulate');
    });

    test('a queue of nothing but corruption still drains', () async {
      final queue = build();
      await queue.init();
      for (var i = 0; i < 30; i++) {
        await store.append('garbage $i');
      }
      expect(await queue.peek(), isEmpty);
      expect(queue.length, 0);
    });

    test('the current record schema version is 1', () {
      expect(TelemetryQueue.schemaVersion, 1);
    });
  });

  group('clear', () {
    test('empties the store', () async {
      final queue = build();
      await queue.init();
      for (var i = 0; i < 10; i++) {
        await queue.add(event(i));
      }
      await queue.clear();
      expect(queue.length, 0);
      expect(await queue.peek(), isEmpty);
    });
  });

  group('what the queue stores', () {
    test('a record is exactly the wire payload, nothing more', () async {
      final queue = build();
      await queue.init();
      await queue.add(event(1));

      final raw = jsonDecode(store.read(store.keys().first)!) as Map;
      expect(raw.keys.toSet(), {'v', 'e'});
      expect((raw['e']! as Map).keys.toSet(), {
        'event_name',
        'event_id',
        'client_ts',
        'launch_type',
      });
    });

    test('no clinical value is used as a key', () async {
      final queue = build();
      await queue.init();
      await queue.add(event(1));
      // Keys are the store's own monotonic integers, not derived from the
      // payload — the store's type signature is itself the guarantee, and
      // this pins the ordering the drop-oldest logic depends on.
      expect(store.keys(), isA<Iterable<int>>());
      expect(store.keys().toList(), [0]);
    });
  });
}
