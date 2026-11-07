import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/community/domain/comment.dart';
import 'package:wellapath_mobile/features/community/domain/community_ids.dart';
import 'package:wellapath_mobile/features/community/domain/community_json.dart';
import 'package:wellapath_mobile/features/community/domain/community_notification.dart';
import 'package:wellapath_mobile/features/community/domain/community_profile.dart';
import 'package:wellapath_mobile/features/community/domain/community_validation.dart';
import 'package:wellapath_mobile/features/community/domain/moderation.dart';
import 'package:wellapath_mobile/features/community/domain/post.dart';
import 'package:wellapath_mobile/features/community/domain/professional_verification.dart';
import 'package:wellapath_mobile/features/community/domain/public_author.dart';
import 'package:wellapath_mobile/features/community/domain/report.dart';
import 'package:wellapath_mobile/features/community/domain/space.dart';

final DateTime _t = DateTime.utc(2026, 11, 7, 10, 15);

Map<String, dynamic> _postJson({Map<String, dynamic>? author}) {
  return <String, dynamic>{
    'id': '0192f1d2-0000-7000-8000-000000000001',
    'space_id': 'pregnancy_maternal',
    'body': 'Hello',
    'author':
        author ??
        <String, dynamic>{
          'display_mode': 'pseudonymous',
          'display_name': null,
          'badge': null,
        },
    'viewer_is_author': false,
    'status': 'visible',
    'comment_count': 2,
    'created_at': '2026-11-07T10:15:00Z',
  };
}

/// Every key anywhere in a JSON tree.
Set<String> _allKeys(Object? node) {
  final Set<String> keys = {};
  if (node is Map) {
    for (final MapEntry<dynamic, dynamic> e in node.entries) {
      keys.add(e.key as String);
      keys.addAll(_allKeys(e.value));
    }
  } else if (node is List) {
    for (final Object? v in node) {
      keys.addAll(_allKeys(v));
    }
  }
  return keys;
}

