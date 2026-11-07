import 'package:flutter/foundation.dart';

import 'community_json.dart';
import 'community_me.dart';

/// `TokenPair` (§3.3 A2/A3). A self DTO: no identity-key rejection.
///
/// ADR-001 A2: the access token lives in memory only; the refresh token goes
/// to `flutter_secure_storage`. [toString] never prints either token.
@immutable
class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.expiresIn,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
    required this.accountCreated,
    required this.account,
  });

  factory TokenPair.fromJson(Map<String, dynamic> json) {
    if (readString(json, 'token_type') != 'Bearer') {
      throw const FormatException('token_type must be Bearer');
    }
    final int expiresIn = readInt(json, 'expires_in', min: 1);
    if (expiresIn > 900) {
      throw const FormatException('access token lifetime exceeds 15 min');
    }
    final String access = readString(json, 'access_token');
    final String refresh = readString(json, 'refresh_token');
    if (access.isEmpty || refresh.isEmpty) {
      throw const FormatException('empty token');
    }
    return TokenPair(
      accessToken: access,
      expiresIn: expiresIn,
      accessTokenExpiresAt: readTime(json, 'access_token_expires_at'),
      refreshToken: refresh,
      refreshTokenExpiresAt: readTime(json, 'refresh_token_expires_at'),
      accountCreated: readBool(json, 'account_created'),
      account: CommunityMe.fromJson(readObject(json, 'account')),
    );
  }

  final String accessToken;
  final int expiresIn;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;

  /// The family's absolute expiry; the idle limit can end it sooner.
  final DateTime refreshTokenExpiresAt;

  /// True on the sign-in that created the account (sign-up).
  final bool accountCreated;
  final CommunityMe account;

  @override
  String toString() => 'TokenPair(<redacted>, created: $accountCreated)';
}

/// One signed-in device (`Session`, §3.3 A5). No IP or user agent.
@immutable
class DeviceSession {
  const DeviceSession({
    required this.sessionId,
    required this.deviceLabel,
    required this.createdAt,
    required this.lastUsedAt,
    required this.expiresAt,
    required this.current,
  });

  factory DeviceSession.fromJson(Map<String, dynamic> json) {
    return DeviceSession(
      sessionId: readString(json, 'session_id'),
      deviceLabel: readNullableString(json, 'device_label'),
      createdAt: readTime(json, 'created_at'),
      lastUsedAt: readTime(json, 'last_used_at'),
      expiresAt: readTime(json, 'expires_at'),
      current: readBool(json, 'current'),
    );
  }

  final String sessionId;
  final String? deviceLabel;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  final DateTime expiresAt;
  final bool current;
}
