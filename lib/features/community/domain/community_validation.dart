/// Client-side validation limits. These mirror the server rules in the
/// canonical contract (`COMMUNITY_API_CONTRACT.md` v1.0-draft); the server
/// remains authoritative. Rule names match the contract's `details.rule`.
library;

/// Thrown when a draft fails validation before it is sent.
class CommunityValidationException implements Exception {
  const CommunityValidationException(this.field, this.rule);

  final String field;

  /// One of the contract's rule names: `required`, `min_length`,
  /// `max_length`, `pattern`, `not_allowed_value`.
  final String rule;

  @override
  String toString() => 'CommunityValidationException($field: $rule)';
}

abstract final class CommunityLimits {
  /// §8.2 C3: 1–2000 after trim.
  static const int postBodyMax = 2000;

  /// §9 C7: 1–1000 after trim.
  static const int commentBodyMax = 1000;

  /// §10 C9: ≤ 500 after trim; empty becomes null.
  static const int reportNoteMax = 500;

  /// §7.2: 3–30 after trim.
  static const int displayNameMin = 3;
  static const int displayNameMax = 30;

  /// §12: 10–500 after trim (moderation lives in the website admin; kept
  /// for the in-memory test backend only).
  static const int moderationReasonMin = 10;
  static const int moderationReasonMax = 500;

  /// §7.2 M5: profession and specialty 2–80 after trim.
  static const int professionMin = 2;
  static const int professionMax = 80;

  /// §3.3 A1: email ≤ 254.
  static const int emailMax = 254;

  /// §3.3 A2: `device_label` 1–64.
  static const int deviceLabelMax = 64;

  /// §7.2 M8: the exact confirmation phrase.
  static const String deleteAccountPhrase = 'DELETE MY ACCOUNT';
}

/// Trims [body] and enforces [min]..[max] characters.
String validateBody(
  String body, {
  required String field,
  required int max,
  int min = 1,
}) {
  final String trimmed = body.trim();
  if (trimmed.isEmpty) throw CommunityValidationException(field, 'required');
  if (trimmed.length < min) {
    throw CommunityValidationException(field, 'min_length');
  }
  if (trimmed.length > max) {
    throw CommunityValidationException(field, 'max_length');
  }
  return trimmed;
}

/// Trims an optional text; empty becomes null.
String? validateOptionalText(
  String? text, {
  required String field,
  required int max,
  int min = 1,
}) {
  if (text == null) return null;
  final String trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length < min) {
    throw CommunityValidationException(field, 'min_length');
  }
  if (trimmed.length > max) {
    throw CommunityValidationException(field, 'max_length');
  }
  return trimmed;
}

/// Trims an optional note; empty becomes null.
String? validateOptionalNote(String? note, {required int max}) {
  return validateOptionalText(note, field: 'note', max: max);
}

/// Every moderation action needs a real reason (contract §12).
String validateModerationReason(String reason) {
  return validateBody(
    reason,
    field: 'reason',
    min: CommunityLimits.moderationReasonMin,
    max: CommunityLimits.moderationReasonMax,
  );
}

final RegExp _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Trims and lower-cases an email for OTP request/verify (§3.3 A1).
String normaliseEmail(String raw) {
  final String email = raw.trim().toLowerCase();
  if (email.isEmpty) {
    throw const CommunityValidationException('email', 'required');
  }
  if (email.length > CommunityLimits.emailMax) {
    throw const CommunityValidationException('email', 'max_length');
  }
  if (!_emailShape.hasMatch(email)) {
    throw const CommunityValidationException('email', 'format');
  }
  return email;
}

final RegExp _otp = RegExp(r'^[0-9]{6}$');

/// The 6-digit email OTP (§3.3 A2).
String validateOtpCode(String raw) {
  final String code = raw.trim();
  if (!_otp.hasMatch(code)) {
    throw const CommunityValidationException('code', 'pattern');
  }
  return code;
}
