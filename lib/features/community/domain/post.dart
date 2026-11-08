import 'package:flutter/foundation.dart';

import 'community_ids.dart';
import 'community_json.dart';
import 'community_validation.dart';
import 'public_author.dart';
import 'space.dart';

/// A validated, text-only post about to be sent (`PostCreate`, §8.2 C3).
/// No title, no attachments, no link metadata, no images.
///
/// One draft is one user intent: its [idempotencyKey] is generated once and
/// reused on every retry of the same draft (§1.2).
@immutable
class PostDraft {
  PostDraft({
    required this.spaceId,
    required String body,
    required this.displayMode,
    String? idempotencyKey,
  }) : body = validateBody(
         body,
         field: 'body',
         max: CommunityLimits.postBodyMax,
       ),
       idempotencyKey = idempotencyKey ?? newUuidV4();

  final SpaceId spaceId;
  final String body;
  final DisplayMode displayMode;
  final String idempotencyKey;

  /// The `PostCreate` body. The space travels in the path; the key travels
  /// in the `Idempotency-Key` header.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{'body': body, 'display_mode': displayMode.wire};
  }
}

/// A post as a member sees it (member `Post` DTO). No author account id.
/// Members only ever receive `status: "visible"`, so there is no status
/// field: a non-visible post is a 404, never a payload.
@immutable
class Post {
  const Post({
    required this.id,
    required this.spaceId,
    required this.body,
    required this.author,
    required this.viewerIsAuthor,
    required this.commentCount,
    required this.createdAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    rejectIdentityKeys(json);
    requireMemberVisible(json);
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
      commentCount: readInt(json, 'comment_count', min: 0),
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

  /// Visible comments only.
  final int commentCount;
  final DateTime createdAt;

  Post copyWith({int? commentCount}) {
    return Post(
      id: id,
      spaceId: spaceId,
      body: body,
      author: author,
      viewerIsAuthor: viewerIsAuthor,
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
      'status': kMemberVisibleStatus,
      'comment_count': commentCount,
      'created_at': wireTime(createdAt),
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
    commentCount,
    createdAt,
  );
}
