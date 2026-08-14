/// Sentry integration, entirely behind the existing crash boundary.
///
/// No other file in the application imports Sentry. Product code depends only
/// on `CrashReporter`, so the provider can be swapped or removed by changing
/// this file and nothing else.
///
/// ### Two gates, both required
///
/// Nothing here runs unless `CrashConfig.fromEnvironment()` reports enabled,
/// which needs both `CRASH_REPORTING_ENABLED=true` and a structurally valid
/// `SENTRY_DSN`. Every ordinary build, local build and test run keeps the
/// no-op sink.
///
/// ### Deliberate omissions
///
/// Two capabilities are switched **off** even though the SDK supports them,
/// and both are recorded in `docs/CRASH_MONITORING.md` as open items:
///
///  * **Native crash handling** (`enableNativeCrashHandling`,
///    `autoInitializeNativeSdk`). A native fatal is captured by the platform
///    SDK and uploaded on next launch **without passing through Dart's
///    `beforeSend`** — so the fail-closed sanitiser in this file could not vet
///    it. Enabling it needs separate approval after the native envelope has
///    been inspected on both platforms.
///  * **Automatic session tracking**. Session envelopes also bypass
///    `beforeSend`. The cost is that crash-free *session* rate is unavailable;
///    the benefit is that the only envelopes leaving the device are ones this
///    sanitiser has rebuilt field by field.
library;

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'crash_config.dart';
import 'crash_reporter.dart';
import 'sentry_event_sanitiser.dart';

/// Forwards sanitised crashes to Sentry.
class SentryCrashSink extends CrashSink {
  SentryCrashSink({this.captureOverride});

  /// Test seam. Replaces the call into the SDK so the sink's behaviour can be
  /// asserted without a live client.
  final Future<void> Function(
    Object error,
    StackTrace? stackTrace,
    Map<String, String> tags,
  )?
  captureOverride;

  /// Local, non-sensitive counters. No payloads, no identifiers.
  int forwarded = 0;
  int suppressed = 0;

  @override
  void report(SanitisedCrashReport report) =>
      reportDetailed(report, null, null);

  @override
  void reportDetailed(
    SanitisedCrashReport sanitised,
    Object? error,
    StackTrace? stackTrace,
  ) {
    // The local line the app has always printed stays exactly as it was, so
    // failures remain visible on-device whether or not a provider is enabled.
    debugPrint(
      'Crash boundary — ${sanitised.classification} in ${sanitised.origin}',
    );

    if (error == null) {
      suppressed++;
      return;
    }

    final tags = <String, String>{
      'crash_source': sanitised.origin,
      'severity': sanitised.isFatal ? 'fatal' : 'non_fatal',
    };

    try {
      forwarded++;
      final capture = captureOverride;
      if (capture != null) {
        unawaited(capture(error, stackTrace, tags));
        return;
      }
      unawaited(
        Sentry.captureException(
          error,
          stackTrace: stackTrace,
          withScope: (scope) {
            for (final entry in tags.entries) {
              scope.setTag(entry.key, entry.value);
            }
          },
        ),
      );
    } catch (_) {
      // A provider failure must never propagate into the app. It cannot
      // prevent startup, block navigation, or change how the original error
      // was going to be handled.
      suppressed++;
    }
  }
}

/// Fire-and-forget without importing `dart:async` for one symbol.
void unawaited(Future<void> future) {
  future.catchError((Object _) {
    // Swallowed deliberately: a failed upload is not an application error.
  });
}

/// Installs crash monitoring if, and only if, both gates are satisfied.
abstract final class CrashMonitoring {
  const CrashMonitoring._();

  /// Sentry SDK version this integration was written and verified against.
  static const String sdkVersion = '9.27.0';

  static CrashConfig _config = CrashConfig.disabled;

  static CrashConfig get config => _config;

  /// Attaches Sentry behind the already-installed boundary, when approved.
  ///
  /// `CrashReporter.install()` must already have run — it does, from `main`,
  /// before the first frame. This only *swaps the sink*, so the handlers are
  /// never chained onto themselves and no error is reported twice.
  ///
  /// Never throws. A provider that fails to initialise leaves the no-op sink
  /// in place and startup proceeds unaffected.
  static Future<void> init({CrashConfig? config}) async {
    _config = config ?? CrashConfig.fromEnvironment();

    if (!_config.enabled) {
      debugPrint('Crash monitoring disabled by configuration');
      return;
    }

    try {
      await SentryFlutter.init(applyPrivacyOptions);
      CrashReporter.setSink(SentryCrashSink());
      debugPrint(
        'Crash monitoring enabled — '
        'environment=${_config.environment} release=${_config.release}',
      );
    } catch (_) {
      // Fail safe, not open: the no-op sink stays.
      debugPrint(
        'Crash monitoring init failed — continuing without a provider',
      );
    }
  }

