import 'package:flutter/foundation.dart';

import 'community_json.dart';

/// In-app notification kinds (§11, §13). Push is out of scope. An unknown
/// `type` means **skip the item** ([CommunityNotification.tryFromJson]).
enum CommunityNotificationType {
  replyToPost,
  commentReply,
  moderationNotice;

  String get wire => snakeCase(name);
}

/// Detail for a [CommunityNotificationType.moderationNotice] (§11, §13).
/// [unrecognised] is client-only: an unknown value shows a generic notice.
enum ModerationNotice {
  contentHidden,
  contentRemoved,
  contentRestored,
  accountRestricted,
  accountSuspended,
  accountReinstated,
  verificationUpdated,
  unrecognised;

  String get wire => snakeCase(name);
}

/// Named `CommunityNotification` to avoid clashing with Flutter's
/// `Notification`. Carries no actor id, no other member's text and no
/// moderator reason (§11).
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

  /// Strict parse; throws on an unknown `type`.
  factory CommunityNotification.fromJson(Map<String, dynamic> json) {
    final CommunityNotification? n = tryFromJson(json);
    if (n == null) throw const FormatException('unknown notification type');
    return n;
  }

  /// Returns null for an unknown `type` (the client skips the item, §13);
  /// throws on any other malformation.
  static CommunityNotification? tryFromJson(Map<String, dynamic> json) {
    rejectIdentityKeys(json);
    final CommunityNotificationType? type = enumFromWire(
      readString(json, 'type'),
      CommunityNotificationType.values,
      (CommunityNotificationType t) => t.wire,
    );
    final String? rawNotice = readNullableString(json, 'notice');
    final String id = readString(json, 'id');
    final String? postId = readNullableString(json, 'post_id');
    final String? commentId = readNullableString(json, 'comment_id');
    final DateTime createdAt = readTime(json, 'created_at');
    final DateTime? readAt = readNullableTime(json, 'read_at');
    if (type == null) return null;
    ModerationNotice? notice;
    if (type == CommunityNotificationType.moderationNotice) {
      if (rawNotice == null) {
        throw const FormatException('moderation_notice needs a notice');
      }
      notice =
          enumFromWire(
            rawNotice,
            ModerationNotice.values
                .where(
                  (ModerationNotice n) => n != ModerationNotice.unrecognised,
                )
                .toList(),
            (ModerationNotice n) => n.wire,
          ) ??
          ModerationNotice.unrecognised;
    } else if (rawNotice != null) {
      throw const FormatException('notice is only valid on moderation_notice');
    }
    return CommunityNotification(
      id: id,
      type: type,
      postId: postId,
      commentId: commentId,
      notice: notice,
      createdAt: createdAt,
      readAt: readAt,
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
          case ModerationNotice.contentRestored:
            return 'A moderator restored some of your content';
          case ModerationNotice.accountRestricted:
            return 'Your account can read but not post for now';
          case ModerationNotice.accountSuspended:
            return 'Your account has been suspended';
          case ModerationNotice.accountReinstated:
            return 'Your account has been reinstated';
          case ModerationNotice.verificationUpdated:
            return 'Your professional verification was updated';
          case ModerationNotice.unrecognised:
            return 'A moderator updated something on your account';
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
      'notice': notice?.wire,
      'created_at': wireTime(createdAt),
      'read_at': readAt == null ? null : wireTime(readAt!),
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
