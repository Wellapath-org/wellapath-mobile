/// An in-memory stand-in for the Community backend, for tests and local
/// development. Nothing is persisted and nothing leaves the device.
///
/// It models the server rules of the canonical contract (v1.0-draft) so the
/// UI and the tests exercise the behaviour the real API implements:
/// - authors are always stored, but member views never carry an account id;
/// - anything not visible to the viewer is 404 `not_found` (never 410);
/// - a profile is required to post, comment or claim (`profile_required`);
/// - restricted accounts are read-only but may still report, delete their
///   own content, export and delete their account;
/// - suspended accounts get 401 `session_revoked` on their next request;
/// - moderators may restrict/suspend/reinstate **members**; a privileged
///   target needs an admin; nobody may act on themselves;
/// - only an admin verifies a professional claim, by verification id;
/// - every moderation action needs a reason and is logged with actor and
///   server time.
///
/// The moderation side ([moderationAs]) exists only to drive states in
/// tests: the app has no moderator UI and no HTTP client for `/mod` or
/// `/admin`.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../domain/comment.dart';
import '../domain/community_me.dart';
import '../domain/community_notification.dart';
import '../domain/community_permissions.dart';
import '../domain/community_profile.dart';
import '../domain/community_validation.dart';
import '../domain/moderation.dart';
import '../domain/post.dart';
import '../domain/professional_verification.dart';
import '../domain/public_author.dart';
import '../domain/report.dart';
import '../domain/space.dart';
import 'community_repositories.dart';

class _Account {
  _Account(this.id, this.role, this.email, this.createdAt);

  final String id;
  CommunityRole role;
  final String email;
  final DateTime createdAt;
  AccountStatus status = AccountStatus.active;
  String? displayName;
  ProfessionalVerification? professional;
  bool deleted = false;

  CommunityProfile? get profile => displayName == null
      ? null
      : CommunityProfile(displayName: displayName!, professional: professional);
}

class _Content {
  _Content({
    required this.id,
    required this.body,
    required this.authorAccountId,
    required this.displayMode,
    required this.createdAt,
    this.spaceId,
    this.postId,
  });

  final String id;
  final SpaceId? spaceId;
  final String? postId;
  String? body;
  final String authorAccountId;
  final DisplayMode displayMode;
  final DateTime createdAt;
  ContentStatus status = ContentStatus.visible;

  bool get visible => status == ContentStatus.visible;
}

class _StoredReport {
  _StoredReport(this.report, this.reporterAccountId);

  Report report;
  final String reporterAccountId;
}

CommunityException _err(CommunityErrorCode code, [String? reason]) {
  return CommunityException(code, reason: reason);
}

