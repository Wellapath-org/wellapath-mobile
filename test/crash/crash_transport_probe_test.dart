/// LOCAL-VERIFICATION-ONLY: the in-app transport probe's gating, single-shot
/// guarantee and closed-vocabulary outcome classification.
///
/// The network itself is replaced through the probe's test seam — no test
/// here performs any I/O. The real probe path is exercised on-device in the
/// diagnostic build only.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wellapath_mobile/core/crash/crash_pipeline_diagnostic.dart';
import 'package:wellapath_mobile/core/crash/crash_transport_probe.dart';

void main() {
  setUp(() {
    CrashPipelineDiagnostic.debugEnabledOverride = true;
    CrashPipelineDiagnostic.reset();
    CrashTransportProbe.debugReset();
  });

  tearDown(() {
    CrashPipelineDiagnostic.debugEnabledOverride = null;
    CrashPipelineDiagnostic.reset();
    CrashTransportProbe.debugReset();
    CrashTransportProbe.debugSendOverride = null;
  });

  Future<void> runWithStatus(int code) {
    CrashTransportProbe.debugSendOverride = (request) async {
      // The empty-body invariant, asserted at the seam: the streamed body
      // must complete with zero bytes.
      final List<int> body = await request.finalize().fold(
        <int>[],
        (List<int> acc, chunk) => acc..addAll(chunk),
      );
      expect(body, isEmpty, reason: 'the probe must post an empty body');
      expect(request.method, 'POST');
      return http.Response('', code);
    };
    return CrashTransportProbe.run();
  }

  test('gated off: records nothing and stays runnable-from-zero', () async {
    CrashPipelineDiagnostic.debugEnabledOverride = false;
    CrashTransportProbe.debugSendOverride = (request) async {
      fail('a gated-off probe must never build or send a request');
    };
    await CrashTransportProbe.run();
    expect(CrashPipelineDiagnostic.stages.value, isEmpty);
  });

  test('a 400 is classified as http_400_empty_body', () async {
    await runWithStatus(400);
    expect(CrashPipelineDiagnostic.stages.value, [
      'probe_started',
      'http_400_empty_body',
    ]);
  });

  test('401 and 403 are classified as http_401_or_403', () async {
    await runWithStatus(401);
    expect(CrashPipelineDiagnostic.stages.value.last, 'http_401_or_403');
    CrashTransportProbe.debugReset();
    CrashPipelineDiagnostic.reset();
    await runWithStatus(403);
    expect(CrashPipelineDiagnostic.stages.value.last, 'http_401_or_403');
  });

  test('other statuses are reduced to their class only', () async {
    await runWithStatus(503);
    expect(CrashPipelineDiagnostic.stages.value.last, 'other_http_status_5xx');
  });

  test(
    'a socket failure is classified by fixed category, not message',
    () async {
      CrashTransportProbe.debugSendOverride = (request) async {
        throw const SocketException('connection refused at 10.0.2.3:53');
      };
      await CrashTransportProbe.run();
      expect(CrashPipelineDiagnostic.stages.value, [
        'probe_started',
        'connection_failed_socket',
      ]);
      // The exception message never reaches the recorder.
      expect(
        CrashPipelineDiagnostic.stages.value.join(),
        isNot(contains('10.0.2.3')),
      );
    },
  );

  test('a TLS handshake failure is classified tls_failed_handshake', () async {
    CrashTransportProbe.debugSendOverride = (request) async {
      throw const HandshakeException('bad cert');
    };
    await CrashTransportProbe.run();
    expect(CrashPipelineDiagnostic.stages.value.last, 'tls_failed_handshake');
  });

  test('exactly one request, ever — a second run does nothing', () async {
    int sends = 0;
    CrashTransportProbe.debugSendOverride = (request) async {
      sends++;
      return http.Response('', 400);
    };
    await CrashTransportProbe.run();
    await CrashTransportProbe.run();
    await CrashTransportProbe.run();
    expect(sends, 1);
    expect(CrashPipelineDiagnostic.stages.value, [
      'probe_started',
      'http_400_empty_body',
    ]);
  });
}
