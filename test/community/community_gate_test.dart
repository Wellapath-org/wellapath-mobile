/// The two-key gate (FEATURE_FLAG_SPEC.md): compile-time define AND server
/// flag, failing closed on everything else.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellapath_mobile/features/community/data/community_auth_service.dart';
import 'package:wellapath_mobile/features/community/data/community_http_client.dart';
import 'package:wellapath_mobile/features/community/gate/community_features.dart';
import 'package:wellapath_mobile/features/community/gate/community_gate.dart';
import 'package:wellapath_mobile/features/community/ui/community_entry_row.dart';
import 'package:wellapath_mobile/features/community/ui/community_safety_banner.dart';
import 'package:wellapath_mobile/features/community/ui/community_scope.dart';
import 'package:wellapath_mobile/features/community/ui/sign_in_screen.dart';
import 'package:wellapath_mobile/features/more/more_screen.dart';
import 'package:wellapath_mobile/features/shell/app_shell.dart';

const CommunityFeatures _internalAllowed = CommunityFeatures(
  state: CommunityFlagState.internal,
  allowed: true,
);

CommunityModule _module(CommunityGate gate, {CommunityAuthService? auth}) {
  return CommunityModule(
    gate: gate,
    auth: auth ?? InMemoryCommunityAuthService(signedIn: true),
    createServices: CommunityServices.inMemoryDemo,
  );
}

