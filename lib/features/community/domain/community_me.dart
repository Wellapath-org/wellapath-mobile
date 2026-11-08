import 'package:flutter/foundation.dart';

import 'community_json.dart';
import 'community_permissions.dart';
import 'community_profile.dart';

/// `Me` (§7.1): the signed-in account, returned **only to itself**
/// (`GET /v1/community/me`, and inside `TokenPair.account`).
///
/// This is a self DTO: `account_id` and `email` are expected here, so the
/// member identity-key rejection is deliberately **not** applied (§7.1).
/// Neither value is ever logged or shown to anyone but the account holder.
@immutable
class CommunityMe {
  const CommunityMe({
    required this.accountId,
    required this.email,
    required this.role,
    required this.status,
    required this.restrictedUntil,
    required this.twoFactorEnabled,
    required this.communityAllowed,
    required this.createdAt,
    required this.profile,
  });

  factory CommunityMe.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? profile = readNullableObject(json, 'profile');
    requireKey(json, 'role');
    requireKey(json, 'status');
    return CommunityMe(
      accountId: readString(json, 'account_id'),
      email: readString(json, 'email'),
      role: CommunityPermissions.roleFromWire(json['role'] as String?),
      status: CommunityPermissions.statusFromWire(json['status'] as String?),
      restrictedUntil: readNullableTime(json, 'restricted_until'),
      twoFactorEnabled: readBool(json, 'two_factor_enabled'),
      communityAllowed: readBool(json, 'community_allowed'),
      createdAt: readTime(json, 'created_at'),
      profile: profile == null ? null : CommunityProfile.fromJson(profile),
    );
  }

  final String accountId;
  final String email;
  final CommunityRole role;
  final AccountStatus status;
  final DateTime? restrictedUntil;
  final bool twoFactorEnabled;
  final bool communityAllowed;
  final DateTime createdAt;
  final CommunityProfile? profile;

  bool can(CommunityCapability c) {
    return CommunityPermissions.can(role, c, status: status);
  }

  CommunityMe withProfile(CommunityProfile? p) {
    return CommunityMe(
      accountId: accountId,
      email: email,
      role: role,
      status: status,
      restrictedUntil: restrictedUntil,
      twoFactorEnabled: twoFactorEnabled,
      communityAllowed: communityAllowed,
      createdAt: createdAt,
      profile: p,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'account_id': accountId,
      'email': email,
      'role': role.wire,
      'status': status.wire,
      'restricted_until': restrictedUntil == null
          ? null
          : wireTime(restrictedUntil!),
      'two_factor_enabled': twoFactorEnabled,
      'community_allowed': communityAllowed,
      'created_at': wireTime(createdAt),
      'profile': profile?.toJson(),
    };
  }
}
