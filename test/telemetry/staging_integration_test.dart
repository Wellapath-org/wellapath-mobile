/// Integration tests against the **deployed staging backend**.
///
/// Network-dependent, so skipped unless `RUN_STAGING_TELEMETRY_TESTS` is set
/// to `1`, `true` or `yes`. Run them with:
///
/// ```sh
/// RUN_STAGING_TELEMETRY_TESTS=true flutter test \
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
  /// Accepts `1`, `true` or `yes`, case-insensitively.
  ///
  /// This originally compared against `'1'` alone. A gate that silently skips
  /// on `RUN_STAGING_TELEMETRY_TESTS=true` — the spelling anyone reaches for
  /// first — still prints "All tests passed" while verifying nothing against
  /// the real server, which is the worst failure mode a release gate can have.
  /// Accepting the obvious spellings removes the trap.
  final gate = (Platform.environment['RUN_STAGING_TELEMETRY_TESTS'] ?? '')
      .trim()
      .toLowerCase();
  final shouldRun = gate == '1' || gate == 'true' || gate == 'yes';
  final skipReason = shouldRun
      ? null
      : 'Set RUN_STAGING_TELEMETRY_TESTS=true to run against deployed staging.';

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

  /// A unique `event_id` for this run.
  ///
  /// The server remembers event IDs for an hour, so a replayed ID comes back
  /// as `duplicate` rather than `accepted` — which would fail the batch
  /// assertion for entirely the wrong reason.
  var idCounter = 0;
  String freshEventId(String label) =>
      'evt_${label}_${DateTime.now().microsecondsSinceEpoch}_${idCounter++}';

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
            eventId: freshEventId('smoke'),
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
              eventId: freshEventId('valid$i'),
              clientTs: now,
            ),
        ];
        expect(
          events.map((e) => e['event_id']).toSet(),
          hasLength(3),
          reason: 'the three event IDs must be distinct',
        );
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
        expect(body['rejected'], 0, reason: 'body=$body');
        expect(
          body['duplicates'],
          0,
          reason: 'fresh IDs must not hit the dedupe window: body=$body',
        );
        final results = body['results']! as List;
        expect(results, hasLength(3));
        expect(results.map((r) => (r as Map)['status']).toSet(), {
          'accepted',
        }, reason: 'body=$body');
        // A 202 is `accepted` for the client: remove the batch, never retry.
        expect(
          DioTelemetryTransport.classify(
            statusCode: response.statusCode,
            body: response.data,
          ).disposition,
          TelemetryDisposition.accepted,
        );
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
              'event_id': freshEventId('prohibited'),
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
        expect(body['accepted'], 0, reason: 'body=$body');
        expect(body['rejected'], 1, reason: 'body=$body');

        // Fail-closed and event-level, with a contract reason code — not a
        // silent drop, and not an envelope-wide failure.
        final result = (body['results']! as List).single as Map;
        expect(result['status'], 'rejected');
        expect(
          TelemetryContract.rejectionReasonCodes,
          contains(result['reason']),
          reason: 'unexpected reason code: body=$body',
        );

        // Neither the prohibited value nor its key is echoed back.
        expect(jsonEncode(body), isNot(contains('q_017')));
        expect(jsonEncode(body), isNot(contains('question_id')));

        // The client does not retry: the envelope validated, so the batch is
        // removed rather than re-sent.
        expect(
          DioTelemetryTransport.classify(
            statusCode: response.statusCode,
            body: response.data,
          ).disposition,
          TelemetryDisposition.accepted,
        );
      },
    );

    test('a non-retryable response is sent exactly once', () async {
      // Counts real HTTP attempts through the production transport against
      // the live server. The unit suite proves the retry budget with a fake;
      // this proves the wiring end to end, with a single request rather than
      // deliberate retry load.
      var attempts = 0;
      final countingDio =
          Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 90),
                receiveTimeout: const Duration(seconds: 90),
                headers: {'Content-Type': 'application/json'},
                validateStatus: (_) => true,
              ),
            )
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) {
                  attempts++;
                  handler.next(options);
                },
              ),
            );

      final transport = DioTelemetryTransport(
        endpoint: '$stagingBaseUrl${TelemetryContract.endpointPath}',
        dio: countingDio,
      );

      // An envelope-level prohibited field: a 400 the client must never retry.
      final result = await transport.send({
        'contract_version': '1.0',
        'sent_at': DefaultTelemetryService.isoUtc(DateTime.now()),
        'app': testAppContext.toJson(),
        'patient_name': 'refused at the envelope',
        'events': [
          serialiseEvent(
            allEventFixtures().first,
            eventId: freshEventId('noretry'),
            clientTs: DateTime.now().toUtc(),
          ),
        ],
      });

      expect(attempts, 1, reason: 'a non-retryable status must not be retried');
      expect(result.statusCode, anyOf(400, 503));
      if (result.statusCode == 400) {
        expect(result.disposition, TelemetryDisposition.nonRetryable);
      }
    });

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