Future<void> _pumpMore(WidgetTester tester, {CommunityModule? module}) async {
  tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: MoreScreen(community: module)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('default build', () {
    test('compile-time flag defaults to off; base URL defaults to empty', () {
      expect(kCommunityScaffoldEnabled, isFalse);
      expect(kCommunityApiBaseUrl, isEmpty);
      expect(CommunityGate.fromEnvironment().compileTimeEnabled, isFalse);
    });

    test('the default gate ignores even an allowing source', () async {
      final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
        _internalAllowed,
      );
      final CommunityGate gate = CommunityGate.fromEnvironment(source: source);
      expect(await gate.evaluate(fresh: true), CommunityGateDecision.hidden);
      expect(source.fetchCount, 0);
    });

    test('the default module builds no client and no services', () {
      final CommunityModule m = CommunityModule.fromEnvironment();
      expect(m.gate.compileTimeEnabled, isFalse);
      expect(m.createServices, throwsStateError);
      expect(m.auth, isA<DisabledCommunityAuthService>());
      expect(() => m.auth.requestOtp('a@b.ng'), throwsStateError);
    });

    test('default gate never opens and needs no network', () async {
      expect(await CommunityGate.fromEnvironment().isOpen(), isFalse);
      expect(
        await CommunityGate.fromEnvironment().isOpen(fresh: true),
        isFalse,
      );
    });

    testWidgets('More tab has no Community row', (tester) async {
      await _pumpMore(tester);
      expect(find.byType(CommunityEntryRow), findsNothing);
      expect(find.text(CommunityEntryRow.label), findsNothing);
      expect(find.textContaining('Community'), findsNothing);
    });

    testWidgets('More tab inside the real shell has no Community row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        const MaterialApp(home: AppShell(initialTab: ShellTab.more)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MoreScreen), findsOneWidget);
      expect(find.byType(CommunityEntryRow), findsNothing);
    });

    testWidgets('compile flag off ignores even a server that allows', (
      tester,
    ) async {
      final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
        _internalAllowed,
      );
      await _pumpMore(
        tester,
        module: _module(
          CommunityGate(compileTimeEnabled: false, source: source),
        ),
      );
      expect(find.byType(CommunityEntryRow), findsNothing);
      expect(source.fetchCount, 0, reason: 'no request in a default build');
    });
  });

  group('compile flag on, server decides', () {
    Future<void> expectHidden(
      WidgetTester tester,
      CommunityFeatureSource source,
    ) async {
      await _pumpMore(
        tester,
        module: _module(
          CommunityGate(compileTimeEnabled: true, source: source),
        ),
      );
      expect(find.text(CommunityEntryRow.label), findsNothing);
    }

    testWidgets('server disabled -> hidden', (tester) async {
      await expectHidden(
        tester,
        StaticCommunityFeatureSource(CommunityFeatures.disabled),
      );
    });

    testWidgets('server disabled with allowed=true -> still hidden', (
      tester,
    ) async {
      await expectHidden(
        tester,
        StaticCommunityFeatureSource(
          const CommunityFeatures(
            state: CommunityFlagState.disabled,
            allowed: true,
          ),
        ),
      );
    });

    testWidgets('fetch error -> hidden (fail closed)', (tester) async {
      await expectHidden(tester, const FailingCommunityFeatureSource());
    });

    testWidgets('internal but not allowlisted -> hidden', (tester) async {
      await expectHidden(
        tester,
        StaticCommunityFeatureSource(
          const CommunityFeatures(
            state: CommunityFlagState.internal,
            allowed: false,
          ),
        ),
      );
    });

    testWidgets('no source configured -> hidden', (tester) async {
      await _pumpMore(
        tester,
        module: _module(CommunityGate(compileTimeEnabled: true)),
      );
      expect(find.text(CommunityEntryRow.label), findsNothing);
    });

    testWidgets('internal + allowlisted -> visible, opens the two spaces', (
      tester,
    ) async {
      await _pumpMore(
        tester,
        module: _module(
          CommunityGate(
            compileTimeEnabled: true,
            source: StaticCommunityFeatureSource(_internalAllowed),
          ),
        ),
      );
      expect(find.text(CommunityEntryRow.label), findsOneWidget);

      await tester.tap(find.text(CommunityEntryRow.label));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('General Health'), findsOneWidget);
      expect(find.text('Pregnancy and Maternal Health'), findsOneWidget);
      expect(find.text(CommunitySafetyBanner.text), findsOneWidget);
    });

    testWidgets('kill switch: server flips to disabled, tap does not enter', (
      tester,
    ) async {
      final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
        _internalAllowed,
      );
      await _pumpMore(
        tester,
        module: _module(
          CommunityGate(compileTimeEnabled: true, source: source),
        ),
      );
      expect(find.text(CommunityEntryRow.label), findsOneWidget);

      source.features = CommunityFeatures.disabled;
      await tester.tap(find.text(CommunityEntryRow.label));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('General Health'), findsNothing);
      expect(find.text(CommunityEntryRow.label), findsNothing);
    });
  });

  group('signed out: sign-in first, content only once allowed', () {
    CommunityGate signInGate(
      StaticCommunityFeatureSource source,
      InMemoryCommunityAuthService auth,
    ) {
      return CommunityGate(
        compileTimeEnabled: true,
        source: source,
        isSignedIn: auth.hasSession,
      );
    }

    test('decision is signInRequired only while signed out', () async {
      final InMemoryCommunityAuthService auth = InMemoryCommunityAuthService();
      final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
        const CommunityFeatures(
          state: CommunityFlagState.internal,
          allowed: false,
        ),
      );
      final CommunityGate gate = signInGate(source, auth);
      expect(await gate.evaluate(), CommunityGateDecision.signInRequired);
      expect(await gate.isOpen(), isFalse, reason: 'no content');
      auth.signedIn = true;
      expect(await gate.evaluate(), CommunityGateDecision.hidden);
      source.features = CommunityFeatures.disabled;
      auth.signedIn = false;
      expect(
        await gate.evaluate(),
        CommunityGateDecision.hidden,
        reason: 'server disabled: not even sign-in is offered',
      );
    });

    testWidgets('row offers sign-in; after OTP the gate decides again', (
      tester,
    ) async {
      final InMemoryCommunityAuthService auth = InMemoryCommunityAuthService();
      final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
        const CommunityFeatures(
          state: CommunityFlagState.internal,
          allowed: false,
        ),
      );
      await _pumpMore(
        tester,
        module: _module(signInGate(source, auth), auth: auth),
      );
      expect(find.text(CommunityEntryRow.label), findsOneWidget);
      await tester.tap(find.text(CommunityEntryRow.label));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Sign in to Community'), findsOneWidget);
      expect(find.text('General Health'), findsNothing);

      await tester.enterText(find.byKey(const Key('signin_email')), 'a@b.ng');
      await tester.tap(find.byKey(const Key('signin_send_code')));
      await tester.pump();
      expect(auth.requestedFor, <String>['a@b.ng']);
      await tester.enterText(find.byKey(const Key('signin_code')), '000000');
      await tester.tap(find.byKey(const Key('signin_verify')));
      await tester.pump();
      expect(find.textContaining('wrong or has expired'), findsOneWidget);

      // The server allowlists this account once it is signed in.
      source.features = _internalAllowed;
      await tester.enterText(find.byKey(const Key('signin_code')), '123456');
      await tester.tap(find.byKey(const Key('signin_verify')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('General Health'), findsOneWidget);
    });

    testWidgets('signed in but not allowlisted: told, and nothing opens', (
      tester,
    ) async {
      final InMemoryCommunityAuthService auth = InMemoryCommunityAuthService();
      final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
        const CommunityFeatures(
          state: CommunityFlagState.closedBeta,
          allowed: false,
        ),
      );
      await _pumpMore(
        tester,
        module: _module(signInGate(source, auth), auth: auth),
      );
      await tester.tap(find.text(CommunityEntryRow.label));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byKey(const Key('signin_email')), 'a@b.ng');
      await tester.tap(find.byKey(const Key('signin_send_code')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('signin_code')), '123456');
      await tester.tap(find.byKey(const Key('signin_verify')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('Community is not available for this account.'),
        findsOneWidget,
      );
      expect(find.text('General Health'), findsNothing);
      expect(find.text(CommunityEntryRow.label), findsNothing);
    });

    testWidgets('recovery entry explains lost device and lost email', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CommunitySignInScreen(auth: InMemoryCommunityAuthService()),
        ),
      );
      await tester.tap(find.byKey(const Key('signin_recovery')));
      await tester.pumpAndSettle();
      expect(find.text(CommunityRecoverySheet.lostDevice), findsOneWidget);
      expect(find.text(CommunityRecoverySheet.lostEmail), findsOneWidget);
    });
  });

  group('CommunityGate caching', () {
    test('an allow is cached for the TTL, then re-fetched', () async {
      DateTime now = DateTime.utc(2026, 11, 7, 10);
      final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
        _internalAllowed,
      );
      final CommunityGate gate = CommunityGate(
        compileTimeEnabled: true,
        source: source,
        clock: () => now,
      );
      expect(await gate.isOpen(), isTrue);
      expect(await gate.isOpen(), isTrue);
      expect(source.fetchCount, 1);
      now = now.add(const Duration(minutes: 6));
      expect(await gate.isOpen(), isTrue);
      expect(source.fetchCount, 2);
    });

    test('fresh bypasses the cache', () async {
      final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
        _internalAllowed,
      );
      final CommunityGate gate = CommunityGate(
        compileTimeEnabled: true,
        source: source,
      );
      await gate.isOpen();
      source.features = CommunityFeatures.disabled;
      expect(await gate.isOpen(), isTrue, reason: 'cached allow');
      expect(await gate.isOpen(fresh: true), isFalse);
      expect(await gate.isOpen(), isFalse, reason: 'deny clears the cache');
    });

    test('an error discards a cached allow (no stale-while-error)', () async {
      DateTime now = DateTime.utc(2026, 11, 7, 10);
      final _FlakySource source = _FlakySource();
      final CommunityGate gate = CommunityGate(
        compileTimeEnabled: true,
        source: source,
        clock: () => now,
      );
      expect(await gate.isOpen(), isTrue);
      source.fail = true;
      now = now.add(const Duration(minutes: 6));
      expect(await gate.isOpen(), isFalse);
      source.fail = false;
      source.features = CommunityFeatures.disabled;
      expect(await gate.isOpen(), isFalse);
    });

    test('invalidate drops the cached allow', () async {
      final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
        _internalAllowed,
      );
      final CommunityGate gate = CommunityGate(
        compileTimeEnabled: true,
        source: source,
      );
      await gate.isOpen();
      gate.invalidate();
      await gate.isOpen();
      expect(source.fetchCount, 2);
    });
  });

  group('/v1/features parsing (strict)', () {
    test('valid states parse', () {
      for (final CommunityFlagState s in CommunityFlagState.values) {
        final CommunityFeatures f = CommunityFeatures.fromJson(
          <String, dynamic>{'community': s.wire, 'community_allowed': true},
        );
        expect(f.state, s);
        expect(f.toJson()['community'], s.wire);
      }
      expect(CommunityFlagState.closedBeta.wire, 'closed_beta');
    });

    test('malformed bodies throw (and so the gate closes)', () {
      final List<Map<String, dynamic>> bad = [
        <String, dynamic>{},
        <String, dynamic>{'community': 'internal'},
        <String, dynamic>{'community_allowed': true},
        <String, dynamic>{'community': 'internal', 'community_allowed': 'yes'},
        <String, dynamic>{'community': 1, 'community_allowed': true},
      ];
      for (final Map<String, dynamic> body in bad) {
        expect(
          () => CommunityFeatures.fromJson(body),
          throwsFormatException,
          reason: '$body',
        );
      }
    });

    test('an unknown mode is treated as disabled (§6, §13)', () {
      final CommunityFeatures f = CommunityFeatures.fromJson(<String, dynamic>{
        'community': 'everyone',
        'community_allowed': true,
      });
      expect(f.state, CommunityFlagState.disabled);
      expect(f.permitsEntry, isFalse);
    });

    test('only an enabled state with allowed=true permits entry', () {
      expect(CommunityFeatures.disabled.permitsEntry, isFalse);
      expect(_internalAllowed.permitsEntry, isTrue);
      expect(
        const CommunityFeatures(
          state: CommunityFlagState.public,
          allowed: false,
        ).permitsEntry,
        isFalse,
      );
    });
  });
}

class _FlakySource implements CommunityFeatureSource {
  bool fail = false;
  CommunityFeatures features = _internalAllowed;

  @override
  Future<CommunityFeatures> fetch() async {
    if (fail) throw const CommunityFeatureFetchException('down');
    return features;
  }
}
