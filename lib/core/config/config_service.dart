import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../network/api_client.dart';

/// Why a `/config` attempt failed, and therefore whether retrying it can
/// possibly help.
///
/// The distinction is the whole point of the startup policy. A cold backend
/// times out on the first request and answers the second in under a second —
/// retrying is exactly right. A 404, a 400 or a response that is not the
/// config shape will return the same answer every time; retrying it burns the
/// startup budget that a genuinely transient failure needs.
enum ConfigFailureKind {
  /// Timeout, connection loss, 408, 429 or 5xx. Retrying may succeed.
  transient,

  /// A 4xx other than 408/429, a bad certificate, or a body that is not a
  /// usable config document. Retrying cannot succeed.
  permanent,

  /// The caller went away (screen disposed) — not a failure of the backend.
  cancelled,

  /// The total startup budget ran out before a usable answer arrived.
  budgetExhausted,
}

/// What one `fetchConfig` call did, for the UI and for reporting.
///
/// Carries no response body and no error detail beyond a fixed-vocabulary
/// reason: this object is logged, and a `/config` body or exception message is
/// not a safe thing to put in a log line.
@immutable
class ConfigFetchOutcome {
  const ConfigFetchOutcome({
    required this.config,
    required this.attempts,
    required this.elapsed,
    this.failureKind,
    this.reason,
  });

  /// The validated config document, or null if no attempt produced one.
  final Map<String, dynamic>? config;

  /// How many requests were actually issued.
  final int attempts;

  /// Wall-clock time spent, including backoff.
  final Duration elapsed;

  /// Null when [config] is non-null.
  final ConfigFailureKind? failureKind;

  /// Fixed-vocabulary description. Never contains a body or a URL.
  final String? reason;

  bool get succeeded => config != null;
}

/// Internal marker so a permanent failure can stop the loop from inside the
/// attempt without being confused with a transport error.
class _PermanentConfigFailure implements Exception {
  const _PermanentConfigFailure(this.reason);
  final String reason;
}

class ConfigService {
  ConfigService({
    Dio? dio,
    this.maxRetries = 3,
    List<Duration>? backoffDurations,
    this.perAttemptTimeout = const Duration(seconds: 10),
    this.totalBudget = const Duration(seconds: 30),
    Future<Response<dynamic>> Function()? requestOverride,
  }) : _dio = dio,
       backoffDurations =
           backoffDurations ??
           const [
             // Short and deterministic — no jitter, so a failing startup takes
             // the same time every run and can be reasoned about and tested.
             // The previous 2s/4s/8s schedule spent 14s waiting on top of four
             // 10s attempts, so a first launch could sit on a static splash for
             // ~54s. The budget below now caps the whole thing at 30s.
             Duration(seconds: 1),
             Duration(seconds: 2),
             Duration(seconds: 3),
           ],
       _requestOverride = requestOverride;

  // Nullable, resolved to the real ApiClient.instance lazily inside
  // _requestConfig — ApiClient.instance reads dotenv, which isn't loaded in
  // a plain unit test, and tests always supply requestOverride instead of
  // ever needing a real Dio.
  final Dio? _dio;
  final int maxRetries;
  final List<Duration> backoffDurations;

  /// Hard wall-clock cap on a single request. Finite by design — the fix for a
  /// slow cold start is another attempt against a now-warm instance, not a
  /// longer wait on the attempt that triggered the spin-up.
  final Duration perAttemptTimeout;

  /// Hard cap on the whole startup fetch, backoff included.
  ///
  /// Without this the worst case is the sum of every attempt and every
  /// backoff, which grows silently whenever either is tuned. With it, startup
  /// has a number a person can hold: the user waits at most this long before
  /// being shown something they can act on.
  final Duration totalBudget;

  final Future<Response<dynamic>> Function()? _requestOverride;

  /// Fetches `/config` under a bounded retry policy.
  ///
  /// Retries only failures that could plausibly succeed on a second attempt.
  /// Stops immediately on a permanent failure, when [isCancelled] returns true,
  /// or when [totalBudget] is spent.
  ///
  /// [onAttempt] is called with the 1-based attempt number before each request
  /// so the splash can show honest progress rather than a frozen logo.
  Future<ConfigFetchOutcome> fetchConfigDetailed({
    void Function(int attempt, int maxAttempts)? onAttempt,
    bool Function()? isCancelled,
  }) async {
    final stopwatch = Stopwatch()..start();
    final maxAttempts = maxRetries + 1;
    var attempts = 0;
    var lastReason = 'unknown';

    for (var index = 0; index < maxAttempts; index++) {
      if (isCancelled?.call() ?? false) {
        return ConfigFetchOutcome(
          config: null,
          attempts: attempts,
          elapsed: stopwatch.elapsed,
          failureKind: ConfigFailureKind.cancelled,
          reason: 'cancelled by caller',
        );
      }

      final remaining = totalBudget - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        return ConfigFetchOutcome(
          config: null,
          attempts: attempts,
          elapsed: stopwatch.elapsed,
          failureKind: ConfigFailureKind.budgetExhausted,
          reason: 'startup budget exhausted after $attempts attempt(s)',
        );
      }

      // Clamp the attempt to whatever budget is left, so the last attempt can
      // never push total startup past the cap.
      final attemptTimeout = remaining < perAttemptTimeout
          ? remaining
          : perAttemptTimeout;

      attempts++;
      onAttempt?.call(attempts, maxAttempts);

      try {
        final config = await _attempt().timeout(attemptTimeout);
        return ConfigFetchOutcome(
          config: config,
          attempts: attempts,
          elapsed: stopwatch.elapsed,
        );
      } on _PermanentConfigFailure catch (e) {
        // Never retried: the same request would produce the same answer.
        debugPrint('Config fetch failed permanently — ${e.reason}');
        return ConfigFetchOutcome(
          config: null,
          attempts: attempts,
          elapsed: stopwatch.elapsed,
          failureKind: ConfigFailureKind.permanent,
          reason: e.reason,
        );
      } catch (error) {
        lastReason = _transientReason(error);
        if (index == maxAttempts - 1) break;

        // Only sleep if the budget can afford it AND the caller is still there.
        final backoff =
            backoffDurations[index.clamp(0, backoffDurations.length - 1)];
        final budgetLeft = totalBudget - stopwatch.elapsed;
        if (budgetLeft <= Duration.zero) break;
        await Future<void>.delayed(backoff < budgetLeft ? backoff : budgetLeft);
      }
    }

