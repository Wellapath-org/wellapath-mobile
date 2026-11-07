import 'package:flutter/foundation.dart';

import 'community_json.dart';
import 'community_validation.dart';
import 'public_author.dart';

/// A validated single-level comment about to be sent. There is no parent
/// comment: replies to comments (nested threads) are out of scope.
@immutable
class CommentDraft {
  CommentDraft({
    required this.postId,
    required String body,
    required this.displayMode,
  }) : body = validateBody(
         body,
         field: 'body',
         max: CommunityLimits.commentBodyMax,
       );

  final String postId;
  final String body;
  final DisplayMode displayMode;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'body': body, 'display_mode': displayMode.wire};
  }
}

/// A comment as a member sees it. No author account id, no parent comment.
@immutable
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.body,
    required this.author,
    required this.viewerIsAuthor,
    required this.status,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    rejectIdentityKeys(json);
    if (json.containsKey('parent_comment_id')) {
      throw const FormatException('comments are single level');
    }
    final String body = readString(json, 'body');
    if (body.trim().isEmpty) throw const FormatException('empty comment body');
    return Comment(
      id: readString(json, 'id'),
      postId: readString(json, 'post_id'),
      body: body,
      author: PublicAuthor.fromJson(readObject(json, 'author')),
      viewerIsAuthor: readBool(json, 'viewer_is_author'),
      status: readEnum(
        json,
        'status',
        ContentStatus.values,
        (ContentStatus s) => s.wire,
      ),
      createdAt: readTime(json, 'created_at'),
    );
  }

  final String id;
  final String postId;
  final String body;
  final PublicAuthor author;
  final bool viewerIsAuthor;
  final ContentStatus status;
  final DateTime createdAt;

  Comment copyWith({ContentStatus? status}) {
    return Comment(
      id: id,
      postId: postId,
      body: body,
      author: author,
      viewerIsAuthor: viewerIsAuthor,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'post_id': postId,
      'body': body,
      'author': author.toJson(),
      'viewer_is_author': viewerIsAuthor,
      'status': status.wire,
      'created_at': createdAt.toUtc().toIso8601String(),
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
        other.status == status &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, postId, body, author, viewerIsAuthor, status, createdAt);
}
