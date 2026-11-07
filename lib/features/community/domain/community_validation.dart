/// Client-side validation limits. These mirror the server rules in
/// `docs/community/API_CONTRACT.md`; the server remains authoritative.
library;

/// Thrown when a draft fails validation before it is sent.
class CommunityValidationException implements Exception {
  const CommunityValidationException(this.field, this.rule);

  final String field;
  final String rule;

  @override
  String toString() => 'CommunityValidationException($field: $rule)';
}

abstract final class CommunityLimits {
  static const int postBodyMax = 2000;
  static const int commentBodyMax = 1000;
  static const int reportNoteMax = 500;
  static const int displayNameMin = 3;
  static const int displayNameMax = 30;
  static const int moderationReasonMin = 10;
  static const int moderationReasonMax = 500;
  static const int professionMax = 80;
}

/// Trims [body] and enforces 1..[max] characters.
String validateBody(String body, {required String field, required int max}) {
  final String trimmed = body.trim();
  if (trimmed.isEmpty) throw CommunityValidationException(field, 'required');
  if (trimmed.length > max) {
    throw CommunityValidationException(field, 'max_length');
  }
  return trimmed;
}

/// Trims an optional note; empty becomes null.
String? validateOptionalNote(String? note, {required int max}) {
  if (note == null) return null;
  final String trimmed = note.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > max) {
    throw const CommunityValidationException('note', 'max_length');
  }
  return trimmed;
}

/// Every moderation action needs a real reason (API contract §11).
String validateModerationReason(String reason) {
  final String trimmed = reason.trim();
  if (trimmed.length < CommunityLimits.moderationReasonMin) {
    throw const CommunityValidationException('reason', 'min_length');
  }
  if (trimmed.length > CommunityLimits.moderationReasonMax) {
    throw const CommunityValidationException('reason', 'max_length');
  }
  return trimmed;
}
