/// Application-wide telemetry entry point.
///
/// A static accessor rather than injected dependencies, matching how the rest
/// of this app reaches its services (`StorageService`, `StagedArtifactLoader.
/// instance`). Introducing a DI container to hold one best-effort analytics
/// service would have been an architecture change, and I1 is explicitly not
/// that.
///
/// The default is [NoOpTelemetryService], so every call site is safe before
/// [Telemetry.init] runs, in widget tests that never initialise it, and in any
/// build where telemetry is configured off.
library;

import 'package:flutter/foundation.dart';

import 'contract/telemetry_event.dart';
import 'telemetry_config.dart';
import 'telemetry_queue.dart';
import 'telemetry_runtime.dart';
import 'telemetry_service.dart';
import 'telemetry_transport.dart';

abstract final class Telemetry {
  const Telemetry._();

  static TelemetryService _instance = const NoOpTelemetryService();

  static TelemetryService get instance => _instance;

  /// Wires up the real service if configuration enables it.
  ///
  /// Never throws and never blocks meaningfully: any failure leaves the no-op
  /// service in place and the app proceeds. Called after `runApp` so it cannot
  /// add to startup latency.
  static Future<void> init({
    TelemetryConfig? config,
    TelemetryAppContext? appContext,
  }) async {
    try {
      final resolved = config ?? TelemetryConfig.fromEnvironment();
      if (!resolved.enabled) {
        _instance = const NoOpTelemetryService();
        debugPrint('Telemetry disabled by configuration');
        return;
      }

      final diagnostics = TelemetryDiagnostics();
      const clock = SystemTelemetryClock();
      final service = DefaultTelemetryService(
        config: resolved,
        queue: TelemetryQueue(
          store: HiveTelemetryQueueStore(),
          clock: clock,
          diagnostics: diagnostics,
        ),
        transport: DioTelemetryTransport(endpoint: resolved.endpoint),
        appContext: appContext ?? TelemetryAppContext.fromPlatform(),
        clock: clock,
        diagnostics: diagnostics,
      );
      await service.init();
      _instance = service;
      debugPrint('Telemetry enabled');
    } catch (_) {
      _instance = const NoOpTelemetryService();
      debugPrint('Telemetry init failed — continuing without telemetry');
    }
  }

  /// Shorthand for `Telemetry.instance.capture(event)`.
  ///
  /// Every instrumentation call site in the app goes through this, so a reader
  /// can find all of them with one search and see that none of them awaits,
  /// branches on, or catches anything.
  static void capture(TelemetryEvent event) => _instance.capture(event);

  /// Replaces the service. Test-only.
  @visibleForTesting
  static void overrideInstance(TelemetryService service) => _instance = service;

  @visibleForTesting
  static Future<void> reset() async {
    await _instance.dispose();
    _instance = const NoOpTelemetryService();
  }
}
