/// ADR-001 §8 A2 on the client: access token in memory only, refresh token
/// in secure storage, rotation, single-flight refresh, `refresh_race`, and
/// 401/429 handling (contract §3.2, §3.3, §1.3, §4.3).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/community/data/community_auth_api.dart';
import 'package:wellapath_mobile/features/community/data/community_http_client.dart';
import 'package:wellapath_mobile/features/community/data/community_repositories.dart';
import 'package:wellapath_mobile/features/community/data/community_secure_store.dart';
import 'package:wellapath_mobile/features/community/data/community_session_manager.dart';
import 'package:wellapath_mobile/features/community/data/http_community_repository.dart';
import 'package:wellapath_mobile/features/community/domain/community_ids.dart';
import 'package:wellapath_mobile/features/community/domain/community_session.dart';

import 'support/fake_community_server.dart';

class _Harness {
  _Harness(FakeHandler handler) : adapter = FakeCommunityAdapter(handler) {
    raw = CommunityHttpClient.forBaseUrl(
      'https://community.test',
      adapter: adapter,
    );
    session = CommunitySessionManager(
      api: CommunityAuthApi(raw),
      store: store,
      clock: () => now,
    );
    repo = HttpCommunityRepository(raw.withTokens(session));
  }

  final FakeCommunityAdapter adapter;
  final InMemoryCommunitySecureStore store = InMemoryCommunitySecureStore();
  DateTime now = DateTime.utc(2026, 11, 7, 10);
  late final CommunityHttpClient raw;
  late final CommunitySessionManager session;
  late final HttpCommunityRepository repo;

  List<RecordedRequest> to(String path) =>
      adapter.requests.where((RecordedRequest r) => r.path == path).toList();
}

Future<FakeReply> _signInOk(RecordedRequest r) async {
  if (r.path == '/v1/auth/otp/request') return const FakeReply(202, {});
  if (r.path == '/v1/auth/otp/verify') {
    return FakeReply(
      200,
      tokenPairJson(access: 'access-1', refresh: wprt('r1'), created: true),
    );
  }
  return const FakeReply(500);
}

