/// LOCAL-VERIFICATION-ONLY: the real-transport outcome instrumentation.
///
/// Proves: the installer is inert outside the five-define gate; the client
/// wrapper delegates method, url, headers and body byte-for-byte; nothing
/// but closed-vocabulary stages is recorded; the transport wrapper delegates
/// exactly once and never retries, even on its bounded observation timeout.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wellapath_mobile/core/crash/crash_pipeline_diagnostic.dart';
import 'package:wellapath_mobile/core/crash/crash_transport_outcome.dart';

class _CapturingClient extends http.BaseClient {
  http.BaseRequest? request;
  List<int>? body;
  int sends = 0;
  int statusCode = 200;
  Object? toThrow;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sends++;
    this.request = request;
    final List<int> collected = <int>[];
    await request.finalize().forEach(collected.addAll);
    body = collected;
    final Object? error = toThrow;
    if (error != null) throw error;
    return http.StreamedResponse(const Stream.empty(), statusCode);
  }
}

class _NeverCompletingTransport implements Transport {
  int sends = 0;

  @override
  Future<SentryId?> send(SentryEnvelope envelope) {
    sends++;
    return Completer<SentryId?>().future;
  }
}

class _ImmediateTransport implements Transport {
  int sends = 0;

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    sends++;
    return SentryId.newId();
  }
}

SentryEnvelope _envelope() => SentryEnvelope.fromEvent(
  SentryEvent(),
  SdkVersion(name: 't', version: '0'),
);

void main() {
  setUp(() {
    CrashPipelineDiagnostic.debugEnabledOverride = true;
    CrashPipelineDiagnostic.reset();
  });

  tearDown(() {
    CrashPipelineDiagnostic.debugEnabledOverride = null;
    CrashPipelineDiagnostic.reset();
    DiagnosticTransport.debugTimeout = const Duration(seconds: 25);
  });

  group('installer gating', () {
    test('an ordinary build cannot activate the instrumentation', () {
      CrashPipelineDiagnostic.debugEnabledOverride = false;
      final options = SentryFlutterOptions();
      final Transport before = options.transport;
      final http.Client clientBefore = options.httpClient;
      installTransportOutcomeDiagnostic(options);
      expect(identical(options.transport, before), isTrue);
      expect(identical(options.httpClient, clientBefore), isTrue);
    });

    test('the five-define build installs both seams', () {
      final options = SentryFlutterOptions();
      options.dsn = 'https://testkey@o0.ingest.de.sentry.io/1234567';
      installTransportOutcomeDiagnostic(options);
      expect(options.transport, isA<DiagnosticTransport>());
      expect(options.httpClient, isA<DiagnosticHttpClient>());
    });
  });

  group('client wrapper delegation', () {
    test('method, url, headers and body pass through unaltered', () async {
      final inner = _CapturingClient();
      final wrapper = DiagnosticHttpClient(inner);
      final source = http.StreamedRequest(
        'POST',
        Uri.parse('https://example.invalid/api/1/envelope/'),
      );
      source.headers.addAll({
        'Content-Type': 'application/x-sentry-envelope',
        'X-Sentry-Auth': 'Sentry sentry_version=7',
        'Content-Encoding': 'gzip',
      });
      final List<int> payload = List<int>.generate(64, (i) => i);
      source.sink.add(payload);
      unawaited(source.sink.close());

      final response = await wrapper.send(source);

      expect(response.statusCode, 200);
      expect(inner.sends, 1);
      expect(inner.request!.method, 'POST');
      expect(inner.request!.url.toString(), source.url.toString());
      expect(inner.request!.headers, source.headers);
      expect(inner.body, payload);
    });

    test('only closed-vocabulary stages are recorded, never payload', () async {
      final inner = _CapturingClient();
      final wrapper = DiagnosticHttpClient(inner);
      final source = http.StreamedRequest(
        'POST',
        Uri.parse('https://example.invalid/api/1/envelope/'),
      );
      source.sink.add('SECRET-BYTES fever 6.5244'.codeUnits);
      unawaited(source.sink.close());

      await wrapper.send(source);

      final List<String> stages = CrashPipelineDiagnostic.stages.value;
      expect(stages, [
        'request_created',
        'request_body_stream_started',
        'request_body_stream_completed',
        'response_received_2xx',
      ]);
      expect(stages.join(), isNot(contains('SECRET')));
      expect(stages.join(), isNot(contains('6.5244')));
    });

    test('status classes 4xx and 5xx are classified', () async {
      for (final (int code, String stage) in [
        (429, 'response_received_4xx'),
        (503, 'response_received_5xx'),
      ]) {
        CrashPipelineDiagnostic.reset();
        final inner = _CapturingClient()..statusCode = code;
        final source = http.StreamedRequest(
          'POST',
          Uri.parse('https://example.invalid/'),
        );
        unawaited(source.sink.close());
        await DiagnosticHttpClient(inner).send(source);
        expect(CrashPipelineDiagnostic.stages.value.last, stage);
      }
    });

    test('a socket failure is classified by type and rethrown', () async {
      final inner = _CapturingClient()
        ..toThrow = const SocketException('refused at 1.2.3.4');
      final source = http.StreamedRequest(
        'POST',
        Uri.parse('https://example.invalid/'),
      );
      unawaited(source.sink.close());
      await expectLater(
        DiagnosticHttpClient(inner).send(source),
        throwsA(isA<SocketException>()),
      );
      expect(
        CrashPipelineDiagnostic.stages.value.last,
        'transport_exception_socket',
      );
      expect(
        CrashPipelineDiagnostic.stages.value.join(),
        isNot(contains('1.2.3.4')),
      );
    });
  });

  group('transport wrapper', () {
    test('delegates exactly once and brackets with entry/return', () async {
      final inner = _ImmediateTransport();
      final SentryId? id = await DiagnosticTransport(inner).send(_envelope());
      expect(inner.sends, 1);
      expect(id, isNotNull);
      expect(CrashPipelineDiagnostic.stages.value, [
        'http_transport_entered',
        'transport_returned',
      ]);
    });

    test(
      'a hung send times out, is never retried, and returns empty',
      () async {
        DiagnosticTransport.debugTimeout = const Duration(milliseconds: 50);
        final inner = _NeverCompletingTransport();
        final SentryId? id = await DiagnosticTransport(inner).send(_envelope());
        expect(inner.sends, 1, reason: 'no retry after timeout, ever');
        expect(id, const SentryId.empty());
        expect(CrashPipelineDiagnostic.stages.value, [
          'http_transport_entered',
          'transport_timeout',
        ]);
      },
    );
  });
}
