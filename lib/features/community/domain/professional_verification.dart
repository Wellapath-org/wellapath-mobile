import 'package:flutter/foundation.dart';

import 'community_ids.dart';
import 'community_json.dart';
import 'community_validation.dart';

/// Verification lifecycle (contract §7.1, §13). Only an admin action on the
/// server moves a claim to [verified]; nothing on the client can construct a
/// verified record except by parsing a server response.
///
/// "Unverified" is **not** a wire value: it is the absence of a record
/// (§15 row 42). [unrecognised] is client-only: an unknown wire value is
/// treated as not verified, with no badge (§13).
enum VerificationStatus {
  pending,
  verified,
  revoked,
  unrecognised;

  String get wire => name;
}

/// What a member sends to claim a profession (`POST
/// /v1/community/me/professional-claim`). It has no status field at all: a
/// self-declared profession is never treated as verified, and sending a
/// `status` would be rejected by the server as `unknown_field`.
@immutable
class ProfessionalClaim {
  ProfessionalClaim({
    required String profession,
    String? specialty,
    String? idempotencyKey,
  }) : idempotencyKey = idempotencyKey ?? newUuidV4(),
       profession = validateBody(
         profession,
         field: 'profession',
         min: CommunityLimits.professionMin,
         max: CommunityLimits.professionMax,
       ),
       specialty = validateOptionalText(
         specialty,
         field: 'specialty',
         min: CommunityLimits.professionMin,
         max: CommunityLimits.professionMax,
       );

  final String profession;
  final String? specialty;

  /// One claim is one intent; retries reuse the key (§1.2, required on M5).
  final String idempotencyKey;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'profession': profession,
      if (specialty != null) 'specialty': specialty,
    };
  }
}

/// The member's own view of their claim (`ProfessionalVerification`).
@immutable
class ProfessionalVerification {
  const ProfessionalVerification._({
    required this.id,
    required this.profession,
    required this.specialty,
    required this.status,
    required this.verifiedAt,
    required this.createdAt,
  });

  /// A just-filed claim: always pending (used by the in-memory backend).
  factory ProfessionalVerification.pending({
    required String id,
    required String profession,
    required String? specialty,
    required DateTime createdAt,
  }) {
    return ProfessionalVerification._(
      id: id,
      profession: profession,
      specialty: specialty,
      status: VerificationStatus.pending,
      verifiedAt: null,
      createdAt: createdAt.toUtc(),
    );
  }

  /// Parses a server record. `verified_at` must be present iff verified, so
  /// a payload claiming `verified` without the server's timestamp is
  /// rejected.
  factory ProfessionalVerification.fromJson(Map<String, dynamic> json) {
    final String rawStatus = readString(json, 'status');
    final VerificationStatus status =
        enumFromWire(rawStatus, const <VerificationStatus>[
          VerificationStatus.pending,
          VerificationStatus.verified,
          VerificationStatus.revoked,
        ], (VerificationStatus s) => s.wire) ??
        VerificationStatus.unrecognised;
    final DateTime? verifiedAt = readNullableTime(json, 'verified_at');
    if (status != VerificationStatus.unrecognised &&
        (status == VerificationStatus.verified) != (verifiedAt != null)) {
      throw const FormatException('verified_at must be set iff verified');
    }
    return ProfessionalVerification._(
      id: readString(json, 'id'),
      profession: readString(json, 'profession'),
      specialty: readNullableString(json, 'specialty'),
      status: status,
      verifiedAt: verifiedAt,
      createdAt: readTime(json, 'created_at'),
    );
  }

  final String id;
  final String profession;
  final String? specialty;
  final VerificationStatus status;
  final DateTime? verifiedAt;
  final DateTime createdAt;

  /// A badge is shown only for an admin-verified record.
  bool get showsBadge => status == VerificationStatus.verified;

  /// A pending or verified claim blocks a new one (409 `claim_exists`).
  bool get isActive =>
      status == VerificationStatus.pending ||
      status == VerificationStatus.verified;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'profession': profession,
      'specialty': specialty,
      'status': status.wire,
      'verified_at': verifiedAt == null ? null : wireTime(verifiedAt!),
      'created_at': wireTime(createdAt),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ProfessionalVerification &&
        other.id == id &&
        other.profession == profession &&
        other.specialty == specialty &&
        other.status == status &&
        other.verifiedAt == verifiedAt &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, profession, specialty, status, verifiedAt, createdAt);
}

/// The public `Badge` carried on a named author. Present only when verified.
@immutable
class ProfessionalBadge {
  const ProfessionalBadge({required this.profession, this.specialty});

  factory ProfessionalBadge.fromJson(Map<String, dynamic> json) {
    return ProfessionalBadge(
      profession: readString(json, 'profession'),
      specialty: readNullableString(json, 'specialty'),
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
