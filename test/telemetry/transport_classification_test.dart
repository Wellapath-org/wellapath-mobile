/// The response-classification table from contract §5, asserted directly.
///
/// Getting this wrong is how a client turns a permanently-rejected batch into
/// a retry storm, or silently discards a batch it should have kept.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_transport.dart';

void main() {
  TelemetryTransportResult classify(
    int? status, {
    Object? body,
    String? retryAfter,
  }) => DioTelemetryTransport.classify(
    statusCode: status,
    body: body,
    retryAfterHeader: retryAfter,
  );

  Map<String, Object?> errorBody(int status, String reason) => {
    'error': {
      'statusCode': status,
      'message': 'Generic message',
      'reason_code': reason,
    },
  };

  group('accepted', () {
    test('202 is accepted', () {
      expect(
        classify(202, body: {'accepted': 3, 'rejected': 0}).disposition,
        TelemetryDisposition.accepted,
      );
    });

    test('202 with every event rejected is still accepted', () {
      // The status describes the envelope, not the events. Re-sending events
      // the server has already refused would never succeed.
      final result = classify(
        202,
        body: {
          'accepted': 0,
          'rejected': 2,
          'results': [
            {'index': 0, 'status': 'rejected', 'reason': 'unknown_event'},
            {'index': 1, 'status': 'rejected', 'reason': 'prohibited_field'},
          ],
        },
      );
      expect(result.disposition, TelemetryDisposition.accepted);
      expect(result.rejected, 2);
      expect(result.rejectionReasons, ['unknown_event', 'prohibited_field']);
    });

    test('200 is accepted', () {
      expect(classify(200).disposition, TelemetryDisposition.accepted);
    });

    test('duplicate counts are read back', () {
      final result = classify(202, body: {'accepted': 1, 'duplicates': 2});
      expect(result.duplicates, 2);
    });
  });

  group('never retried', () {
    for (final status in [400, 413, 415]) {
      test('$status is non-retryable', () {
        expect(
          classify(
            status,
            body: errorBody(status, 'invalid_envelope'),
          ).disposition,
          TelemetryDisposition.nonRetryable,
        );
      });
    }

    test('an unexpected 4xx is also non-retryable', () {
      // 401/403/404/405 mean the request was wrong, not unlucky.
      for (final status in [401, 403, 404, 405, 422]) {
        expect(
          classify(status).disposition,
          TelemetryDisposition.nonRetryable,
          reason: '$status should not be retried',
        );
      }
    });
  });

  group('retried', () {
    test('429 is retryable', () {
      expect(
        classify(429, body: errorBody(429, 'rate_limited')).disposition,
        TelemetryDisposition.retryable,
      );
    });

    for (final status in [500, 502, 503, 504, 599]) {
      test('$status is retryable', () {
        expect(
          classify(status).disposition,
          TelemetryDisposition.retryable,
          reason: '$status should be retried',
        );
      });
    }

    test('a missing status code is retryable', () {
      // This is the network-failure and timeout case.
      expect(classify(null).disposition, TelemetryDisposition.retryable);
    });
  });

  group('session disablement', () {
    test('503 telemetry_disabled disables the session', () {
      final result = classify(503, body: errorBody(503, 'telemetry_disabled'));
      expect(result.disposition, TelemetryDisposition.disableSession);
      expect(result.reasonCode, 'telemetry_disabled');
    });

    test('a 503 without that reason code is merely retryable', () {
      expect(
        classify(503, body: errorBody(503, 'something_else')).disposition,
        TelemetryDisposition.retryable,
      );
      expect(classify(503).disposition, TelemetryDisposition.retryable);
    });

    test('400 unsupported_contract_version disables the session', () {
      // Contract §5: stop sending rather than downgrade the payload.
      expect(
        classify(
          400,
          body: errorBody(400, 'unsupported_contract_version'),
        ).disposition,
        TelemetryDisposition.disableSession,
      );
    });

    test('a 400 with any other reason is an ordinary permanent failure', () {
      expect(
        classify(400, body: errorBody(400, 'invalid_envelope')).disposition,
        TelemetryDisposition.nonRetryable,
      );
    });
  });

  group('retry-after', () {
    test('delta-seconds are honoured', () {
      expect(
        classify(429, retryAfter: '15').retryAfter,
        const Duration(seconds: 15),
      );
    });

    test('a value is capped at 60 seconds', () {
      expect(
        classify(429, retryAfter: '3600').retryAfter,
        const Duration(seconds: 60),
      );
    });

    test('an HTTP-date form is ignored rather than guessed at', () {
      expect(
        classify(429, retryAfter: 'Wed, 21 Oct 2026 07:28:00 GMT').retryAfter,
        isNull,
      );
    });

    test('a negative or malformed value is ignored', () {
      expect(classify(429, retryAfter: '-5').retryAfter, isNull);
      expect(classify(429, retryAfter: 'soon').retryAfter, isNull);
    });
  });

  group('reason-code extraction', () {
    test('reads the nested error envelope', () {
      expect(
        classify(400, body: errorBody(400, 'batch_too_large')).reasonCode,
        'batch_too_large',
      );
    });

    test('reads a top-level reason_code', () {
      expect(
        classify(400, body: {'reason_code': 'empty_batch'}).reasonCode,
        'empty_batch',
      );
    });

    test('a non-map body does not throw', () {
      expect(classify(400, body: 'plain text').reasonCode, isNull);
      expect(classify(400, body: null).reasonCode, isNull);
      expect(classify(400, body: <int>[1, 2]).reasonCode, isNull);
    });
  });
}
