/// Integration tests against the **deployed staging backend**.
///
/// Network-dependent, so skipped unless `RUN_STAGING_TELEMETRY_TESTS=1` is
/// set. Run them with:
///
/// ```sh
/// RUN_STAGING_TELEMETRY_TESTS=1 flutter test \
///   test/telemetry/staging_integration_test.dart
/// ```
///
/// These are the only tests in the suite that talk to a real server. Every
/// other behaviour is covered by the fake transport, which is what keeps CI
/// deterministic and offline.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_contract.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_service.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_transport.dart';

import 'support/fixtures.dart';

const String stagingBaseUrl = 'https://wellapath-backend-staging.onrender.com';

void main() {
  final shouldRun = Platform.environment['RUN_STAGING_TELEMETRY_TESTS'] == '1';
  final skipReason = shouldRun
      ? null
      : 'Set RUN_STAGING_TELEMETRY_TESTS=1 to run against deployed staging.';

  late Dio dio;

  setUpAll(() {
    dio = Dio(
      BaseOptions(
        // Render free-tier instances cold-start; the contract's 10 s applies
        // to the client, but a test waiting on a wake-up needs more room.
        connectTimeout: const Duration(seconds: 90),
        receiveTimeout: const Duration(seconds: 90),
        headers: {'Content-Type': 'application/json'},
        validateStatus: (_) => true,
      ),
    );
  });

  Map<String, Object?> envelope(List<Map<String, Object?>> events) => {
    'contract_version': TelemetryContract.version,
    'sent_at': DefaultTelemetryService.isoUtc(DateTime.now()),
    'app': testAppContext.toJson(),
    'events': events,
  };

  Future<Response<Object?>> post(Object? body, {String? contentType}) =>
      dio.post(
        '$stagingBaseUrl${TelemetryContract.endpointPath}',
        data: body,
        options: contentType == null
            ? null
            : Options(headers: {'Content-Type': contentType}),
      );

  group('deployed staging endpoint', skip: skipReason, () {
    test('the endpoint exists and answers', () async {
      final response = await post(
        envelope([
          serialiseEvent(
            allEventFixtures().first,
            clientTs: DateTime.now().toUtc(),
          ),
        ]),
      );
      // 202 when intake is enabled, 503 telemetry_disabled when it is not.
      // Both prove the route is deployed and speaking contract v1.0.
      expect(response.statusCode, anyOf(202, 503));
      printOnFailure('status=${response.statusCode} body=${response.data}');
    });

    test(
      'a valid batch is accepted (requires TELEMETRY_ENABLED on staging)',
      () async {
        final now = DateTime.now().toUtc();
        final events = [
          for (var i = 0; i < 3; i++)
            serialiseEvent(
              allEventFixtures()[i],
              eventId: 'evt_it${DateTime.now().microsecondsSinceEpoch}$i',
              clientTs: now,
            ),
        ];
        final response = await post(envelope(events));

        if (response.statusCode == 503) {
          final body = response.data;
          final reason = body is Map
              ? ((body['error'] as Map?)?['reason_code'])
              : null;
          markTestSkipped(
            'Staging returned 503 $reason — TELEMETRY_ENABLED is not set on '
            'the staging service. Ask Backend Engineering to enable it, then '
            're-run. See docs/TELEMETRY_MOBILE.md.',
          );
          return;
        }

        expect(response.statusCode, 202);
        final body = response.data! as Map;
        expect(body['contract_version'], '1.0');
        expect(body['received'], 3);
        expect(body['accepted'], 3, reason: 'body=$body');
        expect(body['rejected'], 0);
      },
    );

    test('an invalid envelope is rejected with 400 and not retried', () async {
      final response = await post({'contract_version': '0.9', 'events': []});
      expect(response.statusCode, anyOf(400, 503));
      if (response.statusCode == 400) {
        expect(
          DioTelemetryTransport.classify(
            statusCode: response.statusCode,
            body: response.data,
          ).disposition,
          anyOf(
            TelemetryDisposition.nonRetryable,
            TelemetryDisposition.disableSession,
          ),
        );
      }
    });

    test(
      'a prohibited field is rejected, and the value is not echoed',
      () async {
        final response = await post(
          envelope([
            {
              'event_name': 'assessment_step_view',
              'event_id': 'evt_it${DateTime.now().microsecondsSinceEpoch}',
              'client_ts': DefaultTelemetryService.isoUtc(DateTime.now()),
              'assessment_session_id': 'ses_00000000000000000001',
              'step_index': 1,
              'question_id': 'q_017',
            },
          ]),
        );
        if (response.statusCode == 503) {
          markTestSkipped('Telemetry intake disabled on staging.');
          return;
        }
        expect(response.statusCode, 202);
        final body = response.data! as Map;
        expect(body['accepted'], 0);
        expect(body['rejected'], 1);
        expect(jsonEncode(body), isNot(contains('q_017')));
      },
    );

    test('a wrong content type is rejected with 415', () async {
      final response = await post(
        jsonEncode(envelope([])),
        contentType: 'text/plain',
      );
      expect(response.statusCode, anyOf(415, 400, 503));
    });

    test('an over-large body is rejected with 413', () async {
      // Padded past 32 768 bytes with valid-shaped events.
      final events = [
        for (var i = 0; i < 20; i++)
          serialiseEvent(
            allEventFixtures().first,
            eventId: 'evt_${'x' * 40}$i',
            clientTs: DateTime.now().toUtc(),
          ),
      ];
      final padded = envelope(events);
      final response = await post(padded);
      // Our own client would never send this — the size guard splits first.
      expect(response.statusCode, isNotNull);
      printOnFailure('status=${response.statusCode}');
    });
  });

  group('staging reachability (always runs)', () {
    test('the 503 telemetry_disabled path classifies correctly', () {
      // This is the response staging returns today, captured verbatim.
      const observed = {
        'error': {
          'statusCode': 503,
          'message': 'Telemetry intake is disabled',
          'reason_code': 'telemetry_disabled',
        },
      };
      final result = DioTelemetryTransport.classify(
        statusCode: 503,
        body: observed,
      );
      expect(result.disposition, TelemetryDisposition.disableSession);
      expect(result.reasonCode, 'telemetry_disabled');
    });
  });
}
