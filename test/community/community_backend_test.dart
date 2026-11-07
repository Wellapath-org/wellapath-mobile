/// The in-memory backend models the canonical server rules (contract
/// v1.0-draft), so the app and its tests exercise the behaviour the real API
/// implements.
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

Matcher _code(CommunityErrorCode code, [String? reason]) {
  return throwsA(
    isA<CommunityException>()
        .having((CommunityException e) => e.code, 'code', code)
        .having(
          (CommunityException e) => e.reason,
          'reason',
          reason ?? anything,
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
    b.registerAccount('noname');
    b.registerAccount('mod', role: CommunityRole.moderator, displayName: 'Mod');
    b.registerAccount(
      'mod2',
      role: CommunityRole.moderator,
      displayName: 'Mo2',
    );
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
      expect(seenByBob.toJson().toString().contains('alice'), isFalse);
      expect(() => rejectIdentityKeys(seenByBob.toJson()), returnsNormally);
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

    test('a profile is required to post, even pseudonymously', () {
      expect(
        () => b
            .memberView('noname')
            .createPost(
              PostDraft(
                spaceId: SpaceId.generalHealth,
                body: 'hi',
                displayMode: DisplayMode.pseudonymous,
              ),
            ),
        _code(CommunityErrorCode.invalidState, 'profile_required'),
      );
    });

    test('feeds are per space', () async {
      await alicePosts();
      final CommunityRepository bob = b.memberView('bob');
      expect((await bob.listPosts(SpaceId.generalHealth)).items, hasLength(1));
      expect((await bob.listPosts(SpaceId.pregnancyMaternal)).items, isEmpty);
      expect(await bob.listSpaces(), Space.approved);
    });

    test('delete own only; deleted is a plain 404, never 410', () async {
      final Post p = await alicePosts();
      expect(
        () => b.memberView('bob').deletePost(p.id),
        _code(CommunityErrorCode.forbidden),
      );
      await b.memberView('alice').deletePost(p.id);
      expect(
        () => b.memberView('bob').getPost(p.id),
        _code(CommunityErrorCode.notFound),
      );
      expect(
        () => b.memberView('alice').deletePost(p.id),
        _code(CommunityErrorCode.notFound),
      );
      expect(
        (await b.memberView('bob').listPosts(SpaceId.generalHealth)).items,
        isEmpty,
      );
    });

    test(
      'cursor pagination; bad cursor or limit is validation_failed',
      () async {
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
        expect(
          () => bob.listPosts(SpaceId.generalHealth, cursor: 'forged'),
          _code(CommunityErrorCode.validationFailed),
        );
        expect(
          () => bob.listPosts(SpaceId.generalHealth, limit: 51),
          _code(CommunityErrorCode.validationFailed),
        );
      },
    );
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

      final NotificationPage<CommunityNotification> alice = await b
          .notificationsFor('alice')
          .list();
      expect(
        alice.items.map((CommunityNotification n) => n.type),
        everyElement(CommunityNotificationType.replyToPost),
      );
      expect(alice.items, hasLength(2));
      expect(alice.unreadCount, 2);

      final List<CommunityNotification> bob =
          (await b.notificationsFor('bob').list()).items;
      expect(bob.single.type, CommunityNotificationType.commentReply);
      expect(await b.notificationsFor('carol').unreadCount(), 0);

      await b.notificationsFor('alice').markRead(alice.items.first.id);
      expect(await b.notificationsFor('alice').unreadCount(), 1);
      await b.notificationsFor('alice').markAllRead();
      expect(await b.notificationsFor('alice').unreadCount(), 0);
      expect(
        () => b.notificationsFor('bob').markRead(alice.items.first.id),
        _code(CommunityErrorCode.notFound),
        reason: 'own notifications only',
      );
    });

    test('comment_reply (C7(d)): suspended, deleted and hidden-comment authors '
        'are not notified; a restricted author still is', () async {
      b.registerAccount('dave', displayName: 'Dave');
      b.registerAccount('erin', displayName: 'Erin');
      b.registerAccount('frank', displayName: 'Frank');
      final Post p = await alicePosts();
      Future<Comment> say(String who) => b
          .memberView(who)
          .createComment(
            CommentDraft(
              postId: p.id,
              body: 'hi',
              displayMode: DisplayMode.named,
            ),
          );
      await say('bob'); // suspended below
      await say('carol'); // deletes her account below
      final Comment daves = await say('dave'); // hidden below
      await say('erin'); // restricted below
      // Start from a clean slate: only frank's comment counts.
      for (final String who in <String>['bob', 'dave', 'erin']) {
        await b.notificationsFor(who).markAllRead();
      }
      final InMemoryModeration mod = b.moderationAs('mod');
      await mod.apply(
        req(
          ModerationActionType.suspendAccount,
          ModerationTargetType.account,
          'bob',
        ),
      );
      await b.dataRightsFor('carol').deleteMyAccount('DELETE MY ACCOUNT');
      await mod.apply(
        req(
          ModerationActionType.hideContent,
          ModerationTargetType.comment,
          daves.id,
        ),
      );
      await mod.apply(
        req(
          ModerationActionType.restrictAccount,
          ModerationTargetType.account,
          'erin',
        ),
      );
      await say('frank');

      int unreadReplies(String who) => b
          .storedNotificationsFor(who)
          .where(
            (CommunityNotification n) =>
                n.type == CommunityNotificationType.commentReply &&
                n.readAt == null,
          )
          .length;
      expect(unreadReplies('bob'), 0, reason: 'suspended');
      expect(unreadReplies('carol'), 0, reason: 'deleted');
      expect(unreadReplies('dave'), 0, reason: 'comment hidden');
      expect(unreadReplies('erin'), 1, reason: 'restricted is active');
    });

    test('comment_reply: at most one unread per post per recipient', () async {
      final Post p = await alicePosts();
      Future<void> say(String who) => b
          .memberView(who)
          .createComment(
            CommentDraft(
              postId: p.id,
              body: 'hi',
              displayMode: DisplayMode.named,
            ),
          );
      await say('bob');
      await say('carol');
      await say('carol');
      expect((await b.notificationsFor('bob').list()).items, hasLength(1));
    });

    test('comment delete own only; hidden post comments are 404', () async {
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

      await b
          .moderationAs('mod')
          .apply(
            req(
              ModerationActionType.hideContent,
              ModerationTargetType.post,
              p.id,
            ),
          );
      expect(
        () => b.memberView('bob').listComments(p.id),
        _code(CommunityErrorCode.notFound),
      );
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
      final ReportCreated created = await b.memberView('bob').submitReport(d);
      expect(created.createdAt, clock);
      expect(
        () => b.memberView('bob').submitReport(d),
        _code(CommunityErrorCode.conflict, 'duplicate_report'),
      );
      final Report r = (await b.moderationAs('mod').openReports()).items.single;
      expect(r.reason, ReportReason.misinformation);
      expect(r.toJson().toString().contains('bob'), isFalse);
    });

    test('a target not visible to the reporter is 404', () async {
      final Post p = await alicePosts();
      await b.memberView('alice').deletePost(p.id);
      expect(
        () => b
            .memberView('bob')
            .submitReport(
              ReportDraft(
                targetType: ReportTargetType.post,
                targetId: p.id,
                reason: ReportReason.spam,
              ),
            ),
        _code(CommunityErrorCode.notFound),
      );
    });

    test('self_harm_or_emergency sorts first in the queue', () async {
      final Post p1 = await alicePosts();
      final Post p2 = await alicePosts();
      await b
          .memberView('bob')
          .submitReport(
            ReportDraft(
              targetType: ReportTargetType.post,
              targetId: p1.id,
              reason: ReportReason.spam,
            ),
          );
      await b
          .memberView('bob')
          .submitReport(
            ReportDraft(
              targetType: ReportTargetType.post,
              targetId: p2.id,
              reason: ReportReason.selfHarmOrEmergency,
            ),
          );
      expect(
        (await b.moderationAs('mod').openReports()).items.first.reason,
        ReportReason.selfHarmOrEmergency,
      );
    });

    test('members cannot see the reports queue', () {
      expect(
        () => b.moderationAs('alice').openReports(),
        _code(CommunityErrorCode.forbidden),
      );
    });
  });

  group('account status', () {
    test('C3: a repeated restrict or suspend is 422 already_in_state and '
        'records no audit row', () async {
      final InMemoryModeration mod = b.moderationAs('mod');
      for (final ModerationActionType action in <ModerationActionType>[
        ModerationActionType.restrictAccount,
        ModerationActionType.suspendAccount,
      ]) {
        final String target = action == ModerationActionType.restrictAccount
            ? 'bob'
            : 'carol';
        await mod.apply(req(action, ModerationTargetType.account, target));
        final int before = (await mod.auditLog()).length;
        await expectLater(
          () => mod.apply(req(action, ModerationTargetType.account, target)),
          _code(CommunityErrorCode.invalidState, 'already_in_state'),
        );
        expect((await mod.auditLog()).length, before);
      }
    });

    test(
      'restricted: read-only, but may still report and delete own',
      () async {
        final Post own = await alicePosts();
        final Post others = await b
            .memberView('bob')
            .createPost(
              PostDraft(
                spaceId: SpaceId.generalHealth,
                body: 'Bob here',
                displayMode: DisplayMode.named,
              ),
            );
        await b
            .moderationAs('mod')
            .apply(
              req(
                ModerationActionType.restrictAccount,
                ModerationTargetType.account,
                'alice',
              ),
            );
        final CommunityRepository alice = b.memberView('alice');
        expect(await alice.listSpaces(), hasLength(2));
        expect((await alice.getMe()).status, AccountStatus.restricted);
        expect(() => alicePosts(), _code(CommunityErrorCode.accountRestricted));
        expect(
          () => alice.setDisplayName('AliceTwo'),
          _code(CommunityErrorCode.accountRestricted),
        );
        expect(
          () => alice.claimProfession(ProfessionalClaim(profession: 'Nurse')),
          _code(CommunityErrorCode.accountRestricted),
        );
        // §15 row 37: reporting is a safety exception.
        await alice.submitReport(
          ReportDraft(
            targetType: ReportTargetType.post,
            targetId: others.id,
            reason: ReportReason.harassment,
          ),
        );
        await alice.deletePost(own.id);
        expect(
          (await b.dataRightsFor('alice').exportMyData())['format'],
          'wellapath-community-export',
        );
        expect(
          (await b.notificationsFor('alice').list()).items.first.notice,
          ModerationNotice.accountRestricted,
        );
      },
    );

    test('a moderator may suspend a member (§15 row 49)', () async {
      await b
          .moderationAs('mod')
          .apply(
            req(
              ModerationActionType.suspendAccount,
              ModerationTargetType.account,
              'alice',
            ),
          );
      expect(
        () => b.memberView('alice').listSpaces(),
        _code(CommunityErrorCode.unauthenticated, 'session_revoked'),
      );
      await b
          .moderationAs('mod')
          .apply(
            req(
              ModerationActionType.reinstateAccount,
              ModerationTargetType.account,
              'alice',
            ),
          );
      expect(await b.memberView('alice').listSpaces(), hasLength(2));
      expect(
        (await b.notificationsFor('alice').list()).items.first.notice,
        ModerationNotice.accountReinstated,
      );
      final List<ModerationAction> log = await b.moderationAs('mod').auditLog();
      expect(log.first.action, ModerationActionType.reinstateAccount);
      expect(log.first.actorAccountId, 'mod');
    });

    test('acting on a moderator/admin needs an admin; never on self', () async {
      final ModerationRequest suspendMod2 = req(
        ModerationActionType.suspendAccount,
        ModerationTargetType.account,
        'mod2',
      );
      expect(
        () => b.moderationAs('mod').apply(suspendMod2),
        _code(CommunityErrorCode.forbidden),
      );
      await b.moderationAs('admin').apply(suspendMod2);
      expect(
        () => b
            .moderationAs('admin')
            .apply(
              req(
                ModerationActionType.restrictAccount,
                ModerationTargetType.account,
                'admin',
              ),
            ),
        _code(CommunityErrorCode.selfActionForbidden),
      );
    });

    test('reinstate when active is invalid_state', () {
      expect(
        () => b
            .moderationAs('mod')
            .apply(
              req(
                ModerationActionType.reinstateAccount,
                ModerationTargetType.account,
                'alice',
              ),
            ),
        _code(CommunityErrorCode.invalidState, 'not_restricted_or_suspended'),
      );
    });
  });

  group('moderation (website-admin behaviour the app must handle)', () {
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
      expect(who.toJson().containsKey('email'), isFalse);
      final ModerationAction logged =
          (await b.moderationAs('mod').auditLog()).single;
      expect(logged.action, ModerationActionType.revealIdentity);
      expect(logged.id, who.revealActionId);
      expect(logged.createdAt, clock);
    });

    test('hide: gone from feed, 404 on fetch, author notified', () async {
      final Post p = await alicePosts();
      await b
          .memberView('bob')
          .submitReport(
            ReportDraft(
              targetType: ReportTargetType.post,
              targetId: p.id,
              reason: ReportReason.spam,
            ),
          );
      await b
          .moderationAs('mod')
          .apply(
            req(
              ModerationActionType.hideContent,
              ModerationTargetType.post,
              p.id,
            ),
          );
      expect(
        (await b.memberView('bob').listPosts(SpaceId.generalHealth)).items,
        isEmpty,
      );
      expect(
        () => b.memberView('alice').getPost(p.id),
        _code(CommunityErrorCode.notFound),
        reason: 'not visible to anyone, author included',
      );
      final CommunityNotification n =
          (await b.notificationsFor('alice').list()).items.single;
      expect(n.notice, ModerationNotice.contentHidden);
      expect(n.postId, p.id, reason: 'notice still carries the ids');
      expect((await b.moderationAs('mod').openReports()).items, isEmpty);

      // The author may still delete their hidden post (C5).
      await b.memberView('alice').deletePost(p.id);
      expect(
        () => b
            .moderationAs('mod')
            .apply(
              req(
                ModerationActionType.restoreContent,
                ModerationTargetType.post,
                p.id,
              ),
            ),
        _code(CommunityErrorCode.invalidState, 'content_erased'),
      );
    });

    test('restore brings content back and notifies', () async {
      final Post p = await alicePosts();
      final InMemoryModeration mod = b.moderationAs('mod');
      await mod.apply(
        req(
          ModerationActionType.removeContent,
          ModerationTargetType.post,
          p.id,
        ),
      );
      await mod.apply(
        req(
          ModerationActionType.restoreContent,
          ModerationTargetType.post,
          p.id,
        ),
      );
      expect((await b.memberView('bob').getPost(p.id)).id, p.id);
      expect(
        (await b.notificationsFor('alice').list()).items.first.notice,
        ModerationNotice.contentRestored,
      );
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
        _code(CommunityErrorCode.selfActionForbidden),
      );
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
      expect(int.tryParse(log.single.id), isNotNull, reason: 'decimal string');
    });
  });

  group('professional verification', () {
    test('claim is pending; badge only after admin verify by id', () async {
      final ProfessionalVerification v = await b
          .memberView('alice')
          .claimProfession(ProfessionalClaim(profession: 'Midwife'));
      expect(v.status, VerificationStatus.pending);
      expect(v.id, b.verificationIdOf('alice'));
      expect(
        () => b
            .memberView('alice')
            .claimProfession(ProfessionalClaim(profession: 'Nurse')),
        _code(CommunityErrorCode.conflict, 'claim_exists'),
      );

      final Post p = await alicePosts(mode: DisplayMode.named);
      expect((await b.memberView('bob').getPost(p.id)).author.badge, isNull);

      final ModerationRequest verify = req(
        ModerationActionType.verifyProfessional,
        ModerationTargetType.professionalVerification,
        v.id,
      );
      expect(
        () => b.moderationAs('mod').apply(verify),
        _code(CommunityErrorCode.forbidden),
        reason: 'moderators cannot verify',
      );
      await b.moderationAs('admin').apply(verify);

      final Post after = await b.memberView('bob').getPost(p.id);
      expect(after.author.badge?.profession, 'Midwife');
      final ProfessionalVerification? mine = await b
          .memberView('alice')
          .getProfessionalClaim();
      expect(mine?.status, VerificationStatus.verified);
      expect(mine?.verifiedAt, clock);

      // Badge never shows on pseudonymous content.
      final Post anon = await alicePosts();
      expect((await b.memberView('bob').getPost(anon.id)).author.badge, isNull);
    });

    test('a profile is required to claim', () {
      expect(
        () => b
            .memberView('noname')
            .claimProfession(ProfessionalClaim(profession: 'Nurse')),
        _code(CommunityErrorCode.invalidState, 'profile_required'),
      );
    });

    test('revoke removes the badge; withdraw is audited', () async {
      final ProfessionalVerification v = await b
          .memberView('alice')
          .claimProfession(ProfessionalClaim(profession: 'Nurse'));
      await b
          .moderationAs('admin')
          .apply(
            req(
              ModerationActionType.verifyProfessional,
              ModerationTargetType.professionalVerification,
              v.id,
            ),
          );
      await b
          .moderationAs('admin')
          .apply(
            req(
              ModerationActionType.revokeProfessional,
              ModerationTargetType.professionalVerification,
              v.id,
            ),
          );
      final Post p = await alicePosts(mode: DisplayMode.named);
      expect((await b.memberView('bob').getPost(p.id)).author.badge, isNull);
      expect(
        () => b.memberView('alice').withdrawProfessionalClaim(),
        _code(CommunityErrorCode.invalidState, 'no_active_claim'),
      );

      final ProfessionalVerification again = await b
          .memberView('bob')
          .claimProfession(ProfessionalClaim(profession: 'Nurse'));
      await b.memberView('bob').withdrawProfessionalClaim();
      final ModerationAction w =
          (await b.moderationAs('admin').auditLog()).first;
      expect(w.action, ModerationActionType.withdrawProfessional);
      expect(w.actorAccountId, 'bob');
      expect(w.targetId, again.id);
    });

    test('an admin cannot verify their own claim', () async {
      final ProfessionalVerification v = await b
          .memberView('admin')
          .claimProfession(ProfessionalClaim(profession: 'Doctor'));
      expect(
        () => b
            .moderationAs('admin')
            .apply(
              req(
                ModerationActionType.verifyProfessional,
                ModerationTargetType.professionalVerification,
                v.id,
              ),
            ),
        _code(CommunityErrorCode.selfActionForbidden),
      );
    });
  });

  group('data rights', () {
    test('export contains own data only, in the contract format', () async {
      await alicePosts();
      final Map<String, dynamic> doc = await b
          .dataRightsFor('alice')
          .exportMyData();
      expect(doc['version'], 1);
      expect((doc['account'] as Map<String, dynamic>)['id'], 'alice');
      expect(doc['posts'], hasLength(1));
      expect(doc.toString().contains('bob'), isFalse);
    });

    test('deletion tombstones content and ends the session', () async {
      final Post p = await alicePosts();
      await b.dataRightsFor('alice').deleteMyAccount('DELETE MY ACCOUNT');
      expect(
        () => b.memberView('bob').getPost(p.id),
        _code(CommunityErrorCode.notFound),
      );
      expect(
        () => b.memberView('alice').getMe(),
        _code(CommunityErrorCode.unauthenticated),
      );
    });

    test(
      'P1: export works for every role; self-deletion is members only',
      () async {
        for (final String who in <String>['alice', 'mod', 'admin']) {
          final Map<String, dynamic> doc = await b
              .dataRightsFor(who)
              .exportMyData();
          expect((doc['account'] as Map<String, dynamic>)['id'], who);
        }
        expect(
          () => b.dataRightsFor('admin').deleteMyAccount('DELETE MY ACCOUNT'),
          _code(CommunityErrorCode.invalidState, 'privileged_account'),
        );
      },
    );

    test('privileged accounts must be demoted first; phrase is exact', () {
      expect(
        () => b.dataRightsFor('mod').deleteMyAccount('DELETE MY ACCOUNT'),
        _code(CommunityErrorCode.invalidState, 'privileged_account'),
      );
      expect(
        () => b.dataRightsFor('alice').deleteMyAccount('delete'),
        _code(CommunityErrorCode.validationFailed),
      );
    });
  });
}
