import 'package:flutter/foundation.dart';

import 'community_json.dart';
import 'community_permissions.dart';
import 'community_validation.dart';

/// Moderation and admin action types (§13 `ModerationActionType`).
///
/// **The mobile app sends none of these.** Moderation and verification live
/// in the website admin; these types exist so the in-memory test backend can
/// put content and accounts into the states the app must handle (404 for
/// non-visible content, restricted, suspended, verified badges).
enum ModerationActionType {
  dismissReport,
  revealIdentity,
  hideContent,
  restoreContent,
  removeContent,
  restrictAccount,
  suspendAccount,
  reinstateAccount,
  changeRole,
  resetTotp,
  verifyProfessional,
  revokeProfessional,
  withdrawProfessional,
  deleteAccount;

  String get wire => snakeCase(name);

  /// The capability an actor needs to take this action, or null for the
  /// user-originated actions (withdraw own claim, delete own account).
  /// Account actions on a moderator/admin target additionally need
  /// [CommunityCapability.restrictSuspendReinstatePrivileged].
  CommunityCapability? get requires {
    switch (this) {
      case ModerationActionType.dismissReport:
        return CommunityCapability.viewReportQueue;
      case ModerationActionType.revealIdentity:
        return CommunityCapability.revealIdentity;
      case ModerationActionType.hideContent:
      case ModerationActionType.restoreContent:
      case ModerationActionType.removeContent:
        return CommunityCapability.moderateContent;
      case ModerationActionType.restrictAccount:
      case ModerationActionType.suspendAccount:
      case ModerationActionType.reinstateAccount:
        return CommunityCapability.restrictSuspendReinstateMember;
      case ModerationActionType.changeRole:
        return CommunityCapability.changeRole;
      case ModerationActionType.resetTotp:
        return CommunityCapability.resetTotp;
      case ModerationActionType.verifyProfessional:
      case ModerationActionType.revokeProfessional:
        return CommunityCapability.verifyProfessional;
      case ModerationActionType.withdrawProfessional:
      case ModerationActionType.deleteAccount:
        return null;
    }
  }
}

/// §13 `ModerationTargetType`.
enum ModerationTargetType {
  post,
  comment,
  account,
  report,
  professionalVerification;

  String get wire => snakeCase(name);
}

/// A moderation request as the client sends it: action, target and a
/// mandatory reason. No actor and no timestamp — the server records both.
@immutable
class ModerationRequest {
  ModerationRequest({
    required this.action,
    required this.targetType,
    required this.targetId,
    required String reason,
  }) : reason = validateModerationReason(reason);

  final ModerationActionType action;
  final ModerationTargetType targetType;
  final String targetId;
  final String reason;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'target_type': targetType.wire,
      'target_id': targetId,
      'reason': reason,
    };
  }
}

/// One row of the append-only audit log, as recorded by the server. `id` is
/// a decimal string (bigserial serialised, §1).
@immutable
class ModerationAction {
  const ModerationAction({
    required this.id,
    required this.actorAccountId,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.createdAt,
  });

  factory ModerationAction.fromJson(Map<String, dynamic> json) {
    final String reason = readString(json, 'reason');
    if (reason.trim().isEmpty) {
      throw const FormatException('moderation action without a reason');
    }
    return ModerationAction(
      id: readString(json, 'id'),
      actorAccountId: readString(json, 'actor_account_id'),
      action: readEnum(
        json,
        'action',
        ModerationActionType.values,
        (ModerationActionType a) => a.wire,
      ),
      targetType: readEnum(
        json,
        'target_type',
        ModerationTargetType.values,
        (ModerationTargetType t) => t.wire,
      ),
      targetId: readString(json, 'target_id'),
      reason: reason,
      createdAt: readTime(json, 'created_at'),
    );
  }

  final String id;
  final String actorAccountId;
  final ModerationActionType action;
  final ModerationTargetType targetType;
  final String targetId;
  final String reason;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'actor_account_id': actorAccountId,
      'action': action.wire,
      'target_type': targetType.wire,
      'target_id': targetId,
      'reason': reason,
      'created_at': wireTime(createdAt),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ModerationAction &&
        other.id == id &&
        other.actorAccountId == actorAccountId &&
        other.action == action &&
        other.targetType == targetType &&
        other.targetId == targetId &&
        other.reason == reason &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    actorAccountId,
    action,
    targetType,
    targetId,
    reason,
    createdAt,
  );
}

/// The accountable identity behind content (§12.1). **Moderator-only DTO**,
/// returned only by the audited reveal endpoint, which the app never calls.
/// Email is never part of it.
@immutable
class AccountableIdentity {
  const AccountableIdentity({
    required this.accountId,
    required this.displayName,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.priorModerationActions,
    required this.revealActionId,
  });

  factory AccountableIdentity.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('email')) {
      throw const FormatException('identity reveal never carries an email');
    }
    return AccountableIdentity(
      accountId: readString(json, 'account_id'),
      displayName: readNullableString(json, 'display_name'),
      role: CommunityPermissions.roleFromWire(json['role'] as String?),
      status: CommunityPermissions.statusFromWire(json['status'] as String?),
      createdAt: readTime(json, 'created_at'),
      priorModerationActions: readInt(json, 'prior_moderation_actions'),
      revealActionId: readString(json, 'reveal_action_id'),
    );
  }

  final String accountId;
  final String? displayName;
  final CommunityRole role;
  final AccountStatus status;
  final DateTime createdAt;
  final int priorModerationActions;
  final String revealActionId;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'account_id': accountId,
      'display_name': displayName,
      'role': role.wire,
      'status': status.wire,
      'created_at': wireTime(createdAt),
      'prior_moderation_actions': priorModerationActions,
      'reveal_action_id': revealActionId,
    };
  }
}
