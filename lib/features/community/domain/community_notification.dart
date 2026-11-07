import 'package:flutter/foundation.dart';

import 'community_json.dart';

/// In-app notification kinds (API contract §9). Push is deferred.
enum CommunityNotificationType {
  replyToPost,
  commentReply,
  moderationNotice;

  String get wire => snakeCase(name);
}

/// Detail for a [CommunityNotificationType.moderationNotice].
enum ModerationNotice {
  contentHidden,
  contentRemoved,
  accountRestricted,
  accountSuspended,
  verificationUpdated;

  String get wire => snakeCase(name);
}

/// Named `CommunityNotification` to avoid clashing with Flutter's
/// `Notification`. Carries no actor identity and no other member's text.
@immutable
class CommunityNotification {
  const CommunityNotification({
    required this.id,
    required this.type,
    required this.createdAt,
    this.postId,
    this.commentId,
    this.notice,
    this.readAt,
  });

  factory CommunityNotification.fromJson(Map<String, dynamic> json) {
    rejectIdentityKeys(json);
    final CommunityNotificationType type = readEnum(
      json,
      'type',
      CommunityNotificationType.values,
      (CommunityNotificationType t) => t.wire,
    );
    ModerationNotice? notice;
    if (type == CommunityNotificationType.moderationNotice) {
      notice = readEnum(
        json,
        'notice',
        ModerationNotice.values,
        (ModerationNotice n) => n.wire,
      );
    } else if (json['notice'] != null) {
      throw const FormatException('notice is only valid on moderation_notice');
    }
    return CommunityNotification(
      id: readString(json, 'id'),
      type: type,
      postId: readOptionalString(json, 'post_id'),
      commentId: readOptionalString(json, 'comment_id'),
      notice: notice,
      createdAt: readTime(json, 'created_at'),
      readAt: readOptionalTime(json, 'read_at'),
    );
  }

  final String id;
  final CommunityNotificationType type;
  final String? postId;
  final String? commentId;
  final ModerationNotice? notice;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  /// Neutral one-line summary for the notification centre.
  String get summary {
    switch (type) {
      case CommunityNotificationType.replyToPost:
        return 'Someone commented on your post';
      case CommunityNotificationType.commentReply:
        return 'New comment on a post you commented on';
      case CommunityNotificationType.moderationNotice:
        switch (notice!) {
          case ModerationNotice.contentHidden:
            return 'A moderator hid some of your content';
          case ModerationNotice.contentRemoved:
            return 'A moderator removed some of your content';
          case ModerationNotice.accountRestricted:
            return 'Your account can read but not post for now';
          case ModerationNotice.accountSuspended:
            return 'Your account has been suspended';
          case ModerationNotice.verificationUpdated:
            return 'Your professional verification was updated';
        }
    }
  }

  CommunityNotification markRead(DateTime at) {
    return CommunityNotification(
      id: id,
      type: type,
      postId: postId,
      commentId: commentId,
      notice: notice,
      createdAt: createdAt,
      readAt: readAt ?? at.toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.wire,
      'post_id': postId,
      'comment_id': commentId,
      if (notice != null) 'notice': notice!.wire,
      'created_at': createdAt.toUtc().toIso8601String(),
      'read_at': readAt?.toUtc().toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is CommunityNotification &&
        other.id == id &&
        other.type == type &&
        other.postId == postId &&
        other.commentId == commentId &&
        other.notice == notice &&
        other.createdAt == createdAt &&
        other.readAt == readAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, type, postId, commentId, notice, createdAt, readAt);
}
