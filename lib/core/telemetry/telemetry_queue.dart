/// Persistent, bounded, FIFO offline queue for telemetry events.
///
/// Built on Hive, which the app already uses for the config cache, so no new
/// persistence mechanism is introduced. Hive's `add()` assigns monotonically
/// increasing integer keys, which gives insertion order, cheap drop-oldest and
/// cheap targeted deletion without maintaining an index of our own.
///
/// Hive stores under the app's own data directory, so the queue is removed by
/// an uninstall — required by contract §5.
///
/// **Nothing clinical is stored and nothing clinical is used as a key.** Keys
/// are Hive's own integers; records are the exact serialised event that would
/// go on the wire, which has already passed [PrivacyGuard] before arriving
/// here and is checked again on the way out.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'contract/telemetry_contract.dart';
import 'privacy_guard.dart';
import 'telemetry_runtime.dart';

/// Storage seam, so the queue can be unit-tested without a Hive binding.
abstract class TelemetryQueueStore {
  Future<void> init();
  Iterable<int> keys();
  String? read(int key);
  Future<int> append(String record);
  Future<void> delete(Iterable<int> keys);
  Future<void> clear();
  int get length;
}

/// Hive-backed store. One box, opened lazily.
class HiveTelemetryQueueStore implements TelemetryQueueStore {
  HiveTelemetryQueueStore({this.boxName = 'telemetry_queue'});

  final String boxName;
  Box<String>? _box;

  Box<String> get _open {
    final box = _box;
    if (box == null) {
      throw StateError('TelemetryQueueStore used before init()');
    }
    return box;
  }

  @override
  Future<void> init() async {
    if (_box != null) return;
    try {
      _box = await Hive.openBox<String>(boxName);
    } catch (_) {
      // A box that cannot be opened is almost always a corrupted file from an
      // interrupted write or an incompatible on-disk layout. Telemetry is
      // best-effort, so the correct move is to discard it and carry on — never
      // to fail app startup over an analytics queue.
      await Hive.deleteBoxFromDisk(boxName);
      _box = await Hive.openBox<String>(boxName);
    }
  }

  @override
  Iterable<int> keys() => _open.keys.cast<int>();

  @override
  String? read(int key) => _open.get(key);

  @override
  Future<int> append(String record) => _open.add(record);

  @override
  Future<void> delete(Iterable<int> keys) => _open.deleteAll(keys);

  @override
  Future<void> clear() => _open.clear();

  @override
  int get length => _open.length;
}

/// In-memory store for tests and for the disabled configuration.
class InMemoryTelemetryQueueStore implements TelemetryQueueStore {
  final Map<int, String> _records = {};
  int _nextKey = 0;

  @override
  Future<void> init() async {}

  @override
  Iterable<int> keys() => _records.keys.toList()..sort();

  @override
  String? read(int key) => _records[key];

  @override
  Future<int> append(String record) async {
    final key = _nextKey++;
    _records[key] = record;
    return key;
  }

  @override
  Future<void> delete(Iterable<int> keys) async {
    for (final key in keys) {
      _records.remove(key);
    }
  }

  @override
  Future<void> clear() async => _records.clear();

  @override
  int get length => _records.length;
}

/// One event as it sits in the queue.
class QueuedTelemetryEvent {
  const QueuedTelemetryEvent({required this.key, required this.payload});

  /// Store key — used only to delete the record after a confirmed outcome.
  final int key;

  /// The serialised event, exactly as it will be transmitted. `event_id` and
  /// `client_ts` inside it were stamped at occurrence and are never rewritten,
  /// which is what makes retries de-duplicable server-side.
  final Map<String, Object?> payload;

  String get eventId => payload['event_id'] as String;
  String get eventName => payload['event_name'] as String;
}

/// Bounded FIFO queue with drop-oldest overflow and 30-day expiry.
class TelemetryQueue {
  TelemetryQueue({
    required TelemetryQueueStore store,
    required TelemetryClock clock,
    required TelemetryDiagnostics diagnostics,
    this.capacity = TelemetryContract.maxQueuedEvents,
  }) : _store = store,
       _clock = clock,
       _diagnostics = diagnostics;

