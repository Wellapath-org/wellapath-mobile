/// Privacy-safe performance instrumentation.
///
/// Durations and coarse operation labels, and nothing else. There is no
/// parameter anywhere in this file that could carry a symptom, an answer, a
/// condition, an urgency, a red flag, a facility, a location or a user
/// identifier — a trace is a fixed label from [PerfOperation] plus a number of
/// microseconds.
///
/// These measurements are **not** transmitted. The telemetry contract has no
/// performance event in v1.0, so traces stay on-device: they exist to produce
/// the I1 baseline and to catch a regression in a test, and they are readable
/// through [PerfRecorder.snapshot].
library;

import 'package:flutter/foundation.dart';

/// The operations the I1 baseline measures.
///
/// A closed enum rather than free-form strings, so a label can never become an
/// accidental data channel.
enum PerfOperation {
  appStartCold('app_start_cold'),
  appStartWarm('app_start_warm'),
  artifactLoad('artifact_load'),
  assessmentStart('assessment_start'),
  questionTransition('question_transition'),
  scoring('scoring'),
  resultRender('result_render'),
  locatorStart('locator_start'),
  locatorSearch('locator_search'),
  telemetryQueueWrite('telemetry_queue_write'),
  telemetryBatchSerialise('telemetry_batch_serialise'),
  telemetryFlush('telemetry_flush');

  const PerfOperation(this.label);
  final String label;
}

/// Aggregated timings for one operation.
class PerfStats {
  PerfStats(this.operation);

  final PerfOperation operation;
  final List<int> _samplesUs = [];

  void add(int microseconds) => _samplesUs.add(microseconds);

  int get count => _samplesUs.length;

  double get meanMs =>
      count == 0 ? 0 : _samplesUs.reduce((a, b) => a + b) / count / 1000;

  double get minMs =>
      count == 0 ? 0 : _samplesUs.reduce((a, b) => a < b ? a : b) / 1000;

  double get maxMs =>
      count == 0 ? 0 : _samplesUs.reduce((a, b) => a > b ? a : b) / 1000;

  /// Nearest-rank p95 — the number that matters on a low-end device, where the
  /// mean hides the stalls users actually feel.
  double get p95Ms {
    if (count == 0) return 0;
    final sorted = List<int>.from(_samplesUs)..sort();
    final rank = ((sorted.length * 0.95).ceil() - 1).clamp(
      0,
      sorted.length - 1,
    );
    return sorted[rank] / 1000;
  }

  Map<String, Object?> toJson() => {
    'operation': operation.label,
    'count': count,
    'mean_ms': double.parse(meanMs.toStringAsFixed(3)),
    'p95_ms': double.parse(p95Ms.toStringAsFixed(3)),
    'min_ms': double.parse(minMs.toStringAsFixed(3)),
    'max_ms': double.parse(maxMs.toStringAsFixed(3)),
  };
}

/// In-memory recorder for performance samples.
abstract final class PerfRecorder {
  const PerfRecorder._();

  static final Map<PerfOperation, PerfStats> _stats = {};

  /// Off by default. Enabled by the baseline harness and by tests; a release
  /// build measures nothing unless deliberately switched on, so the
  /// instrumentation cannot itself become the regression.
  static bool enabled = false;

  static void record(PerfOperation operation, Duration elapsed) {
    if (!enabled) return;
    _stats
        .putIfAbsent(operation, () => PerfStats(operation))
        .add(elapsed.inMicroseconds);
  }

  /// Times [action] and records it. Returns whatever [action] returns, and
  /// rethrows whatever it throws — timing must never change control flow.
  static T time<T>(PerfOperation operation, T Function() action) {
    if (!enabled) return action();
    final stopwatch = Stopwatch()..start();
    try {
      return action();
    } finally {
      stopwatch.stop();
      record(operation, stopwatch.elapsed);
    }
  }

  static Future<T> timeAsync<T>(
    PerfOperation operation,
    Future<T> Function() action,
  ) async {
    if (!enabled) return action();
    final stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      stopwatch.stop();
      record(operation, stopwatch.elapsed);
    }
  }

  static List<Map<String, Object?>> snapshot() =>
      _stats.values.map((s) => s.toJson()).toList()..sort(
        (a, b) =>
            (a['operation'] as String).compareTo(b['operation'] as String),
      );

  @visibleForTesting
  static void reset() => _stats.clear();
}
