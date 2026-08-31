/// Bounded startup policy for `/config`.
///
/// The staging backend is Render free-tier and spins down. Measured: the first
/// request after a spin-down took 12.8 s, and a later cold window stalled past
/// 60 s, while a warm instance answers in ~0.5 s. Device testing showed first
/// launch landing on the offline screen because a single 10 s attempt could not
/// outlast the spin-up.
///
/// The fix is not a longer timeout — the request that triggers the spin-up is
/// the one that hangs, and waiting on it just moves the wall. The fix is to
/// retry, because the *next* request meets a warm instance.
///
/// This file pins the policy that makes that safe:
///
///  * every request has a finite cap;
///  * transient failures are retried automatically, more than once;
///  * permanent failures are never retried;
///  * total startup wait is bounded;
///  * nothing unvalidated is ever returned, so nothing unvalidated is cached.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/config/config_service.dart';

/// Fast backoff so the suite does not actually sleep the real schedule.
const List<Duration> _fastBackoff = [
  Duration(milliseconds: 1),
  Duration(milliseconds: 1),
  Duration(milliseconds: 1),
];

Response<dynamic> _response(int status, [Object? data]) => Response<dynamic>(
  requestOptions: RequestOptions(path: '/config'),
  statusCode: status,
  data: data,
);

Response<dynamic> _ok([Map<String, dynamic>? body]) => _response(
  200,
  body ??
      <String, dynamic>{
        'version': '1.0',
        'country': 'ng',
        'artifacts': <String, dynamic>{
          'knowledge_base': <String, dynamic>{
            'version': '2.4',
            'url': 'https://example.invalid/kb.json',
            'hash': 'sha256:abc',
          },
        },
      },
);

DioException _dio(DioExceptionType type, {int? status}) => DioException(
  requestOptions: RequestOptions(path: '/config'),
  type: type,
  response: status == null ? null : _response(status),
);

