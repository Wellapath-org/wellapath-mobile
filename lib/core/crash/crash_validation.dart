/// Controlled crash triggers for validating the monitoring pipeline.
///
/// ### Why this exists and why it is not a button
///
/// Proving that a crash reaches the provider needs a crash. Using a real
/// clinical failure for that would put genuine assessment state into the first
/// event ever sent to a third party, so the triggers here carry **fixed
/// non-clinical markers** instead.
///
/// ### Availability
///
/// Every entry point is guarded by [isAvailable], which requires **all** of:
///
///  * a debug or profile build — `kReleaseMode` disables it outright;
///  * crash monitoring enabled through its own two gates;
///  * the `CRASH_VALIDATION_ENABLED=true` build-time define.
///
/// So an ordinary release build cannot reach it even with the define set, and
/// a public build cannot reach it at all. There is no UI affordance: nothing
/// in the widget tree calls these, they are not reachable by navigation, and
/// no clinical screen was modified to host them. They are invoked from a
/// debug console or a test harness.
///
/// Once internal-beta validation is signed off, this file can be deleted
/// outright — nothing in the product depends on it.
library;

import 'package:flutter/foundation.dart';

import 'crash_reporter.dart';
import 'sentry_crash_sink.dart';

/// Fixed, meaningless markers. Distinctive enough to find in a dashboard,
/// containing no clinical, personal or environmental information.
const String kValidationMarkerFatal = 'WP_VALIDATION_FATAL_A1';
const String kValidationMarkerAsync = 'WP_VALIDATION_ASYNC_B2';
const String kValidationMarkerNonFatal = 'WP_VALIDATION_NONFATAL_C3';

/// An error type that exists only for pipeline validation, so a validation
/// event can never be confused with a real failure in the dashboard.
class CrashValidationError extends Error {
  CrashValidationError(this.marker);

  final String marker;

  @override
  String toString() => 'CrashValidationError: $marker';
}

abstract final class CrashValidation {
  const CrashValidation._();

  static const bool _defineEnabled = bool.fromEnvironment(
    'CRASH_VALIDATION_ENABLED',
  );

  /// True only in a non-release build, with monitoring enabled and the
  /// validation define set.
  static bool get isAvailable =>
      !kReleaseMode && _defineEnabled && CrashMonitoring.config.enabled;

  /// Reports a fatal framework-style error through the boundary.
  ///
  /// Reported rather than thrown: throwing for real would take the app down
  /// during a validation run without proving anything extra, since the
  /// boundary is the same code path either way.
  static bool triggerFatal() {
    if (!isAvailable) return false;
    CrashReporter.reportFatalForValidation(
      CrashValidationError(kValidationMarkerFatal),
      origin: 'flutter_framework',
    );
    return true;
  }

  /// Raises an asynchronous error so it travels the `PlatformDispatcher` path
  /// exactly as an ordinary unhandled async error would.
  static bool triggerAsync() {
    if (!isAvailable) return false;
    Future<void>.error(
      CrashValidationError(kValidationMarkerAsync),
      StackTrace.current,
    ).ignore();
    return true;
  }

  /// Reports a non-fatal error through the handled path.
  static bool triggerNonFatal() {
    if (!isAvailable) return false;
    CrashReporter.reportHandled(
      CrashValidationError(kValidationMarkerNonFatal),
      origin: 'handled',
      stackTrace: StackTrace.current,
    );
    return true;
  }

  /// Every marker, for asserting absence elsewhere.
  static const List<String> markers = [
    kValidationMarkerFatal,
    kValidationMarkerAsync,
    kValidationMarkerNonFatal,
  ];
}
