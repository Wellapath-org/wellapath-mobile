import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/config/config_service.dart';

void main() {
  Response<dynamic> okResponse(Map<String, dynamic> data) => Response(
    requestOptions: RequestOptions(path: '/config'),
    statusCode: 200,
    data: data,
  );

  group('ConfigService retry behaviour', () {
    test(
      'fetchConfig returns null after exhausting all retries when every attempt fails',
      () async {
        var callCount = 0;
        final service = ConfigService(
          maxRetries: 3,
          backoffDurations: const [
            Duration(milliseconds: 1),
            Duration(milliseconds: 1),
            Duration(milliseconds: 1),
          ],
          requestOverride: () async {
            callCount++;
            throw Exception('simulated network failure');
          },
        );

        final result = await service.fetchConfig();

        expect(result, isNull);
        // maxRetries=3 means 4 total attempts (1 initial + 3 retries).
        expect(callCount, equals(4));
      },
    );

    test('fetchConfig succeeds on the 3rd attempt', () async {
      var callCount = 0;
      final service = ConfigService(
        backoffDurations: const [
          Duration(milliseconds: 1),
          Duration(milliseconds: 1),
          Duration(milliseconds: 1),
        ],
        requestOverride: () async {
          callCount++;
          if (callCount < 3) {
            throw Exception('simulated transient failure');
          }
          return okResponse({'version': '1.0', 'artifacts': {}});
        },
      );

      final result = await service.fetchConfig();

      expect(callCount, equals(3));
      expect(result, isNotNull);
      expect(result!['version'], equals('1.0'));
    });

    test(
      'a non-200 response is treated as a failure and retried, not returned as-is',
      () async {
        var callCount = 0;
        final service = ConfigService(
          backoffDurations: const [
            Duration(milliseconds: 1),
            Duration(milliseconds: 1),
            Duration(milliseconds: 1),
          ],
          requestOverride: () async {
            callCount++;
            if (callCount < 2) {
              return Response(
                requestOptions: RequestOptions(path: '/config'),
                statusCode: 503,
              );
            }
            return okResponse({'version': '2.0', 'artifacts': {}});
          },
        );

        final result = await service.fetchConfig();

        expect(callCount, equals(2));
        expect(result!['version'], equals('2.0'));
      },
    );

    test(
      'retries respect the configured backoff durations (1s/2s/3s by default)',
      () async {
        // Defaults changed from 2s/4s/8s in the cold-start work. The old
        // schedule spent 14s in backoff on top of four 10s attempts, so a
        // failing first launch sat on a static splash for ~54s. The schedule
        // is now short and deterministic, and a total budget caps startup.
        final service = ConfigService();
        expect(
          service.backoffDurations,
          equals(const [
            Duration(seconds: 1),
            Duration(seconds: 2),
            Duration(seconds: 3),
          ]),
        );
        expect(service.maxRetries, equals(3));
        expect(service.perAttemptTimeout, equals(const Duration(seconds: 10)));
        expect(service.totalBudget, equals(const Duration(seconds: 30)));

        // Behavioural check with fast, overridden durations: each retry
        // must actually wait for its configured backoff before the next
        // attempt fires.
        final recordedGaps = <Duration>[];
        DateTime? lastAttemptAt;
        final timedService = ConfigService(
          backoffDurations: const [
            Duration(milliseconds: 30),
            Duration(milliseconds: 60),
            Duration(milliseconds: 90),
          ],
          requestOverride: () async {
            final now = DateTime.now();
            if (lastAttemptAt != null) {
              recordedGaps.add(now.difference(lastAttemptAt!));
            }
            lastAttemptAt = now;
            throw Exception('always fails — measuring backoff gaps only');
          },
        );

        await timedService.fetchConfig();

        expect(recordedGaps.length, equals(3));
        expect(recordedGaps[0].inMilliseconds, greaterThanOrEqualTo(25));
        expect(recordedGaps[1].inMilliseconds, greaterThanOrEqualTo(55));
        expect(recordedGaps[2].inMilliseconds, greaterThanOrEqualTo(85));
      },
    );
  });
}
