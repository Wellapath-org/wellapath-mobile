/// Fail-closed privacy boundary for every outbound Sentry event.
///
/// ### Allowlist, not denylist
///
/// This does **not** remove fields from the SDK's event. It builds a **new**
/// event containing only approved fields and discards the original. Anything
/// the SDK adds now, or adds in a future version, is dropped unless it is
/// named here. A denylist would silently start transmitting whatever the next
/// SDK upgrade decides to attach.
///
/// ### What may leave the device
///
///  * sanitised exception class and message
///  * stack frames — file, function, line/column, package, symbolication
///    addresses — with filesystem paths scrubbed
///  * fatal / non-fatal severity, and the crash source
///  * app version, build, platform, release, environment
///
/// ### What may never leave
///
/// User, request, breadcrumbs, contexts, tags outside the allowlist, extras,
/// modules, threads, debug metadata, attachments, device identifiers, locale,
/// timezone, network operator, assessment session IDs, telemetry event IDs,
/// and every category of clinical data.
///
/// ### Hashing is not sanitisation
///
/// A prohibited value is dropped, never hashed and forwarded. A hash of a
/// symptom set is still derived from symptoms, and a hash of an identifier is
/// still an identifier.
///
/// If safe transformation cannot be guaranteed, [sanitise] returns null and
/// the whole event is dropped.
library;

import 'package:sentry_flutter/sentry_flutter.dart';

import 'crash_reporter.dart';

/// Tag keys this app is allowed to send. Anything else is discarded.
const Set<String> kApprovedTagKeys = {'crash_source', 'severity'};

/// Crash sources, mirroring the boundary's origins.
const Set<String> kApprovedCrashSources = {
  'flutter_framework',
  'platform_dispatch',
  'isolate',
  'native',
  'handled',
};

abstract final class SentryEventSanitiser {
  const SentryEventSanitiser._();

  /// Replaces a value that cannot be safely rendered.
  static const String redacted = '[redacted]';

  /// Frames deeper than this are dropped. A stack that long is a loop, and
  /// each frame is another chance to carry a path.
  static const int maxFrames = 120;

  /// Rebuilds [event] from approved fields only. Returns null to drop it.
  static SentryEvent? sanitise(SentryEvent event) {
    try {
      final exceptions = _sanitiseExceptions(event.exceptions);

      // An event with no exception and no message tells engineering nothing
      // and is a pure risk surface. Drop it.
      if (exceptions.isEmpty) return null;

      return SentryEvent(
        eventId: event.eventId,
        timestamp: event.timestamp,
        platform: event.platform,
        level: event.level,
        release: event.release,
        environment: event.environment,
        dist: event.dist,
        exceptions: exceptions,
        tags: _sanitiseTags(event.tags),
        // Everything below is deliberately omitted rather than copied:
        //   user, request, breadcrumbs, contexts, extra, modules, threads,
        //   debugMeta, message, transaction, culprit, fingerprint, logger,
        //   serverName, sdk, type, unknown.
        // Omitting `sdk` costs a little provider-side diagnostics and removes
        // a field whose contents this app does not control.
      );
    } catch (_) {
      // A sanitiser that throws must not let the raw event through.
      return null;
    }
  }

  static Map<String, String>? _sanitiseTags(Map<String, String>? tags) {
    if (tags == null || tags.isEmpty) return null;
    final safe = <String, String>{};
    for (final entry in tags.entries) {
      if (!kApprovedTagKeys.contains(entry.key)) continue;
      final value = entry.value.trim();
      // Values are closed vocabularies, so anything unexpected is dropped
      // rather than sanitised into shape.
      if (entry.key == 'crash_source' &&
          !kApprovedCrashSources.contains(value)) {
        continue;
      }
      if (entry.key == 'severity' && value != 'fatal' && value != 'non_fatal') {
        continue;
      }
      safe[entry.key] = value;
    }
    return safe.isEmpty ? null : safe;
  }

  static List<SentryException> _sanitiseExceptions(
    List<SentryException>? exceptions,
  ) {
    if (exceptions == null) return const [];
    final out = <SentryException>[];
    for (final exception in exceptions) {
      out.add(
        SentryException(
          // A Dart type name, never a value.
          type: _sanitiseType(exception.type),
          // The message goes through the same sanitiser the local boundary
          // uses, so clinical vocabulary and snake_case identifiers are
          // redacted before they can reach the wire.
          value: exception.value == null
              ? null
              : CrashSanitiser.sanitise(exception.value),
          stackTrace: _sanitiseStackTrace(exception.stackTrace),
          // `mechanism` carries handled/synthetic flags only — but it also
          // carries free-form `data`, so it is dropped entirely.
          // `module`, `threadId` and `throwable` are dropped: `throwable`
          // would re-attach the raw object the sanitiser just cleaned.
        ),
      );
    }
    return out;
  }

