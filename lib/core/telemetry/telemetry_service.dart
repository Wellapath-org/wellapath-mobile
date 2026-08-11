/// Privacy-safe product telemetry — contract v1.0.
///
/// The narrow interface is [TelemetryService]. Callers see two methods worth
/// caring about, [TelemetryService.capture] and [TelemetryService.flush], and
/// neither can throw, block, or change what the app does.
///
/// ### Containment
///
/// Every failure mode inside telemetry — a full disk, a corrupted queue, a
/// dead backend, a validation bug, a serialisation error — is caught here and
/// turned into a counter. No call site needs a `try`, and no clinical screen
/// can be made to fail by anything in this layer. [capture] returns `void`
/// synchronously and does its work off the caller's critical path.
///
/// ### What it will never carry
///
/// See `privacy_guard.dart` and `contract/telemetry_event.dart`. There is no
/// path through this file that accepts an untyped map from a caller.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'contract/telemetry_contract.dart';
import 'contract/telemetry_event.dart';
import 'privacy_guard.dart';
import 'telemetry_config.dart';
import 'telemetry_queue.dart';
import 'telemetry_runtime.dart';
import 'telemetry_transport.dart';

/// The narrow interface product code depends on.
abstract class TelemetryService {
  /// Records that [event] occurred, now.
  ///
  /// Returns immediately. `event_id` and `client_ts` are stamped here, at
  /// occurrence — not at flush — so a queued event keeps its original identity
  /// and time across every retry and across an app restart.
  ///
  /// Cannot throw. A rejected event increments a diagnostic counter and is not
  /// enqueued.
  void capture(TelemetryEvent event);

  /// Attempts to deliver queued events. Safe to call concurrently — overlapping
  /// calls share one in-flight pass rather than racing on the queue.
  Future<void> flush();

  /// Signals that the app went to the background — a good moment to flush,
  /// and off any clinical path by definition.
  void onAppBackgrounded();

  /// True when telemetry is configured on and has not been disabled by the
  /// server for this session.
  bool get isActive;

  /// Non-sensitive counters. Never contains payloads, IDs or field values.
  Map<String, Object?> diagnosticsSnapshot();

  Future<void> dispose();
}

/// The disabled implementation. Used when configuration is off, and as the
/// pre-initialisation default so a `capture()` that runs before `init()` is a
/// no-op rather than a crash.
class NoOpTelemetryService implements TelemetryService {
  const NoOpTelemetryService();

  @override
  void capture(TelemetryEvent event) {}

  @override
  Future<void> flush() async {}

  @override
  void onAppBackgrounded() {}

  @override
  bool get isActive => false;

  @override
  Map<String, Object?> diagnosticsSnapshot() => const {
    'enabled': false,
    'queue_length': 0,
  };

  @override
  Future<void> dispose() async {}
}

/// The working implementation.
class DefaultTelemetryService implements TelemetryService {
  DefaultTelemetryService({
    required this.config,
    required TelemetryQueue queue,
    required TelemetryTransport transport,
    required TelemetryAppContext appContext,
    TelemetryClock? clock,
    TelemetryIdGenerator? idGenerator,
    TelemetryJitter? jitter,
    TelemetryConnectivity? connectivity,
    TelemetryDiagnostics? diagnostics,
    Future<void> Function(Duration)? sleep,
  }) : _queue = queue,
       _transport = transport,
       _appContext = appContext,
       _clock = clock ?? const SystemTelemetryClock(),
       _ids = idGenerator ?? SecureTelemetryIdGenerator(),
       _jitter = jitter ?? RandomTelemetryJitter(),
       _connectivity = connectivity ?? const OptimisticConnectivity(),
       _diagnostics = diagnostics ?? TelemetryDiagnostics(),
       _sleep = sleep ?? _realSleep;

  static Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

  final TelemetryConfig config;
  final TelemetryQueue _queue;
  final TelemetryTransport _transport;
  final TelemetryAppContext _appContext;
  final TelemetryClock _clock;
  final TelemetryIdGenerator _ids;
  final TelemetryJitter _jitter;
  final TelemetryConnectivity _connectivity;
  final TelemetryDiagnostics _diagnostics;
  final Future<void> Function(Duration) _sleep;

  /// Set by a 503 `telemetry_disabled` (or an unsupported contract version).
  /// Not persisted — the contract scopes it to the application session, so a
  /// relaunch is allowed to try again.
  bool _sessionDisabled = false;

