/// Environment and feature-gate configuration for telemetry.
///
/// Telemetry is **off unless explicitly switched on**, and cannot be switched
/// on in production by configuration alone. Nothing in the product depends on
/// any of this: with telemetry disabled the service becomes a no-op and every
/// clinical, offline and locator flow behaves exactly as it does today.
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'contract/telemetry_contract.dart';

class TelemetryConfig {
  const TelemetryConfig({
    required this.enabled,
    required this.baseUrl,
    this.flushInterval = const Duration(seconds: 60),
    this.flushAtQueueLength = TelemetryContract.maxEventsPerBatch,
  });

  /// Master gate. False means `capture()` returns immediately and nothing is
  /// validated, queued, persisted or sent.
  final bool enabled;

  /// Base URL only — the endpoint path lives in
  /// [TelemetryContract.endpointPath] and is joined at transport time, so no
  /// application code hard-codes a full endpoint.
  final String baseUrl;

  /// Periodic background flush cadence. Off the clinical critical path by
  /// construction: it is a timer, not a UI callback.
  final Duration flushInterval;

  /// Flush eagerly once the queue reaches a full batch.
  final int flushAtQueueLength;

  String get endpoint => '$baseUrl${TelemetryContract.endpointPath}';

  /// A configuration that disables telemetry entirely. Used as the failure
  /// mode for every unreadable or ambiguous environment.
  static const TelemetryConfig disabled = TelemetryConfig(
    enabled: false,
    baseUrl: '',
  );

  /// Reads configuration from the environment.
  ///
  /// | Variable                       | Meaning                                       |
  /// | ------------------------------ | --------------------------------------------- |
  /// | `TELEMETRY_ENABLED`            | `true` to enable. Absent or anything else = off |
  /// | `TELEMETRY_BASE_URL`           | Base URL. Falls back to `API_BASE_URL`        |
  /// | `APP_ENV`                      | `production` forces telemetry off             |
  /// | `TELEMETRY_PRODUCTION_APPROVED`| Only key that can lift the production block   |
  ///
  /// No secret is read here and none is needed: the endpoint is unauthenticated,
  /// exactly like `/config`.
  ///
  /// **Production is disabled unless approved.** The brief requires production
  /// to stay off until sign-off, so `APP_ENV=production` overrides
  /// `TELEMETRY_ENABLED` unless a second, separate key is also set. Flipping
  /// one flag by accident cannot turn on production collection.
  factory TelemetryConfig.fromEnvironment({Map<String, String>? env}) {
    final source = env ?? dotenv.env;

    final enabledFlag = _isTrue(source['TELEMETRY_ENABLED']);
    if (!enabledFlag) return disabled;

    final appEnv = (source['APP_ENV'] ?? '').toLowerCase().trim();
    final isProduction = appEnv == 'production' || appEnv == 'prod';
    if (isProduction && !_isTrue(source['TELEMETRY_PRODUCTION_APPROVED'])) {
      return disabled;
    }

    final baseUrl = (source['TELEMETRY_BASE_URL']?.trim().isNotEmpty ?? false)
        ? source['TELEMETRY_BASE_URL']!.trim()
        : (source['API_BASE_URL'] ?? '').trim();

    // An enabled config with nowhere to send is a misconfiguration, not a
    // reason to guess a host. Fail closed.
    if (baseUrl.isEmpty) return disabled;

    return TelemetryConfig(
      enabled: true,
      baseUrl: baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl,
    );
  }

  static bool _isTrue(String? raw) => raw?.trim().toLowerCase() == 'true';
}
