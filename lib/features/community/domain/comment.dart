import 'package:flutter/foundation.dart';

import 'community_ids.dart';
import 'community_json.dart';
import 'community_validation.dart';
import 'public_author.dart';

/// A validated single-level comment about to be sent (`CommentCreate`,
/// §9 C7). There is no parent comment: replies to comments are out of scope,
/// and a `parent_comment_id` would be rejected as `unknown_field`.
@immutable
class CommentDraft {
  CommentDraft({
    required this.postId,
    required String body,
    required this.displayMode,
    String? idempotencyKey,
  }) : body = validateBody(
         body,
         field: 'body',
         max: CommunityLimits.commentBodyMax,
       ),
       idempotencyKey = idempotencyKey ?? newUuidV4();

  final String postId;
  final String body;
  final DisplayMode displayMode;
  final String idempotencyKey;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'body': body, 'display_mode': displayMode.wire};
  }
}

/// A comment as a member sees it. No author account id, no parent comment,
/// and always visible (a non-visible comment is simply not listed).
@immutable
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.body,
    required this.author,
    required this.viewerIsAuthor,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    rejectIdentityKeys(json);
    if (json.containsKey('parent_comment_id')) {
      throw const FormatException('comments are single level');
    }
    requireMemberVisible(json);
    final String body = readString(json, 'body');
    if (body.trim().isEmpty) throw const FormatException('empty comment body');
    return Comment(
      id: readString(json, 'id'),
      postId: readString(json, 'post_id'),
      body: body,
      author: PublicAuthor.fromJson(readObject(json, 'author')),
      viewerIsAuthor: readBool(json, 'viewer_is_author'),
      createdAt: readTime(json, 'created_at'),
    );
  }

  final String id;
  final String postId;
  final String body;
  final PublicAuthor author;
  final bool viewerIsAuthor;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'post_id': postId,
      'body': body,
      'author': author.toJson(),
      'viewer_is_author': viewerIsAuthor,
      'status': kMemberVisibleStatus,
      'created_at': wireTime(createdAt),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is Comment &&
        other.id == id &&
        other.postId == postId &&
        other.body == body &&
        other.author == author &&
        other.viewerIsAuthor == viewerIsAuthor &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, postId, body, author, viewerIsAuthor, createdAt);
}
