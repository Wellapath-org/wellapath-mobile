import 'package:flutter/foundation.dart';

import 'community_json.dart';
import 'community_validation.dart';
import 'public_author.dart';
import 'space.dart';

/// A validated, text-only post about to be sent. No title, no attachments.
@immutable
class PostDraft {
  PostDraft({
    required this.spaceId,
    required String body,
    required this.displayMode,
  }) : body = validateBody(
         body,
         field: 'body',
         max: CommunityLimits.postBodyMax,
       );

  final SpaceId spaceId;
  final String body;
  final DisplayMode displayMode;

  /// The `PostCreate` body (API contract §6). The space travels in the path.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'body': body, 'display_mode': displayMode.wire};
  }
}

/// A post as a member sees it (member DTO). No author account id.
@immutable
class Post {
  const Post({
    required this.id,
    required this.spaceId,
    required this.body,
    required this.author,
    required this.viewerIsAuthor,
    required this.status,
    required this.commentCount,
    required this.createdAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    rejectIdentityKeys(json);
    final String body = readString(json, 'body');
    if (body.trim().isEmpty) throw const FormatException('empty post body');
    return Post(
      id: readString(json, 'id'),
      spaceId: readEnum(
        json,
        'space_id',
        SpaceId.values,
        (SpaceId s) => s.wire,
      ),
      body: body,
      author: PublicAuthor.fromJson(readObject(json, 'author')),
      viewerIsAuthor: readBool(json, 'viewer_is_author'),
      status: readEnum(
        json,
        'status',
        ContentStatus.values,
        (ContentStatus s) => s.wire,
      ),
      commentCount: readInt(json, 'comment_count'),
      createdAt: readTime(json, 'created_at'),
    );
  }

  final String id;
  final SpaceId spaceId;
  final String body;
  final PublicAuthor author;

  /// Whether the signed-in viewer wrote this. Enables delete-own without the
  /// payload ever naming the author's account.
  final bool viewerIsAuthor;
  final ContentStatus status;
  final int commentCount;
  final DateTime createdAt;

  Post copyWith({ContentStatus? status, int? commentCount}) {
    return Post(
      id: id,
      spaceId: spaceId,
      body: body,
      author: author,
      viewerIsAuthor: viewerIsAuthor,
      status: status ?? this.status,
      commentCount: commentCount ?? this.commentCount,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'space_id': spaceId.wire,
      'body': body,
      'author': author.toJson(),
      'viewer_is_author': viewerIsAuthor,
      'status': status.wire,
      'comment_count': commentCount,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is Post &&
        other.id == id &&
        other.spaceId == spaceId &&
        other.body == body &&
        other.author == author &&
        other.viewerIsAuthor == viewerIsAuthor &&
        other.status == status &&
        other.commentCount == commentCount &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    spaceId,
    body,
    author,
    viewerIsAuthor,
    status,
    commentCount,
    createdAt,
  );
}
