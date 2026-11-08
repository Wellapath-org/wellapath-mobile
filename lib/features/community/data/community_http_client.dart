/// The one HTTP client every Community, auth and features request goes
/// through. It owns the cross-cutting contract rules so no repository can
/// forget them:
///
/// - **Prohibited keys** (§5): any request whose body (any depth) or query
///   carries an assessment-data key is refused before it is sent.
/// - **Bearer auth** from memory (ADR A2); on 401 `token_expired` it refreshes
///   once (single-flight, in the session manager) and retries once; on 401
///   `unauthenticated` it clears the session (§1.3).
/// - **Error envelope** (§1.3) → [CommunityException], with `Retry-After`
///   on 429 (§4.3). Nothing is auto-retried after a 429.
/// - **Kill switch**: 403 `community_not_allowed`, or 404 on a list/space
///   route, marks the error as closing Community (§1.3 client rule).
/// - **No body, header or query logging, ever** (CLAUDE.md PHI rule). Only
///   the method, the route *template* and the status are printed, in debug
///   builds. This is a dedicated Dio: the app-wide `ApiClient` logger prints
///   request headers by default, which would include the bearer token.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../domain/community_error.dart';
import 'prohibited_keys.dart';

/// Base URL of the Community API. Empty (the default) means Community is
/// hidden: no client is built and no request is made.
const String kCommunityApiBaseUrl = String.fromEnvironment(
  'COMMUNITY_API_BASE_URL',
);

/// Supplies and renews the in-memory access token. Implemented by
/// `CommunitySessionManager`.
abstract interface class CommunityAccessTokens {
  /// A usable access token, refreshing first if it has expired; null when
  /// signed out.
  Future<String?> accessToken();

  /// Called after the server answered `token_expired` for [rejected].
  /// Returns a new token (single-flight refresh), or null if the session
  /// could not be renewed.
  Future<String?> renewAfterExpiry(String rejected);

  /// The server says the session is gone: clear every token.
  Future<void> sessionEnded();
}

enum CommunityAuth {
  /// No `Authorization` header (OTP request/verify, refresh).
  none,

  /// Sent when a session exists, omitted otherwise (`GET /v1/features`).
  optional,

  /// Required; fails locally with `unauthenticated` when signed out.
  required,
}

/// One request, described in contract terms.
@immutable
class CommunityRequest {
  const CommunityRequest({
    required this.method,
    required this.template,
    this.pathParams = const <String, String>{},
    this.body,
    this.query,
    this.idempotencyKey,
    this.auth = CommunityAuth.required,
    this.bearer,
    this.notFoundClosesCommunity = false,
  });

  final String method;

  /// The OpenAPI path template, e.g. `/v1/community/posts/{post_id}`.
  final String template;
  final Map<String, String> pathParams;
  final Object? body;
  final Map<String, dynamic>? query;
  final String? idempotencyKey;
  final CommunityAuth auth;

  /// An explicit bearer, used as-is with no refresh logic. Only sign-out
  /// uses it: A4 accepts an expired-but-validly-signed access token.
  final String? bearer;

  /// A 404 here means Community is off for this viewer (list/space routes).
  final bool notFoundClosesCommunity;

  /// The concrete path. Ids are opaque and percent-encoded, never parsed.
  String get path {
    String out = template;
    pathParams.forEach((String k, String v) {
      out = out.replaceAll('{$k}', Uri.encodeComponent(v));
    });
    if (out.contains('{')) {
      throw ArgumentError('unfilled path parameter in $template');
    }
    return out;
  }
}

@immutable
class CommunityResponse {
  const CommunityResponse(this.status, this.data, {this.retryAfter});

  final int status;
  final Object? data;

  /// The `Retry-After` header, in seconds (§4.3).
  final Duration? retryAfter;

  Map<String, dynamic> get json {
    final Object? d = data;
    if (d is Map<String, dynamic>) return d;
    throw const CommunityException(CommunityErrorCode.internalError);
  }
}

class CommunityHttpClient {
  CommunityHttpClient(this._dio, {CommunityAccessTokens? tokens})
    : _tokens = tokens;

