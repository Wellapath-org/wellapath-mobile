/// Repository interfaces for Community. Each method maps 1:1 to an endpoint
/// in `docs/community/API_CONTRACT.md`; a future HTTP implementation must not
/// add behaviour the contract does not describe.
///
/// Out of scope, so deliberately absent: private consultations, doctor chat,
/// prescriptions, payments, image uploads, nested threads, AI replies.
library;

import '../domain/comment.dart';
import '../domain/community_notification.dart';
import '../domain/community_profile.dart';
import '../domain/moderation.dart';
import '../domain/post.dart';
import '../domain/professional_verification.dart';
import '../domain/report.dart';
import '../domain/space.dart';

/// Mirrors the contract's error `code` (API contract §1.1).
enum CommunityErrorCode {
  validationFailed,
  unauthenticated,
  forbidden,
  communityNotAllowed,
  accountRestricted,
  notFound,
  conflict,
  contentRemoved,
  invalidState,
  rateLimited,
  communityUnavailable,
}

class CommunityException implements Exception {
  const CommunityException(this.code, [this.message = '']);

  final CommunityErrorCode code;
  final String message;

  /// The server has switched Community off for this viewer: close it.
  bool get isKillSwitch => code == CommunityErrorCode.communityNotAllowed;

  @override
  String toString() => 'CommunityException(${code.name}: $message)';
}

/// One page of a cursor-paginated list (API contract §1.2).
class CommunityPage<T> {
  const CommunityPage({required this.items, this.nextCursor});

  final List<T> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

abstract interface class CommunityRepository {
  Future<List<Space>> listSpaces();

  Future<CommunityPage<Post>> listPosts(
    SpaceId space, {
    String? cursor,
    int limit = 20,
  });

  Future<Post> getPost(String postId);

  Future<Post> createPost(PostDraft draft);

  /// Own posts only.
  Future<void> deletePost(String postId);

  Future<CommunityPage<Comment>> listComments(
    String postId, {
    String? cursor,
    int limit = 20,
  });

  Future<Comment> createComment(CommentDraft draft);

  /// Own comments only.
  Future<void> deleteComment(String commentId);

  Future<void> submitReport(ReportDraft draft);

  Future<CommunityProfile?> getProfile();

  Future<CommunityProfile> setDisplayName(String displayName);

  /// Always results in a `pending` record; never `verified`.
  Future<ProfessionalVerification> claimProfession(ProfessionalClaim claim);
}

abstract interface class NotificationRepository {
  Future<CommunityPage<CommunityNotification>> list({
    String? cursor,
    int limit = 20,
  });

  Future<int> unreadCount();

  Future<void> markRead(String notificationId);

  Future<void> markAllRead();
}

abstract interface class ModerationRepository {
  Future<CommunityPage<Report>> openReports({String? cursor, int limit = 20});

  /// Audited read of the account behind a post or comment.
  Future<AccountableIdentity> revealIdentity(ModerationRequest request);

  /// Applies a mutating action (hide, remove, restrict, suspend, ...).
  Future<ModerationAction> apply(ModerationRequest request);

  /// Read-only view of the append-only audit log.
  Future<List<ModerationAction>> auditLog();
}
