/// The member-facing `/v1/auth/*` facade routes (contract §3.3 A1–A6).
///
/// TOTP (A7–A9) is deliberately absent: members never need it, and the app
/// has no privileged UI (moderation lives in the website admin).
library;

import '../domain/community_page.dart';
import '../domain/community_session.dart';
import 'community_http_client.dart';

class CommunityAuthApi {
  CommunityAuthApi(this._client);

  /// Must be a client **without** token handling: A1–A3 send no bearer, and
  /// the refresh call must never recurse into a refresh.
  final CommunityHttpClient _client;

  /// A1 `POST /v1/auth/otp/request`. Always `202 {}` (no enumeration).
  Future<void> requestOtp(String email) async {
    await _client.send(
      CommunityRequest(
        method: 'POST',
        template: '/v1/auth/otp/request',
        body: <String, dynamic>{'email': email},
        auth: CommunityAuth.none,
      ),
    );
  }

  /// A2 `POST /v1/auth/otp/verify`. Sign-in, or sign-up when the account is
  /// new (`account_created: true`).
  Future<TokenPair> verifyOtp({
    required String email,
    required String code,
    required String deviceId,
    String? deviceLabel,
  }) async {
    final CommunityResponse r = await _client.send(
      CommunityRequest(
        method: 'POST',
        template: '/v1/auth/otp/verify',
        body: <String, dynamic>{
          'email': email,
          'code': code,
          'device_id': deviceId,
          'device_label': ?deviceLabel,
        },
        auth: CommunityAuth.none,
      ),
    );
    return TokenPair.fromJson(r.json);
  }

  /// A3 `POST /v1/auth/refresh`: single-use rotation.
  Future<TokenPair> refresh({
    required String refreshToken,
    required String deviceId,
  }) async {
    final CommunityResponse r = await _client.send(
      CommunityRequest(
        method: 'POST',
        template: '/v1/auth/refresh',
        body: <String, dynamic>{
          'refresh_token': refreshToken,
          'device_id': deviceId,
        },
        auth: CommunityAuth.none,
      ),
    );
    return TokenPair.fromJson(r.json);
  }

  /// A4 `POST /v1/auth/logout` with the refresh token alone (contract P6,
  /// adopted 2026-11-07). No `Authorization` header is sent: the refresh
  /// token is the credential, so sign-out works even when the access token
  /// has expired or was never loaded. The server answers the same `204` for
  /// every well-formed token (revoked, already gone or unknown), so any 2xx
  /// is success.
  Future<void> logout({required String refreshToken}) async {
    await _client.send(
      CommunityRequest(
        method: 'POST',
        template: '/v1/auth/logout',
        body: <String, dynamic>{'refresh_token': refreshToken},
        auth: CommunityAuth.none,
      ),
    );
  }

  /// A4 with a bearer only, for when no refresh token is stored. The access
  /// token may be expired (A4 accepts an expired-but-validly-signed token for
  /// this route only).
  Future<void> logoutWithBearer(String accessToken) async {
    await _client.send(
      CommunityRequest(
        method: 'POST',
        template: '/v1/auth/logout',
        bearer: accessToken,
      ),
    );
  }
}

/// A5/A6 need a normal authenticated client, so they live apart from the
/// token-less calls above.
class CommunityDeviceSessionsApi {
  CommunityDeviceSessionsApi(this._client);

  final CommunityHttpClient _client;

  /// A5 `GET /v1/auth/sessions`.
  Future<List<DeviceSession>> list() async {
    final CommunityResponse r = await _client.send(
      const CommunityRequest(method: 'GET', template: '/v1/auth/sessions'),
    );
    return CommunityPage<DeviceSession>.fromJson(
      r.json,
      DeviceSession.fromJson,
    ).items;
  }

  /// A6 `POST /v1/auth/sessions/revoke-others`: account recovery after a
  /// lost device. Returns how many other devices were signed out.
  Future<int> revokeOthers() async {
    final CommunityResponse r = await _client.send(
      const CommunityRequest(
        method: 'POST',
        template: '/v1/auth/sessions/revoke-others',
        body: <String, dynamic>{},
      ),
    );
    final Object? n = r.json['revoked'];
    if (n is! int || n < 0) throw const FormatException('bad revoked count');
    return n;
  }
}