  /// A client for [baseUrl]. [adapter] lets tests record requests without a
  /// network.
  factory CommunityHttpClient.forBaseUrl(
    String baseUrl, {
    HttpClientAdapter? adapter,
    Duration timeout = const Duration(seconds: 10),
  }) {
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        responseType: ResponseType.json,
        headers: <String, Object>{'Accept': 'application/json'},
        // Every status is handled here, not by Dio throwing.
        validateStatus: (int? _) => true,
      ),
    );
    if (adapter != null) dio.httpClientAdapter = adapter;
    return CommunityHttpClient(dio);
  }

  final Dio _dio;
  final CommunityAccessTokens? _tokens;

  /// The same transport, with bearer auth from [tokens].
  CommunityHttpClient withTokens(CommunityAccessTokens tokens) {
    return CommunityHttpClient(_dio, tokens: tokens);
  }

  Future<CommunityResponse> send(CommunityRequest request) async {
    // §5: refuse before anything else, including token refresh.
    assertNoProhibitedKeys(body: request.body, query: request.query);

    String? token = request.bearer;
    final CommunityAccessTokens? tokens = request.bearer == null
        ? _tokens
        : null;
    if (request.auth == CommunityAuth.required && tokens != null) {
      token = await tokens.accessToken();
    } else if (request.auth == CommunityAuth.optional && tokens != null) {
      // Optional auth never fails the request: no usable token, no header.
      try {
        token = await tokens.accessToken();
      } on Object {
        token = null;
      }
    }
    if (request.auth == CommunityAuth.required && token == null) {
      throw const CommunityException(
        CommunityErrorCode.unauthenticated,
        reason: 'missing_token',
      );
    }

    CommunityResponse response = await _once(request, token);
    if (response.status == 401 &&
        token != null &&
        tokens != null &&
        _code(response) == CommunityErrorCode.tokenExpired) {
      // §1.3: refresh once, then retry once.
      final String? renewed = await tokens.renewAfterExpiry(token);
      if (renewed == null) {
        throw const CommunityException(
          CommunityErrorCode.unauthenticated,
          status: 401,
        );
      }
      response = await _once(request, renewed);
    }
    if (response.status >= 200 && response.status < 300) return response;

    final CommunityException error = CommunityException.fromEnvelope(
      response.status,
      response.data,
      retryAfterHeader: response.retryAfter,
      notFoundClosesCommunity: request.notFoundClosesCommunity,
    );
    if (error.code == CommunityErrorCode.unauthenticated &&
        token != null &&
        tokens != null) {
      await tokens.sessionEnded();
    }
    throw error;
  }

  Future<CommunityResponse> _once(
    CommunityRequest request,
    String? token,
  ) async {
    final Map<String, Object> headers = <String, Object>{
      if (request.body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      if (request.idempotencyKey != null)
        'Idempotency-Key': request.idempotencyKey!,
    };
    final Response<Object?> r;
    try {
      r = await _dio.request<Object?>(
        request.path,
        data: request.body,
        queryParameters: request.query,
        options: Options(method: request.method, headers: headers),
      );
    } on DioException catch (e) {
      _log(request, null);
      throw CommunityNetworkException(e.type.name);
    }
    final int status = r.statusCode ?? 0;
    _log(request, status);
    return CommunityResponse(
      status,
      r.data,
      retryAfter: _parseRetryAfter(r.headers.value('retry-after')),
    );
  }

  static CommunityErrorCode? _code(CommunityResponse r) {
    final Object? d = r.data;
    if (d is Map<String, dynamic> && d['error'] is Map<String, dynamic>) {
      return CommunityErrorCode.fromWire(
        (d['error'] as Map<String, dynamic>)['code'] as String?,
      );
    }
    return null;
  }

  static Duration? _parseRetryAfter(String? raw) {
    if (raw == null) return null;
    final int? seconds = int.tryParse(raw.trim());
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds);
  }

  /// Method, route template and status only: never ids, bodies, queries or
  /// headers.
  static void _log(CommunityRequest request, int? status) {
    if (!kDebugMode) return;
    debugPrint(
      'community http: ${request.method} ${request.template} -> '
      '${status ?? 'no response'}',
    );
  }
}
