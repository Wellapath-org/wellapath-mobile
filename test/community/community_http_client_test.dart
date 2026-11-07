/// The Community HTTP client's cross-cutting rules: the prohibited-key guard
/// (contract §5), no body/header logging (CLAUDE.md PHI rule), the error
/// envelope and kill switch (§1.3), idempotency keys (§1.2) and 429 (§4.3).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/community/data/community_http_client.dart';
import 'package:wellapath_mobile/features/community/data/community_repositories.dart';
import 'package:wellapath_mobile/features/community/data/http_community_repository.dart';
import 'package:wellapath_mobile/features/community/data/prohibited_keys.dart';
import 'package:wellapath_mobile/features/community/domain/community_ids.dart';
import 'package:wellapath_mobile/features/community/domain/post.dart';
import 'package:wellapath_mobile/features/community/domain/public_author.dart';
import 'package:wellapath_mobile/features/community/domain/report.dart';
import 'package:wellapath_mobile/features/community/domain/space.dart';

import 'support/fake_community_server.dart';

class _StaticTokens implements CommunityAccessTokens {
  _StaticTokens(this.token);

  String? token;
  int ended = 0;

  @override
  Future<String?> accessToken() async => token;

  @override
  Future<String?> renewAfterExpiry(String rejected) async => null;

  @override
  Future<void> sessionEnded() async {
    ended++;
    token = null;
  }
}

({FakeCommunityAdapter adapter, CommunityHttpClient client, _StaticTokens t})
_client(FakeHandler handler) {
  final FakeCommunityAdapter adapter = FakeCommunityAdapter(handler);
  final _StaticTokens t = _StaticTokens('tok-SECRET-123');
  final CommunityHttpClient client = CommunityHttpClient.forBaseUrl(
    'https://community.test',
    adapter: adapter,
  ).withTokens(t);
  return (adapter: adapter, client: client, t: t);
}

Future<FakeReply> _ok(RecordedRequest r) async => const FakeReply(200, {});

