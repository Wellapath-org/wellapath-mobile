/// Contract tests against the canonical OpenAPI file (mobile copy:
/// `docs/community/community_api_v1.openapi.yaml`; canonical source:
/// `WELLAPATH_ENGINEERING/community_api_v1.openapi.yaml`).
///
/// 1. Every request the client builds matches an operation (method + path)
///    in the spec, and its body, query and required headers conform.
/// 2. Every member-facing operation is implemented by the client; none of the
///    moderator/admin/TOTP operations is.
/// 3. Responses generated from the spec's own schemas decode with the
///    client's strict parsers — once with every optional field filled, once
///    minimal (nulls where allowed, the other `oneOf` branch).
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/community/data/community_auth_api.dart';
import 'package:wellapath_mobile/features/community/data/community_http_client.dart';
import 'package:wellapath_mobile/features/community/data/community_repositories.dart';
import 'package:wellapath_mobile/features/community/data/http_community_repository.dart';
import 'package:wellapath_mobile/features/community/domain/comment.dart';
import 'package:wellapath_mobile/features/community/domain/community_ids.dart';
import 'package:wellapath_mobile/features/community/domain/community_me.dart';
import 'package:wellapath_mobile/features/community/domain/community_notification.dart';
import 'package:wellapath_mobile/features/community/domain/community_profile.dart';
import 'package:wellapath_mobile/features/community/domain/community_session.dart';
import 'package:wellapath_mobile/features/community/domain/community_validation.dart';
import 'package:wellapath_mobile/features/community/domain/post.dart';
import 'package:wellapath_mobile/features/community/domain/professional_verification.dart';
import 'package:wellapath_mobile/features/community/domain/public_author.dart';
import 'package:wellapath_mobile/features/community/domain/report.dart';
import 'package:wellapath_mobile/features/community/domain/space.dart';
import 'package:wellapath_mobile/features/community/gate/community_features.dart';

import 'support/fake_community_server.dart';
import 'support/openapi_spec.dart';

class _Tokens implements CommunityAccessTokens {
  @override
  Future<String?> accessToken() async => 'access';

  @override
  Future<String?> renewAfterExpiry(String rejected) async => null;

  @override
  Future<void> sessionEnded() async {}
}

/// A fake server that answers every request from the spec itself, and
/// records which operation each request hit.
class _SpecServer {
  _SpecServer(this.spec, {required this.rich}) {
    adapter = FakeCommunityAdapter(_answer);
    raw = CommunityHttpClient.forBaseUrl(
      'https://community.test',
      adapter: adapter,
    );
  }

  final OpenApiSpec spec;
  final bool rich;
  late final FakeCommunityAdapter adapter;
  late final CommunityHttpClient raw;
  final List<String> problems = <String>[];
  final Set<String> hit = <String>{};

  Future<FakeReply> _answer(RecordedRequest r) async {
    final SpecOperation? op = spec.find(r.method, r.path);
    if (op == null) {
      problems.add('no spec operation for ${r.method} ${r.path}');
      return const FakeReply(404);
    }
    hit.add(op.id);
    _checkRequest(op, r);
    final (int status, Map<String, Object?>? schema) = op.success;
    return FakeReply(
      status,
      schema == null ? null : spec.generate(schema, rich: rich),
    );
  }

  void _checkRequest(SpecOperation op, RecordedRequest r) {
    final Map<String, Object?>? body = op.requestSchema;
    if (body == null) {
      if (r.body != null) problems.add('${op.id}: sends an undeclared body');
    } else if (r.body == null && op.requestBodyRequired) {
      problems.add('${op.id}: required body missing');
    } else if (r.body != null) {
      for (final String e in spec.validate(body, r.body)) {
        problems.add('${op.id}: body $e');
      }
    }
    final Set<String> declaredQuery = <String>{};
    for (final Map<String, Object?> p in op.parameters) {
      final String name = p['name']! as String;
      final String where = p['in']! as String;
      if (where == 'query') {
        declaredQuery.add(name);
        if (r.query.containsKey(name)) {
          for (final String e in spec.validate(
            p['schema']! as Map<String, Object?>,
            r.query[name],
          )) {
            problems.add('${op.id}: query $name $e');
          }
        }
      }
      if (where == 'header' && p['required'] == true) {
        final String? v = r.header(name);
        if (v == null) {
          problems.add('${op.id}: required header $name missing');
        } else {
          for (final String e in spec.validate(
            p['schema']! as Map<String, Object?>,
            v,
          )) {
            problems.add('${op.id}: header $name $e');
          }
        }
      }
      if (where == 'path') {
        final Map<String, Object?> s = spec.resolve(
          p['schema']! as Map<String, Object?>,
        );
        if (s.containsKey('enum')) {
          final List<String> segs = r.path.split('/');
          final List<String> tpl = op.template.split('/');
          final String value = segs[tpl.indexOf('{$name}')];
          if (!(s['enum']! as List<Object?>).contains(value)) {
            problems.add('${op.id}: path $name "$value" not in enum');
          }
        }
      }
    }
    for (final String q in r.query.keys) {
      if (!declaredQuery.contains(q)) {
        problems.add('${op.id}: undeclared query parameter $q');
      }
    }
    final bool secured =
        op.raw['security'] is! List ||
        (op.raw['security']! as List<Object?>).any(
          (Object? s) => s is Map && s.containsKey('bearerAuth'),
        );
    final bool optional =
        (op.raw['security'] as List<Object?>?)?.any(
          (Object? s) => s is Map && s.isEmpty,
        ) ??
        false;
    final bool sentBearer = r.header('authorization') != null;
    if (secured && !optional && !sentBearer) {
      problems.add('${op.id}: bearer required but not sent');
    }
    if (!secured && sentBearer && op.template != '/v1/auth/logout') {
      problems.add('${op.id}: sends a bearer to a public route');
    }
  }
}

