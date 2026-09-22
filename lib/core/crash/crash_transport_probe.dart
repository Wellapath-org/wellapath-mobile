/// LOCAL-VERIFICATION-ONLY in-app transport probe for the build-212
/// event-loss investigation. Lives only on `build/212-internal-verification`
/// and is NEVER merged into develop.
///
/// One event-free POST of an EMPTY body to the envelope endpoint derived
/// from the compiled DSN, over exactly the stack Sentry 9.27.0's
/// `HttpTransport` uses: `package:http`'s default `Client()` (an `IOClient`
/// over `dart:io HttpClient` — identical to the SDK's
/// `io_client_provider.getClient` result with no proxy configured, which is
/// this app's configuration), the SDK's own `Dsn.postUri` endpoint
/// derivation, and the same three headers `HttpTransportRequestHandler`
/// sends. Deviations, both forced by the empty body: no gzip
/// `Content-Encoding` (there is no payload to compress) and a 15-second
/// timeout the SDK does not set. Neither changes the client or TLS path.
///
/// Structurally unable to create an event: the body is empty, at most one
/// request ever runs (no retry), and no Sentry capture API is touched. The
/// DSN, key, endpoint, headers and response body are never rendered, logged
/// or printed; the only output is a closed-vocabulary stage in
/// [CrashPipelineDiagnostic].
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'crash_pipeline_diagnostic.dart';
import 'sentry_crash_sink.dart';

abstract final class CrashTransportProbe {
  static bool _ran = false;

  /// Test seam: replaces the network send only. Production code never sets
  /// it, so outside tests the probe uses the real SDK-identical stack.
  @visibleForTesting
  static Future<http.Response> Function(http.StreamedRequest request)?
  debugSendOverride;

  @visibleForTesting
  static void debugReset() => _ran = false;

  /// Runs the probe once. A second call, or any call outside the five-define
  /// diagnostic gate, does nothing.
  static Future<void> run() async {
    if (!CrashPipelineDiagnostic.isEnabled) return;
    if (_ran) return; // one request maximum — no retry, ever.
    _ran = true;
    CrashPipelineDiagnostic.record('probe_started');

    http.Client? client;
    try {
      // The compiled DSN, parsed by the SDK's own Dsn class so the endpoint
      // and key derivation are byte-identical to HttpTransport's. The
      // placeholder is reachable ONLY through the test seam — the test
      // binary has no compiled DSN, and a real run never has the override.
      final String dsnString =
          CrashMonitoring.config.dsn.isEmpty && debugSendOverride != null
          ? 'https://testkey@o0.ingest.de.sentry.io/1234567'
          : CrashMonitoring.config.dsn;
      // ignore: invalid_use_of_internal_member
      final Dsn dsn = Dsn.parse(dsnString);
      final SentryFlutterOptions options = SentryFlutterOptions();
      final Map<String, String> headers = {
        // Verbatim from HttpTransportRequestHandler._buildHeaders and
        // _CredentialBuilder (no secret key exists in a public DSN).
        'Content-Type': 'application/x-sentry-envelope',
        'User-Agent': options.sentryClientName,
        'X-Sentry-Auth':
            'Sentry sentry_version=7, '
            'sentry_client=${options.sentryClientName}, '
            // ignore: invalid_use_of_internal_member
            'sentry_key=${dsn.publicKey}',
      };

      // ignore: invalid_use_of_internal_member
      final request = http.StreamedRequest('POST', dsn.postUri);
      request.headers.addAll(headers);
      // Close the sink without writing: the empty body.
      unawaited(request.sink.close());

      final send = debugSendOverride;
      final http.Response response;
      if (send != null) {
        response = await send(request);
      } else {
        client = http.Client();
        response = await client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(const Duration(seconds: 15));
      }

      // Only the status code is classified; the response body and headers
      // are discarded untouched.
      final int code = response.statusCode;
      if (code == 400) {
        CrashPipelineDiagnostic.record('http_400_empty_body');
      } else if (code == 401 || code == 403) {
        CrashPipelineDiagnostic.record('http_401_or_403');
      } else {
        CrashPipelineDiagnostic.record('other_http_status_${code ~/ 100}xx');
      }
    } on TimeoutException {
      CrashPipelineDiagnostic.record('timed_out');
      // The `is` classification below is obfuscation-safe, unlike
      // runtimeType strings; the vocabulary stays closed and fixed.
    } on HandshakeException {
      CrashPipelineDiagnostic.record('tls_failed_handshake');
    } on CertificateException {
      CrashPipelineDiagnostic.record('tls_failed_certificate');
    } on TlsException {
      CrashPipelineDiagnostic.record('tls_failed_tls');
    } on SocketException {
      CrashPipelineDiagnostic.record('connection_failed_socket');
    } on HttpException {
      CrashPipelineDiagnostic.record('connection_failed_http');
    } catch (_) {
      CrashPipelineDiagnostic.record('connection_failed_other');
    } finally {
      client?.close();
    }
  }
}
