import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../network/api_client.dart';
import '../network/retry_with_backoff.dart';

class ConfigService {
  ConfigService({
    Dio? dio,
    this.maxRetries = 3,
    List<Duration>? backoffDurations,
    this.perAttemptTimeout = const Duration(seconds: 10),
    Future<Response<dynamic>> Function()? requestOverride,
  }) : _dio = dio,
       backoffDurations =
           backoffDurations ??
           const [
             Duration(seconds: 2),
             Duration(seconds: 4),
             Duration(seconds: 8),
           ],
       _requestOverride = requestOverride;

  // Nullable, resolved to the real ApiClient.instance lazily inside
  // _requestConfig — ApiClient.instance reads dotenv, which isn't loaded in
  // a plain unit test, and tests always supply requestOverride instead of
  // ever needing a real Dio.
  final Dio? _dio;
  final int maxRetries;
  final List<Duration> backoffDurations;
  final Duration perAttemptTimeout;
  final Future<Response<dynamic>> Function()? _requestOverride;

  /// Fetches `/config`, retrying with exponential backoff (2s/4s/8s, 3
  /// retries — 4 attempts total) on network failure or a non-200 response.
  /// Returns null once all retries are exhausted, matching the previous
  /// single-attempt contract — callers (BootController) already handle a
  /// null result by falling back to cached config, or reporting a failed
  /// boot if no cache exists either.
  Future<Map<String, dynamic>?> fetchConfig() async {
    try {
      final response = await retryWithBackoff<Response<dynamic>>(
        attempt: _requestConfig,
        maxRetries: maxRetries,
        backoffDurations: backoffDurations,
        perAttemptTimeout: perAttemptTimeout,
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Config fetch failed after retries: $e');
      return null;
    }
  }

  Future<Response<dynamic>> _requestConfig() async {
    final response = _requestOverride != null
        ? await _requestOverride()
        : await (_dio ?? ApiClient.instance).get<dynamic>('/config');
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: 'Non-200 status: ${response.statusCode}',
      );
    }
    return response;
  }
}
