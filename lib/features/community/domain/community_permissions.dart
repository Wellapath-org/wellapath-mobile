/// The Community role/capability matrix as code (API contract §11.1).
///
/// The server is authoritative and enforces this on every route. The client
/// mirrors it only to decide what to *offer*; hiding a button is never the
/// security boundary.
library;

import 'community_json.dart';

enum CommunityRole {
  member,
  moderator,
  admin;

  String get wire => name;
}

enum AccountStatus {
  active,
  restricted,
  suspended;

  String get wire => name;
}

enum CommunityCapability {
  readContent,
  createContent,
  deleteOwnContent,
  reportContent,
  claimProfession,
  viewReportsQueue,
  revealIdentity,
  hideContent,
  removeContent,
  restrictAccount,
  viewAuditLog,
  suspendAccount,
  verifyProfessional,
  changeRole,
}

abstract final class CommunityPermissions {
  static const Set<CommunityCapability> _member = {
    CommunityCapability.readContent,
    CommunityCapability.createContent,
    CommunityCapability.deleteOwnContent,
    CommunityCapability.reportContent,
    CommunityCapability.claimProfession,
  };

  static const Set<CommunityCapability> _moderator = {
    ..._member,
    CommunityCapability.viewReportsQueue,
    CommunityCapability.revealIdentity,
    CommunityCapability.hideContent,
    CommunityCapability.removeContent,
    CommunityCapability.restrictAccount,
    CommunityCapability.viewAuditLog,
  };

  static const Set<CommunityCapability> _admin = {
    ..._moderator,
    CommunityCapability.suspendAccount,
    CommunityCapability.verifyProfessional,
    CommunityCapability.changeRole,
  };

  /// The full matrix, by role.
  static const Map<CommunityRole, Set<CommunityCapability>> matrix = {
    CommunityRole.member: _member,
    CommunityRole.moderator: _moderator,
    CommunityRole.admin: _admin,
  };

  /// Whether [role] in [status] holds [capability].
  ///
  /// Restricted accounts keep read only; suspended accounts have nothing.
  static bool can(
    CommunityRole role,
    CommunityCapability capability, {
    AccountStatus status = AccountStatus.active,
  }) {
    switch (status) {
      case AccountStatus.suspended:
        return false;
      case AccountStatus.restricted:
        return capability == CommunityCapability.readContent;
      case AccountStatus.active:
        return matrix[role]!.contains(capability);
    }
  }

  /// Parses a wire role; anything unrecognised is the least-privileged role.
  static CommunityRole roleFromWire(String? raw) {
    for (final CommunityRole r in CommunityRole.values) {
      if (r.wire == raw) return r;
    }
    return CommunityRole.member;
  }

  /// Parses a wire status; anything unrecognised is treated as suspended.
  static AccountStatus statusFromWire(String? raw) {
    for (final AccountStatus s in AccountStatus.values) {
      if (s.wire == raw) return s;
    }
    return AccountStatus.suspended;
  }
}

/// The signed-in account, as returned only to itself (`AccountSelf`).
class CommunityViewer {
  const CommunityViewer({
    required this.accountId,
    required this.role,
    this.status = AccountStatus.active,
  });

  factory CommunityViewer.fromJson(Map<String, dynamic> json) {
    return CommunityViewer(
      accountId: readString(json, 'account_id'),
      role: CommunityPermissions.roleFromWire(json['role'] as String?),
      status: CommunityPermissions.statusFromWire(json['status'] as String?),
    );
  }

  final String accountId;
  final CommunityRole role;
  final AccountStatus status;

  bool can(CommunityCapability c) {
    return CommunityPermissions.can(role, c, status: status);
  }
}
