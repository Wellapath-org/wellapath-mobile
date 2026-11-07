import 'package:flutter/foundation.dart';

import 'community_json.dart';
import 'community_validation.dart';
import 'professional_verification.dart';

/// The signed-in member's own Community profile.
@immutable
class CommunityProfile {
  CommunityProfile({required String displayName, this.professional})
    : displayName = validateDisplayName(displayName);

  factory CommunityProfile.fromJson(Map<String, dynamic> json) {
    rejectIdentityKeys(json);
    final Object? pro = json['professional'];
    if (pro != null && pro is! Map<String, dynamic>) {
      throw const FormatException('expected object or null at "professional"');
    }
    final String name = readString(json, 'display_name');
    try {
      return CommunityProfile(
        displayName: name,
        professional: pro == null
            ? null
            : ProfessionalVerification.fromJson(pro as Map<String, dynamic>),
      );
    } on CommunityValidationException catch (e) {
      throw FormatException('invalid display_name: ${e.rule}');
    }
  }

  final String displayName;
  final ProfessionalVerification? professional;

  static final RegExp _allowed = RegExp(r'^[A-Za-z0-9 _.\-]+$');
  static final RegExp _looksLikeEmail = RegExp(r'@');
  static final RegExp _looksLikePhone = RegExp(r'\d{7,}');

  /// 3–30 chars of letters, digits, space, `_`, `-`, `.`; never an email or a
  /// phone number (a display name is public; those are contact details).
  static String validateDisplayName(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.length < CommunityLimits.displayNameMin) {
      throw const CommunityValidationException('display_name', 'min_length');
    }
    if (trimmed.length > CommunityLimits.displayNameMax) {
      throw const CommunityValidationException('display_name', 'max_length');
    }
    if (_looksLikeEmail.hasMatch(trimmed) ||
        _looksLikePhone.hasMatch(trimmed.replaceAll(' ', ''))) {
      throw const CommunityValidationException('display_name', 'contact_info');
    }
    if (!_allowed.hasMatch(trimmed)) {
      throw const CommunityValidationException('display_name', 'charset');
    }
    return trimmed;
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
