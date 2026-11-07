import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/community/domain/comment.dart';
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
    'id': 'pst_1',
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
      expect(SpaceId.values, hasLength(2));
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
        final Map<String, dynamic> top = _postJson()..[key] = 'acc_1';
        expect(() => Post.fromJson(top), throwsA(isA<IdentityLeakException>()));
        final Map<String, dynamic> nested = _postJson(
          author: <String, dynamic>{
            'display_mode': 'pseudonymous',
            'display_name': null,
            'badge': null,
            key: 'acc_1',
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
    });
  });

  group('Comment', () {
    final Map<String, dynamic> json = <String, dynamic>{
      'id': 'cmt_1',
      'post_id': 'pst_1',
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
          Map<String, dynamic>.of(json)..['parent_comment_id'] = 'cmt_0',
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
          postId: 'pst_1',
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
    test('draft carries reason and optional trimmed note', () {
      final ReportDraft d = ReportDraft(
        targetType: ReportTargetType.comment,
        targetId: 'cmt_1',
        reason: ReportReason.unsafeMedicalAdvice,
        note: '  dosing advice  ',
      );
      expect(d.toJson(), <String, dynamic>{
        'target_type': 'comment',
        'target_id': 'cmt_1',
        'reason': 'unsafe_medical_advice',
        'note': 'dosing advice',
      });
      final ReportDraft noNote = ReportDraft(
        targetType: ReportTargetType.post,
        targetId: 'pst_1',
        reason: ReportReason.spam,
        note: '   ',
      );
      expect(noNote.toJson().containsKey('note'), isFalse);
    });

    test('note too long rejected', () {
      expect(
        () => ReportDraft(
          targetType: ReportTargetType.post,
          targetId: 'pst_1',
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
        id: 'rpt_1',
        targetType: ReportTargetType.post,
        targetId: 'pst_1',
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
          postId: 'pst_1',
          commentId: 'cmt_1',
          createdAt: _t,
        ),
        CommunityNotification(
          id: 'n2',
          type: CommunityNotificationType.commentReply,
          postId: 'pst_1',
          createdAt: _t,
          readAt: _t,
        ),
        CommunityNotification(
          id: 'n3',
          type: CommunityNotificationType.moderationNotice,
          notice: ModerationNotice.contentHidden,
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

    test('moderation_notice needs a notice; others must not carry one', () {
      expect(
        () => CommunityNotification.fromJson(<String, dynamic>{
          'id': 'n',
          'type': 'moderation_notice',
          'created_at': '2026-11-07T10:15:00Z',
        }),
        throwsFormatException,
      );
      expect(
        () => CommunityNotification.fromJson(<String, dynamic>{
          'id': 'n',
          'type': 'reply_to_post',
          'notice': 'content_hidden',
          'created_at': '2026-11-07T10:15:00Z',
        }),
        throwsFormatException,
      );
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
    });

    test('display name rules', () {
      for (final String bad in [
        'ab',
        'x' * 31,
        'me@example.com',
        '08012345678',
        '0801 234 5678',
        'emoji😀name',
      ]) {
        expect(
          () => CommunityProfile(displayName: bad),
          throwsA(isA<CommunityValidationException>()),
          reason: bad,
        );
      }
      expect(CommunityProfile(displayName: 'Ade_O.2').displayName, 'Ade_O.2');
    });
  });

  group('Professional verification', () {
    test('a self-declared claim is pending, never verified', () {
      final ProfessionalClaim claim = ProfessionalClaim(
        profession: 'Midwife',
        specialty: 'Antenatal care',
      );
      expect(claim.toJson().containsKey('status'), isFalse);
      expect(claim.toJson().containsKey('verified_at'), isFalse);
      final ProfessionalVerification v = claim.asPending();
      expect(v.status, VerificationStatus.pending);
      expect(v.showsBadge, isFalse);
      expect(ProfessionalBadge.fromVerification(v), isNull);
    });

    test('verified requires the server timestamp, and vice versa', () {
      expect(
        () => ProfessionalVerification.fromJson(<String, dynamic>{
          'profession': 'Doctor',
          'status': 'verified',
          'verified_at': null,
        }),
        throwsFormatException,
      );
      expect(
        () => ProfessionalVerification.fromJson(<String, dynamic>{
          'profession': 'Doctor',
          'status': 'pending',
          'verified_at': '2026-11-07T10:15:00Z',
        }),
        throwsFormatException,
      );
      final ProfessionalVerification v =
          ProfessionalVerification.fromJson(<String, dynamic>{
            'profession': 'Doctor',
            'specialty': null,
            'status': 'verified',
            'verified_at': '2026-11-07T10:15:00Z',
          });
      expect(v.showsBadge, isTrue);
      expect(ProfessionalVerification.fromJson(v.toJson()), v);
    });

    test('revoked and unverified show no badge', () {
      for (final String s in ['unverified', 'revoked', 'pending']) {
        final ProfessionalVerification v = ProfessionalVerification.fromJson(
          <String, dynamic>{
            'profession': 'Nurse',
            'status': s,
            'verified_at': null,
          },
        );
        expect(v.showsBadge, isFalse, reason: s);
      }
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
            targetId: 'pst_1',
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
        targetId: 'pst_1',
        reason: 'Shares a phone number',
      );
      expect(
        r.toJson().keys,
        unorderedEquals(<String>['target_type', 'target_id', 'reason']),
      );
    });

    test('audit record round-trip; blank reason rejected', () {
      final ModerationAction a = ModerationAction(
        id: 'mod_1',
        actorAccountId: 'acc_mod',
        action: ModerationActionType.revealIdentity,
        targetType: ModerationTargetType.comment,
        targetId: 'cmt_1',
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
