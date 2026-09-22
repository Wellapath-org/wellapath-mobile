/// First-party Sentry transport, replacing the SDK's default transport
/// assembly.
///
/// ### Why a replacement exists
///
/// During the build-212 internal verification (PROGRESS.md, 2026-09-22) two
/// controlled synthetic events were lost in obfuscated release builds using
/// the SDK's default transport assembly, with zero server-side outcomes and
/// zero client-side signals — the SDK swallows every transport failure. A
/// staged diagnostic eliminated every other pipeline stage: the config
/// gates, error boundary, sanitiser and SDK client all worked, the envelope
/// endpoint authenticated an in-app empty-body probe (HTTP 400), and an
/// explicitly constructed transport delivered on the first attempt. The
/// default assembly's failure was bracketed but never reproduced under
/// instrumentation, so per the founder decision it is REPLACED by this
/// reviewable implementation rather than trusted.
///
/// ### What this does
///
/// Exactly what the SDK's `HttpTransport` does, on public API only: derive
/// the envelope endpoint and auth header from the DSN, serialise the
/// envelope with the SDK's own `envelopeStream`, gzip it, POST it with
/// `package:http`'s default client (the same stack the SDK uses), and map
/// the response to the SDK's contract (event id on success, `SentryId.empty`
/// on anything else). Differences, all deliberate:
///
///  * a **bounded send timeout** — the SDK sets none, and an unbounded hang
///    is indistinguishable from silent loss. Dart's `Future.timeout` does
///    not cancel the underlying request; on timeout the single request may
///    still complete server-side. Nothing is ever retried either way.
///  * **no rate-limit bookkeeping** — this app sends rare, single crash
///    events; a 429 simply resolves to `SentryId.empty` with no retry, so
///    there is nothing to amplify.
///  * **no logging** of the DSN, endpoint, headers, payload or response.
///
/// The `SentryClient` factory wraps whatever `options.transport` holds in
/// its `ClientReportTransport` decorator, so SDK client reports still attach
/// to outgoing envelopes and travel through this transport unchanged.
library;

import 'dart:async';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

class WellaPathTransport implements Transport {
  WellaPathTransport(this._options, {http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final SentryOptions _options;
  final http.Client Function() _clientFactory;
  http.Client? _client;

  /// Bounded send timeout. Observation-bounded only: it does not cancel the
  /// in-flight request.
  @visibleForTesting
  static Duration sendTimeout = const Duration(seconds: 15);

  /// Clock for the envelope's sentAt stamp. The SDK's own clock option is
  /// internal API, so the transport owns its clock; tests may override it.
  @visibleForTesting
  static DateTime Function() now = () => DateTime.now().toUtc();

  /// The envelope ingest endpoint for [dsn], mirroring the SDK's own
  /// derivation: `scheme://host[:port]/[prefix/]api/<projectId>/envelope/`.
  /// Any path segments before the project id (self-hosted prefixes) are
  /// preserved.
  static Uri envelopeUriFor(String dsn) {
    final Uri uri = Uri.parse(dsn);
    final List<String> segments = uri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    final String projectId = segments.removeLast();
    final String prefix = segments.isEmpty ? '' : '${segments.join('/')}/';
    final String port =
        uri.hasPort &&
            ((uri.scheme == 'http' && uri.port != 80) ||
                (uri.scheme == 'https' && uri.port != 443))
        ? ':${uri.port}'
        : '';
    return Uri.parse(
      '${uri.scheme}://${uri.host}$port/${prefix}api/$projectId/envelope/',
    );
  }

  /// The `X-Sentry-Auth` header, byte-identical to the SDK's builder for a
  /// public (secret-less) DSN.
  static String authHeaderFor(String dsn, String sdkIdentifier) {
    final String publicKey = Uri.parse(dsn).userInfo;
    return 'Sentry sentry_version=7, sentry_client=$sdkIdentifier, '
        'sentry_key=$publicKey';
  }

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    try {
      envelope.header.sentAt = now();

      final List<int> body = <int>[];
      await envelope.envelopeStream(_options).forEach(body.addAll);

      final String dsn = _options.dsn ?? '';
      final request = http.Request('POST', envelopeUriFor(dsn));
      request.headers.addAll({
        'Content-Type': 'application/x-sentry-envelope',
        'Content-Encoding': 'gzip',
        'User-Agent': _options.sentryClientName,
        'X-Sentry-Auth': authHeaderFor(dsn, _options.sentryClientName),
      });
      request.bodyBytes = gzip.encode(body);

      final client = _client ??= _clientFactory();
      final http.StreamedResponse response = await client
          .send(request)
          .timeout(sendTimeout);
      // Drain without retaining: the body is not read into a value.
      unawaited(
        response.stream.listen((_) {}).asFuture<void>().catchError((_) {}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return envelope.header.eventId ?? SentryId.newId();
      }
      return const SentryId.empty();
    } catch (_) {
      // A transport failure must never propagate into the app, and nothing
      // sensitive may be logged about it. One attempt, no retry.
      return const SentryId.empty();
    }
  }
}
