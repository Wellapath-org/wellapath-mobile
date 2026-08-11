/// I1 performance baseline for the telemetry layer, and a regression guard on
/// scoring.
///
/// ### What this can and cannot measure
///
/// Everything here runs on the **host machine** in the Dart VM. That is the
/// right environment for the CPU-bound work — scoring, artifact parsing,
/// serialisation, queue writes — because those are pure Dart and the numbers
/// are comparable run to run.
///
/// It is the wrong environment for cold/warm app start, question-to-question
/// responsiveness, result rendering, locator startup and memory behaviour:
/// those are frame-scheduling and platform-channel bound, and a host number
/// for them would be misleading. Those are measured on device by the
/// procedure in `docs/TELEMETRY_MOBILE.md`, against the low-end Android
/// profile E9 used (`wellapath_lowend`, 720x1280 @ density 320).
///
/// Print the recorded table with:
/// ```sh
/// flutter test test/telemetry/performance_baseline_test.dart --reporter expanded
/// ```
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:wellapath_mobile/core/perf/perf_trace.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_contract.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_event.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_config.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_queue.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_runtime.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_service.dart';

import 'package:wellapath_mobile/core/engine/engine_controller.dart';
import 'package:wellapath_mobile/core/engine/models/engine_input.dart';

import '../engine/case_bank/artifact_fixtures.dart';
import 'support/fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 8, 11, 9, 0, 0);

  /// Rows are copied out of the recorder as each test finishes, because
  /// `setUp` resets it — otherwise the table printed at the end would only
  /// show whatever the last test happened to measure.
  final baseline = <String, Map<String, Object?>>{};

  void keepBaselineFor(String operation) {
    final row = PerfRecorder.snapshot().firstWhere(
      (r) => r['operation'] == operation,
    );
    baseline[operation] = row;
  }

  setUp(() {
    PerfRecorder.reset();
    PerfRecorder.enabled = true;
  });

  tearDown(() => PerfRecorder.enabled = false);

  tearDownAll(() {
    // Emitted so a CI run records the baseline rather than only asserting it.
    debugPrint('--- I1 telemetry performance baseline (host VM) ---');
    for (final row in baseline.values) {
      debugPrint(jsonEncode(row));
    }
  });

  DefaultTelemetryService buildService({
    required TelemetryQueueStore store,
    required TelemetryDiagnostics diagnostics,
    // Raised above the queue capacity where a test needs the queue to fill
    // rather than drain as it goes.
    int flushAtQueueLength = TelemetryContract.maxEventsPerBatch,
  }) => DefaultTelemetryService(
    config: TelemetryConfig(
      enabled: true,
      baseUrl: 'https://example.invalid',
      flushInterval: const Duration(hours: 1),
      flushAtQueueLength: flushAtQueueLength,
    ),
    queue: TelemetryQueue(
      store: store,
      clock: FakeClock(now),
      diagnostics: diagnostics,
    ),
    transport: FakeTransport([accepted]),
    appContext: testAppContext,
    clock: FakeClock(now),
    idGenerator: SecureTelemetryIdGenerator(),
    diagnostics: diagnostics,
  );

  group('telemetry overhead', () {
    test('queue write stays well under a frame budget', () async {
      final store = InMemoryTelemetryQueueStore();
      final diagnostics = TelemetryDiagnostics();
      final service = buildService(
        store: store,
        diagnostics: diagnostics,
        flushAtQueueLength: 100000,
      );
      await service.init();

      // Warm-up, excluded from the measurement.
      for (var i = 0; i < 100; i++) {
        service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      }
      await Future<void>.delayed(Duration.zero);
      PerfRecorder.reset();

      for (var i = 0; i < 1000; i++) {
        PerfRecorder.time(
          PerfOperation.telemetryQueueWrite,
          () => service.capture(
            const AssessmentStepViewEvent(
              assessmentSessionId: 'ses_00000000000000000001',
              stepIndex: 1,
            ),
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);

      final stats = PerfRecorder.snapshot().firstWhere(
        (row) => row['operation'] == 'telemetry_queue_write',
      );
      // A 60fps frame is 16.7 ms. A single capture must be orders of
      // magnitude below that, since it can happen during a transition.
      expect(stats['p95_ms']! as double, lessThan(1.0));
      expect(stats['mean_ms']! as double, lessThan(0.5));
      keepBaselineFor('telemetry_queue_write');
      await service.dispose();
    });

    test(
      'batch serialisation of a full 20-event batch is sub-millisecond',
      () async {
        final store = InMemoryTelemetryQueueStore();
        final diagnostics = TelemetryDiagnostics();
        final queue = TelemetryQueue(
          store: store,
          clock: FakeClock(now),
          diagnostics: diagnostics,
        );
        await queue.init();
        for (var i = 0; i < 20; i++) {
          await queue.add(
            serialiseEvent(
              allEventFixtures()[i % allEventFixtures().length],
              eventId: 'evt_${i.toString().padLeft(16, '0')}',
              clientTs: now,
            ),
          );
        }
        final batch = await queue.peek();

        for (var i = 0; i < 500; i++) {
          PerfRecorder.time(
            PerfOperation.telemetryBatchSerialise,
            () => utf8.encode(
              jsonEncode({
                'contract_version': TelemetryContract.version,
                'sent_at': DefaultTelemetryService.isoUtc(now),
                'app': testAppContext.toJson(),
                'events': batch.map((e) => e.payload).toList(),
              }),
            ),
          );
        }

        final stats = PerfRecorder.snapshot().firstWhere(
          (row) => row['operation'] == 'telemetry_batch_serialise',
        );
        expect(stats['p95_ms']! as double, lessThan(1.0));
        keepBaselineFor('telemetry_batch_serialise');
      },
    );

    test('a full flush of a full queue completes promptly', () async {
      final store = InMemoryTelemetryQueueStore();
      final diagnostics = TelemetryDiagnostics();
      final service = buildService(
        store: store,
        diagnostics: diagnostics,
        flushAtQueueLength: 100000,
      );
      await service.init();

      for (var i = 0; i < TelemetryContract.maxQueuedEvents; i++) {
        service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      }
      await Future<void>.delayed(Duration.zero);
      expect(store.length, 500);

      await PerfRecorder.timeAsync(PerfOperation.telemetryFlush, service.flush);

      expect(store.length, 0);
      final stats = PerfRecorder.snapshot().firstWhere(
        (row) => row['operation'] == 'telemetry_flush',
      );
      // 25 batches of 20 against an instant transport. Guards against an
      // accidental O(n^2) in the peek/remove path.
      expect(stats['max_ms']! as double, lessThan(2000));
      keepBaselineFor('telemetry_flush');
      await service.dispose();
    });

    test('a full queue does not degrade insertion', () async {
      final store = InMemoryTelemetryQueueStore();
      final diagnostics = TelemetryDiagnostics();
      final queue = TelemetryQueue(
        store: store,
        clock: FakeClock(now),
        diagnostics: diagnostics,
      );
      await queue.init();

      final payload = serialiseEvent(
        const AppOpenEvent(launchType: LaunchType.cold),
        clientTs: now,
      );
      for (var i = 0; i < 500; i++) {
        await queue.add(payload);
      }

      // Now at capacity: every further write also trims. Measure that path.
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 500; i++) {
        await queue.add(payload);
      }
      stopwatch.stop();

      expect(queue.length, 500);
      expect(diagnostics.droppedOldest, 500);
      expect(
        stopwatch.elapsedMilliseconds / 500,
        lessThan(1.0),
        reason: 'drop-oldest must stay cheap at capacity',
      );
    });

    test('disabled telemetry costs effectively nothing', () async {
      final service = DefaultTelemetryService(
        config: const TelemetryConfig(enabled: false, baseUrl: ''),
        queue: memoryQueue(
          clock: FakeClock(now),
          diagnostics: TelemetryDiagnostics(),
        ),
        transport: FakeTransport([accepted]),
        appContext: testAppContext,
      );
      await service.init();

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 100000; i++) {
        service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      }
      stopwatch.stop();

      // A disabled build returns on the first line of `capture`.
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
      await service.dispose();
    });
  });

  group('clinical baselines against the pinned production artifacts', () {
    // kb.ng.v2.4, rules.ng.v2.2, token_dictionary.ng.v1.1 — the same hash-
    // verified fixtures the E8.1 case bank run used. These numbers are the I1
    // baseline for on-device scoring; nothing here changes the engine, and
    // `PerfRecorder.time` is a pass-through wrapper.
    test('artifact load and scoring are measured and unchanged', () {
      late PinnedArtifacts artifacts;
      for (var i = 0; i < 5; i++) {
        artifacts = PerfRecorder.time(
          PerfOperation.artifactLoad,
          loadPinnedArtifacts,
        );
      }

      final engine = EngineController(
        rules: artifacts.rules,
        tokenDictionary: artifacts.tokenDictionary,
        knowledgeBase: artifacts.conditions,
        configMetadata: artifacts.configMetadata,
      );

      const input = EngineInput(
        // The E9 device-pass triage case: fever + headache + chills.
        // Demographic, severity and duration tokens are deliberately absent —
        // they are not symptom tokens and the red-flag evaluator rejects any
        // token missing from the dictionary.
        symptomTokens: ['fever', 'headache', 'chills'],
        candidateConditionIds: [],
      );

      final outputs = [
        for (var i = 0; i < 200; i++)
          PerfRecorder.time(PerfOperation.scoring, () => engine.run(input)),
      ];

      // Determinism: telemetry instrumentation must not have perturbed the
      // engine in any way, including run to run.
      final urgencies = outputs.map((o) => o.urgency).toSet();
      expect(urgencies, hasLength(1));

      final scoring = PerfRecorder.snapshot().firstWhere(
        (row) => row['operation'] == 'scoring',
      );
      // Host-VM ceiling, deliberately loose — this is a smoke guard against an
      // order-of-magnitude regression, not a device number. The device figure
      // comes from the procedure in docs/TELEMETRY_MOBILE.md.
      expect(scoring['p95_ms']! as double, lessThan(50));

      keepBaselineFor('artifact_load');
      keepBaselineFor('scoring');
    });
  });

  group('the recorder itself', () {
    test('is disabled by default, so release builds measure nothing', () {
      PerfRecorder.enabled = false;
      PerfRecorder.reset();
      PerfRecorder.time(PerfOperation.scoring, () => 1);
      expect(PerfRecorder.snapshot(), isEmpty);
    });

    test('time() returns the callee value and rethrows its errors', () {
      expect(PerfRecorder.time(PerfOperation.scoring, () => 42), 42);
      expect(
        () => PerfRecorder.time(
          PerfOperation.scoring,
          () => throw StateError('propagated'),
        ),
        throwsStateError,
      );
    });

    test('labels are a closed enum, never free-form strings', () {
      for (final operation in PerfOperation.values) {
        expect(operation.label, matches(RegExp(r'^[a-z_]+$')));
      }
    });

    test('a snapshot carries durations and labels only', () {
      PerfRecorder.record(
        PerfOperation.scoring,
        const Duration(milliseconds: 5),
      );
      final row = PerfRecorder.snapshot().single;
      expect(row.keys.toSet(), {
        'operation',
        'count',
        'mean_ms',
        'p95_ms',
        'min_ms',
        'max_ms',
      });
    });

    test('p95 is nearest-rank over the recorded samples', () {
      PerfRecorder.reset();
      for (var i = 1; i <= 100; i++) {
        PerfRecorder.record(
          PerfOperation.scoring,
          Duration(microseconds: i * 1000),
        );
      }
      final row = PerfRecorder.snapshot().single;
      expect(row['p95_ms'], 95.0);
      expect(row['max_ms'], 100.0);
      expect(row['min_ms'], 1.0);
    });
  });
}