  /// Every privacy-relevant option, set explicitly.
  ///
  /// Defaults are not trusted: an SDK upgrade can change one, and several of
  /// these are `true` by default. Exposed for testing so the configuration
  /// itself can be asserted without a network client.
  @visibleForTesting
  static void applyPrivacyOptions(SentryFlutterOptions options) {
    options.dsn = _config.dsn;
    options.environment = _config.environment;
    options.release = _config.release;
    options.debug = false;

    // ── Identity ───────────────────────────────────────────────────────────
    options.sendDefaultPii = false; // no IP, no username, no device name
    options.attachThreads = false;
    options.reportPackages = false;

    // ── Breadcrumbs: off, and capped at zero as a second stop ──────────────
    options.maxBreadcrumbs = 0;
    options.beforeBreadcrumb = (breadcrumb, hint) => null;
    options.enableAutoNativeBreadcrumbs = false;
    options.enableAppLifecycleBreadcrumbs = false;
    options.enableWindowMetricBreadcrumbs = false;
    options.enableBrightnessChangeBreadcrumbs = false;
    options.enableTextScaleChangeBreadcrumbs = false;
    options.enableMemoryPressureBreadcrumbs = false;
    options.enableUserInteractionBreadcrumbs = false;

    // ── Attachments and captures of screen content ────────────────────────
    options.attachScreenshot = false;
    // Marked experimental by the SDK. Leaving it unset would rely on a
    // default we do not control, for a capability that uploads the widget
    // tree. Setting it explicitly is the safer side of that trade.
    // ignore: experimental_member_use
    options.attachViewHierarchy = false;
    options.reportViewHierarchyIdentifiers = false;

    // ── Tracing, profiling, performance ───────────────────────────────────
    options.tracesSampleRate = null;
    // Same reasoning as attachViewHierarchy: explicitly disabling profiling
    // is worth depending on an experimental setter.
    // ignore: experimental_member_use
    options.profilesSampleRate = null;
    options.enableAutoPerformanceTracing = false;
    options.enableUserInteractionTracing = false;
    options.enableTimeToFullDisplayTracing = false;
    options.enableFramesTracking = false;
    // App-start measurement is disabled by removing NativeAppStartIntegration
    // below; the `autoAppStart` flag is deprecated in this SDK version.

    // ── Network ───────────────────────────────────────────────────────────
    // No request/response bodies, headers or cookies: the HTTP integration is
    // never enabled, and failed-request capture is switched off explicitly.
    options.captureFailedRequests = false;

    // ── Native ────────────────────────────────────────────────────────────
    // Native envelopes bypass `beforeSend`, so the native SDK is not started
    // at all. This also guarantees no manifest/plist default can begin
    // collecting on its own. See the library comment.
    options.autoInitializeNativeSdk = false;
    options.enableNativeCrashHandling = false;
    options.enableNdkScopeSync = false;
    options.enableWatchdogTerminationTracking = false;
    options.enableAppHangTracking = false;

    // ── Sessions ──────────────────────────────────────────────────────────
    options.enableAutoSessionTracking = false;

    // ── Stack traces ──────────────────────────────────────────────────────
    // Kept: frames are the point of crash reporting. Sanitised per frame by
    // `SentryEventSanitiser`.
    options.attachStacktrace = true;

    // ── The fail-closed outbound boundary ─────────────────────────────────
    options.beforeSend = (event, hint) => SentryEventSanitiser.sanitise(event);

    removeAutomaticErrorIntegrations(options);
  }

  /// Removes the SDK's own error-capturing and context-loading integrations.
  ///
  /// The app already routes every error through `CrashReporter`. Leaving the
  /// SDK's `FlutterErrorIntegration` and `OnErrorIntegration` installed would
  /// capture the same failure a second time — inflating counts and splitting
  /// one issue in two. Context loaders are removed as well: the sanitiser
  /// drops contexts regardless, and not gathering them is stronger than
  /// gathering and discarding.
  @visibleForTesting
  static void removeAutomaticErrorIntegrations(SentryOptions options) {
    const unwanted = {
      'FlutterErrorIntegration',
      'OnErrorIntegration',
      'RunZonedGuardedIntegration',
      'IsolateErrorIntegration',
      'NativeSdkIntegration',
      'LoadContextsIntegration',
      'LoadImageListIntegration',
      'NativeAppStartIntegration',
      'ScreenshotIntegration',
      'WidgetsBindingIntegration',
      'DebugPrintIntegration',
    };
    for (final integration in List<Integration>.of(options.integrations)) {
      if (unwanted.contains(integration.runtimeType.toString())) {
        options.removeIntegration(integration);
      }
    }
  }

  /// Non-sensitive status, safe to print in any build. **Never the DSN.**
  static Map<String, Object?> diagnostics() => {
    ..._config.toDiagnostics(),
    'sdk_version': sdkVersion,
    'native_crash_handling': false,
    'session_tracking': false,
  };
}