    debugPrint('Config fetch failed after $attempts attempt(s) — $lastReason');
    return ConfigFetchOutcome(
      config: null,
      attempts: attempts,
      elapsed: stopwatch.elapsed,
      failureKind: ConfigFailureKind.transient,
      reason: lastReason,
    );
  }

  /// Backwards-compatible entry point: the validated config, or null.
  ///
  /// [BootController] uses this; the richer [fetchConfigDetailed] exists for
  /// the splash, which needs attempt progress to show a loading state.
  Future<Map<String, dynamic>?> fetchConfig({
    void Function(int attempt, int maxAttempts)? onAttempt,
    bool Function()? isCancelled,
  }) async {
    final outcome = await fetchConfigDetailed(
      onAttempt: onAttempt,
      isCancelled: isCancelled,
    );
    return outcome.config;
  }

  /// One request plus validation. Throws [_PermanentConfigFailure] for
  /// anything a retry cannot fix; lets everything else propagate as transient.
  Future<Map<String, dynamic>> _attempt() async {
    final Response<dynamic> response;
    try {
      response = _requestOverride != null
          ? await _requestOverride()
          : await (_dio ?? ApiClient.instance).get<dynamic>('/config');
    } on DioException catch (e) {
      if (_isPermanentDioFailure(e)) {
        throw _PermanentConfigFailure(_permanentReason(e));
      }
      rethrow;
    }

    final status = response.statusCode ?? 0;
    if (status != 200) {
      if (_isPermanentStatus(status)) {
        throw _PermanentConfigFailure('http $status');
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: 'Non-200 status: $status',
      );
    }

    return _validate(response.data);
  }

  /// Rejects anything that is not a usable config document.
  ///
  /// A 200 carrying an error page, an empty body or a truncated JSON object
  /// would otherwise be cached as "last known good config" and then fail every
  /// later boot from cache, with no network involved. Nothing unvalidated is
  /// ever returned, so nothing unvalidated can be cached.
  Map<String, dynamic> _validate(Object? data) {
    if (data is! Map) {
      throw _PermanentConfigFailure('malformed body — not a JSON object');
    }

    final config = Map<String, dynamic>.from(data);
    final artifacts = config['artifacts'];
    if (artifacts is! Map) {
      throw const _PermanentConfigFailure(
        'schema — required "artifacts" object missing',
      );
    }

    // Deliberately not rejecting an empty `artifacts` map. It is a valid
    // document — a deployment may legitimately publish none — and the
    // artifact loader already fails closed per artifact when a URL is absent.
    // Rejecting it here would turn a recoverable configuration state into a
    // hard first-launch failure.
    return config;
  }

  /// 4xx are the client's fault and will not change on retry. 408 (request
  /// timeout) and 429 (rate limited) are the documented exceptions — both are
  /// explicitly "try again".
  static bool _isPermanentStatus(int status) =>
      status >= 400 && status < 500 && status != 408 && status != 429;

  static bool _isPermanentDioFailure(DioException e) {
    if (e.type == DioExceptionType.badCertificate) return true;
    if (e.type == DioExceptionType.badResponse) {
      return _isPermanentStatus(e.response?.statusCode ?? 0);
    }
    return false;
  }

  static String _permanentReason(DioException e) =>
      e.type == DioExceptionType.badCertificate
      ? 'bad certificate'
      : 'http ${e.response?.statusCode ?? 0}';

  /// Fixed vocabulary only — never the exception's message, which can carry a
  /// URL or response detail.
  static String _transientReason(Object error) {
    if (error is TimeoutException) return 'attempt timeout';
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return 'connection timeout';
        case DioExceptionType.receiveTimeout:
          return 'receive timeout';
        case DioExceptionType.sendTimeout:
          return 'send timeout';
        case DioExceptionType.connectionError:
          return 'connection error';
        case DioExceptionType.badResponse:
          return 'http ${error.response?.statusCode ?? 0}';
        default:
          return 'network error';
      }
    }
    return 'network error';
  }
}
