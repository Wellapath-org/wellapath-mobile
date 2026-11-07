/// Repository interfaces for Community. Each method maps 1:1 to a
/// member-facing endpoint in the canonical contract
/// (`WELLAPATH_ENGINEERING/COMMUNITY_API_CONTRACT.md` v1.0-draft; mobile copy
/// of the OpenAPI file in `docs/community/`). An implementation must not add
/// behaviour the contract does not describe.
///
/// Two implementations: `HttpCommunityRepository` (Dio, the real API) and
/// the in-memory backend (tests and local development).
///
/// Deliberately absent: the moderator and admin routes (`/mod/*`,
/// `/admin/*`, TOTP), which live in the website admin; and everything out of
/// scope — private consultations, doctor chat, prescriptions, payments,
/// booking, image or file uploads, link previews, nested threads, AI replies
/// and push notifications.
library;

import '../domain/comment.dart';
import '../domain/community_me.dart';
import '../domain/community_notification.dart';
import '../domain/community_page.dart';
import '../domain/community_profile.dart';
import '../domain/post.dart';
import '../domain/professional_verification.dart';
import '../domain/report.dart';
import '../domain/space.dart';

export '../domain/community_error.dart';
export '../domain/community_page.dart';

abstract interface class CommunityRepository {
  /// M1 `GET /v1/community/me` (not allowlist-gated).
  Future<CommunityMe> getMe();

  /// C1 `GET /v1/community/spaces`.
  Future<List<Space>> listSpaces();

  /// C2 `GET /v1/community/spaces/{space_id}/posts`, newest first.
  Future<CommunityPage<Post>> listPosts(
    SpaceId space, {
    String? cursor,
    int limit = CommunityPaging.defaultLimit,
  });

  /// C4 `GET /v1/community/posts/{post_id}`. 404 `not_found` for anything
  /// not visible to this viewer (never 410).
  Future<Post> getPost(String postId);

  /// C3 `POST /v1/community/spaces/{space_id}/posts` (`Idempotency-Key`).
  Future<Post> createPost(PostDraft draft);

  /// C5 `DELETE /v1/community/posts/{post_id}`. Own posts only.
  Future<void> deletePost(String postId);

  /// C6 `GET /v1/community/posts/{post_id}/comments`, oldest first.
  Future<CommunityPage<Comment>> listComments(
    String postId, {
    String? cursor,
    int limit = CommunityPaging.defaultLimit,
  });

  /// C7 `POST /v1/community/posts/{post_id}/comments` (`Idempotency-Key`).
  Future<Comment> createComment(CommentDraft draft);

  /// C8 `DELETE /v1/community/comments/{comment_id}`. Own comments only.
  Future<void> deleteComment(String commentId);

  /// C9 `POST /v1/community/reports` (`Idempotency-Key`). Allowed for
  /// restricted accounts.
  Future<ReportCreated> submitReport(ReportDraft draft);

  /// M2 `GET /v1/community/me/profile`; null until a profile exists (404).
  Future<CommunityProfile?> getProfile();

  /// M3 `PUT /v1/community/me/profile`.
  Future<CommunityProfile> setDisplayName(String displayName);

  /// M4 `GET /v1/community/me/professional-claim`; null when none (404).
  Future<ProfessionalVerification?> getProfessionalClaim();

  /// M5 `POST /v1/community/me/professional-claim` (`Idempotency-Key`).
  /// Always results in a `pending` record; never `verified`.
  Future<ProfessionalVerification> claimProfession(ProfessionalClaim claim);

  /// M6 `DELETE /v1/community/me/professional-claim`.
  Future<void> withdrawProfessionalClaim();
}

abstract interface class NotificationRepository {
  /// N1 `GET /v1/community/notifications`, newest first.
  Future<NotificationPage<CommunityNotification>> list({
    String? cursor,
    int limit = CommunityPaging.defaultLimit,
  });

  /// N2 `GET /v1/community/notifications/unread-count`. Poll at most once a
  /// minute.
  Future<int> unreadCount();

  /// N3 `POST /v1/community/notifications/{notification_id}/read`.
  Future<void> markRead(String notificationId);

  /// N4 `POST /v1/community/notifications/read-all`.
  Future<void> markAllRead();
}

/// NDPA data rights (§7.2 M7, M8). Not allowlist-gated; restricted accounts
/// may use both.
abstract interface class DataRightsRepository {
  /// M7 `GET /v1/community/me/export`. The `wellapath-community-export`
  /// document, version 1. It contains the caller's own email: show it only
  /// to them, never log it.
  Future<Map<String, dynamic>> exportMyData();

  /// M8 `POST /v1/community/me/delete` with the exact confirmation phrase.
  Future<void> deleteMyAccount(String confirmPhrase);
}

/// Validates the M7 export envelope (`format`, `version`, required keys).
Map<String, dynamic> checkExportDocument(Map<String, dynamic> json) {
  if (json['format'] != 'wellapath-community-export' || json['version'] != 1) {
    throw const FormatException('not a wellapath-community-export v1');
  }
  const List<String> required = <String>[
    'exported_at',
    'account',
    'profile',
    'professional_verifications',
    'posts',
    'comments',
    'reports_filed',
    'notifications',
    'sessions',
    'restrictions',
  ];
  for (final String key in required) {
    if (!json.containsKey(key)) throw FormatException('export missing $key');
  }
  return json;
}
