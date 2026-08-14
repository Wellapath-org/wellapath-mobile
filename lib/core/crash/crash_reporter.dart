/// Provider-neutral crash-reporting boundary with privacy sanitisation.
///
/// **No crash provider is configured, and none was added.** The repository has
/// never had Sentry, Firebase Crashlytics or any equivalent, and adding one is
/// a third-party data-processor decision that needs founder and engineering
/// lead approval — not something an instrumentation task gets to decide. So
/// this file is the seam, not the integration: it defines where a provider
/// would attach, sanitises everything that would flow to it, and ships with a
/// sink that forwards nowhere.
///
/// The provider decision is recorded as unresolved in
/// `docs/TELEMETRY_MOBILE.md`.
///
/// ### What this does not do
///
/// It does not swallow errors. `FlutterError.onError` still reaches Flutter's
/// default handler, so a clinical failure fails exactly as loudly as it does
/// today. Suppressing errors to improve a crash-free metric would be trading a
/// safety signal for a vanity number.
library;

import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// Where a sanitised report would go. The default implementation goes nowhere.
abstract class CrashSink {
  /// Const so the disabled default sink stays a compile-time constant.
  const CrashSink();

  void report(SanitisedCrashReport report);

  /// Optional richer channel for a provider that can symbolicate.
  ///
  /// A provider needs the original error and stack to build structured,
  /// symbolicated frames — a pre-flattened string cannot be symbolicated. The
  /// raw objects are handed over here and are sanitised by the provider sink's
  /// own outbound boundary before anything leaves the device; they are never
  /// logged and never persisted in raw form.
  ///
  /// Sinks that cannot use them ignore them, which is why this defaults to the
  /// sanitised-only path.
  void reportDetailed(
    SanitisedCrashReport sanitised,
    Object? error,
    StackTrace? stackTrace,
  ) => report(sanitised);
}

/// The shipped sink. Retains the app's existing local behaviour — a single
/// non-clinical line via `debugPrint` — and transmits nothing.
class NoOpCrashSink extends CrashSink {
  const NoOpCrashSink();

  @override
  void report(SanitisedCrashReport report) {
    debugPrint('Crash boundary — ${report.classification} in ${report.origin}');
  }
}

/// Collects reports in memory. Test-only.
class RecordingCrashSink extends CrashSink {
  final List<SanitisedCrashReport> reports = [];

  @override
  void report(SanitisedCrashReport report) => reports.add(report);
}

/// A crash report after sanitisation.
///
/// Carries a coarse classification and a redacted message. There is no
/// attachment surface at all — no assessment state, no answers, no results, no
/// scores, no red flags, no tokens, no artifact contents, no queued telemetry
/// payloads, no breadcrumbs and no location. A provider integration must build
/// its payload from these fields only.
class SanitisedCrashReport {
  const SanitisedCrashReport({
    required this.classification,
    required this.origin,
    required this.message,
    required this.isFatal,
  });

  /// Coarse, fixed-vocabulary error class — the runtime type name of the
  /// error, which is a Dart type, never a value.
  final String classification;

  /// Where the boundary caught it: `flutter_framework` or `platform_dispatch`.
  final String origin;

  /// The exception message with prohibited patterns redacted.
  final String message;

  final bool isFatal;

  Map<String, Object?> toJson() => {
    'classification': classification,
    'origin': origin,
    'message': message,
    'is_fatal': isFatal,
  };
}

/// Redacts values that must never appear in a crash report.
///
/// Exception messages are the classic leak: `RangeError` quotes an index,
/// `type 'X' is not a subtype of Y` quotes a type, and a hand-thrown
/// `StateError('no rule matched rf_006 for severe_headache')` quotes clinical
/// content verbatim. The engine does not build messages like that today, but
/// "today" is not a control.
abstract final class CrashSanitiser {
  const CrashSanitiser._();

  static const String redacted = '[redacted]';

  /// Quoted string literals, which is how most Dart errors embed a value.
  static final RegExp _quoted = RegExp(r'''(['"])(?:(?!\1).){2,}\1''');

  /// Coordinate pairs and high-precision decimals.
  static final RegExp _coordinates = RegExp(
    r'-?\d{1,3}\.\d{4,}\s*[,;]\s*-?\d{1,3}\.\d{4,}|-?\d{1,3}\.\d{6,}',
  );

