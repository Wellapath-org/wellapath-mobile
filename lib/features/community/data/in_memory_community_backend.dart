/// An in-memory stand-in for the Community backend, for the internal
/// scaffold and tests. Nothing is persisted and nothing leaves the device.
///
/// It models the server-side rules in `docs/community/API_CONTRACT.md` so the
/// UI and the tests exercise the same behaviour the PoC must implement:
/// authors are always stored, member views never carry an account id, every
/// moderation action needs a reason and is logged with actor and time, and
/// only an admin can verify a professional.
library;

import '../domain/comment.dart';
import '../domain/community_notification.dart';
import '../domain/community_permissions.dart';
import '../domain/community_profile.dart';
import '../domain/moderation.dart';
import '../domain/post.dart';
import '../domain/professional_verification.dart';
import '../domain/public_author.dart';
import '../domain/report.dart';
import '../domain/space.dart';
import 'community_repositories.dart';

class _Account {
  _Account(this.id, this.role);

  final String id;
  CommunityRole role;
  AccountStatus status = AccountStatus.active;
  CommunityProfile? profile;
  ProfessionalVerification? professional;
}

class _StoredPost {
  _StoredPost({
    required this.id,
    required this.spaceId,
    required this.body,
    required this.authorAccountId,
    required this.displayMode,
    required this.createdAt,
  });

  final String id;
  final SpaceId spaceId;
  final String body;
  final String authorAccountId;
  final DisplayMode displayMode;
  final DateTime createdAt;
  ContentStatus status = ContentStatus.visible;
}

class _StoredComment {
  _StoredComment({
    required this.id,
    required this.postId,
    required this.body,
    required this.authorAccountId,
    required this.displayMode,
    required this.createdAt,
  });

  final String id;
  final String postId;
  final String body;
  final String authorAccountId;
  final DisplayMode displayMode;
  final DateTime createdAt;
  ContentStatus status = ContentStatus.visible;
}

class _StoredReport {
  _StoredReport(this.report, this.reporterAccountId);

  Report report;
  final String reporterAccountId;
}