class InMemoryCommunityBackend {
  InMemoryCommunityBackend({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, _Account> _accounts = {};
  final List<_Content> _posts = [];
  final List<_Content> _comments = [];
  final List<_StoredReport> _reports = [];
  final Map<String, List<CommunityNotification>> _notifications = {};
  final List<ModerationAction> _audit = [];
  int _seq = 0;

  DateTime _now() => _clock().toUtc();

  /// Opaque, UUID-shaped ids (§1: content ids are UUID strings).
  String _uuid() {
    final String n = (++_seq).toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-$n';
  }

  /// Creates (or returns) an account. Roles are otherwise only changed by an
  /// admin, which the website does.
  void registerAccount(
    String accountId, {
    CommunityRole role = CommunityRole.member,
    String? displayName,
  }) {
    final _Account account = _accounts.putIfAbsent(
      accountId,
      () => _Account(accountId, role, '$accountId@example.test', _now()),
    );
    if (displayName != null) {
      account.displayName = CommunityProfile.validateDisplayName(displayName);
    }
  }

  /// Test inspection: what the server stored for [accountId], whatever the
  /// account's state (a suspended or deleted account cannot list its own).
  @visibleForTesting
  List<CommunityNotification> storedNotificationsFor(String accountId) {
    return List<CommunityNotification>.unmodifiable(
      _notifications[accountId] ?? const <CommunityNotification>[],
    );
  }

  CommunityRepository memberView(String accountId) {
    return _MemberRepository(this, accountId);
  }

  NotificationRepository notificationsFor(String accountId) {
    return _NotificationRepository(this, accountId);
  }

  DataRightsRepository dataRightsFor(String accountId) {
    return _DataRightsRepository(this, accountId);
  }

  /// Test harness for server-side state changes (see library doc).
  InMemoryModeration moderationAs(String accountId) {
    return InMemoryModeration._(this, accountId);
  }

  /// Test/diagnostic hook: the server-side author of a post. Not part of any
  /// member repository.
  String? storedAuthorOf(String postId) {
    for (final _Content p in _posts) {
      if (p.id == postId) return p.authorAccountId;
    }
    return null;
  }

  /// Test hook: the id of [accountId]'s current professional claim.
  String? verificationIdOf(String accountId) {
    return _accounts[accountId]?.professional?.id;
  }

  // ---- internals -----------------------------------------------------------

  /// Resolves the caller. A deleted account has no session; a suspended one
  /// had its sessions revoked (§2.2).
  _Account _session(String accountId) {
    final _Account? a = _accounts[accountId];
    if (a == null || a.deleted) {
      throw _err(CommunityErrorCode.unauthenticated, 'session_revoked');
    }
    if (a.status == AccountStatus.suspended) {
      throw _err(CommunityErrorCode.unauthenticated, 'session_revoked');
    }
    return a;
  }

  _Account _can(String accountId, CommunityCapability capability) {
    final _Account a = _session(accountId);
    if (!CommunityPermissions.matrix[a.role]!.contains(capability)) {
      throw _err(CommunityErrorCode.forbidden);
    }
    if (!CommunityPermissions.can(a.role, capability, status: a.status)) {
      throw _err(CommunityErrorCode.accountRestricted);
    }
    return a;
  }

  void _requireProfile(_Account a) {
    if (a.displayName == null) {
      throw _err(CommunityErrorCode.invalidState, 'profile_required');
    }
  }

  PublicAuthor _publicAuthor(String accountId, DisplayMode mode) {
    if (mode == DisplayMode.pseudonymous) {
      return const PublicAuthor.pseudonymous();
    }
    final _Account account = _accounts[accountId]!;
    return PublicAuthor.named(
      displayName: account.displayName ?? 'Community member',
      badge: ProfessionalBadge.fromVerification(account.professional),
    );
  }

  Post _toMemberPost(_Content p, String viewerId) {
    return Post(
      id: p.id,
      spaceId: p.spaceId!,
      body: p.body!,
      author: _publicAuthor(p.authorAccountId, p.displayMode),
      viewerIsAuthor: p.authorAccountId == viewerId,
      commentCount: _comments
          .where((_Content c) => c.postId == p.id && c.visible)
          .length,
      createdAt: p.createdAt,
    );
  }

  Comment _toMemberComment(_Content c, String viewerId) {
    return Comment(
      id: c.id,
      postId: c.postId!,
      body: c.body!,
      author: _publicAuthor(c.authorAccountId, c.displayMode),
      viewerIsAuthor: c.authorAccountId == viewerId,
      createdAt: c.createdAt,
    );
  }

  _Content _find(List<_Content> list, String id) {
    for (final _Content c in list) {
      if (c.id == id) return c;
    }
    throw _err(CommunityErrorCode.notFound);
  }

  /// Members see visible content only; everything else is 404.
  _Content _visible(List<_Content> list, String id) {
    final _Content c = _find(list, id);
    if (!c.visible) throw _err(CommunityErrorCode.notFound);
    return c;
  }

  void _notify(
    String accountId,
    CommunityNotificationType type, {
    String? postId,
    String? commentId,
    ModerationNotice? notice,
  }) {
    final List<CommunityNotification> mine = _notifications.putIfAbsent(
      accountId,
      () => <CommunityNotification>[],
    );
    if (type == CommunityNotificationType.commentReply &&
        mine.any(
          (CommunityNotification n) =>
              n.type == type && n.postId == postId && !n.isRead,
        )) {
      return; // at most one unread comment_reply per post per recipient
    }
    mine.insert(
      0,
      CommunityNotification(
        id: _uuid(),
        type: type,
        postId: postId,
        commentId: commentId,
        notice: notice,
        createdAt: _now(),
      ),
    );
  }

  ModerationAction _record(
    String actor,
    ModerationActionType action,
    ModerationTargetType targetType,
    String targetId,
    String reason,
  ) {
    final ModerationAction a = ModerationAction(
      id: '${_audit.length + 1}',
      actorAccountId: actor,
      action: action,
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      createdAt: _now(),
    );
    _audit.add(a);
    return a;
  }

  /// Opaque cursor; anything else is 400 `validation_failed` (§1.1).
  static CommunityPage<T> _page<T>(List<T> all, String? cursor, int limit) {
    if (limit < 1 || limit > CommunityPaging.maxLimit) {
      throw const CommunityException(
        CommunityErrorCode.validationFailed,
        field: 'limit',
      );
    }
    int start = 0;
    if (cursor != null) {
      final int? n = cursor.startsWith('mem:')
          ? int.tryParse(cursor.substring(4))
          : null;
      if (n == null || n < 0 || n > all.length) {
        throw const CommunityException(
          CommunityErrorCode.validationFailed,
          field: 'cursor',
        );
      }
      start = n;
    }
    final int end = (start + limit).clamp(0, all.length);
    return CommunityPage<T>(
      items: all.sublist(start, end),
      nextCursor: end < all.length ? 'mem:$end' : null,
    );
  }
}

class _MemberRepository implements CommunityRepository {
  _MemberRepository(this._b, this._id);

  final InMemoryCommunityBackend _b;
  final String _id;

  @override
  Future<CommunityMe> getMe() async {
    final _Account a = _b._session(_id);
    return CommunityMe(
      accountId: a.id,
      email: a.email,
      role: a.role,
      status: a.status,
      restrictedUntil: null,
      twoFactorEnabled: false,
      communityAllowed: true,
      createdAt: a.createdAt,
      profile: a.profile,
    );
  }

  @override
  Future<List<Space>> listSpaces() async {
    _b._can(_id, CommunityCapability.readContent);
    return Space.approved;
  }

  @override
  Future<CommunityPage<Post>> listPosts(
    SpaceId space, {
    String? cursor,
    int limit = CommunityPaging.defaultLimit,
  }) async {
    _b._can(_id, CommunityCapability.readContent);
    final List<Post> visible = _b._posts.reversed
        .where((_Content p) => p.spaceId == space && p.visible)
        .map((_Content p) => _b._toMemberPost(p, _id))
        .toList();
    return InMemoryCommunityBackend._page(visible, cursor, limit);
  }

  @override
  Future<Post> getPost(String postId) async {
    _b._can(_id, CommunityCapability.readContent);
    return _b._toMemberPost(_b._visible(_b._posts, postId), _id);
  }

  @override
  Future<Post> createPost(PostDraft draft) async {
    final _Account me = _b._can(_id, CommunityCapability.createContent);
    _b._requireProfile(me);
    final _Content p = _Content(
      id: _b._uuid(),
      spaceId: draft.spaceId,
      body: draft.body,
      authorAccountId: _id,
      displayMode: draft.displayMode,
      createdAt: _b._now(),
    );
    _b._posts.add(p);
    return _b._toMemberPost(p, _id);
  }

  /// C5: own posts, from `visible` or `hidden`. A visible post that is not
  /// the caller's is 403; anything else the caller cannot see is 404.
  void _deleteOwn(_Content c) {
    final bool own = c.authorAccountId == _id;
    if (c.visible && !own) throw _err(CommunityErrorCode.forbidden);
    if (!own || !(c.visible || c.status == ContentStatus.hidden)) {
      throw _err(CommunityErrorCode.notFound);
    }
    c.status = ContentStatus.deletedByAuthor;
    c.body = null;
  }

  @override
  Future<void> deletePost(String postId) async {
    _b._can(_id, CommunityCapability.deleteOwnContent);
    _deleteOwn(_b._find(_b._posts, postId));
  }

  @override
  Future<CommunityPage<Comment>> listComments(
    String postId, {
    String? cursor,
    int limit = CommunityPaging.defaultLimit,
  }) async {
    _b._can(_id, CommunityCapability.readContent);
    _b._visible(_b._posts, postId);
    final List<Comment> visible = _b._comments
        .where((_Content c) => c.postId == postId && c.visible)
        .map((_Content c) => _b._toMemberComment(c, _id))
        .toList();
    return InMemoryCommunityBackend._page(visible, cursor, limit);
  }

  @override
  Future<Comment> createComment(CommentDraft draft) async {
    final _Account me = _b._can(_id, CommunityCapability.createContent);
    final _Content post = _b._visible(_b._posts, draft.postId);
    _b._requireProfile(me);
    // C7(d) (founder, 2026-11-08): only earlier commenters whose comment is
    // still visible and whose account is active (not suspended, not
    // deleted). A restricted (read-only) account is still notified.
    final Set<String> priorCommenters = _b._comments
        .where((_Content c) => c.postId == post.id && c.visible)
        .map((_Content c) => c.authorAccountId)
        .where((String id) {
          final _Account? a = _b._accounts[id];
          return a != null && !a.deleted && a.status != AccountStatus.suspended;
        })
        .toSet();
    final _Content c = _Content(
      id: _b._uuid(),
      postId: post.id,
      body: draft.body,
      authorAccountId: _id,
      displayMode: draft.displayMode,
      createdAt: _b._now(),
    );
    _b._comments.add(c);
    if (post.authorAccountId != _id) {
      _b._notify(
        post.authorAccountId,
        CommunityNotificationType.replyToPost,
        postId: post.id,
        commentId: c.id,
      );
    }
    for (final String other in priorCommenters) {
      if (other == _id || other == post.authorAccountId) continue;
      _b._notify(
        other,
        CommunityNotificationType.commentReply,
        postId: post.id,
        commentId: c.id,
      );
    }
    return _b._toMemberComment(c, _id);
  }

  @override
  Future<void> deleteComment(String commentId) async {
    _b._can(_id, CommunityCapability.deleteOwnContent);
    _deleteOwn(_b._find(_b._comments, commentId));
  }

  @override
  Future<ReportCreated> submitReport(ReportDraft draft) async {
    _b._can(_id, CommunityCapability.reportContent);
    // 404 unless the target is visible to the reporter (no state oracle).
    _b._visible(
      draft.targetType == ReportTargetType.post ? _b._posts : _b._comments,
      draft.targetId,
    );
    final bool duplicate = _b._reports.any(
      (_StoredReport r) =>
          r.reporterAccountId == _id &&
          r.report.targetId == draft.targetId &&
          r.report.targetType == draft.targetType &&
          r.report.status == ReportStatus.open,
    );
    if (duplicate) throw _err(CommunityErrorCode.conflict, 'duplicate_report');
    final Report report = Report(
      id: _b._uuid(),
      targetType: draft.targetType,
      targetId: draft.targetId,
      reason: draft.reason,
      note: draft.note,
      status: ReportStatus.open,
      createdAt: _b._now(),
    );
    _b._reports.add(_StoredReport(report, _id));
    return ReportCreated(id: report.id, createdAt: report.createdAt);
  }

  @override
  Future<CommunityProfile?> getProfile() async {
    return _b._can(_id, CommunityCapability.readContent).profile;
  }

  @override
  Future<CommunityProfile> setDisplayName(String displayName) async {
    final _Account me = _b._can(_id, CommunityCapability.setProfile);
    final String name = CommunityProfile.validateDisplayName(displayName);
    final bool taken = _b._accounts.values.any(
      (_Account a) =>
          a.id != _id && a.displayName?.toLowerCase() == name.toLowerCase(),
    );
    if (taken) throw _err(CommunityErrorCode.conflict, 'display_name_taken');
    me.displayName = name;
    return me.profile!;
  }

  @override
  Future<ProfessionalVerification?> getProfessionalClaim() async {
    return _b._can(_id, CommunityCapability.readContent).professional;
  }

  @override
  Future<ProfessionalVerification> claimProfession(
    ProfessionalClaim claim,
  ) async {
    final _Account me = _b._can(_id, CommunityCapability.claimProfession);
    _b._requireProfile(me);
    if (me.professional?.isActive ?? false) {
      throw _err(CommunityErrorCode.conflict, 'claim_exists');
    }
    me.professional = ProfessionalVerification.pending(
      id: _b._uuid(),
      profession: claim.profession,
      specialty: claim.specialty,
      createdAt: _b._now(),
    );
    return me.professional!;
  }

  @override
  Future<void> withdrawProfessionalClaim() async {
    final _Account me = _b._can(_id, CommunityCapability.readContent);
    final ProfessionalVerification? claim = me.professional;
    if (claim == null || !claim.isActive) {
      throw _err(CommunityErrorCode.invalidState, 'no_active_claim');
    }
    me.professional = null;
    _b._record(
      _id,
      ModerationActionType.withdrawProfessional,
      ModerationTargetType.professionalVerification,
      claim.id,
      'withdrawn by user',
    );
  }
}

class _NotificationRepository implements NotificationRepository {
  _NotificationRepository(this._b, this._id);

  final InMemoryCommunityBackend _b;
  final String _id;

  List<CommunityNotification> get _mine {
    _b._can(_id, CommunityCapability.readOwnNotifications);
    return _b._notifications.putIfAbsent(_id, () => <CommunityNotification>[]);
  }

  @override
  Future<NotificationPage<CommunityNotification>> list({
    String? cursor,
    int limit = CommunityPaging.defaultLimit,
  }) async {
    final List<CommunityNotification> mine = _mine;
    final CommunityPage<CommunityNotification> page =
        InMemoryCommunityBackend._page(
          List<CommunityNotification>.of(mine),
          cursor,
          limit,
        );
    return NotificationPage<CommunityNotification>(
      items: page.items,
      nextCursor: page.nextCursor,
      unreadCount: mine.where((CommunityNotification n) => !n.isRead).length,
    );
  }

  @override
  Future<int> unreadCount() async {
    return _mine.where((CommunityNotification n) => !n.isRead).length;
  }

  @override
  Future<void> markRead(String notificationId) async {
    final List<CommunityNotification> mine = _mine;
    final int i = mine.indexWhere(
      (CommunityNotification n) => n.id == notificationId,
    );
    if (i < 0) throw _err(CommunityErrorCode.notFound);
    mine[i] = mine[i].markRead(_b._now());
  }

  @override
  Future<void> markAllRead() async {
    final List<CommunityNotification> mine = _mine;
    for (int i = 0; i < mine.length; i++) {
      mine[i] = mine[i].markRead(_b._now());
    }
  }
}

class _DataRightsRepository implements DataRightsRepository {
  _DataRightsRepository(this._b, this._id);

  final InMemoryCommunityBackend _b;
  final String _id;

  @override
  Future<Map<String, dynamic>> exportMyData() async {
    final _Account me = _b._can(_id, CommunityCapability.exportOwnData);
    List<Map<String, dynamic>> own(List<_Content> list) => list
        .where((_Content c) => c.authorAccountId == _id)
        .map(
          (_Content c) => <String, dynamic>{
            'id': c.id,
            'body': c.body,
            'status': c.status.wire,
            'display_mode': c.displayMode.wire,
            'created_at': c.createdAt.toIso8601String(),
          },
        )
        .toList();
    return checkExportDocument(<String, dynamic>{
      'format': 'wellapath-community-export',
      'version': 1,
      'exported_at': _b._now().toIso8601String(),
      'account': <String, dynamic>{
        'id': me.id,
        'email': me.email,
        'role': me.role.wire,
        'two_factor_enabled': false,
        'created_at': me.createdAt.toIso8601String(),
      },
      'profile': me.profile?.toJson(),
      'professional_verifications': <Map<String, dynamic>>[
        if (me.professional != null) me.professional!.toJson(),
      ],
      'posts': own(_b._posts),
      'comments': own(_b._comments),
      'reports_filed': _b._reports
          .where((_StoredReport r) => r.reporterAccountId == _id)
          .map((_StoredReport r) => r.report.toJson())
          .toList(),
      'notifications': (_b._notifications[_id] ?? <CommunityNotification>[])
          .map((CommunityNotification n) => n.toJson())
          .toList(),
      'sessions': <Map<String, dynamic>>[],
      'restrictions': <Map<String, dynamic>>[],
    });
  }

  @override
  Future<void> deleteMyAccount(String confirmPhrase) async {
    final _Account me = _b._session(_id);
    if (confirmPhrase != CommunityLimits.deleteAccountPhrase) {
      throw const CommunityException(
        CommunityErrorCode.validationFailed,
        field: 'confirm',
      );
    }
    if (me.role != CommunityRole.member) {
      throw _err(CommunityErrorCode.invalidState, 'privileged_account');
    }
    for (final _Content c in <_Content>[..._b._posts, ..._b._comments]) {
      if (c.authorAccountId == _id) {
        c.status = ContentStatus.tombstoned;
        c.body = null;
      }
    }
    me.displayName = null;
    me.professional = null;
    me.deleted = true;
    _b._notifications.remove(_id);
    _b._record(
      _id,
      ModerationActionType.deleteAccount,
      ModerationTargetType.account,
      _id,
      'user-requested account deletion',
    );
  }
}

/// Server-side moderation, for tests only (see the library doc).
class InMemoryModeration {
  InMemoryModeration._(this._b, this._id);

  final InMemoryCommunityBackend _b;
  final String _id;

  _Account _actor(CommunityCapability capability) {
    final _Account a = _b._session(_id);
    if (!CommunityPermissions.can(a.role, capability, status: a.status)) {
      throw _err(CommunityErrorCode.forbidden);
    }
    return a;
  }

  Future<CommunityPage<Report>> openReports({
    String? cursor,
    int limit = CommunityPaging.defaultLimit,
  }) async {
    _actor(CommunityCapability.viewReportQueue);
    final List<Report> open =
        _b._reports
            .map((_StoredReport r) => r.report)
            .where((Report r) => r.status == ReportStatus.open)
            .toList()
          // self_harm_or_emergency first, then oldest first (§12.2 D1).
          ..sort((Report a, Report b) {
            final int pa = a.reason == ReportReason.selfHarmOrEmergency ? 0 : 1;
            final int pb = b.reason == ReportReason.selfHarmOrEmergency ? 0 : 1;
            return pa != pb ? pa - pb : a.createdAt.compareTo(b.createdAt);
          });
    return InMemoryCommunityBackend._page(open, cursor, limit);
  }

  /// D6: audited read of the account behind a post or comment.
  Future<AccountableIdentity> revealIdentity(ModerationRequest request) async {
    _actor(CommunityCapability.revealIdentity);
    final _Content c = _content(request);
    final ModerationAction logged = _b._record(
      _id,
      ModerationActionType.revealIdentity,
      request.targetType,
      request.targetId,
      request.reason,
    );
    final _Account who = _b._accounts[c.authorAccountId]!;
    return AccountableIdentity(
      accountId: who.id,
      displayName: who.displayName,
      role: who.role,
      status: who.status,
      createdAt: who.createdAt,
      priorModerationActions: _b._audit
          .where(
            (ModerationAction a) =>
                a.targetType == ModerationTargetType.account &&
                a.targetId == who.id,
          )
          .length,
      revealActionId: logged.id,
    );
  }

  /// D3, D7–D12, X4, X5.
  Future<ModerationAction> apply(ModerationRequest request) async {
    final CommunityCapability? needs = request.action.requires;
    if (needs == null ||
        request.action == ModerationActionType.revealIdentity) {
      throw _err(CommunityErrorCode.validationFailed);
    }
    _actor(needs);
    switch (request.action) {
      case ModerationActionType.hideContent:
      case ModerationActionType.restoreContent:
      case ModerationActionType.removeContent:
        _setContentStatus(request);
      case ModerationActionType.dismissReport:
        final _StoredReport r = _b._reports.firstWhere(
          (_StoredReport r) => r.report.id == request.targetId,
          orElse: () => throw _err(CommunityErrorCode.notFound),
        );
        if (r.report.status != ReportStatus.open) {
          throw _err(CommunityErrorCode.invalidState, 'already_in_state');
        }
        r.report = r.report.copyWith(status: ReportStatus.dismissed);
      case ModerationActionType.restrictAccount:
      case ModerationActionType.suspendAccount:
      case ModerationActionType.reinstateAccount:
        _setAccountStatus(request);
      case ModerationActionType.verifyProfessional:
      case ModerationActionType.revokeProfessional:
        _setVerification(request);
      case ModerationActionType.changeRole:
      case ModerationActionType.resetTotp:
        // Role and TOTP administration are website-admin features that the
        // app never exercises; not modelled here.
        throw _err(CommunityErrorCode.invalidState);
      case ModerationActionType.revealIdentity:
      case ModerationActionType.withdrawProfessional:
      case ModerationActionType.deleteAccount:
        throw _err(CommunityErrorCode.validationFailed);
    }
    return _b._record(
      _id,
      request.action,
      request.targetType,
      request.targetId,
      request.reason,
    );
  }

  /// Read-only view of the append-only audit log (D13).
  Future<List<ModerationAction>> auditLog() async {
    _actor(CommunityCapability.viewAuditLog);
    return List<ModerationAction>.unmodifiable(_b._audit.reversed);
  }

  _Content _content(ModerationRequest request) {
    switch (request.targetType) {
      case ModerationTargetType.post:
        return _b._find(_b._posts, request.targetId);
      case ModerationTargetType.comment:
        return _b._find(_b._comments, request.targetId);
      case ModerationTargetType.account:
      case ModerationTargetType.report:
      case ModerationTargetType.professionalVerification:
        throw _err(CommunityErrorCode.validationFailed);
    }
  }

  void _setContentStatus(ModerationRequest request) {
    final _Content c = _content(request);
    if (c.authorAccountId == _id) {
      throw _err(CommunityErrorCode.selfActionForbidden);
    }
    final ContentStatus from = c.status;
    late final ContentStatus to;
    late final ModerationNotice notice;
    switch (request.action) {
      case ModerationActionType.hideContent:
        if (from != ContentStatus.visible) {
          throw _err(CommunityErrorCode.invalidState, 'already_in_state');
        }
        to = ContentStatus.hidden;
        notice = ModerationNotice.contentHidden;
      case ModerationActionType.removeContent:
        if (from != ContentStatus.visible && from != ContentStatus.hidden) {
          throw _err(CommunityErrorCode.invalidState, 'already_in_state');
        }
        to = ContentStatus.removed;
        notice = ModerationNotice.contentRemoved;
      default:
        if (from == ContentStatus.deletedByAuthor ||
            from == ContentStatus.tombstoned) {
          throw _err(CommunityErrorCode.invalidState, 'content_erased');
        }
        if (from != ContentStatus.hidden && from != ContentStatus.removed) {
          throw _err(CommunityErrorCode.invalidState, 'not_hidden_or_removed');
        }
        to = ContentStatus.visible;
        notice = ModerationNotice.contentRestored;
    }
    c.status = to;
    for (final _StoredReport r in _b._reports) {
      if (r.report.targetId == c.id && r.report.status == ReportStatus.open) {
        r.report = r.report.copyWith(status: ReportStatus.actioned);
      }
    }
    _b._notify(
      c.authorAccountId,
      CommunityNotificationType.moderationNotice,
      postId: c.postId ?? c.id,
      commentId: c.postId == null ? null : c.id,
      notice: notice,
    );
  }

  void _setAccountStatus(ModerationRequest request) {
    if (request.targetType != ModerationTargetType.account) {
      throw _err(CommunityErrorCode.validationFailed);
    }
    if (request.targetId == _id) {
      throw _err(CommunityErrorCode.selfActionForbidden);
    }
    final _Account target =
        _b._accounts[request.targetId] ??
        (throw _err(CommunityErrorCode.notFound));
    if (target.role != CommunityRole.member) {
      // §2.1: a moderator/admin target needs an admin.
      _actor(CommunityCapability.restrictSuspendReinstatePrivileged);
    }
    switch (request.action) {
      case ModerationActionType.restrictAccount:
        // C3 (founder, 2026-11-08): no-op transitions are refused before
        // anything is recorded, so the audit log has no duplicate row.
        if (target.status == AccountStatus.restricted) {
          throw _err(CommunityErrorCode.invalidState, 'already_in_state');
        }
        target.status = AccountStatus.restricted;
        _b._notify(
          target.id,
          CommunityNotificationType.moderationNotice,
          notice: ModerationNotice.accountRestricted,
        );
      case ModerationActionType.suspendAccount:
        if (target.status == AccountStatus.suspended) {
          throw _err(CommunityErrorCode.invalidState, 'already_in_state');
        }
        target.status = AccountStatus.suspended;
        _b._notify(
          target.id,
          CommunityNotificationType.moderationNotice,
          notice: ModerationNotice.accountSuspended,
        );
      default:
        if (target.status == AccountStatus.active) {
          throw _err(
            CommunityErrorCode.invalidState,
            'not_restricted_or_suspended',
          );
        }
        target.status = AccountStatus.active;
        _b._notify(
          target.id,
          CommunityNotificationType.moderationNotice,
          notice: ModerationNotice.accountReinstated,
        );
    }
  }

  void _setVerification(ModerationRequest request) {
    if (request.targetType != ModerationTargetType.professionalVerification) {
      throw _err(CommunityErrorCode.validationFailed);
    }
    _Account? target;
    for (final _Account a in _b._accounts.values) {
      if (a.professional?.id == request.targetId) target = a;
    }
    if (target == null) throw _err(CommunityErrorCode.notFound);
    if (target.id == _id) throw _err(CommunityErrorCode.selfActionForbidden);
    final ProfessionalVerification current = target.professional!;
    final bool verifying =
        request.action == ModerationActionType.verifyProfessional;
    if (verifying && current.status != VerificationStatus.pending) {
      throw _err(CommunityErrorCode.invalidState, 'not_pending');
    }
    if (!verifying && !current.isActive) {
      throw _err(CommunityErrorCode.invalidState, 'already_in_state');
    }
    // The only place a verified record is created: an admin action, parsed
    // through the same server-shaped constructor the client uses.
    target.professional = ProfessionalVerification.fromJson(<String, dynamic>{
      ...current.toJson(),
      'status': verifying
          ? VerificationStatus.verified.wire
          : VerificationStatus.revoked.wire,
      'verified_at': verifying ? _b._now().toIso8601String() : null,
    });
    _b._notify(
      target.id,
      CommunityNotificationType.moderationNotice,
      notice: ModerationNotice.verificationUpdated,
    );
  }
}
