/// Transport for telemetry batches, and the contract's response-classification
/// rules.
///
/// Classification is the whole point of this file. Contract §5 is specific
/// about which responses may be retried, and getting it wrong is how a client
/// turns a rejected batch into a retry storm or silently discards a batch it
/// should have kept.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'contract/telemetry_contract.dart';

/// What the client must do next with a batch.
enum TelemetryDisposition {
  /// 2xx. The envelope was valid; remove the batch from the queue.
  ///
  /// Note that a 202 is returned even when every event inside it was rejected
  /// — per-event results are reported in the body, not the status. Those
  /// rejections are counted locally but the batch is still done: re-sending
  /// events the server has already refused would never succeed.
  accepted,

  /// 429, 5xx, network failure or timeout. Retry within the attempt budget,
  /// then keep the batch queued for a later flush.
  retryable,

  /// 400, 413, 415. Permanent. Drop the batch — re-sending it unchanged would
  /// fail identically forever.
  nonRetryable,

  /// 503 `telemetry_disabled`, or 400 `unsupported_contract_version`. Discard
  /// the pending batch and stop sending for the rest of the app session.
  disableSession,
}

class TelemetryTransportResult {
  const TelemetryTransportResult({
    required this.disposition,
    this.statusCode,
    this.reasonCode,
    this.retryAfter,
    this.accepted = 0,
    this.rejected = 0,
    this.duplicates = 0,
    this.rejectionReasons = const [],
  });

  final TelemetryDisposition disposition;
  final int? statusCode;

  /// The server's `reason_code`, which is fixed vocabulary and carries no user
  /// data — the contract guarantees error messages never quote what was sent.
  final String? reasonCode;

  /// Honoured on 429 when present.
  final Duration? retryAfter;

  final int accepted;
  final int rejected;
  final int duplicates;

  /// Per-event rejection reasons from a 202 body, for diagnostics only.
  final List<String> rejectionReasons;
}

/// Seam so the dispatcher can be driven by a fake in unit tests.
abstract class TelemetryTransport {
  Future<TelemetryTransportResult> send(Map<String, Object?> envelope);
}

/// Dio-backed transport.
///
/// Uses its own [Dio] instance rather than `ApiClient.instance`, for two
/// reasons: the telemetry base URL is configured separately from the product
/// API base URL, and this client must never inherit a request/response logging
/// interceptor. Telemetry bodies are non-clinical by construction, but logging
/// them would still put event IDs and session IDs in the device log for no
/// operational benefit.
class DioTelemetryTransport implements TelemetryTransport {
  DioTelemetryTransport({required String endpoint, Dio? dio})
    : _endpoint = endpoint,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: TelemetryContract.requestTimeout,
              sendTimeout: TelemetryContract.requestTimeout,
              receiveTimeout: TelemetryContract.requestTimeout,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              // Classify every status ourselves instead of letting Dio throw
              // on 4xx/5xx — the disposition rules do not map onto its
              // exception model.
              validateStatus: (_) => true,
            ),
          );

  final Dio _dio;
  final String _endpoint;

  @override
  Future<TelemetryTransportResult> send(Map<String, Object?> envelope) async {
    try {
      final response = await _dio.post<Object?>(_endpoint, data: envelope);
      return classify(
        statusCode: response.statusCode,
        body: response.data,
        retryAfterHeader: response.headers.value('retry-after'),
      );
    } on DioException catch (e) {
      // Timeouts and connection failures are the offline case: retryable, and
      // the batch stays queued.
      debugPrint('Telemetry send failed — ${e.type.name}');
      return const TelemetryTransportResult(
        disposition: TelemetryDisposition.retryable,
      );
    } catch (_) {
      debugPrint('Telemetry send failed');
      return const TelemetryTransportResult(
        disposition: TelemetryDisposition.retryable,
      );
    }
  }

  /// Applies contract §5's response rules. Exposed for direct unit testing of
  /// the classification table.
  @visibleForTesting
  static TelemetryTransportResult classify({
    required int? statusCode,
    Object? body,
    String? retryAfterHeader,
  }) {
    final reasonCode = _reasonCode(body);
    final retryAfter = _parseRetryAfter(retryAfterHeader);

    if (statusCode == null) {
      return const TelemetryTransportResult(
        disposition: TelemetryDisposition.retryable,
      );
    }

    // The server disables intake for everyone, or refuses our contract
    // version. Either way, continuing to send this session is pure waste.
    if (statusCode == 503 && reasonCode == 'telemetry_disabled') {
      return TelemetryTransportResult(
        disposition: TelemetryDisposition.disableSession,
        statusCode: statusCode,
        reasonCode: reasonCode,
      );
    }
    if (statusCode == 400 && reasonCode == 'unsupported_contract_version') {
      return TelemetryTransportResult(
        disposition: TelemetryDisposition.disableSession,
        statusCode: statusCode,
        reasonCode: reasonCode,
      );
    }

    if (statusCode >= 200 && statusCode < 300) {
      final map = body is Map ? body : const {};
      return TelemetryTransportResult(
        disposition: TelemetryDisposition.accepted,
        statusCode: statusCode,
        accepted: (map['accepted'] as num?)?.toInt() ?? 0,
        rejected: (map['rejected'] as num?)?.toInt() ?? 0,
        duplicates: (map['duplicates'] as num?)?.toInt() ?? 0,
        rejectionReasons: _perEventReasons(map['results']),
      );
    }

    if (statusCode == 400 || statusCode == 413 || statusCode == 415) {
      return TelemetryTransportResult(
        disposition: TelemetryDisposition.nonRetryable,
        statusCode: statusCode,
        reasonCode: reasonCode,
      );
    }

    if (statusCode == 429 || statusCode >= 500) {
      return TelemetryTransportResult(
        disposition: TelemetryDisposition.retryable,
        statusCode: statusCode,
        reasonCode: reasonCode,
        retryAfter: retryAfter,
      );
    }

    // Any other 4xx is a client-side problem that re-sending will not fix
    // (401/403/404/405 all mean the request was wrong, not unlucky).
    return TelemetryTransportResult(
      disposition: TelemetryDisposition.nonRetryable,
      statusCode: statusCode,
      reasonCode: reasonCode,
    );
  }

  static String? _reasonCode(Object? body) {
    if (body is! Map) return null;
    final error = body['error'];
    if (error is Map && error['reason_code'] is String) {
      return error['reason_code'] as String;
    }
    return body['reason_code'] is String ? body['reason_code'] as String : null;
  }

  static List<String> _perEventReasons(Object? results) {
    if (results is! List) return const [];
    return results
        .whereType<Map>()
        .map((r) => r['reason'])
        .whereType<String>()
        .toList();
  }

  /// `retry-after` in delta-seconds. The HTTP-date form is not parsed: the
  /// backend documents a rate limiter, which emits seconds, and guessing at a
  /// date form we have never seen would be worse than falling back to the
  /// ordinary backoff schedule.
  static Duration? _parseRetryAfter(String? header) {
    if (header == null) return null;
    final seconds = int.tryParse(header.trim());
    if (seconds == null || seconds < 0) return null;
    // Cap it: a cooperative client should not be talked into sleeping for
    // minutes by a header, and the batch is durable anyway.
    return Duration(seconds: seconds.clamp(0, 60));
  }
}
