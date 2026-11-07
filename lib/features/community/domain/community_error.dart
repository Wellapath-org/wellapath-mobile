/// The Community error envelope (contract §1.3) and the client-side errors.
library;

import 'community_json.dart';

/// Mirrors the contract's `ErrorCode` enum exactly (§1.3, §13). An unknown
/// wire code is treated as [internalError] (§13).
enum CommunityErrorCode {
  validationFailed,
  invalidCode,
  tokenExpired,
  unauthenticated,
  forbidden,
  communityNotAllowed,
  accountRestricted,
  accountSuspended,
  mfaEnrollmentRequired,
  mfaStepUpRequired,
  selfActionForbidden,
  notFound,
  conflict,
  invalidState,
  idempotencyKeyReused,
  rateLimited,
  internalError,
  communityUnavailable;

  String get wire => snakeCase(name);

  static CommunityErrorCode fromWire(String? raw) {
    return enumFromWire(
          raw,
          CommunityErrorCode.values,
          (CommunityErrorCode c) => c.wire,
        ) ??
        CommunityErrorCode.internalError;
  }
}

/// A non-2xx answer from a Community, auth or features route.
///
/// Carries only what the envelope allows: never input values, emails or
/// tokens (§1.3), so it is safe to show its [code] or log its [requestId].
class CommunityException implements Exception {
  const CommunityException(
    this.code, {
    this.status,
    this.reason,
    this.field,
    this.rule,
    this.retryAfter,
    this.until,
    this.requestId,
    this.closesCommunity = false,
  });

  /// Parses the `{ "error": {...} }` envelope. A body that is not a valid
  /// envelope becomes [CommunityErrorCode.internalError].
  factory CommunityException.fromEnvelope(
    int status,
    Object? body, {
    Duration? retryAfterHeader,
    bool notFoundClosesCommunity = false,
  }) {
    CommunityErrorCode code = CommunityErrorCode.internalError;
    String? requestId;
    Map<String, dynamic> details = const <String, dynamic>{};
    if (body is Map<String, dynamic> && body['error'] is Map<String, dynamic>) {
      final Map<String, dynamic> error = body['error'] as Map<String, dynamic>;
      code = CommunityErrorCode.fromWire(error['code'] as String?);
      final Object? rid = error['request_id'];
      requestId = rid is String ? rid : null;
      final Object? d = error['details'];
      if (d is Map<String, dynamic>) details = d;
    }
    Duration? retryAfter = retryAfterHeader;
    final Object? seconds = details['retry_after_seconds'];
    if (retryAfter == null && seconds is int && seconds > 0) {
      retryAfter = Duration(seconds: seconds);
    }
    DateTime? until;
    final Object? rawUntil = details['until'];
    if (rawUntil is String) until = DateTime.tryParse(rawUntil)?.toUtc();
    final bool closes =
        code == CommunityErrorCode.communityNotAllowed ||
        (status == 404 && notFoundClosesCommunity);
    return CommunityException(
      code,
      status: status,
      reason: details['reason'] is String ? details['reason'] as String : null,
      field: details['field'] is String ? details['field'] as String : null,
      rule: details['rule'] is String ? details['rule'] as String : null,
      retryAfter: retryAfter,
      until: until,
      requestId: requestId,
      closesCommunity: closes,
    );
  }

  final CommunityErrorCode code;
  final int? status;

  /// `details.reason` (e.g. `display_name_taken`, `refresh_race`).
  final String? reason;
  final String? field;
  final String? rule;

  /// From the `Retry-After` header (always set on 429, §4.3).
  final Duration? retryAfter;

  /// `details.until` on `account_restricted`.
  final DateTime? until;
  final String? requestId;

  /// Whether the client must close Community: 403 `community_not_allowed`,
  /// or a 404 on a list or space route (§1.3 client rule).
  final bool closesCommunity;

  /// The server switched Community off for this viewer.
  bool get isKillSwitch =>
      closesCommunity || code == CommunityErrorCode.communityNotAllowed;

  /// The session is gone; the user must sign in again.
  bool get requiresSignIn => code == CommunityErrorCode.unauthenticated;

  @override
  String toString() {
    final String extra = reason == null ? '' : ' ($reason)';
    return 'CommunityException(${code.wire}$extra, status: $status)';
  }
}

/// The request never reached the server, or no response came back.
class CommunityNetworkException implements Exception {
  const CommunityNetworkException(this.kind);

  final String kind;

  @override
  String toString() => 'CommunityNetworkException($kind)';
}

/// Thrown **before sending** when a request would carry a key the contract
/// prohibits (§5). Nothing is sent.
class ProhibitedPayloadException implements Exception {
  const ProhibitedPayloadException(this.path);

  /// Where the key was found, e.g. `body.meta.<key>` or `query.<key>`.
  final String path;

  @override
  String toString() => 'ProhibitedPayloadException($path)';
}
