// DIAGNOSTIC ONLY — NEVER MERGE, NEVER SHIP.
//
// Local, no-network instrumentation for the build-213 audit finding that
// events arrive at Sentry without `debug_meta` (every frame
// `unknown_image`). This module runs the REAL production initialisation
// (`CrashMonitoring.init()` → `applyPrivacyOptions`) and then observes each
// stage of event processing with closed-vocabulary, fields-only tokens on
// `debugPrint` (prefix `WPDIAG`). It records:
//
//   integration/processor installation → raw stack-string header lines →
//   parsed buildId/baseAddr → image creation → pre/post sanitiser counts →
//   byte-level serialized-envelope count.
//
// The transport is replaced AFTER init with a recorder that cannot contact
// any host; the DSN in the diagnostic build is a structurally valid
// non-credential placeholder on a non-routable host. No stack contents,
// addresses, paths, DSNs, payload bytes or event values are ever printed
// or stored — only presence booleans, counts and schema field names.
//
// Wrapping note: the SDK's debug-images event processor is moved to the
// end of the processor list by the remove-and-rewrap step. That is
// behaviourally equivalent for this question (no other processor touches
// `debugMeta`, and `beforeSend` still runs after every processor), and it
// is the only way to observe true entry without forking the SDK.

// ignore_for_file: implementation_imports, depend_on_referenced_packages
// ignore_for_file: invalid_use_of_internal_member
// Justification: this DIAGNOSTIC-ONLY file must identify the SDK's
// @internal integration/processor by TYPE (the only obfuscation-safe
// membership test) and read the live hub options where installation
// results are observable. It is never merged, so the internal-API risk
// never reaches production.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry/src/load_dart_debug_images_integration.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'sentry_crash_sink.dart';

/// Compile-time gate. Absent or anything but `true` → this module is dead
/// code and the tree-shaker removes it.
const bool kDebugImageDiagnostics = bool.fromEnvironment(
  'DEBUG_IMAGE_DIAGNOSTICS',
);

void _t(String token) => debugPrint('WPDIAG $token');

abstract final class DebugImageDiagnostics {
  const DebugImageDiagnostics._();

  /// Runs the production init, instruments it, fires ONE synthetic error
  /// through the real `FlutterError.onError` boundary, and reports tokens.
  static Future<void> run() async {
    _t('diag_started');

    // The unmodified production path: gates, applyPrivacyOptions,
    // WellaPathTransport, sanitiser beforeSend, sink swap.
    await CrashMonitoring.init();

    if (!CrashMonitoring.config.enabled) {
      _t('crash_config_disabled');
      return;
    }

    // The live options object is the only place installation results are
    // observable (see file-level justification).
    final options = Sentry.currentHub.options as SentryFlutterOptions;

    // ── Stage 0: what actually got installed ─────────────────────────────
    final integrationInstalled = options.integrations.any(
      (i) => i is LoadDartDebugImagesIntegration,
    );
    _t(integrationInstalled ? 'integration_installed' : 'integration_absent');

    final sdkProcessors = options.eventProcessors
        .whereType<LoadDartDebugImagesIntegrationEventProcessor>()
        .toList();
    _t(sdkProcessors.isNotEmpty ? 'processor_installed' : 'processor_absent');

    _t('runtime_obfuscated_${options.runtimeChecker.isAppObfuscated()}');
    _t('split_debug_info_${options.runtimeChecker.isSplitDebugInfoBuild()}');

    // ── Stage 1: wrap the SDK processor to observe entry and creation ────
    for (final p in sdkProcessors) {
      options.removeEventProcessor(p);
      options.addEventProcessor(_ProcessorProbe(p));
    }

    // ── Stage 2: wrap beforeSend to observe the sanitiser boundary ───────
    final originalBeforeSend = options.beforeSend;
    options.beforeSend = (SentryEvent event, Hint hint) async {
      _t('pre_sanitiser_debug_meta_${event.debugMeta?.images.length ?? 0}');
      final out = await originalBeforeSend?.call(event, hint);
      _t('post_sanitiser_debug_meta_${out?.debugMeta?.images.length ?? 0}');
      return out;
    };

    // ── Stage 3: replace the transport with a local recorder ─────────────
    // Read at send time by SentryClient, so the swap fully disconnects the
    // pipeline from the network before any capture exists.
    options.transport = _RecordingTransport(options);

    // ── Trigger: one synthetic error through the real framework boundary ─
    // Same origin as the 213 event (crash_source=flutter_framework).
    try {
      throw StateError('synthetic diagnostic debug image check');
    } on StateError catch (error, stackTrace) {
      final raw = stackTrace.toString();
      _t(
        "raw_build_id_line_${raw.contains("build_id: '") ? 'present' : 'absent'}",
      );
      _t(
        'raw_isolate_dso_base_line_${raw.contains('isolate_dso_base') ? 'present' : 'absent'}',
      );
      _t(
        'raw_abs_frame_line_${RegExp(r'#\d+ +abs +[0-9a-fA-F]+').hasMatch(raw) ? 'present' : 'absent'}',
      );
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stackTrace),
      );
    }

    // The capture path is fire-and-forget; give it a beat, then finish.
    await Future<void>.delayed(const Duration(seconds: 3));
    _t('diag_complete');
  }
}