/// Calls every client operation once.
Future<void> _driveEveryOperation(_SpecServer s) async {
  final CommunityAuthApi auth = CommunityAuthApi(s.raw);
  final CommunityHttpClient authed = s.raw.withTokens(_Tokens());
  final HttpCommunityRepository repo = HttpCommunityRepository(authed);
  final CommunityDeviceSessionsApi devices = CommunityDeviceSessionsApi(authed);
  final String device = newUuidV4();

  await RemoteCommunityFeatureSource(authed).fetch();
  await auth.requestOtp('a@b.ng');
  await auth.verifyOtp(
    email: 'a@b.ng',
    code: '123456',
    deviceId: device,
    deviceLabel: 'WellaPath app on Android',
  );
  await auth.verifyOtp(email: 'a@b.ng', code: '123456', deviceId: device);
  await auth.refresh(refreshToken: wprt('r1'), deviceId: device);
  await auth.logout(accessToken: 'access', refreshToken: wprt('r2'));
  await auth.logout(accessToken: 'access');
  await devices.list();
  await devices.revokeOthers();

  await repo.getMe();
  await repo.getProfile();
  await repo.setDisplayName('SunnyMum');
  await repo.getProfessionalClaim();
  await repo.claimProfession(
    ProfessionalClaim(profession: 'Midwife', specialty: 'Antenatal care'),
  );
  await repo.claimProfession(ProfessionalClaim(profession: 'Nurse'));
  await repo.withdrawProfessionalClaim();
  await repo.exportMyData();
  await repo.deleteMyAccount('DELETE MY ACCOUNT');

  await repo.listSpaces();
  for (final SpaceId id in SpaceId.values) {
    await repo.listPosts(id);
    await repo.listPosts(id, cursor: 'opaque', limit: 50);
    await repo.createPost(
      PostDraft(spaceId: id, body: 'Hello', displayMode: DisplayMode.named),
    );
  }
  await repo.getPost('0192f1d2-aaaa');
  await repo.deletePost('0192f1d2-aaaa');
  await repo.listComments('0192f1d2-aaaa', limit: 1);
  await repo.createComment(
    CommentDraft(
      postId: '0192f1d2-aaaa',
      body: 'Thanks',
      displayMode: DisplayMode.pseudonymous,
    ),
  );
  await repo.deleteComment('c-1');
  await repo.submitReport(
    ReportDraft(
      targetType: ReportTargetType.comment,
      targetId: 'c-1',
      reason: ReportReason.unsafeMedicalAdvice,
      note: 'dosing',
    ),
  );
  await repo.submitReport(
    ReportDraft(
      targetType: ReportTargetType.post,
      targetId: 'p-1',
      reason: ReportReason.spam,
    ),
  );
  await repo.list();
  await repo.list(cursor: 'next', limit: 5);
  await repo.unreadCount();
  await repo.markRead('n-1');
  await repo.markAllRead();
}

bool _memberFacing(SpecOperation op) {
  return !op.template.contains('/mod/') &&
      !op.template.contains('/admin/') &&
      !op.template.contains('/totp');
}

