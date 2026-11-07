import 'package:flutter/foundation.dart';

import 'community_json.dart';
import 'community_validation.dart';
import 'professional_verification.dart';

/// The signed-in member's own Community `Profile` (§7.1):
/// `{ display_name, professional: ProfessionalVerification | null }`.
///
/// A profile is required before posting, commenting or claiming a
/// profession, pseudonymous posting included (422 `profile_required`).
@immutable
class CommunityProfile {
  const CommunityProfile._({required this.displayName, this.professional});

  /// A locally validated profile (used by the in-memory backend).
  CommunityProfile({required String displayName, this.professional})
    : displayName = validateDisplayName(displayName);

  /// Parses a server `Profile`. The server is authoritative on the name, so
  /// it is not re-validated here beyond being a non-empty string.
  factory CommunityProfile.fromJson(Map<String, dynamic> json) {
    final String name = readString(json, 'display_name');
    if (name.trim().isEmpty) throw const FormatException('empty display_name');
    final Map<String, dynamic>? pro = readNullableObject(json, 'professional');
    return CommunityProfile._(
      displayName: name,
      professional: pro == null ? null : ProfessionalVerification.fromJson(pro),
    );
  }

  final String displayName;
  final ProfessionalVerification? professional;

  CommunityProfile withProfessional(ProfessionalVerification? p) {
    return CommunityProfile._(displayName: displayName, professional: p);
  }

  static final RegExp _allowed = RegExp(r'^[A-Za-z0-9 _.\-]+$');
  static final RegExp _doubleSpace = RegExp(r' {2,}');
  static final RegExp _digit = RegExp(r'[0-9]');

  /// Contract §7.2 (P7, founder-approved 2026-11-08), identical to the
  /// backend's `EMAIL_LIKE`: contains `@`, or ends with a letter or digit,
  /// `.` and a common TLD (case-insensitive).
  static final RegExp emailLike = RegExp(
    r'@|[A-Za-z0-9]\.(com|net|org|ng|io|co|uk|edu|gov|info|me|app)$',
    caseSensitive: false,
  );

  /// 7 or more digits in total, anywhere in the name, is a phone number.
  static const int maxDigits = 6;

  /// `display_name` rules (§7.2):
  /// - 3–30 chars after trim, pattern `^[A-Za-z0-9 _.-]+$`;
  /// - no run of two or more spaces;
  /// - must not contain 7 or more digits in total, and must not be
  ///   email-like ([emailLike]): `not_allowed_value`, checked before the
  ///   pattern (P7). A display name is public; those are contact details.
  static String validateDisplayName(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const CommunityValidationException('display_name', 'required');
    }
    if (trimmed.length < CommunityLimits.displayNameMin) {
      throw const CommunityValidationException('display_name', 'min_length');
    }
    if (trimmed.length > CommunityLimits.displayNameMax) {
      throw const CommunityValidationException('display_name', 'max_length');
    }
    if (_digit.allMatches(trimmed).length > maxDigits ||
        emailLike.hasMatch(trimmed)) {
      throw const CommunityValidationException(
        'display_name',
        'not_allowed_value',
      );
    }
    if (!_allowed.hasMatch(trimmed) || _doubleSpace.hasMatch(trimmed)) {
      throw const CommunityValidationException('display_name', 'pattern');
    }
    return trimmed;
  }

  /// The `PUT /v1/community/me/profile` body.
  static Map<String, dynamic> updateBody(String displayName) {
    return <String, dynamic>{'display_name': validateDisplayName(displayName)};
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'display_name': displayName,
      'professional': professional?.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is CommunityProfile &&
        other.displayName == displayName &&
        other.professional == professional;
  }

  @override
  int get hashCode => Object.hash(displayName, professional);
}
