/// A Dio adapter that answers Community requests from a handler and records
/// every request that actually left the client. No network.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class RecordedRequest {
  RecordedRequest(this.method, this.path, this.query, this.headers, this.body);

  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Map<String, dynamic> headers;
  final Object? body;

  String? header(String name) {
    for (final MapEntry<String, dynamic> e in headers.entries) {
      if (e.key.toLowerCase() == name.toLowerCase()) return '${e.value}';
    }
    return null;
  }

  @override
  String toString() => '$method $path';
}

class FakeReply {
  const FakeReply(this.status, [this.body, this.headers = const {}]);

  final int status;
  final Object? body;
  final Map<String, String> headers;
}

typedef FakeHandler = Future<FakeReply> Function(RecordedRequest request);

Map<String, dynamic> errorBody(String code, {Map<String, dynamic>? details}) {
  return <String, dynamic>{
    'error': <String, dynamic>{
      'code': code,
      'message': 'safe message',
      'request_id': 'req_12345678',
      'details': ?details,
    },
  };
}

class FakeCommunityAdapter implements HttpClientAdapter {
  FakeCommunityAdapter(this.handler);

  FakeHandler handler;
  final List<RecordedRequest> requests = <RecordedRequest>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final RecordedRequest r = RecordedRequest(
      options.method,
      options.uri.path,
      Map<String, dynamic>.of(options.queryParameters),
      Map<String, dynamic>.of(options.headers),
      options.data,
    );
    requests.add(r);
    final FakeReply reply = await handler(r);
    final Map<String, List<String>> headers = <String, List<String>>{
      'content-type': <String>['application/json'],
      for (final MapEntry<String, String> e in reply.headers.entries)
        e.key.toLowerCase(): <String>[e.value],
    };
    if (reply.body == null) {
      return ResponseBody.fromString('', reply.status, headers: headers);
    }
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.status,
      headers: headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A well-formed `Me`.
Map<String, dynamic> meJson({
  String role = 'member',
  String status = 'active',
  Map<String, dynamic>? profile,
}) {
  return <String, dynamic>{
    'account_id': 'Xk3abc',
    'email': 'a@b.ng',
    'role': role,
    'status': status,
    'restricted_until': null,
    'two_factor_enabled': false,
    'community_allowed': true,
    'created_at': '2026-11-07T10:15:00.000Z',
    'profile': profile,
  };
}

/// A well-formed `TokenPair` with the given tokens.
Map<String, dynamic> tokenPairJson({
  required String access,
  required String refresh,
  bool created = false,
  int expiresIn = 900,
}) {
  return <String, dynamic>{
    'token_type': 'Bearer',
    'access_token': access,
    'expires_in': expiresIn,
    'access_token_expires_at': '2026-11-07T10:30:00.000Z',
    'refresh_token': refresh,
    'refresh_token_expires_at': '2026-12-07T10:15:00.000Z',
    'account_created': created,
    'account': meJson(),
  };
}

/// A refresh token shaped like the contract's `^wprt_[A-Za-z0-9_-]{43,}$`.
String wprt(String seed) => 'wprt_${seed.padRight(43, 'x')}';
