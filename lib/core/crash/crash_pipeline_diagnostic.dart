/// LOCAL-VERIFICATION-ONLY pipeline diagnostic for the build-212 event-loss
/// investigation. Lives only on `build/212-internal-verification` and is
/// NEVER merged into develop.
///
/// Purpose: the release 212 build loses the synthetic event somewhere between
/// the confirmed dialog action and Sentry ingest, with zero server-side
/// outcomes and zero on-device logging (release builds are silent by design).
/// This diagnostic makes an obfuscated release build report, on screen, which
/// pipeline stage was reached — while being STRUCTURALLY unable to contact
/// Sentry: when it is active, the SDK's transport is replaced by
/// [RecordingTransport], which contains no HTTP client, socket, native
/// transport or forwarding fallback. No envelope can leave the device.
///
/// What is recorded: closed-vocabulary stage names from [allowedStages] and a
/// numeric envelope-item count. Nothing else — never the envelope payload,
/// DSN, headers, exception message, stack content, device data or any
/// identifier. [record] drops anything outside the vocabulary rather than
/// storing it.
///
/// Gating: all four [CrashVerificationGate] conditions PLUS
/// `CRASH_PIPELINE_DIAGNOSTIC=true`. Absent, partial, malformed, production
/// -context or differently-invalid combinations fail closed: [record] is a
/// no-op, the transport is untouched and no UI renders.
library;

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'crash_verification_gate.dart';

abstract final class CrashPipelineDiagnostic {
  /// The complete closed vocabulary. `transport_send_called items=<count>`
  /// is the one parameterised form, and only a digit run may follow.
  static const Set<String> allowedStages = {
    'flutter_error_handler_entered',
    'crash_reporter_report_called',
    'sentry_sink_capture_called',
    'before_send_invoked',
    'before_send_returned_event',
    'before_send_returned_null',
    'capture_returned_id_nonzero',
    'capture_returned_id_zero',
    'transport_send_returned',
  };

  static final RegExp _transportStage = RegExp(
    r'^transport_send_called items=\d+$',
  );

  /// Pure gate logic, testable without rebuilding: the full verification
  /// gate plus the dedicated diagnostic define.
  static bool evaluate(Map<String, String> defines) =>
      CrashVerificationGate.evaluate(defines) &&
      (defines['CRASH_PIPELINE_DIAGNOSTIC'] ?? '').trim().toLowerCase() ==
          'true';

  /// The resolved gate for this binary.
  static final bool enabled = evaluate(_dartDefines);

  /// Test-only override so widget and recorder tests can exercise both
  /// states; production code never sets it.
  @visibleForTesting
  static bool? debugEnabledOverride;

  static bool get isEnabled => debugEnabledOverride ?? enabled;

  /// The recorded stage sequence, in arrival order, for the on-screen panel.
  static final ValueNotifier<List<String>> stages = ValueNotifier(
    const <String>[],
  );

  /// Appends [stage] when the diagnostic is active and the stage is inside
  /// the closed vocabulary. Anything else is dropped — this recorder can
  /// never become a channel for free-form data.
  static void record(String stage) {
    if (!isEnabled) return;
    if (!allowedStages.contains(stage) && !_transportStage.hasMatch(stage)) {
      return;
    }
    stages.value = List.unmodifiable([...stages.value, stage]);
  }

  /// Records the transport stage with its numeric item count.
  static void recordTransportSend(int itemCount) =>
      record('transport_send_called items=$itemCount');

  @visibleForTesting
  static void reset() => stages.value = const <String>[];

  static const Map<String, String> _dartDefines = {
    'CRASH_VERIFICATION_TRIGGER_ENABLED': String.fromEnvironment(
      'CRASH_VERIFICATION_TRIGGER_ENABLED',
    ),
    'CRASH_REPORTING_ENABLED': String.fromEnvironment(
      'CRASH_REPORTING_ENABLED',
    ),
    'CRASH_REPORTING_PRODUCTION_APPROVED': String.fromEnvironment(
      'CRASH_REPORTING_PRODUCTION_APPROVED',
    ),
    'CRASH_REPORTING_CONTEXT': String.fromEnvironment(
      'CRASH_REPORTING_CONTEXT',
    ),
    'CRASH_PIPELINE_DIAGNOSTIC': String.fromEnvironment(
      'CRASH_PIPELINE_DIAGNOSTIC',
    ),
  };
}

/// A [Transport] that records and goes nowhere.
///
/// Deliberately contains no HTTP client, socket, native transport or
/// forwarding fallback — there is nothing here that could reach a network,
/// so a diagnostic build cannot leak an envelope even by accident. The
/// SDK's `ClientReportTransport` wrapper delegates to this instance, so any
/// SDK-internal send (including client reports) terminates here too.
class RecordingTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    // Only the item COUNT is read; the items and header are never inspected,
    // retained or serialised.
    CrashPipelineDiagnostic.recordTransportSend(envelope.items.length);
    CrashPipelineDiagnostic.record('transport_send_returned');
    return SentryId.newId();
  }
}