void main() {
  group('Space', () {
    test('exactly the two approved spaces', () {
      expect(Space.approved, hasLength(2));
      expect(Space.approved.map((Space s) => s.id.wire), [
        'general_health',
        'pregnancy_maternal',
      ]);
      expect(Space.approved.map((Space s) => s.name), [
        'General Health',
        'Pregnancy and Maternal Health',
      ]);
      expect(SpaceId.values, hasLength(2));
    });

    test('a list with an unknown space id ignores that space (§8.1)', () {
      final List<Space> spaces = Space.listFromJson(<String, dynamic>{
        'items': <Object>[
          Space.approved.first.toJson(),
          <String, dynamic>{
            'id': 'mental_health',
            'name': 'x',
            'description': 'y',
          },
        ],
      });
      expect(spaces, <Space>[Space.approved.first]);
    });

    test('round-trips and rejects unknown ids', () {
      for (final Space s in Space.approved) {
        expect(Space.fromJson(s.toJson()), s);
      }
      expect(
        () => Space.fromJson(<String, dynamic>{
          'id': 'mental_health',
          'name': 'x',
          'description': 'y',
        }),
        throwsFormatException,
      );
    });
  });

  group('Post', () {
    test('JSON round-trip (pseudonymous and named with badge)', () {
      final Post p = Post.fromJson(_postJson());
      expect(Post.fromJson(p.toJson()), p);
      expect(p.author.label, 'Community member');

      final Post named = Post.fromJson(
        _postJson(
          author: <String, dynamic>{
            'display_mode': 'named',
            'display_name': 'SunnyMum',
            'badge': <String, dynamic>{
              'profession': 'Midwife',
              'specialty': null,
            },
          },
        ),
      );
      expect(Post.fromJson(named.toJson()), named);
      expect(named.author.badge!.profession, 'Midwife');
    });

    test('only status "visible" is accepted in a member DTO (§8.1)', () {
      for (final String s in <String>[
        'hidden',
        'removed',
        'deleted_by_author',
        'tombstoned',
      ]) {
        expect(
          () => Post.fromJson(_postJson()..['status'] = s),
          throwsFormatException,
          reason: s,
        );
      }
      expect(Post.fromJson(_postJson()).toJson()['status'], 'visible');
    });

    test('identity keys are rejected at any depth', () {
      final Map<String, dynamic> deep = _postJson();
      (deep['author'] as Map<String, dynamic>)['badge'] = <String, dynamic>{
        'profession': 'Midwife',
        'specialty': null,
        'reporter_id': 'r',
      };
      deep['author'] = <String, dynamic>{
        'display_mode': 'named',
        'display_name': 'X',
        'badge': (deep['author'] as Map<String, dynamic>)['badge'],
      };
      expect(() => Post.fromJson(deep), throwsA(isA<IdentityLeakException>()));
      expect(
        kForbiddenMemberIdentityKeys,
        containsAll(<String>['author_email', 'email', 'reporter_id']),
      );
    });

    test('pseudonymous member DTO has no author id anywhere', () {
      final Post p = Post.fromJson(_postJson());
      final Set<String> keys = _allKeys(p.toJson());
      for (final String forbidden in kForbiddenMemberIdentityKeys) {
        expect(keys, isNot(contains(forbidden)));
      }
      expect(keys.where((String k) => k.contains('account')), isEmpty);
    });

    test('a payload leaking an author id is rejected', () {
      for (final String key in kForbiddenMemberIdentityKeys) {
        final Map<String, dynamic> top = _postJson()..[key] = 'Xk3abc';
        expect(() => Post.fromJson(top), throwsA(isA<IdentityLeakException>()));
        final Map<String, dynamic> nested = _postJson(
          author: <String, dynamic>{
            'display_mode': 'pseudonymous',
            'display_name': null,
            'badge': null,
            key: 'Xk3abc',
          },
        );
        expect(
          () => Post.fromJson(nested),
          throwsA(isA<IdentityLeakException>()),
        );
      }
    });

    test('pseudonymous author carrying a name or badge is rejected', () {
      expect(
        () => Post.fromJson(
          _postJson(
            author: <String, dynamic>{
              'display_mode': 'pseudonymous',
              'display_name': 'SunnyMum',
              'badge': null,
            },
          ),
        ),
        throwsFormatException,
      );
    });

    test('empty body rejected in draft and payload', () {
      for (final String body in ['', '   ', '\n\t']) {
        expect(
          () => PostDraft(
            spaceId: SpaceId.generalHealth,
            body: body,
            displayMode: DisplayMode.named,
          ),
          throwsA(isA<CommunityValidationException>()),
        );
      }
      expect(
        () => Post.fromJson(_postJson()..['body'] = ' '),
        throwsFormatException,
      );
    });

    test('over-long body rejected; body is trimmed', () {
      expect(
        () => PostDraft(
          spaceId: SpaceId.generalHealth,
          body: 'a' * (CommunityLimits.postBodyMax + 1),
          displayMode: DisplayMode.named,
        ),
        throwsA(isA<CommunityValidationException>()),
      );
      final PostDraft d = PostDraft(
        spaceId: SpaceId.generalHealth,
        body: '  hi  ',
        displayMode: DisplayMode.pseudonymous,
      );
      expect(d.toJson(), <String, dynamic>{
        'body': 'hi',
        'display_mode': 'pseudonymous',
      });
    });

    test('missing/mistyped fields throw', () {
      expect(
        () => Post.fromJson(_postJson()..remove('created_at')),
        throwsFormatException,
      );
      expect(
        () => Post.fromJson(_postJson()..['comment_count'] = '2'),
        throwsFormatException,
      );
      expect(
        () => Post.fromJson(_postJson()..['status'] = 'pinned'),
        throwsFormatException,
      );
      expect(
        () => Post.fromJson(_postJson()..['comment_count'] = -1),
        throwsFormatException,
      );
      final Map<String, dynamic> noBadgeKey = _postJson(
        author: <String, dynamic>{'display_mode': 'named', 'display_name': 'A'},
      );
      expect(() => Post.fromJson(noBadgeKey), throwsFormatException);
    });

    test('drafts carry a UUID idempotency key, stable per draft', () {
      final PostDraft d = PostDraft(
        spaceId: SpaceId.generalHealth,
        body: 'x',
        displayMode: DisplayMode.named,
      );
      expect(isUuid(d.idempotencyKey), isTrue);
      expect(d.toJson().containsKey('idempotency_key'), isFalse);
      expect(
        PostDraft(
          spaceId: SpaceId.generalHealth,
          body: 'x',
          displayMode: DisplayMode.named,
        ).idempotencyKey,
        isNot(d.idempotencyKey),
      );
    });
  });

  group('Comment', () {
    final Map<String, dynamic> json = <String, dynamic>{
      'id': 'c0000000-0000-4000-8000-000000000001',
      'post_id': '0192f1d2-0000-7000-8000-000000000001',
      'body': 'Thanks',
      'author': <String, dynamic>{
        'display_mode': 'named',
        'display_name': 'Ade',
        'badge': null,
      },
      'viewer_is_author': true,
      'status': 'visible',
      'created_at': '2026-11-07T10:15:00Z',
    };

    test('round-trip', () {
      final Comment c = Comment.fromJson(json);
      expect(Comment.fromJson(c.toJson()), c);
    });

    test('single level: parent_comment_id is rejected', () {
      expect(
        () => Comment.fromJson(
          Map<String, dynamic>.of(json)
            ..['parent_comment_id'] = 'c0000000-0000-4000-8000-000000000000',
        ),
        throwsFormatException,
      );
      expect(
        Comment.fromJson(json).toJson(),
        isNot(contains('parent_comment_id')),
      );
    });

    test('empty body rejected; identity keys rejected', () {
      expect(
        () => CommentDraft(
          postId: '0192f1d2-0000-7000-8000-000000000001',
          body: '  ',
          displayMode: DisplayMode.named,
        ),
        throwsA(isA<CommunityValidationException>()),
      );
      expect(
        () => Comment.fromJson(
          Map<String, dynamic>.of(json)..['author_id'] = 'a',
        ),
        throwsA(isA<IdentityLeakException>()),
      );
    });
  });

  group('Report', () {
    test('ReportCreated is always open', () {
      final ReportCreated r = ReportCreated.fromJson(<String, dynamic>{
        'id': 'r1',
        'status': 'open',
        'created_at': '2026-11-07T10:15:00.000Z',
      });
      expect(ReportCreated.fromJson(r.toJson()).id, 'r1');
      expect(
        () => ReportCreated.fromJson(<String, dynamic>{
          'id': 'r1',
          'status': 'actioned',
          'created_at': '2026-11-07T10:15:00.000Z',
        }),
        throwsFormatException,
      );
    });

    test('draft carries reason and optional trimmed note', () {
      final ReportDraft d = ReportDraft(
        targetType: ReportTargetType.comment,
        targetId: 'c0000000-0000-4000-8000-000000000001',
        reason: ReportReason.unsafeMedicalAdvice,
        note: '  dosing advice  ',
      );
      expect(d.toJson(), <String, dynamic>{
        'target_type': 'comment',
        'target_id': 'c0000000-0000-4000-8000-000000000001',
        'reason': 'unsafe_medical_advice',
        'note': 'dosing advice',
      });
      final ReportDraft noNote = ReportDraft(
        targetType: ReportTargetType.post,
        targetId: '0192f1d2-0000-7000-8000-000000000001',
        reason: ReportReason.spam,
        note: '   ',
      );
      expect(noNote.toJson().containsKey('note'), isFalse);
    });

    test('P9: target_id is capped at 64 (not 128)', () {
      expect(CommunityLimits.reportTargetIdMax, 64);
      expect(
        ReportDraft(
          targetType: ReportTargetType.post,
          targetId: 'a' * 64,
          reason: ReportReason.spam,
        ).targetId,
        hasLength(64),
      );
      expect(
        () => ReportDraft(
          targetType: ReportTargetType.post,
          targetId: 'a' * 65,
          reason: ReportReason.spam,
        ),
        throwsA(
          isA<CommunityValidationException>().having(
            (CommunityValidationException e) => e.field,
            'field',
            'target_id',
          ),
        ),
      );
    });

    test('note too long rejected', () {
      expect(
        () => ReportDraft(
          targetType: ReportTargetType.post,
          targetId: '0192f1d2-0000-7000-8000-000000000001',
          reason: ReportReason.other,
          note: 'x' * (CommunityLimits.reportNoteMax + 1),
        ),
        throwsA(isA<CommunityValidationException>()),
      );
    });

    test('reason wire names match the contract', () {
      expect(ReportReason.values.map((ReportReason r) => r.wire), [
        'spam',
        'harassment',
        'misinformation',
        'unsafe_medical_advice',
        'self_harm_or_emergency',
        'personal_information',
        'other',
      ]);
    });

    test('stored report round-trip', () {
      final Report r = Report(
        id: 'a0000000-0000-4000-8000-000000000001',
        targetType: ReportTargetType.post,
        targetId: '0192f1d2-0000-7000-8000-000000000001',
        reason: ReportReason.harassment,
        note: null,
        status: ReportStatus.open,
        createdAt: _t,
      );
      expect(Report.fromJson(r.toJson()), r);
    });
  });

  group('Notification', () {
    test('round-trip for all types', () {
      final List<CommunityNotification> all = [
        CommunityNotification(
          id: 'n1',
          type: CommunityNotificationType.replyToPost,
          postId: '0192f1d2-0000-7000-8000-000000000001',
          commentId: 'c0000000-0000-4000-8000-000000000001',
          createdAt: _t,
        ),
        CommunityNotification(
          id: 'n2',
          type: CommunityNotificationType.commentReply,
          postId: '0192f1d2-0000-7000-8000-000000000001',
          createdAt: _t,
          readAt: _t,
        ),
        CommunityNotification(
          id: 'n3',
          type: CommunityNotificationType.moderationNotice,
          notice: ModerationNotice.contentHidden,
          createdAt: _t,
        ),
        for (final ModerationNotice notice in <ModerationNotice>[
          ModerationNotice.contentRestored,
          ModerationNotice.accountReinstated,
        ])
          CommunityNotification(
            id: 'n_${notice.wire}',
            type: CommunityNotificationType.moderationNotice,
            notice: notice,
            createdAt: _t,
          ),
      ];
      for (final CommunityNotification n in all) {
        expect(CommunityNotification.fromJson(n.toJson()), n);
        expect(n.summary, isNotEmpty);
      }
      expect(CommunityNotificationType.replyToPost.wire, 'reply_to_post');
      expect(CommunityNotificationType.commentReply.wire, 'comment_reply');
      expect(
        CommunityNotificationType.moderationNotice.wire,
        'moderation_notice',
      );
    });

    Map<String, dynamic> n(String type, String? notice) => <String, dynamic>{
      'id': 'n',
      'type': type,
      'post_id': null,
      'comment_id': null,
      'notice': notice,
      'created_at': '2026-11-07T10:15:00Z',
      'read_at': null,
    };

    test('moderation_notice needs a notice; others must not carry one', () {
      expect(
        () => CommunityNotification.fromJson(n('moderation_notice', null)),
        throwsFormatException,
      );
      expect(
        () => CommunityNotification.fromJson(
          n('reply_to_post', 'content_hidden'),
        ),
        throwsFormatException,
      );
    });

    test('unknown type is skipped; unknown notice is generic (§13)', () {
      expect(CommunityNotification.tryFromJson(n('new_kind', null)), isNull);
      final CommunityNotification g = CommunityNotification.fromJson(
        n('moderation_notice', 'new_notice'),
      );
      expect(g.notice, ModerationNotice.unrecognised);
      expect(g.summary, isNotEmpty);
    });

    test('markRead is idempotent', () {
      final CommunityNotification n = CommunityNotification(
        id: 'n',
        type: CommunityNotificationType.replyToPost,
        createdAt: _t,
      );
      final CommunityNotification read = n.markRead(_t);
      expect(read.isRead, isTrue);
      expect(read.markRead(_t.add(const Duration(days: 1))).readAt, _t);
    });
  });

  group('Profile', () {
    test('round-trip', () {
      final CommunityProfile p = CommunityProfile(displayName: ' SunnyMum ');
      expect(p.displayName, 'SunnyMum');
      expect(CommunityProfile.fromJson(p.toJson()), p);
      expect(
        () => CommunityProfile.fromJson(<String, dynamic>{
          'display_name': 'SunnyMum',
        }),
        throwsFormatException,
        reason: 'professional is a required (nullable) key',
      );
    });

    test('display name rules use the contract rule names', () {
      final Map<String, String> bad = <String, String>{
        'ab': 'min_length',
        'x' * 31: 'max_length',
        'me@example.com': 'not_allowed_value',
        '08012345678': 'not_allowed_value',
        '0801 234 5678': 'not_allowed_value',
        'emoji😀name': 'pattern',
        'two  spaces': 'pattern',
      };
      bad.forEach((String name, String rule) {
        expect(
          () => CommunityProfile(displayName: name),
          throwsA(
            isA<CommunityValidationException>().having(
              (CommunityValidationException e) => e.rule,
              'rule',
              rule,
            ),
          ),
          reason: name,
        );
      });
      expect(CommunityProfile(displayName: 'Ade_O.2').displayName, 'Ade_O.2');
      expect(CommunityProfile(displayName: 'Mum of 2').displayName, 'Mum of 2');
    });

    // P7 (founder-approved 2026-11-08): the same cases as the backend suite
    // (tests/community/content.test.ts), so both sides apply one rule.
    test('P7: 7+ digits in total or email-like is not_allowed_value', () {
      for (final String name in <String>[
        'call 0803123456',
        'john.doe.gmail.com',
        'Mum1234567',
        'M1u2m3 4x5y6z7',
        '0 8 0 1 2 3 4',
        'me@example.com',
        'a@b',
        'sunny.NG',
        'mum.app',
      ]) {
        expect(
          () => CommunityProfile(displayName: name),
          throwsA(
            isA<CommunityValidationException>().having(
              (CommunityValidationException e) => e.rule,
              'rule',
              'not_allowed_value',
            ),
          ),
          reason: name,
        );
      }
      for (final String name in <String>[
        'Mum123456',
        'M1u2m3 4x5y6',
        'Dr. Ada',
        'ada.lovelace',
        'cool.company x',
        '.com fan',
      ]) {
        expect(CommunityProfile(displayName: name).displayName, name);
      }
      expect(CommunityProfile.maxDigits, 6);
      expect(
        CommunityProfile.emailLike.pattern,
        r'@|[A-Za-z0-9]\.(com|net|org|ng|io|co|uk|edu|gov|info|me|app)$',
      );
    });
  });

  group('Professional verification', () {
    test('a self-declared claim is pending, never verified', () {
      final ProfessionalClaim claim = ProfessionalClaim(
        profession: 'Midwife',
        specialty: 'Antenatal care',
      );
      expect(
        claim.toJson().keys,
        unorderedEquals(<String>['profession', 'specialty']),
      );
      final ProfessionalVerification v = ProfessionalVerification.pending(
        id: 'v1',
        profession: claim.profession,
        specialty: claim.specialty,
        createdAt: _t,
      );
      expect(v.status, VerificationStatus.pending);
      expect(v.showsBadge, isFalse);
      expect(ProfessionalBadge.fromVerification(v), isNull);
    });

    Map<String, dynamic> pv(String status, String? verifiedAt) =>
        <String, dynamic>{
          'id': 'v1',
          'profession': 'Doctor',
          'specialty': null,
          'status': status,
          'verified_at': verifiedAt,
          'created_at': '2026-11-07T10:00:00Z',
        };

    test('verified requires the server timestamp, and vice versa', () {
      expect(
        () => ProfessionalVerification.fromJson(pv('verified', null)),
        throwsFormatException,
      );
      expect(
        () => ProfessionalVerification.fromJson(
          pv('pending', '2026-11-07T10:15:00Z'),
        ),
        throwsFormatException,
      );
      final ProfessionalVerification v = ProfessionalVerification.fromJson(
        pv('verified', '2026-11-07T10:15:00Z'),
      );
      expect(v.showsBadge, isTrue);
      expect(ProfessionalVerification.fromJson(v.toJson()), v);
    });

    test('only verified shows a badge; unknown status fails closed', () {
      for (final String s in ['revoked', 'pending', 'claimed', 'unverified']) {
        final ProfessionalVerification v = ProfessionalVerification.fromJson(
          pv(s, null),
        );
        expect(v.showsBadge, isFalse, reason: s);
      }
      // "unverified" is not a wire value (§15 row 42): no record means it.
      expect(
        ProfessionalVerification.fromJson(pv('unverified', null)).status,
        VerificationStatus.unrecognised,
      );
    });

    test('profession and specialty are 2–80 after trim', () {
      expect(
        () => ProfessionalClaim(profession: 'x'),
        throwsA(isA<CommunityValidationException>()),
      );
      expect(
        () => ProfessionalClaim(profession: 'Nurse', specialty: 'x'),
        throwsA(isA<CommunityValidationException>()),
      );
      expect(
        ProfessionalClaim(profession: ' Nurse ', specialty: '  ').toJson(),
        <String, dynamic>{'profession': 'Nurse'},
      );
    });

    test('empty profession rejected', () {
      expect(
        () => ProfessionalClaim(profession: '  '),
        throwsA(isA<CommunityValidationException>()),
      );
    });
  });

  group('Moderation', () {
    test('every request needs a real reason', () {
      for (final String reason in ['', '   ', 'too short']) {
        expect(
          () => ModerationRequest(
            action: ModerationActionType.hideContent,
            targetType: ModerationTargetType.post,
            targetId: '0192f1d2-0000-7000-8000-000000000001',
            reason: reason,
          ),
          throwsA(isA<CommunityValidationException>()),
        );
      }
    });

    test('request carries no actor or timestamp', () {
      final ModerationRequest r = ModerationRequest(
        action: ModerationActionType.hideContent,
        targetType: ModerationTargetType.post,
        targetId: '0192f1d2-0000-7000-8000-000000000001',
        reason: 'Shares a phone number',
      );
      expect(
        r.toJson().keys,
        unorderedEquals(<String>['target_type', 'target_id', 'reason']),
      );
    });

    test('audit record round-trip; blank reason rejected', () {
      final ModerationAction a = ModerationAction(
        id: '1042',
        actorAccountId: 'Mod9xyz',
        action: ModerationActionType.revealIdentity,
        targetType: ModerationTargetType.comment,
        targetId: 'c0000000-0000-4000-8000-000000000001',
        reason: 'Investigating a harassment report',
        createdAt: _t,
      );
      expect(ModerationAction.fromJson(a.toJson()), a);
      expect(
        () => ModerationAction.fromJson(a.toJson()..['reason'] = ' '),
        throwsFormatException,
      );
      expect(ModerationActionType.revealIdentity.wire, 'reveal_identity');
    });
  });
}
