/// The first-party crash transport: endpoint/auth derivation, delivery
/// contract, failure mapping, single-attempt guarantee and wire fidelity.
///
/// No test here performs network I/O — the client is injected. The transport
/// exists because the SDK's default assembly lost two controlled events in
/// obfuscated release builds (PROGRESS.md, 2026-09-22); these tests pin the
/// replacement's behaviour.
library;

import 'dart:async';
import 'dart:io' show SocketException, gzip;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wellapath_mobile/core/crash/sentry_crash_sink.dart';
import 'package:wellapath_mobile/core/crash/wellapath_transport.dart';

const String kTestDsn = 'https://testkey@o0.ingest.de.sentry.io/1234567';

class _FakeClient extends http.BaseClient {
  int sends = 0;
  int statusCode = 200;
  Object? toThrow;
  bool neverComplete = false;
  http.BaseRequest? request;
  List<int>? body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    this.request = request;
    final List<int> collected = <int>[];
    await request.finalize().forEach(collected.addAll);
    body = collected;
    if (neverComplete) return Completer<http.StreamedResponse>().future;
    final Object? error = toThrow;
    if (error != null) throw error;
    return http.StreamedResponse(const Stream.empty(), statusCode);
  }
}

void main() {
  tearDown(() {
    WellaPathTransport.sendTimeout = const Duration(seconds: 15);
    WellaPathTransport.now = () => DateTime.now().toUtc();
  });

  SentryOptions options() => SentryOptions(dsn: kTestDsn);

  SentryEnvelope envelope() => SentryEnvelope.fromEvent(
    SentryEvent(eventId: SentryId.newId()),
    SdkVersion(name: 'test', version: '0'),
  );

  group('endpoint and auth derivation', () {
    test('a standard saas dsn maps to its envelope endpoint', () {
      expect(
        WellaPathTransport.envelopeUriFor(kTestDsn).toString(),
        'https://o0.ingest.de.sentry.io/api/1234567/envelope/',
      );
    });

    test('a self-hosted path prefix is preserved', () {
      expect(
        WellaPathTransport.envelopeUriFor(
          'https://key@sentry.example.com/prefix/42',
        ).toString(),
        'https://sentry.example.com/prefix/api/42/envelope/',
      );
    });

    test('a non-default port is preserved', () {
      expect(
        WellaPathTransport.envelopeUriFor(
          'https://key@sentry.example.com:8443/42',
        ).toString(),
        'https://sentry.example.com:8443/api/42/envelope/',
      );
    });

    test('the auth header carries version, client and key', () {
      expect(
        WellaPathTransport.authHeaderFor(kTestDsn, 'client/1.0'),
        'Sentry sentry_version=7, sentry_client=client/1.0, '
        'sentry_key=testkey',
      );
    });
  });

  group('delivery contract', () {
    test('a 2xx resolves to the envelope event id', () async {
      final client = _FakeClient();
      final transport = WellaPathTransport(
        options(),
        clientFactory: () => client,
      );
      final env = envelope();
      final SentryId? id = await transport.send(env);
      expect(id, env.header.eventId);
      expect(client.sends, 1);
    });

    test('the request carries the sdk-shaped headers and endpoint', () async {
      final client = _FakeClient();
      final opts = options();
      await WellaPathTransport(
        opts,
        clientFactory: () => client,
      ).send(envelope());
      final request = client.request!;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://o0.ingest.de.sentry.io/api/1234567/envelope/',
      );
      expect(request.headers['Content-Type'], 'application/x-sentry-envelope');
      expect(request.headers['Content-Encoding'], 'gzip');
      expect(request.headers['User-Agent'], opts.sentryClientName);
      expect(request.headers['X-Sentry-Auth'], contains('sentry_key=testkey'));
    });

    test('the gzip body decodes to exactly the sdk envelope bytes', () async {
      final client = _FakeClient();
      final opts = options();
      final env = envelope();
      await WellaPathTransport(opts, clientFactory: () => client).send(env);

      // Serialise the same envelope the same way for the expectation. sentAt
      // was stamped by the transport, so the streams now agree.
      final List<int> expected = <int>[];
      await env.envelopeStream(opts).forEach(expected.addAll);
      expect(gzip.decode(client.body!), expected);
    });

    test('sentAt is stamped from the transport clock', () async {
      final fixed = DateTime.utc(2026, 9, 22, 12);
      WellaPathTransport.now = () => fixed;
      final env = envelope();
      await WellaPathTransport(
        options(),
        clientFactory: () => _FakeClient(),
      ).send(env);
      expect(env.header.sentAt, fixed);
    });
  });

  group('failure mapping — one attempt, never a retry, never a throw', () {
    for (final int code in [400, 401, 429, 500, 503]) {
      test(
        'a $code resolves to SentryId.empty after exactly one send',
        () async {
          final client = _FakeClient()..statusCode = code;
          final SentryId? id = await WellaPathTransport(
            options(),
            clientFactory: () => client,
          ).send(envelope());
          expect(id, const SentryId.empty());
          expect(client.sends, 1);
        },
      );
    }

    test('a network exception resolves to empty without propagating', () async {
      final client = _FakeClient()..toThrow = const SocketException('refused');
      final SentryId? id = await WellaPathTransport(
        options(),
        clientFactory: () => client,
      ).send(envelope());
      expect(id, const SentryId.empty());
      expect(client.sends, 1);
    });

    test('a hung request times out to empty with exactly one send', () async {
      WellaPathTransport.sendTimeout = const Duration(milliseconds: 50);
      final client = _FakeClient()..neverComplete = true;
      final SentryId? id = await WellaPathTransport(
        options(),
        clientFactory: () => client,
      ).send(envelope());
      expect(id, const SentryId.empty());
      expect(client.sends, 1, reason: 'no retry after timeout, ever');
    });

    test(
      'a malformed dsn resolves to empty without touching the network',
      () async {
        final client = _FakeClient();
        final SentryId? id = await WellaPathTransport(
          SentryOptions(dsn: 'not a dsn'),
          clientFactory: () => client,
        ).send(envelope());
        expect(id, const SentryId.empty());
        expect(client.sends, 0);
      },
    );
  });

  group('wiring', () {
    test('applyPrivacyOptions installs the first-party transport', () {
      final opts = SentryFlutterOptions();
      // ignore: invalid_use_of_visible_for_testing_member
      CrashMonitoring.applyPrivacyOptions(opts);
      expect(opts.transport, isA<WellaPathTransport>());
    });
  });
}