/// Wraps the SDK's debug-images processor to observe its inputs and output.
class _ProcessorProbe implements EventProcessor {
  _ProcessorProbe(this._inner);

  final LoadDartDebugImagesIntegrationEventProcessor _inner;

  @override
  Future<SentryEvent?> apply(SentryEvent event, Hint hint) async {
    _t('processor_entered');
    final st = event.stacktrace;
    _t('incoming_stacktrace_${st != null ? 'present' : 'absent'}');
    if (st != null) {
      _t('parsed_build_id_${st.buildId != null ? 'present' : 'absent'}');
      _t('parsed_base_addr_${st.baseAddr != null ? 'present' : 'absent'}');
      _t(
        'native_frame_${st.frames.any((f) => f.platform == 'native') ? 'present' : 'absent'}',
      );
    }
    final out = await _inner.apply(event, hint);
    _t('debug_images_created_${out?.debugMeta?.images.length ?? 0}');
    return out;
  }
}

/// Records the serialized envelope locally. CANNOT contact any host: it
/// performs no I/O beyond in-memory byte inspection, and the bytes are
/// discarded immediately after counting.
class _RecordingTransport implements Transport {
  _RecordingTransport(this._options);

  final SentryOptions _options;

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    _t('transport_send_invoked');
    try {
      final bytes = <int>[];
      await envelope.envelopeStream(_options).forEach(bytes.addAll);
      _inspect(utf8.decode(bytes, allowMalformed: true));
    } on Object {
      _t('envelope_parse_failed');
    }
    return envelope.header.eventId ?? SentryId.newId();
  }

  /// Envelope format: header line, then per item a JSON header line followed
  /// by its payload line. Only the `event` item is inspected, only for
  /// `debug_meta` shape. Counts and schema field names only.
  void _inspect(String text) {
    final lines = const LineSplitter().convert(text);
    for (var i = 1; i < lines.length - 1; i++) {
      Map<String, dynamic>? header;
      try {
        header = jsonDecode(lines[i]) as Map<String, dynamic>;
      } on Object {
        continue;
      }
      if (header['type'] != 'event') continue;
      try {
        final payload = jsonDecode(lines[i + 1]) as Map<String, dynamic>;
        final debugMeta = payload['debug_meta'];
        final images = debugMeta is Map<String, dynamic>
            ? (debugMeta['images'] as List<dynamic>? ?? const [])
            : const <dynamic>[];
        _t('serialized_envelope_debug_meta_${images.length}');
        const approved = {
          'type',
          'image_addr',
          'debug_id',
          'code_id',
          'code_file',
        };
        for (final img in images) {
          final keys = (img as Map<String, dynamic>).keys.toSet();
          if (keys.difference(approved).isEmpty) {
            _t('envelope_image_fields_within_five');
          } else {
            // Schema field names only — never values.
            _t(
              'envelope_image_extra_fields_${(keys.difference(approved).toList()..sort()).join(',')}',
            );
          }
        }
      } on Object {
        _t('envelope_event_payload_unreadable');
      }
      return;
    }
    _t('envelope_event_item_missing');
  }
}
