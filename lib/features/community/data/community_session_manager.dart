/// Community session handling (ADR-001 §8 A2; contract §3.2, §3.3).
///
/// - The **access token lives in memory only**. It is never written to disk,
///   never logged, and is gone when the app process ends.
/// - The **refresh token** is single-use and lives only in
///   `flutter_secure_storage`. Every refresh rotates it: the new token is
///   written to secure storage *before* the new access token is used.
/// - A **`device_id`** (UUID v4) is generated once per install, kept in
///   secure storage and sent on verify and refresh (the server binds the
///   token family to it).
/// - Refresh is **single-flight**: concurrent callers share one request.
/// - On 409 `refresh_race` the stored token is re-read; the refresh is
///   retried once only if it changed (another isolate won). Otherwise the
///   user must sign in again.
/// - On 401 from refresh (`refresh_invalid`, `refresh_reused`,
///   `refresh_expired`, `session_revoked`) every token is cleared.
/// - 429 and network errors leave the stored token alone and surface to the
///   caller; nothing auto-retries (§4.3).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/community_error.dart';
import '../domain/community_ids.dart';
import '../domain/community_me.dart';
import '../domain/community_session.dart';
import '../domain/community_validation.dart';
import 'community_auth_api.dart';
import 'community_http_client.dart';
import 'community_secure_store.dart';

enum CommunitySignInState { signedOut, signedIn }

class CommunitySessionManager extends ChangeNotifier
    implements CommunityAccessTokens {
  CommunitySessionManager({
    required CommunityAuthApi api,
    required CommunitySecureStore store,
    DateTime Function()? clock,
    String? deviceLabel,
  }) : _api = api,
       _store = store,
       _clock = clock ?? DateTime.now,
       _deviceLabel = deviceLabel;

  final CommunityAuthApi _api;
  final CommunitySecureStore _store;
  final DateTime Function() _clock;
  final String? _deviceLabel;

  /// Refresh this long before the access token's local expiry, so a request
  /// in flight does not cross it.
  static const Duration expirySkew = Duration(seconds: 30);

  String? _accessToken;
  DateTime? _accessValidUntil;
  CommunityMe? _me;
  Future<String?>? _inflightRefresh;

  /// How many refresh requests have been sent (diagnostics and tests).
  int refreshRequests = 0;

  CommunityMe? get me => _me;

  CommunitySignInState get state => _accessToken == null && _me == null
      ? CommunitySignInState.signedOut
      : CommunitySignInState.signedIn;

  /// Whether a refresh token is stored (a session may be resumable).
  Future<bool> hasStoredSession() async {
    return (await _store.read(CommunitySecureKeys.refreshToken)) != null;
  }

  /// The per-install device id, generated on first use.
  Future<String> deviceId() async {
    final String? existing = await _store.read(CommunitySecureKeys.deviceId);
    if (existing != null && isUuid(existing)) return existing;
    final String created = newUuidV4();
    await _store.write(CommunitySecureKeys.deviceId, created);
    return created;
  }

  /// A1: start sign-in or sign-up. Always "accepted" (no enumeration).
  Future<void> requestOtp(String email) {
    return _api.requestOtp(normaliseEmail(email));
  }

  /// A2: complete sign-in or sign-up with the 6-digit code.
  Future<TokenPair> verifyOtp({
    required String email,
    required String code,
  }) async {
    final TokenPair pair = await _api.verifyOtp(
      email: normaliseEmail(email),
      code: validateOtpCode(code),
      deviceId: await deviceId(),
      deviceLabel: _deviceLabel,
    );
    await _adopt(pair);
    return pair;
  }

  /// Updates the cached `Me` (e.g. after `GET /v1/community/me`).
  void updateMe(CommunityMe me) {
    _me = me;
    notifyListeners();
  }

  @override
  Future<String?> accessToken() async {
    final String? token = _accessToken;
    final DateTime? until = _accessValidUntil;
    if (token != null && until != null && _clock().isBefore(until)) {
      return token;
    }
    return refresh();
  }

  @override
  Future<String?> renewAfterExpiry(String rejected) async {
    // Another caller may already have refreshed while this request was out.
    final String? current = _accessToken;
    if (current != null && current != rejected) {
      final DateTime? until = _accessValidUntil;
      if (until != null && _clock().isBefore(until)) return current;
    }
    _accessToken = null;
    _accessValidUntil = null;
    return refresh();
  }

  @override
  Future<void> sessionEnded() => _clearTokens();

  /// Single-flight refresh. Returns the new access token, or null when the
  /// user must sign in again. Throws on 429, 503 or network failure.
  Future<String?> refresh() {
    return _inflightRefresh ??= _refresh().whenComplete(() {
      _inflightRefresh = null;
    });
  }

  Future<String?> _refresh() async {
    String? presented = await _store.read(CommunitySecureKeys.refreshToken);
    if (presented == null) return null;
    final String device = await deviceId();
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        refreshRequests++;
        final TokenPair pair = await _api.refresh(
          refreshToken: presented!,
          deviceId: device,
        );
        await _adopt(pair);
        return pair.accessToken;
      } on CommunityException catch (e) {
        if (e.code == CommunityErrorCode.conflict &&
            e.reason == 'refresh_race' &&
            attempt == 0) {
          final String? stored = await _store.read(
            CommunitySecureKeys.refreshToken,
          );
          if (stored != null && stored != presented) {
            presented = stored;
            continue;
          }
          await _clearTokens();
          return null;
        }
        if (e.code == CommunityErrorCode.unauthenticated ||
            e.code == CommunityErrorCode.conflict ||
            e.code == CommunityErrorCode.validationFailed) {
          await _clearTokens();
          return null;
        }
        rethrow;
      }
    }
    await _clearTokens();
    return null;
  }

  Future<void> _adopt(TokenPair pair) async {
    // Rotation: persist the new single-use refresh token first, so a crash
    // between the two steps never leaves only a used token on disk.
    await _store.write(CommunitySecureKeys.refreshToken, pair.refreshToken);
    _accessToken = pair.accessToken;
    _accessValidUntil = _clock()
        .add(Duration(seconds: pair.expiresIn))
        .subtract(expirySkew);
    _me = pair.account;
    notifyListeners();
  }

  /// A4 sign-out of this device. The server call is best effort; local
  /// tokens are cleared whatever it answers. The install's `device_id` is
  /// kept (it identifies the install, not the account, §3.3 A2).
  Future<void> signOut() async {
    final String? refreshToken = await _store.read(
      CommunitySecureKeys.refreshToken,
    );
    String? access = _accessToken;
    try {
      if (access == null && refreshToken != null) access = await refresh();
      if (access != null) {
        await _api.logout(
          accessToken: access,
          refreshToken: await _store.read(CommunitySecureKeys.refreshToken),
        );
      }
    } on Object catch (e) {
      debugPrint('community sign-out: server call failed (${e.runtimeType})');
    } finally {
      await _clearTokens();
    }
  }

  /// After account deletion (M8): erase everything Community stored on the
  /// device, including the `device_id`.
  Future<void> forgetDevice() async {
    await _clearTokens();
    for (final String key in CommunitySecureKeys.all) {
      await _store.delete(key);
    }
  }

  Future<void> _clearTokens() async {
    _accessToken = null;
    _accessValidUntil = null;
    _me = null;
    await _store.delete(CommunitySecureKeys.refreshToken);
    notifyListeners();
  }
}
