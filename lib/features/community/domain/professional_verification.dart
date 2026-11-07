import 'package:flutter/foundation.dart';

import 'community_json.dart';
import 'community_validation.dart';

/// Verification lifecycle. Only an admin action on the server moves a claim
/// to [verified]; nothing on the client can construct a verified record
/// except by parsing a server response.
enum VerificationStatus {
  unverified,
  pending,
  verified,
  revoked;

  String get wire => name;
}

/// What a member sends to claim a profession. It has no status field at all:
/// a self-declared profession is never treated as verified.
@immutable
class ProfessionalClaim {
  ProfessionalClaim({required String profession, String? specialty})
    : profession = _validateProfession(profession),
      specialty = validateOptionalNote(
        specialty,
        max: CommunityLimits.professionMax,
      );

  final String profession;
  final String? specialty;

  static String _validateProfession(String raw) {
    return validateBody(
      raw,
      field: 'profession',
      max: CommunityLimits.professionMax,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'profession': profession,
      if (specialty != null) 'specialty': specialty,
    };
  }

  /// The record a member holds immediately after claiming: always pending.
  ProfessionalVerification asPending() {
    return ProfessionalVerification._(
      profession: profession,
      specialty: specialty,
      status: VerificationStatus.pending,
      verifiedAt: null,
    );
  }
}

@immutable
class ProfessionalVerification {
  const ProfessionalVerification._({
    required this.profession,
    required this.specialty,
    required this.status,
    required this.verifiedAt,
  });

  /// Parses a server record. `verified_at` must be present iff verified, so a
  /// payload claiming `verified` without the server's timestamp is rejected.
  factory ProfessionalVerification.fromJson(Map<String, dynamic> json) {
    final VerificationStatus status = readEnum(
      json,
      'status',
      VerificationStatus.values,
      (VerificationStatus s) => s.wire,
    );
    final DateTime? verifiedAt = readOptionalTime(json, 'verified_at');
    if ((status == VerificationStatus.verified) != (verifiedAt != null)) {
      throw const FormatException('verified_at must be set iff verified');
    }
    return ProfessionalVerification._(
      profession: readString(json, 'profession'),
      specialty: readOptionalString(json, 'specialty'),
      status: status,
      verifiedAt: verifiedAt,
    );
  }

  final String profession;
  final String? specialty;
  final VerificationStatus status;
  final DateTime? verifiedAt;

  /// A badge is shown only for an admin-verified record.
  bool get showsBadge => status == VerificationStatus.verified;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'profession': profession,
      'specialty': specialty,
      'status': status.wire,
      'verified_at': verifiedAt?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ProfessionalVerification &&
        other.profession == profession &&
        other.specialty == specialty &&
        other.status == status &&
        other.verifiedAt == verifiedAt;
  }

  @override
  int get hashCode => Object.hash(profession, specialty, status, verifiedAt);
}

/// The public badge carried on a named author. Present only when verified.
@immutable
class ProfessionalBadge {
  const ProfessionalBadge({required this.profession, this.specialty});

  factory ProfessionalBadge.fromJson(Map<String, dynamic> json) {
    return ProfessionalBadge(
      profession: readString(json, 'profession'),
      specialty: readOptionalString(json, 'specialty'),
    );
  }

  /// Returns a badge only for a verified record, otherwise null.
  static ProfessionalBadge? fromVerification(ProfessionalVerification? v) {
    if (v == null || !v.showsBadge) return null;
    return ProfessionalBadge(profession: v.profession, specialty: v.specialty);
  }

  final String profession;
  final String? specialty;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'profession': profession, 'specialty': specialty};
  }

  @override
  bool operator ==(Object other) {
    return other is ProfessionalBadge &&
        other.profession == profession &&
        other.specialty == specialty;
  }

  @override
  int get hashCode => Object.hash(profession, specialty);
}
