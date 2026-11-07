import 'package:flutter/foundation.dart';

import 'community_json.dart';
import 'community_permissions.dart';
import 'community_validation.dart';

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
  verifyProfessional,
  revokeProfessional;

  String get wire => snakeCase(name);

  /// The capability an actor needs to take this action.
  CommunityCapability get requires {
    switch (this) {
      case ModerationActionType.dismissReport:
        return CommunityCapability.viewReportsQueue;
      case ModerationActionType.revealIdentity:
        return CommunityCapability.revealIdentity;
      case ModerationActionType.hideContent:
      case ModerationActionType.restoreContent:
        return CommunityCapability.hideContent;
      case ModerationActionType.removeContent:
        return CommunityCapability.removeContent;
      case ModerationActionType.restrictAccount:
        return CommunityCapability.restrictAccount;
      case ModerationActionType.suspendAccount:
      case ModerationActionType.reinstateAccount:
        return CommunityCapability.suspendAccount;
      case ModerationActionType.changeRole:
        return CommunityCapability.changeRole;
      case ModerationActionType.verifyProfessional:
      case ModerationActionType.revokeProfessional:
        return CommunityCapability.verifyProfessional;
    }
  }
}

enum ModerationTargetType {
  post,
  comment,
  account,
  report;

  String get wire => name;
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

/// One row of the append-only audit log, as recorded by the server.
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
      'created_at': createdAt.toUtc().toIso8601String(),
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

/// The accountable identity behind content. **Moderator-only DTO**, returned
/// only by the audited reveal endpoint.
@immutable
class AccountableIdentity {
  const AccountableIdentity({
    required this.accountId,
    required this.displayName,
    required this.status,
  });

  factory AccountableIdentity.fromJson(Map<String, dynamic> json) {
    return AccountableIdentity(
      accountId: readString(json, 'account_id'),
      displayName: readOptionalString(json, 'display_name'),
      status: CommunityPermissions.statusFromWire(json['status'] as String?),
    );
  }

  final String accountId;
  final String? displayName;
  final AccountStatus status;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'account_id': accountId,
      'display_name': displayName,
      'status': status.wire,
    };
  }
}