void main() {
  group('TokenPair (P5: expires_in 60-900, wprt_ refresh token)', () {
    test('accepts the bounds, rejects anything outside them', () {
      for (final int ok in <int>[60, 900]) {
        expect(
          TokenPair.fromJson(
            tokenPairJson(access: 'a', refresh: wprt('r'), expiresIn: ok),
          ).expiresIn,
          ok,
        );
      }
      for (final int bad in <int>[0, 1, 59, 901]) {
        expect(
          () => TokenPair.fromJson(
            tokenPairJson(access: 'a', refresh: wprt('r'), expiresIn: bad),
          ),
          throwsFormatException,
          reason: '$bad',
        );
      }
      for (final String bad in <String>[
        'rt_${'x' * 43}',
        'wprt_${'x' * 42}',
        'wprt_${'x' * 42}!',
        '',
      ]) {
        expect(
          () => TokenPair.fromJson(tokenPairJson(access: 'a', refresh: bad)),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });

  group('sign-in', () {
    test('verify stores only the refresh token and device id', () async {
      final _Harness h = _Harness(_signInOk);
      await h.session.requestOtp('  A@B.ng ');
      expect(
        (h.to('/v1/auth/otp/request').single.body as Map)['email'],
        'a@b.ng',
      );

      final bool created = (await h.session.verifyOtp(
        email: 'a@b.ng',
        code: '123456',
      )).accountCreated;
      expect(created, isTrue);

      final Map<String, dynamic> verify =
          h.to('/v1/auth/otp/verify').single.body! as Map<String, dynamic>;
      expect(isUuid(verify['device_id'] as String), isTrue);
      expect(verify['code'], '123456');

      // Access token: memory only. Secure storage holds exactly two keys.
      expect(h.store.values.keys.toSet(), CommunitySecureKeys.all.toSet());
      expect(h.store.values[CommunitySecureKeys.refreshToken], wprt('r1'));
      expect(h.store.values.values, isNot(contains('access-1')));
      expect(await h.session.accessToken(), 'access-1');
      expect(h.session.me?.email, 'a@b.ng');
    });

    test('device_id is generated once per install and reused', () async {
      final _Harness h = _Harness(_signInOk);
      final String first = await h.session.deviceId();
      expect(await h.session.deviceId(), first);
      await h.session.verifyOtp(email: 'a@b.ng', code: '123456');
      expect(
        (h.to('/v1/auth/otp/verify').single.body as Map)['device_id'],
        first,
      );
    });

    test('TokenPair.toString never prints a token', () async {
      final _Harness h = _Harness(_signInOk);
      final String printed = (await h.session.verifyOtp(
        email: 'a@b.ng',
        code: '123456',
      )).toString();
      expect(printed, isNot(contains('access-1')));
      expect(printed, isNot(contains('wprt_')));
    });
  });

  group('refresh', () {
    test('rotation: each refresh stores the new single-use token', () async {
      int n = 1;
      final _Harness h = _Harness((RecordedRequest r) async {
        if (r.path == '/v1/auth/otp/verify') {
          return FakeReply(
            200,
            tokenPairJson(access: 'a1', refresh: wprt('r1'), expiresIn: 60),
          );
        }
        if (r.path == '/v1/auth/refresh') {
          n++;
          return FakeReply(
            200,
            tokenPairJson(access: 'a$n', refresh: wprt('r$n'), expiresIn: 60),
          );
        }
        return const FakeReply(500);
      });
      await h.session.verifyOtp(email: 'a@b.ng', code: '123456');
      h.now = h.now.add(const Duration(minutes: 2));
      expect(await h.session.accessToken(), 'a2');
      final Map<String, dynamic> body =
          h.to('/v1/auth/refresh').single.body! as Map<String, dynamic>;
      expect(body['refresh_token'], wprt('r1'));
      expect(isUuid(body['device_id'] as String), isTrue);
      expect(h.store.values[CommunitySecureKeys.refreshToken], wprt('r2'));
    });

    test('single-flight: concurrent callers share one refresh', () async {
      final Completer<FakeReply> gate = Completer<FakeReply>();
      final _Harness h = _Harness((RecordedRequest r) {
        if (r.path == '/v1/auth/refresh') return gate.future;
        return Future<FakeReply>.value(const FakeReply(500));
      });
      h.store.values[CommunitySecureKeys.refreshToken] = wprt('stored');
      final List<Future<String?>> calls = <Future<String?>>[
        for (int i = 0; i < 5; i++) h.session.accessToken(),
      ];
      await Future<void>.delayed(Duration.zero);
      gate.complete(
        FakeReply(200, tokenPairJson(access: 'fresh', refresh: wprt('next'))),
      );
      expect(await Future.wait(calls), everyElement('fresh'));
      expect(h.to('/v1/auth/refresh'), hasLength(1));
    });

    test('401 token_expired: refresh once, then retry once', () async {
      int spaces = 0;
      final _Harness h = _Harness((RecordedRequest r) async {
        if (r.path == '/v1/auth/otp/verify') {
          return FakeReply(
            200,
            tokenPairJson(access: 'old', refresh: wprt('r1')),
          );
        }
        if (r.path == '/v1/auth/refresh') {
          return FakeReply(
            200,
            tokenPairJson(access: 'new', refresh: wprt('r2')),
          );
        }
        spaces++;
        if (r.header('authorization') == 'Bearer old') {
          return FakeReply(401, errorBody('token_expired'));
        }
        return const FakeReply(200, <String, dynamic>{'items': <Object>[]});
      });
      await h.session.verifyOtp(email: 'a@b.ng', code: '123456');
      expect(await h.repo.listSpaces(), isEmpty);
      expect(spaces, 2, reason: 'one rejected try, one retry');
      expect(h.to('/v1/auth/refresh'), hasLength(1));
      expect(h.store.values[CommunitySecureKeys.refreshToken], wprt('r2'));
    });

    test('token_expired twice: no refresh loop', () async {
      final _Harness h = _Harness((RecordedRequest r) async {
        if (r.path == '/v1/auth/otp/verify') {
          return FakeReply(
            200,
            tokenPairJson(access: 'a0', refresh: wprt('r0')),
          );
        }
        if (r.path == '/v1/auth/refresh') {
          return FakeReply(
            200,
            tokenPairJson(access: 'a1', refresh: wprt('r1')),
          );
        }
        return FakeReply(401, errorBody('token_expired'));
      });
      await h.session.verifyOtp(email: 'a@b.ng', code: '123456');
      await expectLater(
        h.repo.listSpaces(),
        throwsA(isA<CommunityException>()),
      );
      expect(h.to('/v1/auth/refresh'), hasLength(1));
      expect(h.to('/v1/community/spaces'), hasLength(2));
    });

    test(
      '409 refresh_race: retry once only if the stored token changed',
      () async {
        late final _Harness h;
        h = _Harness((RecordedRequest r) async {
          final String presented = (r.body! as Map)['refresh_token'] as String;
          if (presented == wprt('old')) {
            h.store.values[CommunitySecureKeys.refreshToken] = wprt('winner');
            return FakeReply(
              409,
              errorBody('conflict', details: {'reason': 'refresh_race'}),
            );
          }
          return FakeReply(
            200,
            tokenPairJson(access: 'won', refresh: wprt('n')),
          );
        });
        h.store.values[CommunitySecureKeys.refreshToken] = wprt('old');
        expect(await h.session.accessToken(), 'won');
        expect(
          h
              .to('/v1/auth/refresh')
              .map((RecordedRequest r) => (r.body! as Map)['refresh_token']),
          <String>[wprt('old'), wprt('winner')],
        );
      },
    );

    test('409 refresh_race with unchanged storage: sign in again', () async {
      final _Harness h = _Harness((RecordedRequest r) async {
        return FakeReply(
          409,
          errorBody('conflict', details: {'reason': 'refresh_race'}),
        );
      });
      h.store.values[CommunitySecureKeys.refreshToken] = wprt('old');
      expect(await h.session.accessToken(), isNull);
      expect(h.to('/v1/auth/refresh'), hasLength(1));
      expect(
        h.store.values.containsKey(CommunitySecureKeys.refreshToken),
        isFalse,
      );
    });

    for (final String reason in <String>[
      'refresh_reused',
      'refresh_invalid',
      'refresh_expired',
      'session_revoked',
    ]) {
      test('401 $reason from refresh clears the session', () async {
        final _Harness h = _Harness((RecordedRequest r) async {
          return FakeReply(
            401,
            errorBody('unauthenticated', details: {'reason': reason}),
          );
        });
        h.store.values[CommunitySecureKeys.refreshToken] = wprt('r');
        expect(await h.session.accessToken(), isNull);
        expect(await h.session.hasStoredSession(), isFalse);
        expect(
          h.store.values.containsKey(CommunitySecureKeys.deviceId),
          isTrue,
          reason: 'the install id survives',
        );
      });
    }

    test('429 on refresh keeps the token and surfaces Retry-After', () async {
      final _Harness h = _Harness((RecordedRequest r) async {
        return FakeReply(
          429,
          errorBody('rate_limited', details: {'retry_after_seconds': 30}),
          {'Retry-After': '30'},
        );
      });
      h.store.values[CommunitySecureKeys.refreshToken] = wprt('r');
      await expectLater(
        h.session.accessToken(),
        throwsA(
          isA<CommunityException>()
              .having(
                (CommunityException e) => e.code,
                'code',
                CommunityErrorCode.rateLimited,
              )
              .having(
                (CommunityException e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 30),
              ),
        ),
      );
      expect(h.store.values[CommunitySecureKeys.refreshToken], wprt('r'));
      expect(h.to('/v1/auth/refresh'), hasLength(1), reason: 'no auto-retry');
    });
  });

  group('401 unauthenticated on a content route', () {
    test('clears tokens and surfaces requiresSignIn', () async {
      final _Harness h = _Harness((RecordedRequest r) async {
        if (r.path == '/v1/auth/otp/verify') {
          return FakeReply(200, tokenPairJson(access: 'a', refresh: wprt('r')));
        }
        return FakeReply(
          401,
          errorBody('unauthenticated', details: {'reason': 'session_revoked'}),
        );
      });
      await h.session.verifyOtp(email: 'a@b.ng', code: '123456');
      await expectLater(
        h.repo.listSpaces(),
        throwsA(
          isA<CommunityException>().having(
            (CommunityException e) => e.requiresSignIn,
            'requiresSignIn',
            isTrue,
          ),
        ),
      );
      expect(await h.session.hasStoredSession(), isFalse);
      expect(h.session.state, CommunitySignInState.signedOut);
    });

    test(
      'signed out: required-auth calls fail locally, nothing sent',
      () async {
        final _Harness h = _Harness((RecordedRequest r) async {
          return const FakeReply(500);
        });
        await expectLater(
          h.repo.listSpaces(),
          throwsA(isA<CommunityException>()),
        );
        expect(h.adapter.requests, isEmpty);
      },
    );
  });

  group('sign-out', () {
    test(
      'calls A4 with the refresh token only (P6, no bearer), 204 is success, '
      'and clears secure storage',
      () async {
        final _Harness h = _Harness((RecordedRequest r) async {
          if (r.path == '/v1/auth/otp/verify') {
            return FakeReply(
              200,
              tokenPairJson(access: 'a', refresh: wprt('r')),
            );
          }
          if (r.path == '/v1/auth/logout') return const FakeReply(204);
          return const FakeReply(500);
        });
        await h.session.verifyOtp(email: 'a@b.ng', code: '123456');
        await h.session.signOut();
        final RecordedRequest logout = h.to('/v1/auth/logout').single;
        expect(logout.header('authorization'), isNull);
        expect(logout.body, <String, Object?>{'refresh_token': wprt('r')});
        expect(
          h.store.values.containsKey(CommunitySecureKeys.refreshToken),
          isFalse,
        );
        expect(await h.session.accessToken(), isNull);
        expect(h.session.state, CommunitySignInState.signedOut);
      },
    );

    test(
      'with no access token in memory (e.g. after a restart, or expired), '
      'signs out with the stored refresh token and never refreshes first',
      () async {
        final _Harness h = _Harness((RecordedRequest r) async {
          if (r.path == '/v1/auth/logout') return const FakeReply(204);
          return const FakeReply(500);
        });
        h.store.values[CommunitySecureKeys.refreshToken] = wprt('stored');
        await h.session.signOut();
        expect(h.to('/v1/auth/refresh'), isEmpty);
        final RecordedRequest logout = h.to('/v1/auth/logout').single;
        expect(logout.header('authorization'), isNull);
        expect(logout.body, <String, Object?>{'refresh_token': wprt('stored')});
        expect(await h.session.hasStoredSession(), isFalse);
      },
    );

    test(
      'a refresh-token sign-out never carries an Authorization header',
      () async {
        final _Harness h = _Harness((RecordedRequest r) async {
          if (r.path == '/v1/auth/otp/verify') {
            return FakeReply(
              200,
              tokenPairJson(access: 'a', refresh: wprt('r')),
            );
          }
          if (r.path == '/v1/auth/logout') return const FakeReply(204);
          return const FakeReply(500);
        });
        await h.session.verifyOtp(email: 'a@b.ng', code: '123456');
        await h.session.signOut();
        expect(
          h.adapter.requests
              .where((RecordedRequest r) => r.path == '/v1/auth/logout')
              .every((RecordedRequest r) => r.header('authorization') == null),
          isTrue,
        );
        expect(
          h.store.values.containsKey(CommunitySecureKeys.refreshToken),
          isFalse,
        );
        expect(await h.session.accessToken(), isNull);
      },
    );

    test('clears local tokens even when the server call fails', () async {
      final _Harness h = _Harness((RecordedRequest r) async {
        if (r.path == '/v1/auth/otp/verify') {
          return FakeReply(200, tokenPairJson(access: 'a', refresh: wprt('r')));
        }
        return const FakeReply(503);
      });
      await h.session.verifyOtp(email: 'a@b.ng', code: '123456');
      await h.session.signOut();
      expect(await h.session.hasStoredSession(), isFalse);
    });

    test(
      'P8: sign-out keeps the install device_id; the next sign-in reuses it',
      () async {
        final _Harness h = _Harness((RecordedRequest r) async {
          if (r.path == '/v1/auth/logout') return const FakeReply(204);
          return _signInOk(r);
        });
        await h.session.verifyOtp(email: 'a@b.ng', code: '123456');
        final String device = await h.session.deviceId();
        await h.session.signOut();
        expect(h.store.values[CommunitySecureKeys.deviceId], device);
        await h.session.verifyOtp(email: 'a@b.ng', code: '123456');
        expect(
          h
              .to('/v1/auth/otp/verify')
              .map((RecordedRequest r) => (r.body! as Map)['device_id'])
              .toSet(),
          <Object?>{device},
        );
      },
    );

    test('forgetDevice (after deletion) erases every Community key', () async {
      final _Harness h = _Harness(_signInOk);
      await h.session.verifyOtp(email: 'a@b.ng', code: '123456');
      await h.session.forgetDevice();
      expect(h.store.values, isEmpty);
    });
  });
}