void main() {
  group('prohibited keys (§5): refused before sending', () {
    test('the guard matches every reference key, case-insensitively', () {
      for (final String key in kProhibitedReferenceKeys) {
        expect(isProhibitedKey(key), isTrue, reason: key);
        expect(isProhibitedKey(key.toUpperCase()), isTrue, reason: key);
      }
      for (final String allowed in <String>[
        'body',
        'display_mode',
        'note',
        'reason',
        'target_id',
        'profession',
        'display_name',
        'refresh_token',
        'device_id',
        'confirm',
        'email',
        'code',
      ]) {
        expect(isProhibitedKey(allowed), isFalse, reason: allowed);
      }
    });

    for (final String key in kProhibitedReferenceKeys) {
      test(
        'body carrying "$key" (top level and nested) is never sent',
        () async {
          final c = _client(_ok);
          for (final Object body in <Object>[
            <String, dynamic>{'body': 'hi', key: 'x'},
            <String, dynamic>{
              'body': 'hi',
              'meta': <String, dynamic>{key: 1},
            },
            <String, dynamic>{
              'items': <Object>[
                <String, dynamic>{key: true},
              ],
            },
          ]) {
            await expectLater(
              c.client.send(
                CommunityRequest(
                  method: 'POST',
                  template: '/v1/community/reports',
                  body: body,
                ),
              ),
              throwsA(isA<ProhibitedPayloadException>()),
            );
          }
          await expectLater(
            c.client.send(
              CommunityRequest(
                method: 'GET',
                template: '/v1/community/spaces',
                query: <String, dynamic>{key: 'x'},
              ),
            ),
            throwsA(isA<ProhibitedPayloadException>()),
          );
          expect(
            c.adapter.requests,
            isEmpty,
            reason: 'nothing left the device',
          );
        },
      );
    }

    test('the exception names the path, never the value', () async {
      final c = _client(_ok);
      try {
        await c.client.send(
          const CommunityRequest(
            method: 'POST',
            template: '/v1/community/reports',
            body: <String, dynamic>{
              'x': <String, dynamic>{'triage_level': 'VALUE-42'},
            },
          ),
        );
        fail('should throw');
      } on ProhibitedPayloadException catch (e) {
        expect(e.path, 'body.x.triage_level');
        expect(e.toString(), isNot(contains('VALUE-42')));
      }
    });

    test('every request model the client builds is clean', () {
      final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[
        PostDraft(
          spaceId: SpaceId.generalHealth,
          body: 'Is it normal to feel tired?',
          displayMode: DisplayMode.named,
        ).toJson(),
        ReportDraft(
          targetType: ReportTargetType.post,
          targetId: 'p1',
          reason: ReportReason.selfHarmOrEmergency,
          note: 'worried',
        ).toJson(),
      ];
      for (final Map<String, dynamic> b in bodies) {
        expect(() => assertNoProhibitedKeys(body: b), returnsNormally);
      }
    });
  });

  group('logging (PHI rule)', () {
    test('no body, header, token, query or id is printed', () async {
      final List<String> lines = <String>[];
      final DebugPrintCallback original = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => lines.add(m ?? '');
      addTearDown(() => debugPrint = original);

      final c = _client((RecordedRequest r) async {
        return FakeReply(201, <String, dynamic>{
          'id': 'post-ID-777',
          'space_id': 'general_health',
          'body': 'RESPONSE-BODY-SENTINEL',
          'author': <String, dynamic>{
            'display_mode': 'pseudonymous',
            'display_name': null,
            'badge': null,
          },
          'viewer_is_author': true,
          'status': 'visible',
          'comment_count': 0,
          'created_at': '2026-11-07T10:15:00.000Z',
        });
      });
      await HttpCommunityRepository(c.client).createPost(
        PostDraft(
          spaceId: SpaceId.generalHealth,
          body: 'REQUEST-BODY-SENTINEL',
          displayMode: DisplayMode.pseudonymous,
        ),
      );
      final String all = lines.join('\n');
      expect(
        all,
        contains('POST /v1/community/spaces/{space_id}/posts -> 201'),
      );
      for (final String secret in <String>[
        'REQUEST-BODY-SENTINEL',
        'RESPONSE-BODY-SENTINEL',
        'tok-SECRET-123',
        'Bearer',
        'post-ID-777',
        'general_health',
        'Idempotency',
      ]) {
        expect(all, isNot(contains(secret)), reason: secret);
      }
    });
  });

  group('requests', () {
    test('creates carry a UUID Idempotency-Key, reused on retry', () async {
      final c = _client((RecordedRequest r) async {
        return FakeReply(429, errorBody('rate_limited'), {'Retry-After': '12'});
      });
      final HttpCommunityRepository repo = HttpCommunityRepository(c.client);
      final PostDraft draft = PostDraft(
        spaceId: SpaceId.pregnancyMaternal,
        body: 'hello',
        displayMode: DisplayMode.named,
      );
      for (int i = 0; i < 2; i++) {
        await expectLater(
          repo.createPost(draft),
          throwsA(
            isA<CommunityException>().having(
              (CommunityException e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 12),
            ),
          ),
        );
      }
      final List<String?> keys = c.adapter.requests
          .map((RecordedRequest r) => r.header('idempotency-key'))
          .toList();
      expect(keys, hasLength(2), reason: 'one request per user action');
      expect(isUuid(keys.first!), isTrue);
      expect(keys.toSet(), hasLength(1));
      expect(
        c.adapter.requests.first.header('authorization'),
        'Bearer tok-SECRET-123',
      );
    });

    test(
      'limit and cursor go in the query; cursor is passed as given',
      () async {
        final c = _client((RecordedRequest r) async {
          return const FakeReply(200, <String, dynamic>{
            'items': <Object>[],
            'next_cursor': null,
          });
        });
        await HttpCommunityRepository(
          c.client,
        ).listPosts(SpaceId.generalHealth, cursor: 'opaque==', limit: 50);
        final RecordedRequest r = c.adapter.requests.single;
        expect(r.path, '/v1/community/spaces/general_health/posts');
        expect(r.query, <String, dynamic>{'limit': 50, 'cursor': 'opaque=='});
        expect(
          () => HttpCommunityRepository(
            c.client,
          ).listPosts(SpaceId.generalHealth, limit: 51),
          throwsArgumentError,
        );
      },
    );
  });

  group('errors and the kill switch (§1.3)', () {
    Future<CommunityException> failing(
      Future<Object?> Function(HttpCommunityRepository) call,
      FakeReply reply,
    ) async {
      final c = _client((RecordedRequest r) async => reply);
      try {
        await call(HttpCommunityRepository(c.client));
      } on CommunityException catch (e) {
        return e;
      }
      throw StateError('expected a CommunityException');
    }

    test('403 community_not_allowed closes Community anywhere', () async {
      final CommunityException e = await failing(
        (HttpCommunityRepository r) => r.getPost('p'),
        FakeReply(403, errorBody('community_not_allowed')),
      );
      expect(e.closesCommunity, isTrue);
    });

    test('404 on list/space routes closes Community', () async {
      final FakeReply notFound = FakeReply(404, errorBody('not_found'));
      for (final Future<Object?> Function(HttpCommunityRepository) call
          in <Future<Object?> Function(HttpCommunityRepository)>[
            (HttpCommunityRepository r) => r.listSpaces(),
            (HttpCommunityRepository r) => r.listPosts(SpaceId.generalHealth),
            (HttpCommunityRepository r) => r.list(),
            (HttpCommunityRepository r) => r.unreadCount(),
          ]) {
        expect((await failing(call, notFound)).closesCommunity, isTrue);
      }
    });

    test('404 on a single post or comment means only "unavailable"', () async {
      final FakeReply notFound = FakeReply(404, errorBody('not_found'));
      final CommunityException post = await failing(
        (HttpCommunityRepository r) => r.getPost('p'),
        notFound,
      );
      expect(post.code, CommunityErrorCode.notFound);
      expect(post.closesCommunity, isFalse);
      final CommunityException comments = await failing(
        (HttpCommunityRepository r) => r.listComments('p'),
        notFound,
      );
      expect(comments.closesCommunity, isFalse);
    });

    test(
      'P2: only C1/C2/N1/N2 close Community on 404; C6 and the rest do not',
      () async {
        final FakeReply notFound = FakeReply(404, errorBody('not_found'));
        final Map<String, Future<Object?> Function(HttpCommunityRepository)>
        others = <String, Future<Object?> Function(HttpCommunityRepository)>{
          'C6 comments list': (HttpCommunityRepository r) =>
              r.listComments('p'),
          'C4 single post': (HttpCommunityRepository r) => r.getPost('p'),
          'C5 delete own post': (HttpCommunityRepository r) =>
              r.deletePost('p'),
          'C8 delete own comment': (HttpCommunityRepository r) =>
              r.deleteComment('c'),
          'N3 mark read': (HttpCommunityRepository r) => r.markRead('n'),
        };
        for (final MapEntry<
              String,
              Future<Object?> Function(HttpCommunityRepository)
            >
            e
            in others.entries) {
          final CommunityException x = await failing(e.value, notFound);
          expect(x.code, CommunityErrorCode.notFound, reason: e.key);
          expect(x.closesCommunity, isFalse, reason: e.key);
        }
      },
    );

    test('M2/M4 404 means "none yet", not an error', () async {
      final c = _client((RecordedRequest r) async {
        return FakeReply(404, errorBody('not_found'));
      });
      final HttpCommunityRepository repo = HttpCommunityRepository(c.client);
      expect(await repo.getProfile(), isNull);
      expect(await repo.getProfessionalClaim(), isNull);
    });

    test(
      'envelope details are read; unknown codes are internal_error',
      () async {
        final CommunityException restricted = await failing(
          (HttpCommunityRepository r) => r.createPost(
            PostDraft(
              spaceId: SpaceId.generalHealth,
              body: 'x',
              displayMode: DisplayMode.named,
            ),
          ),
          FakeReply(
            403,
            errorBody(
              'account_restricted',
              details: {'until': '2026-12-01T00:00:00.000Z'},
            ),
          ),
        );
        expect(restricted.code, CommunityErrorCode.accountRestricted);
        expect(restricted.until, DateTime.utc(2026, 12));
        expect(restricted.requestId, 'req_12345678');

        final CommunityException unknown = await failing(
          (HttpCommunityRepository r) => r.listSpaces(),
          FakeReply(418, errorBody('teapot')),
        );
        expect(unknown.code, CommunityErrorCode.internalError);

        final CommunityException taken = await failing(
          (HttpCommunityRepository r) => r.setDisplayName('SunnyMum'),
          FakeReply(
            409,
            errorBody('conflict', details: {'reason': 'display_name_taken'}),
          ),
        );
        expect(taken.reason, 'display_name_taken');
      },
    );

    test('401 unauthenticated ends the session', () async {
      final c = _client((RecordedRequest r) async {
        return FakeReply(
          401,
          errorBody('unauthenticated', details: {'reason': 'session_revoked'}),
        );
      });
      await expectLater(
        HttpCommunityRepository(c.client).listSpaces(),
        throwsA(isA<CommunityException>()),
      );
      expect(c.t.ended, 1);
    });

    test('a transport failure is a CommunityNetworkException', () async {
      final c = _client((RecordedRequest r) async {
        throw Exception('socket closed');
      });
      await expectLater(
        HttpCommunityRepository(c.client).listSpaces(),
        throwsA(isA<CommunityNetworkException>()),
      );
    });
  });

  test('delete account requires the exact phrase before sending', () async {
    final c = _client((RecordedRequest r) async => const FakeReply(204));
    final HttpCommunityRepository repo = HttpCommunityRepository(c.client);
    await expectLater(
      repo.deleteMyAccount('delete my account'),
      throwsA(isA<Exception>()),
    );
    expect(c.adapter.requests, isEmpty);
    await repo.deleteMyAccount('DELETE MY ACCOUNT');
    expect(c.adapter.requests.single.body, <String, dynamic>{
      'confirm': 'DELETE MY ACCOUNT',
    });
  });
}
