/// The in-memory backend models the server rules the PoC must implement.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/community/data/community_repositories.dart';
import 'package:wellapath_mobile/features/community/data/in_memory_community_backend.dart';
import 'package:wellapath_mobile/features/community/domain/comment.dart';
import 'package:wellapath_mobile/features/community/domain/community_json.dart';
import 'package:wellapath_mobile/features/community/domain/community_notification.dart';
import 'package:wellapath_mobile/features/community/domain/community_permissions.dart';
import 'package:wellapath_mobile/features/community/domain/moderation.dart';
import 'package:wellapath_mobile/features/community/domain/post.dart';
import 'package:wellapath_mobile/features/community/domain/professional_verification.dart';
import 'package:wellapath_mobile/features/community/domain/public_author.dart';
import 'package:wellapath_mobile/features/community/domain/report.dart';
import 'package:wellapath_mobile/features/community/domain/space.dart';

Matcher _code(CommunityErrorCode code) {
  return throwsA(
    isA<CommunityException>().having(
      (CommunityException e) => e.code,
      'code',
      code,
    ),
  );
}

void main() {
  late InMemoryCommunityBackend b;
  final DateTime clock = DateTime.utc(2026, 11, 7, 9);

  setUp(() {
    b = InMemoryCommunityBackend(clock: () => clock);
    b.registerAccount('alice', displayName: 'Alice');
    b.registerAccount('bob', displayName: 'Bobby');
    b.registerAccount('carol', displayName: 'Carol');
    b.registerAccount('mod', role: CommunityRole.moderator, displayName: 'Mod');
    b.registerAccount('admin', role: CommunityRole.admin, displayName: 'Admin');
  });

  Future<Post> alicePosts({DisplayMode mode = DisplayMode.pseudonymous}) {
    return b
        .memberView('alice')
        .createPost(
          PostDraft(
            spaceId: SpaceId.generalHealth,
            body: 'A question about sleep',
            displayMode: mode,
          ),
        );
  }

  ModerationRequest req(
    ModerationActionType a,
    ModerationTargetType t,
    String id,
  ) {
    return ModerationRequest(
      action: a,
      targetType: t,
      targetId: id,
      reason: 'Reviewed against the guidelines',
    );
  }

  group('posts and accountable pseudonymity', () {
    test('author is stored, but no member view exposes it', () async {
      final Post created = await alicePosts();
      expect(b.storedAuthorOf(created.id), 'alice');

      final Post seenByBob = await b.memberView('bob').getPost(created.id);
      expect(seenByBob.author, const PublicAuthor.pseudonymous());
      expect(seenByBob.viewerIsAuthor, isFalse);
      final String wire = seenByBob.toJson().toString();
      expect(wire.contains('alice'), isFalse);
      for (final String k in kForbiddenMemberIdentityKeys) {
        expect(seenByBob.toJson().containsKey(k), isFalse);
      }
      expect(
        (await b.memberView('alice').getPost(created.id)).viewerIsAuthor,
        isTrue,
      );
    });

    test('named posts show the display name, not the account id', () async {
      final Post p = await alicePosts(mode: DisplayMode.named);
      final Post seen = await b.memberView('bob').getPost(p.id);
      expect(seen.author.displayName, 'Alice');
      expect(seen.toJson().toString().contains('alice'), isFalse);
    });

    test('feeds are per space', () async {
      await alicePosts();
      final CommunityRepository bob = b.memberView('bob');
      expect((await bob.listPosts(SpaceId.generalHealth)).items, hasLength(1));
      expect((await bob.listPosts(SpaceId.pregnancyMaternal)).items, isEmpty);
      expect(await bob.listSpaces(), Space.approved);
    });

    test('delete own only', () async {
      final Post p = await alicePosts();
      expect(
        () => b.memberView('bob').deletePost(p.id),
        _code(CommunityErrorCode.forbidden),
      );
      await b.memberView('alice').deletePost(p.id);
      expect(
        () => b.memberView('bob').getPost(p.id),
        _code(CommunityErrorCode.contentRemoved),
      );
      expect(
        (await b.memberView('bob').listPosts(SpaceId.generalHealth)).items,
        isEmpty,
      );
    });

    test('pagination by cursor', () async {
      for (int i = 0; i < 5; i++) {
        await alicePosts();
      }
      final CommunityRepository bob = b.memberView('bob');
      final CommunityPage<Post> first = await bob.listPosts(
        SpaceId.generalHealth,
        limit: 2,
      );
      expect(first.items, hasLength(2));
      expect(first.hasMore, isTrue);
      final CommunityPage<Post> rest = await bob.listPosts(
        SpaceId.generalHealth,
        cursor: first.nextCursor,
        limit: 50,
      );
      expect(rest.items, hasLength(3));
      expect(rest.hasMore, isFalse);
    });
  });

  group('comments and notifications', () {
    test('comment notifies post author and prior commenters', () async {
      final Post p = await alicePosts();
      await b
          .memberView('bob')
          .createComment(
            CommentDraft(
              postId: p.id,
              body: 'Same here',
              displayMode: DisplayMode.named,
            ),
          );
      await b
          .memberView('carol')
          .createComment(
            CommentDraft(
              postId: p.id,
              body: 'Me too',
              displayMode: DisplayMode.pseudonymous,
            ),
          );

      final List<CommunityNotification> alice =
          (await b.notificationsFor('alice').list()).items;
      expect(
        alice.map((CommunityNotification n) => n.type),
        everyElement(CommunityNotificationType.replyToPost),
      );
      expect(alice, hasLength(2));

      final List<CommunityNotification> bob =
          (await b.notificationsFor('bob').list()).items;
      expect(bob.single.type, CommunityNotificationType.commentReply);
      expect(await b.notificationsFor('carol').unreadCount(), 0);

      await b.notificationsFor('alice').markRead(alice.first.id);
      expect(await b.notificationsFor('alice').unreadCount(), 1);
      await b.notificationsFor('alice').markAllRead();
      expect(await b.notificationsFor('alice').unreadCount(), 0);
    });

    test('comment delete own only', () async {
      final Post p = await alicePosts();
      final Comment c = await b
          .memberView('bob')
          .createComment(
            CommentDraft(
              postId: p.id,
              body: 'Hi',
              displayMode: DisplayMode.named,
            ),
          );
      expect(
        () => b.memberView('alice').deleteComment(c.id),
        _code(CommunityErrorCode.forbidden),
      );
      await b.memberView('bob').deleteComment(c.id);
      expect((await b.memberView('alice').listComments(p.id)).items, isEmpty);
    });
  });

  group('reports', () {
    test('report recorded; duplicate open report rejected', () async {
      final Post p = await alicePosts();
      final ReportDraft d = ReportDraft(
        targetType: ReportTargetType.post,
        targetId: p.id,
        reason: ReportReason.misinformation,
      );
      await b.memberView('bob').submitReport(d);
      expect(
        () => b.memberView('bob').submitReport(d),
        _code(CommunityErrorCode.conflict),
      );
      final Report r = (await b.moderationAs('mod').openReports()).items.single;
      expect(r.reason, ReportReason.misinformation);
      expect(r.createdAt, clock);
      expect(r.toJson().toString().contains('bob'), isFalse);
    });

    test('members cannot see the reports queue', () {
      expect(
        () => b.moderationAs('alice').openReports(),
        _code(CommunityErrorCode.forbidden),
      );
    });
  });

  group('moderation', () {
    test('reveal identity is moderator-only and audited', () async {
      final Post p = await alicePosts();
      final ModerationRequest r = req(
        ModerationActionType.revealIdentity,
        ModerationTargetType.post,
        p.id,
      );
      expect(
        () => b.moderationAs('bob').revealIdentity(r),
        _code(CommunityErrorCode.forbidden),
      );
      final AccountableIdentity who = await b
          .moderationAs('mod')
          .revealIdentity(r);
      expect(who.accountId, 'alice');
      final ModerationAction logged =
          (await b.moderationAs('mod').auditLog()).single;
      expect(logged.action, ModerationActionType.revealIdentity);
      expect(logged.actorAccountId, 'mod');
      expect(logged.createdAt, clock);
      expect(logged.reason, isNotEmpty);
    });

    test('hide removes from feed and notifies the author', () async {
      final Post p = await alicePosts();
      final ModerationAction a = await b
          .moderationAs('mod')
          .apply(
            req(
              ModerationActionType.hideContent,
              ModerationTargetType.post,
              p.id,
            ),
          );
      expect(a.actorAccountId, 'mod');
      expect(
        (await b.memberView('bob').listPosts(SpaceId.generalHealth)).items,
        isEmpty,
      );
      final CommunityNotification n =
          (await b.notificationsFor('alice').list()).items.single;
      expect(n.notice, ModerationNotice.contentHidden);
    });

    test('moderators cannot moderate their own content', () async {
      final Post own = await b
          .memberView('mod')
          .createPost(
            PostDraft(
              spaceId: SpaceId.generalHealth,
              body: 'Mine',
              displayMode: DisplayMode.named,
            ),
          );
      expect(
        () => b
            .moderationAs('mod')
            .apply(
              req(
                ModerationActionType.removeContent,
                ModerationTargetType.post,
                own.id,
              ),
            ),
        _code(CommunityErrorCode.forbidden),
      );
    });

    test('restrict (moderator) makes an account read-only', () async {
      await b
          .moderationAs('mod')
          .apply(
            req(
              ModerationActionType.restrictAccount,
              ModerationTargetType.account,
              'alice',
            ),
          );
      expect(
        await b.memberView('alice').listSpaces(),
        hasLength(2),
        reason: 'read still allowed',
      );
      expect(() => alicePosts(), _code(CommunityErrorCode.accountRestricted));
    });

    test('suspend is admin-only', () async {
      final ModerationRequest r = req(
        ModerationActionType.suspendAccount,
        ModerationTargetType.account,
        'alice',
      );
      expect(
        () => b.moderationAs('mod').apply(r),
        _code(CommunityErrorCode.forbidden),
      );
      await b.moderationAs('admin').apply(r);
      expect(
        () => b.memberView('alice').listSpaces(),
        _code(CommunityErrorCode.accountRestricted),
      );
      final List<ModerationAction> log = await b
          .moderationAs('admin')
          .auditLog();
      expect(log.single.actorAccountId, 'admin');
    });

    test('audit log is append-only from the client view', () async {
      final Post p = await alicePosts();
      await b
          .moderationAs('mod')
          .apply(
            req(
              ModerationActionType.hideContent,
              ModerationTargetType.post,
              p.id,
            ),
          );
      final List<ModerationAction> log = await b.moderationAs('mod').auditLog();
      expect(() => log.clear(), throwsUnsupportedError);
    });
  });

  group('professional verification', () {
    test('claim is pending; badge only after admin verify', () async {
      final ProfessionalVerification v = await b
          .memberView('alice')
          .claimProfession(ProfessionalClaim(profession: 'Midwife'));
      expect(v.status, VerificationStatus.pending);

      final Post p = await alicePosts(mode: DisplayMode.named);
      expect((await b.memberView('bob').getPost(p.id)).author.badge, isNull);

      final ModerationRequest verify = req(
        ModerationActionType.verifyProfessional,
        ModerationTargetType.account,
        'alice',
      );
      expect(
        () => b.moderationAs('mod').apply(verify),
        _code(CommunityErrorCode.forbidden),
        reason: 'moderators cannot verify',
      );
      await b.moderationAs('admin').apply(verify);

      final Post after = await b.memberView('bob').getPost(p.id);
      expect(after.author.badge?.profession, 'Midwife');
      final ProfessionalVerification? mine =
          (await b.memberView('alice').getProfile())?.professional;
      expect(mine?.status, VerificationStatus.verified);
      expect(mine?.verifiedAt, clock);

      // Badge never shows on pseudonymous content.
      final Post anon = await alicePosts();
      expect((await b.memberView('bob').getPost(anon.id)).author.badge, isNull);
    });

    test('cannot verify without a pending claim', () {
      expect(
        () => b
            .moderationAs('admin')
            .apply(
              req(
                ModerationActionType.verifyProfessional,
                ModerationTargetType.account,
                'bob',
              ),
            ),
        _code(CommunityErrorCode.invalidState),
      );
    });

    test('revoke removes the badge', () async {
      await b
          .memberView('alice')
          .claimProfession(ProfessionalClaim(profession: 'Nurse'));
      final InMemoryCommunityBackend backend = b;
      await backend
          .moderationAs('admin')
          .apply(
            req(
              ModerationActionType.verifyProfessional,
              ModerationTargetType.account,
              'alice',
            ),
          );
      await backend
          .moderationAs('admin')
          .apply(
            req(
              ModerationActionType.revokeProfessional,
              ModerationTargetType.account,
              'alice',
            ),
          );
      final Post p = await alicePosts(mode: DisplayMode.named);
      expect((await b.memberView('bob').getPost(p.id)).author.badge, isNull);
    });
  });
}