  static final RegExp _email = RegExp(r'[^\s@]+@[^\s@]+\.[A-Za-z]{2,}');

  static final RegExp _phone = RegExp(r'\+?\d[\d\s-]{8,}\d');

  /// Any snake_case identifier.
  ///
  /// This is the rule that does most of the work, and it is deliberately
  /// broad. Every clinical identifier in this codebase is snake_case — symptom
  /// tokens (`severe_headache`), red-flag rules (`rf_006`), question IDs
  /// (`q_017`), duration tokens (`days_1_3`), urgency values (`non_urgent`) —
  /// so redacting the shape catches the whole family, including tokens added
  /// after this file was written. Over-redacting a Dart identifier in an error
  /// message costs a little debuggability; under-redacting costs PHI.
  ///
  /// A word-boundary vocabulary list cannot do this job: `_` is a word
  /// character, so `\bheadache\b` does not match inside `severe_headache`.
  /// That gap was found by the exception-message tests, not by inspection.
  static final RegExp _snakeCaseIdentifier = RegExp(
    r'\b[A-Za-z]{1,}(?:_[A-Za-z0-9]+)+\b',
  );

  /// SCREAMING_CASE and bare capitals — how urgency levels are written.
  static final RegExp _screamingCase = RegExp(r'\b[A-Z]{3,}\b');

  /// Long opaque tokens: assessment session IDs, telemetry event IDs, API
  /// keys. Matches a 16+ character run from the ID alphabet that contains at
  /// least one digit **and** one letter.
  ///
  /// The digit requirement is what keeps ordinary Dart identifiers readable —
  /// `EngineController` is exactly 16 characters and must survive, while
  /// `gt9mliaiMVXuZLEJodZxtSw9` must not. Found by the outbound-envelope
  /// tests: an assessment session ID quoted in an exception message passed
  /// every other rule.
  static final RegExp _opaqueToken = RegExp(
    r'\b(?=[A-Za-z0-9_-]*[0-9])(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{16,}\b',
  );

  /// Bare clinical and identity vocabulary that is neither snake_case nor
  /// capitalised. The list is not exhaustive and is not relied on to be —
  /// it backs up the two shape rules above.
  static final RegExp _sensitiveVocabulary = RegExp(
    r'\b('
    r'symptoms?|complaints?|answers?|questions?|'
    r'urgency|urgent|triage|emergency|redflags?|rules?|'
    r'conditions?|diagnos\w*|differentials?|scores?|scoring|'
    r'pregnan\w*|malaria|typhoid|meningitis|sepsis|cholera|'
    r'headache|fever|cough|bleeding|seizure\w*|'
    r'token|bearer|password|secret|cookie|authorization'
    r')\b',
    caseSensitive: false,
  );

  /// Hard ceiling. A long message is a stack trace or a serialised object that
  /// slipped into an exception string; neither is worth the risk.
  static const int maxMessageLength = 240;

  static String sanitise(Object? error) {
    var text = error?.toString() ?? '';
    text = text.replaceAll(_quoted, redacted);
    text = text.replaceAll(_coordinates, redacted);
    text = text.replaceAll(_email, redacted);
    text = text.replaceAll(_phone, redacted);
    text = text.replaceAll(_opaqueToken, redacted);
    text = text.replaceAll(_snakeCaseIdentifier, redacted);
    text = text.replaceAll(_screamingCase, redacted);
    text = text.replaceAll(_sensitiveVocabulary, redacted);
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > maxMessageLength) {
      text = '${text.substring(0, maxMessageLength)}…';
    }
    return text;
  }

  /// The error's runtime type — a class name, never a value.
  static String classify(Object? error) =>
      error == null ? 'UnknownError' : error.runtimeType.toString();
}

/// Installs the crash boundary.
abstract final class CrashReporter {
  const CrashReporter._();

  static CrashSink _sink = const NoOpCrashSink();

  static CrashSink get sink => _sink;

