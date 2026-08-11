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
  ///
  /// ### Build-time overrides
  ///
  /// Any of the three telemetry keys may also be supplied as a `--dart-define`,
  /// which **takes precedence over the bundled `.env`**:
  ///
  /// ```sh
  /// flutter build apk --release --dart-define=TELEMETRY_ENABLED=true
  /// ```
  ///
  /// This exists so a developer can produce an internal-testing build without
  /// editing `.env` — which is a *tracked* file, making an edit one `git add`
  /// away from shipping `TELEMETRY_ENABLED=true` to everyone.
  ///
  /// A `.env.local` overlay was the original intent and is not implementable:
  /// `flutter_dotenv` reads through the asset bundle, so the file would have to
  /// be declared in `pubspec.yaml`, and declaring a gitignored file that
  /// usually does not exist fails the build. `--dart-define` is the idiomatic
  /// Flutter mechanism for exactly this, and `TelemetryAppContext` already uses
  /// it for `APP_VERSION`/`APP_BUILD`.
  ///
  /// The production block still applies: a define cannot enable production
  /// collection on its own, because `TELEMETRY_PRODUCTION_APPROVED` is checked
  /// separately and defaults to off.
  factory TelemetryConfig.fromEnvironment({
    Map<String, String>? env,
    Map<String, String>? defines,
  }) {
    final resolvedDefines = defines ?? _dartDefines;
    final dotEnv = env ?? dotenv.env;

    /// A define wins when it is present and non-empty; otherwise `.env`.
    String? read(String key) {
      final define = resolvedDefines[key];
      if (define != null && define.trim().isNotEmpty) return define;
      return dotEnv[key];
    }

    final source = <String, String?>{
      'TELEMETRY_ENABLED': read('TELEMETRY_ENABLED'),
      'TELEMETRY_BASE_URL': read('TELEMETRY_BASE_URL'),
      'TELEMETRY_PRODUCTION_APPROVED': read('TELEMETRY_PRODUCTION_APPROVED'),
      'APP_ENV': read('APP_ENV'),
      'API_BASE_URL': read('API_BASE_URL'),
    };

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

  /// The `--dart-define` values, read at compile time.
  ///
  /// `String.fromEnvironment` must be `const` to be resolved by the compiler,
  /// so each key is spelled out rather than looked up dynamically. An absent
  /// define yields the empty string, which [TelemetryConfig.fromEnvironment]
  /// treats as "not supplied" and falls back to `.env`.
  static const Map<String, String> _dartDefines = {
    'TELEMETRY_ENABLED': String.fromEnvironment('TELEMETRY_ENABLED'),
    'TELEMETRY_BASE_URL': String.fromEnvironment('TELEMETRY_BASE_URL'),
    'TELEMETRY_PRODUCTION_APPROVED': String.fromEnvironment(
      'TELEMETRY_PRODUCTION_APPROVED',
    ),
    'APP_ENV': String.fromEnvironment('APP_ENV'),
    'API_BASE_URL': String.fromEnvironment('API_BASE_URL'),
  };
}
