/// The real Community API over Dio (`CommunityHttpClient`). Every method is
/// one contract operation; the client handles auth, errors, the kill switch
/// and the prohibited-key guard.
library;

import '../domain/comment.dart';
import '../domain/community_me.dart';
import '../domain/community_notification.dart';
import '../domain/community_profile.dart';
import '../domain/community_validation.dart';
import '../domain/post.dart';
import '../domain/professional_verification.dart';
import '../domain/report.dart';
import '../domain/space.dart';
import 'community_http_client.dart';
import 'community_repositories.dart';

class HttpCommunityRepository
    implements
        CommunityRepository,
        NotificationRepository,
        DataRightsRepository {
  HttpCommunityRepository(this._client);

  final CommunityHttpClient _client;

  Map<String, dynamic> _page(String? cursor, int limit) {
    return <String, dynamic>{
      'limit': CommunityPaging.checkLimit(limit),
      'cursor': ?cursor,
    };
  }

  Future<CommunityResponse> _get(
    String template, {
    Map<String, String> params = const <String, String>{},
    Map<String, dynamic>? query,
    bool closesOn404 = false,
  }) {
    return _client.send(
      CommunityRequest(
        method: 'GET',
        template: template,
        pathParams: params,
        query: query,
        notFoundClosesCommunity: closesOn404,
      ),
    );
  }

  /// A 404 that only means "nothing here yet" (M2, M4).
  Future<T?> _orNullOn404<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on CommunityException catch (e) {
      if (e.code == CommunityErrorCode.notFound) return null;
      rethrow;
    }
  }

  // ---- self ----------------------------------------------------------------

  @override
  Future<CommunityMe> getMe() async {
    final CommunityResponse r = await _get('/v1/community/me');
    return CommunityMe.fromJson(r.json);
  }

  @override
  Future<CommunityProfile?> getProfile() {
    return _orNullOn404(() async {
      final CommunityResponse r = await _get('/v1/community/me/profile');
      return CommunityProfile.fromJson(r.json);
    });
  }

  @override
  Future<CommunityProfile> setDisplayName(String displayName) async {
    final CommunityResponse r = await _client.send(
      CommunityRequest(
        method: 'PUT',
        template: '/v1/community/me/profile',
        body: CommunityProfile.updateBody(displayName),
      ),
    );
    return CommunityProfile.fromJson(r.json);
  }

  @override
  Future<ProfessionalVerification?> getProfessionalClaim() {
    return _orNullOn404(() async {
      final CommunityResponse r = await _get(
        '/v1/community/me/professional-claim',
      );
      return ProfessionalVerification.fromJson(r.json);
    });
  }

  @override
  Future<ProfessionalVerification> claimProfession(
    ProfessionalClaim claim,
  ) async {
    final CommunityResponse r = await _client.send(
      CommunityRequest(
        method: 'POST',
        template: '/v1/community/me/professional-claim',
        body: claim.toJson(),
        idempotencyKey: claim.idempotencyKey,
      ),
    );
    final ProfessionalVerification v = ProfessionalVerification.fromJson(
      r.json,
    );
    if (v.status != VerificationStatus.pending) {
      throw const FormatException('a new claim must be pending');
    }
    return v;
  }

  @override
  Future<void> withdrawProfessionalClaim() async {
    await _client.send(
      const CommunityRequest(
        method: 'DELETE',
        template: '/v1/community/me/professional-claim',
      ),
    );
  }

  // ---- data rights -----------------------------------------------------------

  @override
  Future<Map<String, dynamic>> exportMyData() async {
    final CommunityResponse r = await _get('/v1/community/me/export');
    return checkExportDocument(r.json);
  }

  @override
  Future<void> deleteMyAccount(String confirmPhrase) async {
    if (confirmPhrase != CommunityLimits.deleteAccountPhrase) {
      throw const CommunityValidationException('confirm', 'not_allowed_value');
    }
    await _client.send(
      CommunityRequest(
        method: 'POST',
        template: '/v1/community/me/delete',
        body: <String, dynamic>{'confirm': confirmPhrase},
      ),
    );
  }

  // ---- spaces, posts, comments ----------------------------------------------

  @override
  Future<List<Space>> listSpaces() async {
    final CommunityResponse r = await _get(
      '/v1/community/spaces',
      closesOn404: true,
    );
    return Space.listFromJson(r.json);
  }

  @override
  Future<CommunityPage<Post>> listPosts(
    SpaceId space, {
    String? cursor,
    int limit = CommunityPaging.defaultLimit,
  }) async {
    final CommunityResponse r = await _get(
      '/v1/community/spaces/{space_id}/posts',
      params: <String, String>{'space_id': space.wire},
      query: _page(cursor, limit),
      closesOn404: true,
    );
    return CommunityPage<Post>.fromJson(r.json, Post.fromJson);
  }

  @override
  Future<Post> getPost(String postId) async {
    final CommunityResponse r = await _get(
      '/v1/community/posts/{post_id}',
      params: <String, String>{'post_id': postId},
    );
    return Post.fromJson(r.json);
  }

  @override
  Future<Post> createPost(PostDraft draft) async {
    final CommunityResponse r = await _client.send(
      CommunityRequest(
        method: 'POST',
        template: '/v1/community/spaces/{space_id}/posts',
        pathParams: <String, String>{'space_id': draft.spaceId.wire},
        body: draft.toJson(),
        idempotencyKey: draft.idempotencyKey,
      ),
    );
    return Post.fromJson(r.json);
  }

  @override
  Future<void> deletePost(String postId) async {
    await _client.send(
      CommunityRequest(
        method: 'DELETE',
        template: '/v1/community/posts/{post_id}',
        pathParams: <String, String>{'post_id': postId},
      ),
    );
  }

  @override
  Future<CommunityPage<Comment>> listComments(
    String postId, {
    String? cursor,
    int limit = CommunityPaging.defaultLimit,
  }) async {
    // A 404 here means the post is not visible, not that Community is off
    // (see the deliverable's proposed contract clarification).
    final CommunityResponse r = await _get(
      '/v1/community/posts/{post_id}/comments',
      params: <String, String>{'post_id': postId},
      query: _page(cursor, limit),
    );
    return CommunityPage<Comment>.fromJson(r.json, Comment.fromJson);
  }

  @override
  Future<Comment> createComment(CommentDraft draft) async {
    final CommunityResponse r = await _client.send(
      CommunityRequest(
        method: 'POST',
        template: '/v1/community/posts/{post_id}/comments',
        pathParams: <String, String>{'post_id': draft.postId},
        body: draft.toJson(),
        idempotencyKey: draft.idempotencyKey,
      ),
    );
    return Comment.fromJson(r.json);
  }

  @override
  Future<void> deleteComment(String commentId) async {
    await _client.send(
      CommunityRequest(
        method: 'DELETE',
        template: '/v1/community/comments/{comment_id}',
        pathParams: <String, String>{'comment_id': commentId},
      ),
    );
  }

  @override
  Future<ReportCreated> submitReport(ReportDraft draft) async {
    final CommunityResponse r = await _client.send(
      CommunityRequest(
        method: 'POST',
        template: '/v1/community/reports',
        body: draft.toJson(),
        idempotencyKey: draft.idempotencyKey,
      ),
    );
    return ReportCreated.fromJson(r.json);
  }

  // ---- notifications ---------------------------------------------------------

  @override
  Future<NotificationPage<CommunityNotification>> list({
    String? cursor,
    int limit = CommunityPaging.defaultLimit,
  }) async {
    final CommunityResponse r = await _get(
      '/v1/community/notifications',
      query: _page(cursor, limit),
      closesOn404: true,
    );
    final Map<String, dynamic> json = r.json;
    final CommunityPage<CommunityNotification> page =
        CommunityPage<CommunityNotification>.fromJson(
          json,
          CommunityNotification.tryFromJson,
        );
    final Object? unread = json['unread_count'];
    if (unread is! int || unread < 0) {
      throw const FormatException('bad unread_count');
    }
    return NotificationPage<CommunityNotification>(
      items: page.items,
      nextCursor: page.nextCursor,
      unreadCount: unread,
    );
  }

  @override
  Future<int> unreadCount() async {
    final CommunityResponse r = await _get(
      '/v1/community/notifications/unread-count',
      closesOn404: true,
    );
    final Object? unread = r.json['unread_count'];
    if (unread is! int || unread < 0) {
      throw const FormatException('bad unread_count');
    }
    return unread;
  }

  @override
  Future<void> markRead(String notificationId) async {
    await _client.send(
      CommunityRequest(
        method: 'POST',
        template: '/v1/community/notifications/{notification_id}/read',
        pathParams: <String, String>{'notification_id': notificationId},
      ),
    );
  }

  @override
  Future<void> markAllRead() async {
    await _client.send(
      const CommunityRequest(
        method: 'POST',
        template: '/v1/community/notifications/read-all',
      ),
    );
  }
}
