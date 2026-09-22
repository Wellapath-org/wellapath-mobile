/// LOCAL-VERIFICATION-ONLY real-transport outcome instrumentation for the
/// build-212 event-loss investigation. Lives only on
/// `build/212-internal-verification` and is NEVER merged into develop.
///
/// As of this commit the five-define diagnostic build DELIVERS its one
/// confirmed synthetic event through Sentry's REAL `HttpTransport` — the
/// earlier no-network `RecordingTransport` is no longer wired (the class and
/// its tests remain for the record). Two seams observe progress:
///
///  1. **The documented client seam** — `SentryOptions.httpClient` ("If
///     httpClient is provided, it is used instead of the default client").
///     [DiagnosticHttpClient] wraps the SDK's default stack (`Client()`, the
///     exact object `io_client_provider` returns with no proxy) and records
///     when the SDK hands it a request, when the request body stream starts
///     and completes, and the response's status class. `Transport.send`
///     alone hides all of that, which is why this seam exists.
///  2. **A thin `Transport` wrapper** — [DiagnosticTransport] delegates to a
///     real `HttpTransport` and brackets it with entry/return stages plus a
///     bounded diagnostic timeout, so a send that never completes becomes
///     visible instead of hanging silently forever (the SDK sets no timeout
///     of its own).
///
/// **Timeout semantics, documented per the approved requirements:** Dart's
/// `Future.timeout` does NOT cancel the source future — on
/// `transport_timeout` the underlying HTTP request stays in flight and may
/// complete later (a late completion records a trailing
/// `transport_returned`). Nothing is ever retried.
///
/// Nothing is inspected, copied, retained, rendered or logged from the
/// envelope bytes, headers, DSN, URL, exception content or response body:
/// the body stream is piped through untouched (chunks are forwarded, never
/// read), classification uses obfuscation-safe `is`-type checks, and the
/// only output is closed-vocabulary stages in [CrashPipelineDiagnostic].
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
// The real transport is not publicly constructible; these paths are pinned
// to CrashMonitoring.sdkVersion like the sink's other implementation imports.
// ignore: implementation_imports
import 'package:sentry/src/transport/http_transport.dart';
// ignore: implementation_imports
import 'package:sentry/src/transport/rate_limiter.dart';

import 'crash_pipeline_diagnostic.dart';

/// Installs both diagnostic seams. A no-op unless the five-define gate
/// passes, so ordinary, production and four-gate verification builds keep
/// the SDK's untouched transport.
void installTransportOutcomeDiagnostic(SentryFlutterOptions options) {
  if (!CrashPipelineDiagnostic.isEnabled) return;
  options.httpClient = DiagnosticHttpClient(http.Client());
  // ignore: invalid_use_of_internal_member
  options.transport = DiagnosticTransport(
    // ignore: invalid_use_of_internal_member
    HttpTransport(options, RateLimiter(options)),
  );
}

/// Brackets the real transport with entry/return stages and a bounded
/// diagnostic timeout. Delegates exactly once per send — never retries.
class DiagnosticTransport implements Transport {
  DiagnosticTransport(this._inner);

  final Transport _inner;

  /// Bounded OBSERVATION timeout. It does not cancel the underlying request.
  @visibleForTesting
  static Duration debugTimeout = const Duration(seconds: 25);

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    CrashPipelineDiagnostic.record('http_transport_entered');
    final Future<SentryId?> inner = _inner.send(envelope);
    try {
      final SentryId? id = await inner.timeout(debugTimeout);
      CrashPipelineDiagnostic.record('transport_returned');
      return id;
    } on TimeoutException {
      CrashPipelineDiagnostic.record('transport_timeout');
      // The single request may still complete later; record that, retry
      // nothing.
      unawaited(
        inner
            .then((_) => CrashPipelineDiagnostic.record('transport_returned'))
            .catchError((Object _) {}),
      );
      return const SentryId.empty();
    }
  }
}

/// The documented `SentryOptions.httpClient` seam: forwards every request to
/// the SDK-default inner client byte-for-byte, recording only progress
/// stages and the response's status class.
class DiagnosticHttpClient extends http.BaseClient {
  DiagnosticHttpClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    CrashPipelineDiagnostic.record('request_created');

    // Re-wrap the request so the body stream's lifecycle is observable.
    // Method, URL, headers and every body chunk are forwarded UNALTERED;
    // chunks are never read, decoded or retained.
    final forwarded = http.StreamedRequest(request.method, request.url);
    forwarded.headers.addAll(request.headers);
    forwarded.persistentConnection = request.persistentConnection;
    forwarded.followRedirects = request.followRedirects;
    forwarded.maxRedirects = request.maxRedirects;

    bool started = false;
    request.finalize().listen(
      (List<int> chunk) {
        if (!started) {
          started = true;
          CrashPipelineDiagnostic.record('request_body_stream_started');
        }
        forwarded.sink.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        forwarded.sink.addError(error, stackTrace);
      },
      onDone: () {
        CrashPipelineDiagnostic.record('request_body_stream_completed');
        unawaited(forwarded.sink.close());
      },
    );

    final http.StreamedResponse response;
    try {
      response = await _inner.send(forwarded);
    } on HandshakeException {
      CrashPipelineDiagnostic.record('transport_exception_handshake');
      rethrow;
    } on CertificateException {
      CrashPipelineDiagnostic.record('transport_exception_certificate');
      rethrow;
    } on TlsException {
      CrashPipelineDiagnostic.record('transport_exception_tls');
      rethrow;
    } on SocketException {
      CrashPipelineDiagnostic.record('transport_exception_socket');
      rethrow;
    } on HttpException {
      CrashPipelineDiagnostic.record('transport_exception_http');
      rethrow;
    } on http.ClientException {
      CrashPipelineDiagnostic.record('transport_exception_client');
      rethrow;
    } catch (_) {
      CrashPipelineDiagnostic.record('transport_exception_other');
      rethrow;
    }

    // Status class only; the response body is returned unconsumed.
    final int cls = response.statusCode ~/ 100;
    CrashPipelineDiagnostic.record(
      cls == 2
          ? 'response_received_2xx'
          : cls == 4
          ? 'response_received_4xx'
          : cls == 5
          ? 'response_received_5xx'
          : 'response_received_other',
    );
    return response;
  }

  @override
  void close() => _inner.close();
}