  /// Held for the duration of a flush pass. A second caller awaits this rather
  /// than starting its own, which is what stops two passes from reading the
  /// same records and deleting each other's keys.
  Future<void>? _inFlight;

  Timer? _flushTimer;
  bool _disposed = false;

  @visibleForTesting
  TelemetryDiagnostics get diagnostics => _diagnostics;

  @override
  bool get isActive => config.enabled && !_sessionDisabled && !_disposed;

  /// Opens the queue and starts the periodic background flush.
  ///
  /// Called after `runApp`, never before it: the brief requires telemetry not
  /// to delay startup, and there is nothing here worth a single frame of
  /// splash time.
  Future<void> init() async {
    if (!config.enabled) return;
    await _queue.init();
    _flushTimer = Timer.periodic(config.flushInterval, (_) {
      unawaited(flush());
    });
  }

  // ── Capture ───────────────────────────────────────────────────────────────

  @override
  void capture(TelemetryEvent event) {
    if (!isActive) return;
    try {
      final payload = <String, Object?>{
        'event_name': event.eventName,
        'event_id': _ids.newEventId(),
        'client_ts': isoUtc(_clock.nowUtc()),
        ...event.toProperties(),
      };

      // First of the two privacy checks: before persistence.
      final verdict = PrivacyGuard.validateEvent(payload, now: _clock.nowUtc());
      if (!verdict.isValid) {
        // Fail the capture rather than repairing it. A rejection here means a
        // bug in the typed event layer, and quietly stripping the field would
        // hide it. The reason code is fixed vocabulary; the value that caused
        // it is never recorded.
        _diagnostics.recordRejected(verdict.reason!);
        assert(() {
          debugPrint(
            'Telemetry capture rejected — ${verdict.reason}'
            '${verdict.field == null ? '' : ' (${verdict.field})'}',
          );
          return true;
        }());
        return;
      }

      _diagnostics.recordAccepted(event.eventName);
      unawaited(_enqueue(payload));
    } catch (_) {
      // Nothing a caller can do about it, and nothing it should have to.
      _diagnostics.recordRejected('invalid_type');
    }
  }

  Future<void> _enqueue(Map<String, Object?> payload) async {
    try {
      await _queue.add(payload);
      if (_queue.length >= config.flushAtQueueLength) {
        unawaited(flush());
      }
    } catch (_) {
      debugPrint('Telemetry enqueue failed');
    }
  }

  @override
  void onAppBackgrounded() {
    if (!isActive) return;
    unawaited(flush());
  }

  // ── Flush ─────────────────────────────────────────────────────────────────

  @override
  Future<void> flush() {
    if (!isActive) return Future<void>.value();
    // Concurrent-flush protection: whoever gets here first owns the pass;
    // everyone else awaits the same future.
    final existing = _inFlight;
    if (existing != null) return existing;
    final pass = _flushOnce().whenComplete(() => _inFlight = null);
    _inFlight = pass;
    return pass;
  }

  Future<void> _flushOnce() async {
    try {
      if (!await _connectivity.isOnline()) return;

      // Bounded: at most as many batches as a full queue could hold, so a
      // server that keeps accepting can drain the backlog in one pass but a
      // pathological loop still terminates.
      final maxBatches =
          (TelemetryContract.maxQueuedEvents /
                  TelemetryContract.maxEventsPerBatch)
              .ceil();

      for (var batchNumber = 0; batchNumber < maxBatches; batchNumber++) {
        if (!isActive) return;

        final batch = await _queue.peek();
        if (batch.isEmpty) return;

        final keepGoing = await _deliver(batch);
        if (!keepGoing) return;
      }
    } catch (_) {
      debugPrint('Telemetry flush failed');
    }
  }