class InMemoryCommunityBackend {
  InMemoryCommunityBackend({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, _Account> _accounts = {};
  final List<_StoredPost> _posts = [];
  final List<_StoredComment> _comments = [];
  final List<_StoredReport> _reports = [];
  final Map<String, List<CommunityNotification>> _notifications = {};
  final List<ModerationAction> _audit = [];
  int _seq = 0;

  DateTime _now() => _clock().toUtc();

  String _id(String prefix) => '${prefix}_${++_seq}';

  /// Creates (or returns) an account. Roles are otherwise only changed by an
  /// admin through [ModerationRepository.apply].
  CommunityViewer registerAccount(
    String accountId, {
    CommunityRole role = CommunityRole.member,
    String? displayName,
  }) {
    final _Account account = _accounts.putIfAbsent(
      accountId,
      () => _Account(accountId, role),
    );
    if (displayName != null) {
      account.profile = CommunityProfile(displayName: displayName);
    }
    return CommunityViewer(
      accountId: accountId,
      role: account.role,
      status: account.status,
    );
  }

  CommunityRepository memberView(String accountId) {
    return _MemberRepository(this, _require(accountId));
  }

  NotificationRepository notificationsFor(String accountId) {
    return _NotificationRepository(this, _require(accountId));
  }

  ModerationRepository moderationAs(String accountId) {
    return _ModerationRepository(this, _require(accountId));
  }

  /// Test/diagnostic hook: the server-side author of a post. Not part of any
  /// member repository.
  String? storedAuthorOf(String postId) {
    for (final _StoredPost p in _posts) {
      if (p.id == postId) return p.authorAccountId;
    }
    return null;
  }

  _Account _require(String accountId) {
    final _Account? account = _accounts[accountId];
    if (account == null) {
      throw const CommunityException(CommunityErrorCode.unauthenticated);
    }
    return account;
  }

  void _requireCapability(_Account account, CommunityCapability capability) {
    if (account.status == AccountStatus.restricted &&
        capability != CommunityCapability.readContent) {
      throw const CommunityException(CommunityErrorCode.accountRestricted);
    }
    if (account.status == AccountStatus.suspended) {
      throw const CommunityException(CommunityErrorCode.accountRestricted);
    }
    if (!CommunityPermissions.can(
      account.role,
      capability,
      status: account.status,
    )) {
      throw const CommunityException(CommunityErrorCode.forbidden);
    }
  }

  PublicAuthor _publicAuthor(String accountId, DisplayMode mode) {
    if (mode == DisplayMode.pseudonymous) {
      return const PublicAuthor.pseudonymous();
    }
    final _Account account = _accounts[accountId]!;
    return PublicAuthor.named(
      displayName: account.profile?.displayName ?? 'Community member',
      badge: ProfessionalBadge.fromVerification(account.professional),
    );
  }

  Post _toMemberPost(_StoredPost p, String viewerId) {
    return Post(
      id: p.id,
      spaceId: p.spaceId,
      body: p.body,
      author: _publicAuthor(p.authorAccountId, p.displayMode),
      viewerIsAuthor: p.authorAccountId == viewerId,
      status: p.status,
      commentCount: _comments
          .where(
            (_StoredComment c) =>
                c.postId == p.id && c.status == ContentStatus.visible,
          )
          .length,
      createdAt: p.createdAt,
    );
  }

  Comment _toMemberComment(_StoredComment c, String viewerId) {
    return Comment(
      id: c.id,
      postId: c.postId,
      body: c.body,
      author: _publicAuthor(c.authorAccountId, c.displayMode),
      viewerIsAuthor: c.authorAccountId == viewerId,
      status: c.status,
      createdAt: c.createdAt,
    );
  }

  _StoredPost _post(String id) {
    for (final _StoredPost p in _posts) {
      if (p.id == id) return p;
    }
    throw const CommunityException(CommunityErrorCode.notFound);
  }

  _StoredComment _comment(String id) {
    for (final _StoredComment c in _comments) {
      if (c.id == id) return c;
    }
    throw const CommunityException(CommunityErrorCode.notFound);
  }

  void _notify(
    String accountId,
    CommunityNotificationType type, {
    String? postId,
    String? commentId,
    ModerationNotice? notice,
  }) {
    _notifications
        .putIfAbsent(accountId, () => <CommunityNotification>[])
        .insert(
          0,
          CommunityNotification(
            id: _id('ntf'),
            type: type,
            postId: postId,
            commentId: commentId,
            notice: notice,
            createdAt: _now(),
          ),
        );
  }

  static CommunityPage<T> _page<T>(List<T> all, String? cursor, int limit) {
    final int start = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    final int clamped = limit.clamp(1, 50);
    final int end = (start + clamped).clamp(0, all.length);
    return CommunityPage<T>(
      items: all.sublist(start.clamp(0, all.length), end),
      nextCursor: end < all.length ? '$end' : null,
    );
  }
}

class _MemberRepository implements CommunityRepository {
  _MemberRepository(this._b, this._me);

  final InMemoryCommunityBackend _b;
  final _Account _me;

  @override
  Future<List<Space>> listSpaces() async {
    _b._requireCapability(_me, CommunityCapability.readContent);
    return Space.approved;
  }

  @override
  Future<CommunityPage<Post>> listPosts(
    SpaceId space, {
    String? cursor,
    int limit = 20,
  }) async {
    _b._requireCapability(_me, CommunityCapability.readContent);
    final List<Post> visible = _b._posts.reversed
        .where(
          (_StoredPost p) =>
              p.spaceId == space && p.status == ContentStatus.visible,
        )
        .map((_StoredPost p) => _b._toMemberPost(p, _me.id))
        .toList();
    return InMemoryCommunityBackend._page(visible, cursor, limit);
  }

  @override
  Future<Post> getPost(String postId) async {
    _b._requireCapability(_me, CommunityCapability.readContent);
    final _StoredPost p = _b._post(postId);
    if (p.status != ContentStatus.visible) {
      throw const CommunityException(CommunityErrorCode.contentRemoved);
    }
    return _b._toMemberPost(p, _me.id);
  }

  @override
  Future<Post> createPost(PostDraft draft) async {
    _b._requireCapability(_me, CommunityCapability.createContent);
    if (_me.profile == null) {
      throw const CommunityException(
        CommunityErrorCode.invalidState,
        'profile required',
      );
    }
    final _StoredPost p = _StoredPost(
      id: _b._id('pst'),
      spaceId: draft.spaceId,
      body: draft.body,
      authorAccountId: _me.id,
      displayMode: draft.displayMode,
      createdAt: _b._now(),
    );
    _b._posts.add(p);
    return _b._toMemberPost(p, _me.id);
  }

  @override
  Future<void> deletePost(String postId) async {
    _b._requireCapability(_me, CommunityCapability.deleteOwnContent);
    final _StoredPost p = _b._post(postId);
    if (p.authorAccountId != _me.id) {
      throw const CommunityException(CommunityErrorCode.forbidden);
    }
    p.status = ContentStatus.deletedByAuthor;
  }

  @override
  Future<CommunityPage<Comment>> listComments(
    String postId, {
    String? cursor,
    int limit = 20,
  }) async {
    _b._requireCapability(_me, CommunityCapability.readContent);
    final List<Comment> visible = _b._comments
        .where(
          (_StoredComment c) =>
              c.postId == postId && c.status == ContentStatus.visible,
        )
        .map((_StoredComment c) => _b._toMemberComment(c, _me.id))
        .toList();
    return InMemoryCommunityBackend._page(visible, cursor, limit);
  }

  @override
  Future<Comment> createComment(CommentDraft draft) async {
    _b._requireCapability(_me, CommunityCapability.createContent);
    final _StoredPost post = _b._post(draft.postId);
    if (post.status != ContentStatus.visible) {
      throw const CommunityException(CommunityErrorCode.contentRemoved);
    }
    if (_me.profile == null) {
      throw const CommunityException(
        CommunityErrorCode.invalidState,
        'profile required',
      );
    }
    final Set<String> priorCommenters = _b._comments
        .where((_StoredComment c) => c.postId == post.id)
        .map((_StoredComment c) => c.authorAccountId)
        .toSet();
    final _StoredComment c = _StoredComment(
      id: _b._id('cmt'),
      postId: post.id,
      body: draft.body,
      authorAccountId: _me.id,
      displayMode: draft.displayMode,
      createdAt: _b._now(),
    );
    _b._comments.add(c);
    if (post.authorAccountId != _me.id) {
      _b._notify(
        post.authorAccountId,
        CommunityNotificationType.replyToPost,
        postId: post.id,
        commentId: c.id,
      );
    }
    for (final String other in priorCommenters) {
      if (other == _me.id || other == post.authorAccountId) continue;
      _b._notify(
        other,
        CommunityNotificationType.commentReply,
        postId: post.id,
        commentId: c.id,
      );
    }
    return _b._toMemberComment(c, _me.id);
  }

  @override
  Future<void> deleteComment(String commentId) async {
    _b._requireCapability(_me, CommunityCapability.deleteOwnContent);
    final _StoredComment c = _b._comment(commentId);
    if (c.authorAccountId != _me.id) {
      throw const CommunityException(CommunityErrorCode.forbidden);
    }
    c.status = ContentStatus.deletedByAuthor;
  }

  @override
  Future<void> submitReport(ReportDraft draft) async {
    _b._requireCapability(_me, CommunityCapability.reportContent);
    if (draft.targetType == ReportTargetType.post) {
      _b._post(draft.targetId);
    } else {
      _b._comment(draft.targetId);
    }
    final bool duplicate = _b._reports.any(
      (_StoredReport r) =>
          r.reporterAccountId == _me.id &&
          r.report.targetId == draft.targetId &&
          r.report.targetType == draft.targetType &&
          r.report.status == ReportStatus.open,
    );
    if (duplicate) {
      throw const CommunityException(CommunityErrorCode.conflict);
    }
    _b._reports.add(
      _StoredReport(
        Report(
          id: _b._id('rpt'),
          targetType: draft.targetType,
          targetId: draft.targetId,
          reason: draft.reason,
          note: draft.note,
          status: ReportStatus.open,
          createdAt: _b._now(),
        ),
        _me.id,
      ),
    );
  }

  @override
  Future<CommunityProfile?> getProfile() async => _me.profile;

  @override
  Future<CommunityProfile> setDisplayName(String displayName) async {
    final String name = CommunityProfile.validateDisplayName(displayName);
    final bool taken = _b._accounts.values.any(
      (_Account a) =>
          a.id != _me.id &&
          a.profile?.displayName.toLowerCase() == name.toLowerCase(),
    );
    if (taken) throw const CommunityException(CommunityErrorCode.conflict);
    _me.profile = CommunityProfile(
      displayName: name,
      professional: _me.professional,
    );
    return _me.profile!;
  }

  @override
  Future<ProfessionalVerification> claimProfession(
    ProfessionalClaim claim,
  ) async {
    _b._requireCapability(_me, CommunityCapability.claimProfession);
    final ProfessionalVerification pending = claim.asPending();
    _me.professional = pending;
    if (_me.profile != null) {
      _me.profile = CommunityProfile(
        displayName: _me.profile!.displayName,
        professional: pending,
      );
    }
    return pending;
  }
}

class _NotificationRepository implements NotificationRepository {
  _NotificationRepository(this._b, this._me);

  final InMemoryCommunityBackend _b;
  final _Account _me;

  List<CommunityNotification> get _mine =>
      _b._notifications.putIfAbsent(_me.id, () => <CommunityNotification>[]);

  @override
  Future<CommunityPage<CommunityNotification>> list({
    String? cursor,
    int limit = 20,
  }) async {
    return InMemoryCommunityBackend._page(
      List<CommunityNotification>.of(_mine),
      cursor,
      limit,
    );
  }

  @override
  Future<int> unreadCount() async {
    return _mine.where((CommunityNotification n) => !n.isRead).length;
  }

  @override
  Future<void> markRead(String notificationId) async {
    final List<CommunityNotification> mine = _mine;
    for (int i = 0; i < mine.length; i++) {
      if (mine[i].id == notificationId) mine[i] = mine[i].markRead(_b._now());
    }
  }

  @override
  Future<void> markAllRead() async {
    final List<CommunityNotification> mine = _mine;
    for (int i = 0; i < mine.length; i++) {
      mine[i] = mine[i].markRead(_b._now());
    }
  }
}

class _ModerationRepository implements ModerationRepository {
  _ModerationRepository(this._b, this._me);

  final InMemoryCommunityBackend _b;
  final _Account _me;

  @override
  Future<CommunityPage<Report>> openReports({
    String? cursor,
    int limit = 20,
  }) async {
    _b._requireCapability(_me, CommunityCapability.viewReportsQueue);
    final List<Report> open = _b._reports
        .map((_StoredReport r) => r.report)
        .where((Report r) => r.status == ReportStatus.open)
        .toList();
    return InMemoryCommunityBackend._page(open, cursor, limit);
  }

  @override
  Future<AccountableIdentity> revealIdentity(ModerationRequest request) async {
    if (request.action != ModerationActionType.revealIdentity) {
      throw const CommunityException(CommunityErrorCode.validationFailed);
    }
    _b._requireCapability(_me, CommunityCapability.revealIdentity);
    final String accountId = _authorOfTarget(request);
    _record(request);
    final _Account account = _b._accounts[accountId]!;
    return AccountableIdentity(
      accountId: account.id,
      displayName: account.profile?.displayName,
      status: account.status,
    );
  }

  @override
  Future<ModerationAction> apply(ModerationRequest request) async {
    if (request.action == ModerationActionType.revealIdentity) {
      throw const CommunityException(CommunityErrorCode.validationFailed);
    }
    _b._requireCapability(_me, request.action.requires);
    switch (request.action) {
      case ModerationActionType.hideContent:
      case ModerationActionType.restoreContent:
      case ModerationActionType.removeContent:
        _setContentStatus(request);
      case ModerationActionType.dismissReport:
        final _StoredReport r = _b._reports.firstWhere(
          (_StoredReport r) => r.report.id == request.targetId,
          orElse: () =>
              throw const CommunityException(CommunityErrorCode.notFound),
        );
        r.report = r.report.copyWith(status: ReportStatus.dismissed);
      case ModerationActionType.restrictAccount:
      case ModerationActionType.suspendAccount:
      case ModerationActionType.reinstateAccount:
        _setAccountStatus(request);
      case ModerationActionType.verifyProfessional:
      case ModerationActionType.revokeProfessional:
        _setVerification(request);
      case ModerationActionType.changeRole:
        // Role payloads are not modelled in the scaffold; the contract
        // reserves the endpoint for admins.
        throw const CommunityException(CommunityErrorCode.invalidState);
      case ModerationActionType.revealIdentity:
        throw const CommunityException(CommunityErrorCode.validationFailed);
    }
    return _record(request);
  }

  @override
  Future<List<ModerationAction>> auditLog() async {
    _b._requireCapability(_me, CommunityCapability.viewAuditLog);
    return List<ModerationAction>.unmodifiable(_b._audit);
  }

  ModerationAction _record(ModerationRequest request) {
    final ModerationAction action = ModerationAction(
      id: _b._id('mod'),
      actorAccountId: _me.id,
      action: request.action,
      targetType: request.targetType,
      targetId: request.targetId,
      reason: request.reason,
      createdAt: _b._now(),
    );
    _b._audit.add(action);
    return action;
  }

  String _authorOfTarget(ModerationRequest request) {
    switch (request.targetType) {
      case ModerationTargetType.post:
        return _b._post(request.targetId).authorAccountId;
      case ModerationTargetType.comment:
        return _b._comment(request.targetId).authorAccountId;
      case ModerationTargetType.account:
      case ModerationTargetType.report:
        throw const CommunityException(CommunityErrorCode.validationFailed);
    }
  }

  void _setContentStatus(ModerationRequest request) {
    final String author = _authorOfTarget(request);
    if (author == _me.id) {
      throw const CommunityException(
        CommunityErrorCode.forbidden,
        'cannot moderate own content',
      );
    }
    final ContentStatus next = switch (request.action) {
      ModerationActionType.hideContent => ContentStatus.hidden,
      ModerationActionType.removeContent => ContentStatus.removed,
      _ => ContentStatus.visible,
    };
    if (request.targetType == ModerationTargetType.post) {
      _b._post(request.targetId).status = next;
    } else {
      _b._comment(request.targetId).status = next;
    }
    if (next != ContentStatus.visible) {
      _b._notify(
        author,
        CommunityNotificationType.moderationNotice,
        notice: next == ContentStatus.hidden
            ? ModerationNotice.contentHidden
            : ModerationNotice.contentRemoved,
      );
    }
  }

  void _setAccountStatus(ModerationRequest request) {
    if (request.targetType != ModerationTargetType.account) {
      throw const CommunityException(CommunityErrorCode.validationFailed);
    }
    if (request.targetId == _me.id) {
      throw const CommunityException(CommunityErrorCode.forbidden);
    }
    final _Account target =
        _b._accounts[request.targetId] ??
        (throw const CommunityException(CommunityErrorCode.notFound));
    switch (request.action) {
      case ModerationActionType.restrictAccount:
        target.status = AccountStatus.restricted;
        _b._notify(
          target.id,
          CommunityNotificationType.moderationNotice,
          notice: ModerationNotice.accountRestricted,
        );
      case ModerationActionType.suspendAccount:
        target.status = AccountStatus.suspended;
        _b._notify(
          target.id,
          CommunityNotificationType.moderationNotice,
          notice: ModerationNotice.accountSuspended,
        );
      default:
        target.status = AccountStatus.active;
    }
  }

  void _setVerification(ModerationRequest request) {
    if (request.targetType != ModerationTargetType.account) {
      throw const CommunityException(CommunityErrorCode.validationFailed);
    }
    final _Account target =
        _b._accounts[request.targetId] ??
        (throw const CommunityException(CommunityErrorCode.notFound));
    final ProfessionalVerification? current = target.professional;
    final bool verifying =
        request.action == ModerationActionType.verifyProfessional;
    if (current == null ||
        (verifying && current.status != VerificationStatus.pending) ||
        (!verifying && current.status != VerificationStatus.verified)) {
      throw const CommunityException(CommunityErrorCode.invalidState);
    }
    final DateTime now = _b._now();
    // The only place a verified record is created: an admin action, parsed
    // through the same server-shaped constructor the client uses.
    target.professional = ProfessionalVerification.fromJson(<String, dynamic>{
      'profession': current.profession,
      'specialty': current.specialty,
      'status': verifying
          ? VerificationStatus.verified.wire
          : VerificationStatus.revoked.wire,
      'verified_at': verifying ? now.toIso8601String() : null,
    });
    if (target.profile != null) {
      target.profile = CommunityProfile(
        displayName: target.profile!.displayName,
        professional: target.professional,
      );
    }
    _b._notify(
      target.id,
      CommunityNotificationType.moderationNotice,
      notice: ModerationNotice.verificationUpdated,
    );
  }
}