  final TelemetryQueueStore _store;
  final TelemetryClock _clock;
  final TelemetryDiagnostics _diagnostics;
  final int capacity;

  /// On-disk record layout version.
  ///
  /// Bumped whenever the record envelope changes shape. A record written by a
  /// different version is discarded rather than migrated: the queue holds at
  /// most a few hundred best-effort analytics events with a 30-day life, so
  /// discarding is strictly cheaper and safer than maintaining migration code
  /// for data nobody can miss. See `docs/TELEMETRY_MOBILE.md`.
  static const int schemaVersion = 1;

  Future<void> init() => _store.init();

  int get length => _store.length;

  /// Appends [payload] and enforces the capacity ceiling.
  ///
  /// Returns false only if the write itself failed — the caller treats that as
  /// a dropped event and nothing more. Overflow is *not* a failure: the oldest
  /// records are removed and the new one is kept, because in a queue of
  /// product analytics the recent events are the ones worth having.
  Future<bool> add(Map<String, Object?> payload) async {
    try {
      await _store.append(jsonEncode({'v': schemaVersion, 'e': payload}));
      await _trimToCapacity();
      return true;
    } catch (e) {
      // Never surface a storage failure to a caller on a clinical screen.
      debugPrint('Telemetry queue write failed');
      return false;
    }
  }

  Future<void> _trimToCapacity() async {
    final keys = _store.keys().toList()..sort();
    if (keys.length <= capacity) return;
    final excess = keys.take(keys.length - capacity).toList();
    await _store.delete(excess);
    _diagnostics.droppedOldest += excess.length;
  }

  /// Reads up to [max] deliverable events, oldest first.
  ///
  /// Along the way it permanently removes records that can never be delivered:
  ///
  ///  * unparseable or wrong-schema records — a corrupted entry is discarded,
  ///    never rethrown, so one bad row cannot wedge the queue forever;
  ///  * records whose `client_ts` is outside the contract's 30-day window, or
  ///    that no longer validate. Sending them would only earn a
  ///    `timestamp_out_of_range` rejection.
  ///
  /// Both removals bump a diagnostic counter so a queue quietly shedding
  /// events is visible without inspecting any payload.
  Future<List<QueuedTelemetryEvent>> peek({
    int max = TelemetryContract.maxEventsPerBatch,
  }) async {
    final now = _clock.nowUtc();
    final deliverable = <QueuedTelemetryEvent>[];
    final discard = <int>[];

    for (final key in _store.keys().toList()..sort()) {
      if (deliverable.length >= max) break;

      final raw = _store.read(key);
      if (raw == null) continue;

      Map<String, Object?>? payload;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map &&
            decoded['v'] == schemaVersion &&
            decoded['e'] is Map) {
          payload = Map<String, Object?>.from(decoded['e'] as Map);
        }
      } catch (_) {
        payload = null;
      }

      if (payload == null) {
        discard.add(key);
        _diagnostics.corruptedRecordsDiscarded++;
        continue;
      }

      // Re-validate on the way out. A record can become invalid purely by
      // ageing, and this is also the second of the two privacy checks: an
      // event that somehow reached the queue in a prohibited shape is stopped
      // here, before it can reach the transport.
      final verdict = PrivacyGuard.validateEvent(payload, now: now);
      if (!verdict.isValid) {
        discard.add(key);
        if (verdict.reason == 'timestamp_out_of_range') {
          _diagnostics.expired++;
        } else {
          _diagnostics.recordRejected(verdict.reason!);
        }
        continue;
      }

      deliverable.add(QueuedTelemetryEvent(key: key, payload: payload));
    }

    if (discard.isNotEmpty) {
      await _store.delete(discard);
    }
    return deliverable;
  }

  /// Removes events after a confirmed outcome — a 202 from the server, or a
  /// defined non-retryable disposition. Never called speculatively.
  Future<void> remove(Iterable<QueuedTelemetryEvent> events) =>
      _store.delete(events.map((e) => e.key));

  /// Drops everything. Used by the `telemetry_disabled` path and by the
  /// documented manual queue-clear procedure.
  Future<void> clear() => _store.clear();
}