  /// Delivers one batch. Returns true if the pass may continue to the next.
  Future<bool> _deliver(List<QueuedTelemetryEvent> batch) async {
    final sized = _fitToRequestLimit(batch);
    if (sized.isEmpty) return false;

    final envelope = buildEnvelope(sized);

    for (
      var attempt = 0;
      attempt < TelemetryContract.maxAttemptsPerBatch;
      attempt++
    ) {
      _diagnostics.flushAttempts++;
      final result = await _transport.send(envelope);

      switch (result.disposition) {
        case TelemetryDisposition.accepted:
          for (final reason in result.rejectionReasons) {
            _diagnostics.recordRejected(reason);
          }
          // Removed only now — after a confirmed response.
          await _queue.remove(sized);
          return true;

        case TelemetryDisposition.nonRetryable:
          // Permanent by contract. Keeping it would block the queue head
          // forever behind a batch that can never succeed.
          _diagnostics.nonRetryableDrops += sized.length;
          if (result.reasonCode != null) {
            _diagnostics.recordRejected(result.reasonCode!);
          }
          await _queue.remove(sized);
          return true;

        case TelemetryDisposition.disableSession:
          await _disableForSession();
          return false;

        case TelemetryDisposition.retryable:
          final isLastAttempt =
              attempt == TelemetryContract.maxAttemptsPerBatch - 1;
          if (isLastAttempt) {
            // Budget spent. The batch stays queued with its original event IDs
            // and timestamps, and a later flush — or the next app launch —
            // will try again.
            return false;
          }
          _diagnostics.retries++;
          await _sleep(_backoffFor(attempt, result.retryAfter));
      }
    }
    return false;
  }

  /// Exponential backoff with jitter, honouring `retry-after` when the server
  /// asks for longer than we would have waited.
  Duration _backoffFor(int attempt, Duration? retryAfter) {
    final base = TelemetryContract
        .backoff[attempt.clamp(0, TelemetryContract.backoff.length - 1)];
    final jittered = Duration(
      milliseconds: (base.inMilliseconds * _jitter.factor()).round(),
    );
    if (retryAfter != null && retryAfter > jittered) return retryAfter;
    return jittered;
  }

  Future<void> _disableForSession() async {
    _sessionDisabled = true;
    _diagnostics.sessionDisabled = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    // "Discard the pending batch" — and there is no point keeping the rest
    // either, since nothing more will be sent this session and the records
    // would only age towards expiry.
    await _queue.clear();
    debugPrint('Telemetry disabled by server for this session');
  }

  // ── Envelope ──────────────────────────────────────────────────────────────

  /// Builds the request envelope for [batch].
  @visibleForTesting
  Map<String, Object?> buildEnvelope(List<QueuedTelemetryEvent> batch) => {
    'contract_version': TelemetryContract.version,
    'sent_at': isoUtc(_clock.nowUtc()),
    'app': _appContext.toJson(),
    'events': batch.map((e) => e.payload).toList(),
  };

  /// Trims [batch] until the encoded request fits the 32 768-byte ceiling.
  ///
  /// Enforced client-side so a 413 is something we never provoke. Halving
  /// rather than trimming one event at a time keeps this O(log n) encodes; the
  /// contract's field limits make an event a few hundred bytes at most, so a
  /// full 20-event batch is nowhere near the ceiling and this loop normally
  /// runs its size check exactly once.
  List<QueuedTelemetryEvent> _fitToRequestLimit(
    List<QueuedTelemetryEvent> batch,
  ) {
    var candidate = batch;
    while (candidate.isNotEmpty) {
      final bytes = utf8.encode(jsonEncode(buildEnvelope(candidate))).length;
      if (bytes <= TelemetryContract.maxBodyBytes) return candidate;
      if (candidate.length == 1) {
        // A single event that cannot fit is undeliverable by any batching
        // strategy. Drop it rather than blocking the queue head forever.
        _diagnostics.nonRetryableDrops++;
        _diagnostics.recordRejected('payload_too_large');
        unawaited(_queue.remove(candidate));
        return const [];
      }
      candidate = candidate.sublist(0, (candidate.length / 2).ceil());
    }
    return const [];
  }

  @override
  Map<String, Object?> diagnosticsSnapshot() => {
    'enabled': config.enabled,
    ..._diagnostics.snapshot(queueLength: _queue.length),
  };

  @override
  Future<void> dispose() async {
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _inFlight;
  }

  /// ISO-8601 UTC with millisecond precision — `2026-08-11T09:01:14.639Z`.
  ///
  /// Dart's own `toIso8601String()` emits six fractional digits whenever
  /// microseconds are non-zero, which the contract's 24-character limit and
  /// `\.\d{1,3}` pattern both reject. Rebuilding the value at millisecond
  /// precision is what keeps every timestamp on the wire valid.
  @visibleForTesting
  static String isoUtc(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
      utc.millisecond,
    ).toIso8601String();
  }
}