void main() {
  final OpenApiSpec spec = OpenApiSpec.load();

  group('the mobile spec copy', () {
    test('is the canonical file, recorded by hash in the pointer doc', () {
      final String yaml = File(kSpecPath).readAsStringSync();
      expect(yaml.split('\n').first, contains('CANONICAL'));
      final String hash = sha256
          .convert(File(kSpecPath).readAsBytesSync())
          .toString();
      final String pointer = File(
        'docs/community/API_CONTRACT.md',
      ).readAsStringSync();
      expect(
        pointer,
        contains(hash),
        reason:
            'docs/community/API_CONTRACT.md must record the SHA-256 of the '
            'copied spec; re-copy from WELLAPATH_ENGINEERING and update it',
      );
    });

    test('has the operations this test relies on', () {
      expect(spec.operations.length, greaterThan(40));
      expect(
        spec.find('GET', '/v1/community/spaces/general_health/posts'),
        isNotNull,
      );
      expect(
        spec.find('POST', '/v1/community/notifications/read-all')!.template,
        '/v1/community/notifications/read-all',
      );
    });
  });

  test('the checker itself catches violations (guard self-test)', () {
    expect(spec.find('POST', '/v1/community/posts/p/replies'), isNull);
    expect(spec.find('PATCH', '/v1/community/me/profile'), isNull);
    expect(spec.find('POST', '/v1/community/mod/posts/p/hide'), isNotNull);
    final Map<String, Object?> claim = spec.schema('ProfessionalClaim');
    expect(
      spec.validate(claim, <String, Object?>{
        'profession': 'Midwife',
        'status': 'verified',
      }),
      contains(r'$.status: unknown_field'),
    );
    expect(spec.validate(claim, <String, Object?>{}), isNotEmpty);
    expect(
      spec.validate(spec.schema('PostCreate'), <String, Object?>{
        'body': 'x',
        'display_mode': 'anonymous',
      }),
      isNotEmpty,
    );
    expect(
      spec.validate(spec.schema('CommentCreate'), <String, Object?>{
        'body': 'x',
        'display_mode': 'named',
        'parent_comment_id': 'c',
      }),
      isNotEmpty,
    );
    expect(
      spec.validate(spec.schema('PublicAuthor'), <String, Object?>{
        'display_mode': 'pseudonymous',
        'display_name': 'SunnyMum',
        'badge': null,
      }),
      isNotEmpty,
    );
  });

  for (final bool rich in <bool>[true, false]) {
    final String mode = rich ? 'rich' : 'minimal';
    test('every client request matches the spec ($mode fixtures)', () async {
      final _SpecServer s = _SpecServer(spec, rich: rich);
      await _driveEveryOperation(s);
      expect(s.problems, isEmpty);
      expect(s.adapter.requests, isNotEmpty);
    });
  }

  test(
    'every member-facing operation is implemented, nothing privileged',
    () async {
      final _SpecServer s = _SpecServer(spec, rich: true);
      await _driveEveryOperation(s);
      final Set<String> memberOps = spec.operations
          .where(_memberFacing)
          .map((SpecOperation o) => o.id)
          .toSet();
      expect(memberOps.difference(s.hit), isEmpty, reason: 'not implemented');
      expect(
        s.hit.where((String id) => !memberOps.contains(id)),
        isEmpty,
        reason: 'the app has no moderator/admin/TOTP client',
      );
    },
  );

  group('fixtures generated from spec schemas decode', () {
    final Map<String, void Function(Map<String, dynamic>)> decoders =
        <String, void Function(Map<String, dynamic>)>{
          'Features': CommunityFeatures.fromJson,
          'TokenPair': TokenPair.fromJson,
          'Session': DeviceSession.fromJson,
          'Me': CommunityMe.fromJson,
          'Profile': CommunityProfile.fromJson,
          'ProfessionalVerification': ProfessionalVerification.fromJson,
          'Badge': ProfessionalBadge.fromJson,
          'PublicAuthor': PublicAuthor.fromJson,
          'Space': Space.fromJson,
          'Post': Post.fromJson,
          'Comment': Comment.fromJson,
          'PostPage': (Map<String, dynamic> j) =>
              CommunityPage<Post>.fromJson(j, Post.fromJson),
          'CommentPage': (Map<String, dynamic> j) =>
              CommunityPage<Comment>.fromJson(j, Comment.fromJson),
          'ReportCreated': ReportCreated.fromJson,
          'Notification': CommunityNotification.fromJson,
          'NotificationPage': (Map<String, dynamic> j) =>
              CommunityPage<CommunityNotification>.fromJson(
                j,
                CommunityNotification.tryFromJson,
              ),
          'Export': checkExportDocument,
          'Error': (Map<String, dynamic> j) {
            final CommunityException e = CommunityException.fromEnvelope(
              400,
              j,
            );
            expect(e.code, CommunityErrorCode.validationFailed);
          },
        };

    for (final MapEntry<String, void Function(Map<String, dynamic>)> d
        in decoders.entries) {
      for (final bool rich in <bool>[true, false]) {
        test('${d.key} (${rich ? 'rich' : 'minimal'})', () {
          final Object? fixture = spec.generate(<String, Object?>{
            r'$ref': '#/components/schemas/${d.key}',
          }, rich: rich);
          expect(
            spec.validate(spec.schema(d.key), fixture),
            isEmpty,
            reason: 'generator must produce spec-valid data',
          );
          d.value(fixture! as Map<String, dynamic>);
        });
      }
    }

    test(
      'both PublicAuthor branches decode; the forbidden mix is rejected',
      () {
        final Map<String, Object?> s = spec.schema('PublicAuthor');
        for (final Object? branch in s['oneOf']! as List<Object?>) {
          final Map<String, dynamic> j =
              spec.generate(branch! as Map<String, Object?>, rich: true)!
                  as Map<String, dynamic>;
          expect(PublicAuthor.fromJson(j).displayMode.wire, j['display_mode']);
        }
        expect(
          () => PublicAuthor.fromJson(<String, dynamic>{
            'display_mode': 'pseudonymous',
            'display_name': 'SunnyMum',
            'badge': null,
          }),
          throwsFormatException,
        );
      },
    );

    test('every notification type and notice in the spec decodes', () {
      for (final Object? t
          in spec.schema('NotificationType')['enum']! as List<Object?>) {
        for (final Object? n
            in spec.schema('ModerationNotice')['enum']! as List<Object?>) {
          final bool mod = t == 'moderation_notice';
          final CommunityNotification parsed =
              CommunityNotification.fromJson(<String, dynamic>{
                'id': 'n',
                'type': t,
                'post_id': null,
                'comment_id': null,
                'notice': mod ? n : null,
                'created_at': '2026-11-07T10:15:00.000Z',
                'read_at': null,
              });
          if (mod) expect(parsed.notice!.wire, n);
        }
      }
    });

    test('client enums cover the spec enums exactly', () {
      List<Object?> e(String name) =>
          spec.schema(name)['enum']! as List<Object?>;
      expect(
        e('ErrorCode'),
        CommunityErrorCode.values.map((CommunityErrorCode c) => c.wire),
      );
      expect(e('SpaceId'), SpaceId.values.map((SpaceId s) => s.wire));
      expect(
        e('DisplayMode'),
        DisplayMode.values.map((DisplayMode d) => d.wire),
      );
      expect(
        e('ReportReason'),
        ReportReason.values.map((ReportReason r) => r.wire),
      );
      expect(
        e('ReportTargetType'),
        ReportTargetType.values.map((ReportTargetType r) => r.wire),
      );
      expect(
        e('ModContentStatus'),
        ContentStatus.values.map((ContentStatus c) => c.wire),
      );
      expect(
        e('VerificationStatus'),
        VerificationStatus.values
            .where(
              (VerificationStatus v) => v != VerificationStatus.unrecognised,
            )
            .map((VerificationStatus v) => v.wire),
      );
      expect(
        e('ModerationNotice'),
        ModerationNotice.values
            .where((ModerationNotice n) => n != ModerationNotice.unrecognised)
            .map((ModerationNotice n) => n.wire),
      );
      expect(
        e('NotificationType'),
        CommunityNotificationType.values.map(
          (CommunityNotificationType t) => t.wire,
        ),
      );
      expect(
        e('CommunityMode'),
        CommunityFlagState.values.map((CommunityFlagState f) => f.wire),
      );
    });

    test('client limits equal the spec limits', () {
      Map<String, Object?> prop(String schema, String p) => spec.resolve(
        (spec.schema(schema)['properties']! as Map<String, Object?>)[p]!
            as Map<String, Object?>,
      );
      expect(
        prop('PostCreate', 'body')['maxLength'],
        CommunityLimits.postBodyMax,
      );
      expect(
        prop('CommentCreate', 'body')['maxLength'],
        CommunityLimits.commentBodyMax,
      );
      expect(
        prop('ReportCreate', 'note')['maxLength'],
        CommunityLimits.reportNoteMax,
      );
      expect(
        prop('ProfileUpdate', 'display_name')['minLength'],
        CommunityLimits.displayNameMin,
      );
      expect(
        prop('ProfileUpdate', 'display_name')['maxLength'],
        CommunityLimits.displayNameMax,
      );
      expect(
        prop('ProfessionalClaim', 'profession')['minLength'],
        CommunityLimits.professionMin,
      );
      expect(
        prop('ProfessionalClaim', 'profession')['maxLength'],
        CommunityLimits.professionMax,
      );
      expect(
        prop('DeleteAccount', 'confirm')['const'],
        CommunityLimits.deleteAccountPhrase,
      );
      expect((spec.root['components']! as Map)['parameters'], isNotNull);
    });
  });
}
