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

import 'package:flutter/foundation.dart';

/// Where a sanitised report would go. The default implementation goes nowhere.
abstract class CrashSink {
  void report(SanitisedCrashReport report);
}

/// The shipped sink. Retains the app's existing local behaviour — a single
/// non-clinical line via `debugPrint` — and transmits nothing.
class NoOpCrashSink implements CrashSink {
  const NoOpCrashSink();

  @override
  void report(SanitisedCrashReport report) {
    debugPrint('Crash boundary — ${report.classification} in ${report.origin}');
  }
}

/// Collects reports in memory. Test-only.
class RecordingCrashSink implements CrashSink {
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
  static void install({CrashSink? sink}) {
    _sink = sink ?? const NoOpCrashSink();

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _report(details.exception, origin: 'flutter_framework', isFatal: false);
      // Never suppressed — the framework still presents the error.
      previousOnError?.call(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _report(error, origin: 'platform_dispatch', isFatal: true);
      // false = not handled here, so the zone's default behaviour still runs.
      return false;
    };
  }

  /// Reports an error caught by application code without changing how that
  /// code handles it.
  static void reportHandled(Object error, {required String origin}) =>
      _report(error, origin: origin, isFatal: false);

  static void _report(
    Object? error, {
    required String origin,
    required bool isFatal,
  }) {
    try {
      _sink.report(
        SanitisedCrashReport(
          classification: CrashSanitiser.classify(error),
          origin: origin,
          message: CrashSanitiser.sanitise(error),
          isFatal: isFatal,
        ),
      );
    } catch (_) {
      // A failing crash reporter must not become the crash.
    }
  }

  @visibleForTesting
  static void resetForTest() => _sink = const NoOpCrashSink();
}