  /// Type names are Dart identifiers. Anything with whitespace or punctuation
  /// beyond generics is not a type name and is replaced.
  static String? _sanitiseType(String? type) {
    if (type == null) return null;
    final trimmed = type.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 80) return redacted;
    // Generics are the only place a Dart type name contains a space, and only
    // ever after a comma. Normalising those away first means any *remaining*
    // space marks a prose string — "Error for patient X" — not a type name.
    final normalised = trimmed.replaceAll(', ', ',');
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_<>,.]*$').hasMatch(normalised)
        ? trimmed
        : redacted;
  }

  static SentryStackTrace? _sanitiseStackTrace(SentryStackTrace? stackTrace) {
    if (stackTrace == null) return null;
    final frames = stackTrace.frames.take(maxFrames).map(_sanitiseFrame);
    return SentryStackTrace(
      frames: frames.toList(),
      // `registers` can hold raw memory values; dropped.
    );
  }

  /// Keeps what makes a frame useful and drops what makes it risky.
  ///
  /// Retained: file name, function, line/column, package, in-app flag, and the
  /// image/symbol/instruction addresses symbolication needs for an obfuscated
  /// release build.
  ///
  /// Dropped: `contextLine`, `preContext`, `postContext` and `vars` — these are
  /// *source text and local variable values*, which is precisely where an
  /// assessment payload would appear.
  static SentryStackFrame _sanitiseFrame(SentryStackFrame frame) {
    return SentryStackFrame(
      absPath: _scrubPath(frame.absPath),
      fileName: _scrubPath(frame.fileName),
      function: _scrubSymbol(frame.function),
      module: _scrubSymbol(frame.module),
      lineNo: frame.lineNo,
      colNo: frame.colNo,
      inApp: frame.inApp,
      package: frame.package,
      native: frame.native,
      platform: frame.platform,
      imageAddr: frame.imageAddr,
      symbolAddr: frame.symbolAddr,
      instructionAddr: frame.instructionAddr,
      rawFunction: _scrubSymbol(frame.rawFunction),
      symbol: _scrubSymbol(frame.symbol),
      stackStart: frame.stackStart,
    );
  }

  /// A local absolute path leaks the developer's username and directory
  /// layout, and a `file://` URL can carry a query string. Package-relative
  /// paths (`package:wellapath_mobile/...`, `dart:core`) are kept — they are
  /// what makes a frame readable.
  static String? _scrubPath(String? path) {
    if (path == null) return null;
    final value = path.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('package:') ||
        value.startsWith('dart:') ||
        value.startsWith('flutter:')) {
      return _stripQuery(value);
    }
    // Anything rooted in a real filesystem or a URL keeps only its basename.
    if (value.startsWith('/') ||
        value.startsWith('file:') ||
        value.startsWith('http:') ||
        value.startsWith('https:') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
      final basename = value
          .split(RegExp(r'[\\/]'))
          .where((s) => s.isNotEmpty)
          .lastOrNull;
      return basename == null ? redacted : _stripQuery(basename);
    }
    return _stripQuery(value);
  }

  static String _stripQuery(String value) {
    final cut = value.indexOf(RegExp(r'[?#]'));
    return cut == -1 ? value : value.substring(0, cut);
  }

  /// Function and symbol names are compiler-generated identifiers. A name
  /// carrying whitespace or a quote is a dynamically constructed label with
  /// user content interpolated into it, so it is replaced rather than kept.
  static String? _scrubSymbol(String? symbol) {
    if (symbol == null) return null;
    final value = symbol.trim();
    if (value.isEmpty) return null;
    if (value.length > 200) return redacted;
    if (RegExp(r'''["']''').hasMatch(value)) return redacted;
    if (RegExp(r'\s').hasMatch(value)) return redacted;
    // Reuse the local sanitiser's vocabulary rules: a frame named after a
    // clinical token is redacted for the same reason a message would be.
    final cleaned = CrashSanitiser.sanitise(value);
    return cleaned.contains(CrashSanitiser.redacted) ? redacted : value;
  }
}