  /// Installs handlers that sanitise, forward to [sink], **and then let the
  /// original behaviour proceed**.
  ///
  /// [stackTrace] is never forwarded to the sink. A stack trace is a sequence
  /// of file paths and symbol names, which is exactly what a provider would
  /// want — but this app has no approved provider, and until one exists the
  /// safest amount of stack detail to retain is none. When a provider is
  /// approved, the stack becomes the first thing to review for leakage.
  /// Swaps the destination without touching the installed handlers.
  ///
  /// This is how a provider is attached after startup. Calling [install] twice
  /// would chain the framework handler onto the one this class installed
  /// first, so the same error would be reported twice — the sink is swapped
  /// instead.
  static void setSink(CrashSink sink) => _sink = sink;

  static void install({CrashSink? sink}) {
    _sink = sink ?? const NoOpCrashSink();

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _report(
        details.exception,
        stackTrace: details.stack,
        origin: 'flutter_framework',
        isFatal: false,
      );
      // Never suppressed — the framework still presents the error.
      previousOnError?.call(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _report(
        error,
        stackTrace: stack,
        origin: 'platform_dispatch',
        isFatal: true,
      );
      // false = not handled here, so the zone's default behaviour still runs.
      return false;
    };

    _installIsolateListener();
  }

  static RawReceivePort? _isolatePort;

  /// Catches errors thrown on this isolate that no zone handler saw.
  ///
  /// Registered once; a second `install()` (as tests do) reuses the existing
  /// port rather than stacking listeners, which would double-report.
  static void _installIsolateListener() {
    if (_isolatePort != null) return;
    try {
      final port = RawReceivePort((dynamic pair) {
        if (pair is! List || pair.isEmpty) return;
        final error = pair.first;
        final stack = pair.length > 1 && pair[1] is String
            ? StackTrace.fromString(pair[1] as String)
            : null;
        _report(error, stackTrace: stack, origin: 'isolate', isFatal: true);
      });
      Isolate.current.addErrorListener(port.sendPort);
      _isolatePort = port;
    } catch (_) {
      // Unsupported on some targets (web). Not a reason to fail startup.
    }
  }

  /// Reports an error caught by application code without changing how that
  /// code handles it.
  static void reportHandled(
    Object error, {
    required String origin,
    StackTrace? stackTrace,
  }) => _report(error, stackTrace: stackTrace, origin: origin, isFatal: false);

  /// Reports a fatal error without altering how the caller handles it.
  ///
  /// Used only by `CrashValidation`, which needs the fatal severity a real
  /// framework crash would carry. Product code uses [reportHandled]; there is
  /// no product call site for this, and its only caller is gated behind
  /// `kReleaseMode`, the monitoring gates and a validation define.
  static void reportFatalForValidation(
    Object error, {
    required String origin,
    StackTrace? stackTrace,
  }) => _report(
    error,
    stackTrace: stackTrace ?? StackTrace.current,
    origin: origin,
    isFatal: true,
  );

  /// The last report's identity and time, for de-duplication.
  ///
  /// Overlapping handlers can observe the same failure — a framework error
  /// that also surfaces through the zone, for example. Reporting it twice
  /// inflates crash counts and splits one issue across two. Identity is the
  /// *sanitised* classification, origin and message, so de-duplication never
  /// requires holding a raw value.
  static String? _lastKey;
  static DateTime? _lastAt;

  /// Two identical reports inside this window are treated as one event.
  static const Duration dedupeWindow = Duration(seconds: 2);

  @visibleForTesting
  static void resetDedupe() {
    _lastKey = null;
    _lastAt = null;
  }

  static void _report(
    Object? error, {
    required String origin,
    required bool isFatal,
    StackTrace? stackTrace,
  }) {
    try {
      final report = SanitisedCrashReport(
        classification: CrashSanitiser.classify(error),
        origin: origin,
        message: CrashSanitiser.sanitise(error),
        isFatal: isFatal,
      );

      final key = '${report.classification}|${report.origin}|${report.message}';
      final now = DateTime.now();
      if (_lastKey == key &&
          _lastAt != null &&
          now.difference(_lastAt!) < dedupeWindow) {
        return;
      }
      _lastKey = key;
      _lastAt = now;

      _sink.reportDetailed(report, error, stackTrace);
    } catch (_) {
      // A failing crash reporter must not become the crash.
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _sink = const NoOpCrashSink();
    resetDedupe();
  }
}