void main() {
  group('fast success — no retry, no wasted time', () {
    test('a warm backend answers on the first attempt', () async {
      var calls = 0;
      final service = ConfigService(
        backoffDurations: _fastBackoff,
        requestOverride: () async {
          calls++;
          return _ok();
        },
      );

      final outcome = await service.fetchConfigDetailed();

      expect(outcome.succeeded, isTrue);
      expect(outcome.attempts, equals(1));
      expect(calls, equals(1));
      expect(outcome.failureKind, isNull);
      expect(outcome.config!['version'], equals('1.0'));
    });
  });

  group('first timeout then success — the cold-start case', () {
    test('one transient timeout is recovered automatically', () async {
      var calls = 0;
      final service = ConfigService(
        backoffDurations: _fastBackoff,
        requestOverride: () async {
          calls++;
          // Exactly the shape of a Render cold start: the request that
          // triggers the spin-up hangs, the next one lands on a warm instance.
          if (calls == 1) throw _dio(DioExceptionType.receiveTimeout);
          return _ok();
        },
      );

      final outcome = await service.fetchConfigDetailed();

      expect(outcome.succeeded, isTrue);
      expect(outcome.attempts, equals(2));
      expect(
        calls,
        equals(2),
        reason: 'the automatic retry is what fixes the cold start',
      );
    });

    test('recovers when the backend warms up only on the third attempt', () {
      return () async {
        var calls = 0;
        final service = ConfigService(
          backoffDurations: _fastBackoff,
          requestOverride: () async {
            calls++;
            if (calls < 3) throw _dio(DioExceptionType.connectionTimeout);
            return _ok();
          },
        );

        final outcome = await service.fetchConfigDetailed();

        expect(outcome.succeeded, isTrue);
        expect(outcome.attempts, equals(3));
      }();
    });

    test(
      'a per-attempt hang is cut off and the retry still succeeds',
      () async {
        var calls = 0;
        final service = ConfigService(
          backoffDurations: _fastBackoff,
          // Short cap so the test does not wait the real 10s.
          perAttemptTimeout: const Duration(milliseconds: 60),
          requestOverride: () async {
            calls++;
            if (calls == 1) {
              // Hangs well past the per-attempt cap — the request that never
              // returns, which is what actually happened on device.
              await Future<void>.delayed(const Duration(seconds: 5));
            }
            return _ok();
          },
        );

        final outcome = await service.fetchConfigDetailed();

        expect(outcome.succeeded, isTrue);
        expect(outcome.attempts, equals(2));
      },
    );
  });

  group('repeated timeout — fails safely, not forever', () {
    test('exhausts its attempts and reports a transient failure', () async {
      var calls = 0;
      final service = ConfigService(
        backoffDurations: _fastBackoff,
        requestOverride: () async {
          calls++;
          throw _dio(DioExceptionType.receiveTimeout);
        },
      );

      final outcome = await service.fetchConfigDetailed();

      expect(outcome.succeeded, isFalse);
      expect(outcome.config, isNull);
      expect(outcome.failureKind, equals(ConfigFailureKind.transient));
      expect(calls, equals(4), reason: '1 initial + 3 retries');
      expect(outcome.reason, equals('receive timeout'));
    });

    test('total startup wait is capped by the budget', () async {
      final service = ConfigService(
        // A schedule that would run far past the budget if it were unbounded.
        backoffDurations: const [
          Duration(milliseconds: 40),
          Duration(milliseconds: 40),
          Duration(milliseconds: 40),
        ],
        perAttemptTimeout: const Duration(milliseconds: 80),
        totalBudget: const Duration(milliseconds: 150),
        requestOverride: () async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return _ok();
        },
      );

      final stopwatch = Stopwatch()..start();
      final outcome = await service.fetchConfigDetailed();
      stopwatch.stop();

      expect(outcome.succeeded, isFalse);
      expect(
        outcome.failureKind,
        anyOf(ConfigFailureKind.budgetExhausted, ConfigFailureKind.transient),
      );
      // Generous ceiling: the assertion is that the budget bounds the wait at
      // all, not that timer scheduling is precise.
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(milliseconds: 900)),
        reason: 'startup must not run past its budget',
      );
    });

    test(
      'the last attempt is clamped so it cannot overrun the budget',
      () async {
        final service = ConfigService(
          backoffDurations: _fastBackoff,
          perAttemptTimeout: const Duration(seconds: 10),
          totalBudget: const Duration(milliseconds: 120),
          requestOverride: () async {
            await Future<void>.delayed(const Duration(seconds: 30));
            return _ok();
          },
        );

        final stopwatch = Stopwatch()..start();
        await service.fetchConfigDetailed();
        stopwatch.stop();

        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 2)),
          reason:
              'a 10s per-attempt cap must not be allowed to run inside a 120ms '
              'budget — the attempt is clamped to the remaining time',
        );
      },
    );
  });

  group('offline — no connection at all', () {
    test('connection errors are transient and retried', () async {
      var calls = 0;
      final service = ConfigService(
        backoffDurations: _fastBackoff,
        requestOverride: () async {
          calls++;
          throw _dio(DioExceptionType.connectionError);
        },
      );

      final outcome = await service.fetchConfigDetailed();

      expect(outcome.failureKind, equals(ConfigFailureKind.transient));
      expect(calls, equals(4));
      expect(outcome.reason, equals('connection error'));
    });

    test(
      'fetchConfig still returns null so BootController is unchanged',
      () async {
        final service = ConfigService(
          backoffDurations: _fastBackoff,
          requestOverride: () async =>
              throw _dio(DioExceptionType.connectionError),
        );

        expect(await service.fetchConfig(), isNull);
      },
    );
  });

  group('malformed response — permanent, never retried, never cached', () {
    test(
      'a 200 carrying a non-object body is rejected without retry',
      () async {
        var calls = 0;
        final service = ConfigService(
          backoffDurations: _fastBackoff,
          requestOverride: () async {
            calls++;
            return _response(200, '<html>captive portal</html>');
          },
        );

        final outcome = await service.fetchConfigDetailed();

        expect(outcome.succeeded, isFalse);
        expect(outcome.failureKind, equals(ConfigFailureKind.permanent));
        expect(
          calls,
          equals(1),
          reason: 'a malformed body returns the same thing on every retry',
        );
        expect(outcome.reason, contains('malformed'));
      },
    );

    test('a 200 missing the artifacts object is a schema failure', () async {
      var calls = 0;
      final service = ConfigService(
        backoffDurations: _fastBackoff,
        requestOverride: () async {
          calls++;
          return _response(200, <String, dynamic>{'version': '1.0'});
        },
      );

      final outcome = await service.fetchConfigDetailed();

      expect(outcome.failureKind, equals(ConfigFailureKind.permanent));
      expect(outcome.reason, contains('schema'));
      expect(calls, equals(1));
    });

    test('nothing unvalidated is ever returned to the caller', () async {
      // BootController caches whatever fetchConfig returns. If an invalid
      // document could escape validation it would be written to Hive as "last
      // known good config" and poison every later offline boot.
      for (final bad in <Object?>[
        null,
        'not json',
        42,
        <String, dynamic>{'version': '1.0'},
        <String, dynamic>{'artifacts': 'not-a-map'},
      ]) {
        final service = ConfigService(
          backoffDurations: _fastBackoff,
          requestOverride: () async => _response(200, bad),
        );

        expect(
          await service.fetchConfig(),
          isNull,
          reason: 'invalid body $bad must never reach the cache',
        );
      }
    });
  });

  group('permanent HTTP failures are not retried as transient', () {
    for (final status in const [400, 401, 403, 404, 410, 422]) {
      test('$status stops immediately', () async {
        var calls = 0;
        final service = ConfigService(
          backoffDurations: _fastBackoff,
          requestOverride: () async {
            calls++;
            return _response(status);
          },
        );

        final outcome = await service.fetchConfigDetailed();

        expect(outcome.failureKind, equals(ConfigFailureKind.permanent));
        expect(
          calls,
          equals(1),
          reason: '$status will not change on retry; retrying burns budget',
        );
        expect(outcome.reason, equals('http $status'));
      });
    }

    test('a bad TLS certificate is permanent', () async {
      var calls = 0;
      final service = ConfigService(
        backoffDurations: _fastBackoff,
        requestOverride: () async {
          calls++;
          throw _dio(DioExceptionType.badCertificate);
        },
      );

      final outcome = await service.fetchConfigDetailed();

      expect(outcome.failureKind, equals(ConfigFailureKind.permanent));
      expect(calls, equals(1));
    });
  });

  group('transient HTTP failures ARE retried', () {
    for (final status in const [408, 429, 500, 502, 503, 504]) {
      test('$status is retried and can recover', () async {
        var calls = 0;
        final service = ConfigService(
          backoffDurations: _fastBackoff,
          requestOverride: () async {
            calls++;
            if (calls == 1) return _response(status);
            return _ok();
          },
        );

        final outcome = await service.fetchConfigDetailed();

        expect(outcome.succeeded, isTrue, reason: '$status must be retried');
        expect(calls, equals(2));
      });
    }
  });

  group('cancellation when the screen is disposed', () {
    test('a cancelled fetch stops instead of finishing its retries', () async {
      var calls = 0;
      var cancelled = false;

      final service = ConfigService(
        backoffDurations: _fastBackoff,
        requestOverride: () async {
          calls++;
          // The screen goes away during the first attempt.
          cancelled = true;
          throw _dio(DioExceptionType.receiveTimeout);
        },
      );

      final outcome = await service.fetchConfigDetailed(
        isCancelled: () => cancelled,
      );

      expect(outcome.failureKind, equals(ConfigFailureKind.cancelled));
      expect(
        calls,
        equals(1),
        reason: 'no further request may be issued after cancellation',
      );
    });

    test(
      'a fetch cancelled before it starts issues no request at all',
      () async {
        var calls = 0;
        final service = ConfigService(
          backoffDurations: _fastBackoff,
          requestOverride: () async {
            calls++;
            return _ok();
          },
        );

        final outcome = await service.fetchConfigDetailed(
          isCancelled: () => true,
        );

        expect(calls, equals(0));
        expect(outcome.attempts, equals(0));
        expect(outcome.failureKind, equals(ConfigFailureKind.cancelled));
      },
    );
  });

  group('attempt progress is reported for the loading state', () {
    test('every attempt is announced exactly once, in order', () async {
      final announced = <int>[];
      var maxSeen = 0;

      final service = ConfigService(
        backoffDurations: _fastBackoff,
        requestOverride: () async =>
            throw _dio(DioExceptionType.receiveTimeout),
      );

      await service.fetchConfigDetailed(
        onAttempt: (attempt, maxAttempts) {
          announced.add(attempt);
          maxSeen = maxAttempts;
        },
      );

      expect(announced, equals([1, 2, 3, 4]));
      expect(maxSeen, equals(4));
    });

    test('a fast success announces only the first attempt', () async {
      final announced = <int>[];
      final service = ConfigService(
        backoffDurations: _fastBackoff,
        requestOverride: () async => _ok(),
      );

      await service.fetchConfigDetailed(
        onAttempt: (attempt, _) => announced.add(attempt),
      );

      expect(announced, equals([1]));
    });
  });

  group('the policy is bounded by construction', () {
    test('defaults give a finite, short, deterministic schedule', () {
      final service = ConfigService();

      expect(service.perAttemptTimeout, equals(const Duration(seconds: 10)));
      expect(service.totalBudget, equals(const Duration(seconds: 30)));
      expect(service.maxRetries, greaterThanOrEqualTo(1));

      // Deterministic: strictly increasing, no jitter, and short.
      final backoff = service.backoffDurations;
      for (var i = 1; i < backoff.length; i++) {
        expect(backoff[i], greaterThan(backoff[i - 1]));
      }
      for (final d in backoff) {
        expect(d, lessThanOrEqualTo(const Duration(seconds: 3)));
      }
    });

    test('at least one automatic retry happens before giving up', () async {
      var calls = 0;
      final service = ConfigService(
        backoffDurations: _fastBackoff,
        requestOverride: () async {
          calls++;
          throw _dio(DioExceptionType.receiveTimeout);
        },
      );

      await service.fetchConfigDetailed();

      expect(
        calls,
        greaterThanOrEqualTo(2),
        reason: 'a single attempt is what made the cold start fail on device',
      );
    });

    test(
      'elapsed time is reported so a slow startup can be measured',
      () async {
        final service = ConfigService(
          backoffDurations: _fastBackoff,
          requestOverride: () async => _ok(),
        );

        final outcome = await service.fetchConfigDetailed();
        expect(outcome.elapsed, greaterThanOrEqualTo(Duration.zero));
      },
    );
  });
}
