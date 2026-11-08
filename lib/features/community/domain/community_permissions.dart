/// The Community capability matrix as code (contract §2.1 and §2.2).
///
/// The server is authoritative and enforces this on every route. The client
/// mirrors it only to decide what to *offer*; hiding a button is never the
/// security boundary. The app has **no privileged UI**: moderation and
/// verification live in the website admin (`/v1/community/mod/*` and
/// `/v1/community/admin/*`), so the privileged rows below are used only by
/// the in-memory test backend.
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
  // Member rows (§2.1).
  readContent,
  readOwnNotifications,
  createContent,
  deleteOwnContent,
  reportContent,
  setProfile,
  claimProfession,
  exportOwnData,
  deleteOwnAccount,
  // Privileged rows (website admin only; TOTP step-up required).
  viewReportQueue,
  revealIdentity,
  moderateContent,
  restrictSuspendReinstateMember,
  restrictSuspendReinstatePrivileged,
  viewAuditLog,
  verifyProfessional,
  changeRole,
  resetTotp,
}

abstract final class CommunityPermissions {
  static const Set<CommunityCapability> _memberBase = {
    CommunityCapability.readContent,
    CommunityCapability.readOwnNotifications,
    CommunityCapability.createContent,
    CommunityCapability.deleteOwnContent,
    CommunityCapability.reportContent,
    CommunityCapability.setProfile,
    CommunityCapability.claimProfession,
    // M7: export is "any role", not allowlist-gated.
    CommunityCapability.exportOwnData,
  };

  static const Set<CommunityCapability> _member = {
    ..._memberBase,
    // M8: a moderator or admin must be demoted first (422
    // `privileged_account`).
    CommunityCapability.deleteOwnAccount,
  };

  static const Set<CommunityCapability> _moderator = {
    ..._memberBase,
    CommunityCapability.viewReportQueue,
    CommunityCapability.revealIdentity,
    CommunityCapability.moderateContent,
    // §15 row 49: moderators restrict, suspend and reinstate members.
    CommunityCapability.restrictSuspendReinstateMember,
    CommunityCapability.viewAuditLog,
  };

  static const Set<CommunityCapability> _admin = {
    ..._moderator,
    CommunityCapability.restrictSuspendReinstatePrivileged,
    CommunityCapability.verifyProfessional,
    CommunityCapability.changeRole,
    CommunityCapability.resetTotp,
  };

  /// What a restricted (read-only) account keeps (§2.2): reading,
  /// **reporting** (a safety exception, §15 row 37), notifications, deleting
  /// its own content (§8.2 C5), export and deletion.
  static const Set<CommunityCapability> restrictedKeeps = {
    CommunityCapability.readContent,
    CommunityCapability.readOwnNotifications,
    CommunityCapability.reportContent,
    CommunityCapability.deleteOwnContent,
    CommunityCapability.exportOwnData,
    CommunityCapability.deleteOwnAccount,
  };

  /// The full matrix, by role.
  static const Map<CommunityRole, Set<CommunityCapability>> matrix = {
    CommunityRole.member: _member,
    CommunityRole.moderator: _moderator,
    CommunityRole.admin: _admin,
  };

  /// Whether [role] in [status] holds [capability].
  static bool can(
    CommunityRole role,
    CommunityCapability capability, {
    AccountStatus status = AccountStatus.active,
  }) {
    if (!matrix[role]!.contains(capability)) return false;
    switch (status) {
      case AccountStatus.suspended:
        return false;
      case AccountStatus.restricted:
        return restrictedKeeps.contains(capability);
      case AccountStatus.active:
        return true;
    }
  }

  /// Parses a wire role; anything unrecognised is the least-privileged role
  /// (§13).
  static CommunityRole roleFromWire(String? raw) {
    return enumFromWire(
          raw,
          CommunityRole.values,
          (CommunityRole r) => r.wire,
        ) ??
        CommunityRole.member;
  }

  /// Parses a wire status; anything unrecognised is treated as suspended
  /// (fail closed, §13).
  static AccountStatus statusFromWire(String? raw) {
    return enumFromWire(
          raw,
          AccountStatus.values,
          (AccountStatus s) => s.wire,
        ) ??
        AccountStatus.suspended;
  }
}
