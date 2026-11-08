/// The Home-screen Community entry (build 219 discoverability fix).
///
/// Visibility follows the compile-time scaffold flag only; access follows the
/// server and the session exactly as before (FEATURE_FLAG_SPEC.md). A tap
/// that is refused navigates nowhere and says why, so there is no blank page.
/// Clinical and emergency surfaces gain no Community link.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellapath_mobile/features/community/data/community_auth_service.dart';
import 'package:wellapath_mobile/features/community/gate/community_features.dart';
import 'package:wellapath_mobile/features/community/gate/community_gate.dart';
import 'package:wellapath_mobile/features/community/ui/community_entry_row.dart';
import 'package:wellapath_mobile/features/community/ui/community_safety_banner.dart';
import 'package:wellapath_mobile/features/community/ui/community_scope.dart';
import 'package:wellapath_mobile/features/community/ui/space_list_screen.dart';
import 'package:wellapath_mobile/features/home/home_screen.dart';
import 'package:wellapath_mobile/features/shell/app_shell.dart';

const CommunityFeatures _internalAllowed = CommunityFeatures(
  state: CommunityFlagState.internal,
  allowed: true,
);
const CommunityFeatures _internalNotAllowed = CommunityFeatures(
  state: CommunityFlagState.internal,
  allowed: false,
);

CommunityModule _module(
  CommunityFeatureSource? source, {
  bool compiled = true,
  InMemoryCommunityAuthService? auth,
}) {
  final InMemoryCommunityAuthService a =
      auth ?? InMemoryCommunityAuthService(signedIn: true);
  return CommunityModule(
    gate: CommunityGate(
      compileTimeEnabled: compiled,
      source: source,
      isSignedIn: a.hasSession,
    ),
    auth: a,
    createServices: CommunityServices.inMemoryDemo,
  );
}

void _tallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpHome(WidgetTester tester, {CommunityModule? module}) async {
  _tallPhone(tester);
  await tester.pumpWidget(MaterialApp(home: HomeScreen(community: module)));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _tapEntry(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('community_entry_row')));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('scaffold disabled', () {
    testWidgets('default build: Home has no Community entry', (tester) async {
      await _pumpHome(tester);
      expect(find.byType(CommunityEntryRow), findsNothing);
      expect(find.textContaining('Community'), findsNothing);
    });

    testWidgets('default build: Home inside the real shell has no entry', (
      tester,
    ) async {
      _tallPhone(tester);
      await tester.pumpWidget(const MaterialApp(home: AppShell()));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(CommunityEntryRow), findsNothing);
    });

    testWidgets('compile flag off: no entry and no request, even if allowed', (
      tester,
    ) async {
      final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
        _internalAllowed,
      );
      await _pumpHome(tester, module: _module(source, compiled: false));
      expect(find.byType(CommunityEntryRow), findsNothing);
      expect(source.fetchCount, 0);
    });
  });

  group('scaffold enabled', () {
    testWidgets('entry is visible with its copy, below the emergency row', (
      tester,
    ) async {
      final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
        _internalNotAllowed,
      );
      await _pumpHome(tester, module: _module(source));
      expect(find.byType(CommunityEntryRow), findsOneWidget);
      expect(find.text(CommunityEntryRow.label), findsOneWidget);
      expect(find.text(CommunityEntryRow.subtitle), findsOneWidget);
      expect(source.fetchCount, 0, reason: 'no request until the user taps');

      final double emergencyBottom = tester
          .getRect(find.text('Need urgent help?'))
          .bottom;
      final double findClinicBottom = tester
          .getRect(find.text('Find a clinic'))
          .bottom;
      final double communityTop = tester
          .getRect(find.byType(CommunityEntryRow))
          .top;
      expect(communityTop, greaterThan(emergencyBottom));
      expect(communityTop, greaterThan(findClinicBottom));
    });

    testWidgets('signed out: tap leads to the Community sign-in flow only', (
      tester,
    ) async {
      final InMemoryCommunityAuthService auth = InMemoryCommunityAuthService();
      await _pumpHome(
        tester,
        module: _module(
          StaticCommunityFeatureSource(_internalNotAllowed),
          auth: auth,
        ),
      );
      await _tapEntry(tester);
      expect(find.text('Sign in to Community'), findsOneWidget);
      expect(find.byType(SpaceListScreen), findsNothing);
      expect(find.text('General Health'), findsNothing);
    });

    testWidgets('signed in, not allowlisted: no Community content, told why', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        module: _module(StaticCommunityFeatureSource(_internalNotAllowed)),
      );
      await _tapEntry(tester);
      expect(find.byType(SpaceListScreen), findsNothing);
      expect(find.text('General Health'), findsNothing);
      expect(find.text(CommunityEntryRow.notAllowedMessage), findsOneWidget);
      expect(find.byType(CommunityEntryRow), findsOneWidget);
    });

    testWidgets(
      'signed out, then not allowlisted after sign-in: nothing opens',
      (tester) async {
        final InMemoryCommunityAuthService auth =
            InMemoryCommunityAuthService();
        await _pumpHome(
          tester,
          module: _module(
            StaticCommunityFeatureSource(_internalNotAllowed),
            auth: auth,
          ),
        );
        await _tapEntry(tester);
        await tester.enterText(find.byKey(const Key('signin_email')), 'a@b.ng');
        await tester.tap(find.byKey(const Key('signin_send_code')));
        await tester.pump();
        await tester.enterText(find.byKey(const Key('signin_code')), '123456');
        await tester.tap(find.byKey(const Key('signin_verify')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(SpaceListScreen), findsNothing);
        expect(find.text(CommunityEntryRow.notAllowedMessage), findsOneWidget);
      },
    );

    testWidgets('signed in and allowlisted: Community opens', (tester) async {
      await _pumpHome(
        tester,
        module: _module(StaticCommunityFeatureSource(_internalAllowed)),
      );
      await _tapEntry(tester);
      expect(find.byType(SpaceListScreen), findsOneWidget);
      expect(find.text('General Health'), findsOneWidget);
      expect(find.text(CommunitySafetyBanner.text), findsOneWidget);
    });

    testWidgets('server disabled: graceful unavailable message, no route', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        module: _module(
          StaticCommunityFeatureSource(CommunityFeatures.disabled),
        ),
      );
      await _tapEntry(tester);
      expect(find.byType(SpaceListScreen), findsNothing);
      expect(find.text('Sign in to Community'), findsNothing);
      expect(find.text(CommunityEntryRow.disabledMessage), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget, reason: 'still on Home');
    });

    testWidgets('server unreachable: fails closed with a retry message', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        module: _module(const FailingCommunityFeatureSource()),
      );
      await _tapEntry(tester);
      expect(find.byType(SpaceListScreen), findsNothing);
      expect(find.text(CommunityEntryRow.unreachableMessage), findsOneWidget);
    });

    testWidgets('kill switch is honoured on tap (cache bypassed)', (
      tester,
    ) async {
      final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
        _internalAllowed,
      );
      final CommunityModule module = _module(source);
      expect(await module.gate.evaluate(), CommunityGateDecision.open);
      source.features = CommunityFeatures.disabled; // cached allow is stale
      await _pumpHome(tester, module: module);
      await _tapEntry(tester);
      expect(find.byType(SpaceListScreen), findsNothing);
      expect(find.text(CommunityEntryRow.disabledMessage), findsOneWidget);
    });
  });

  group('gate decision is unchanged by the reason detail', () {
    test('check() and evaluate() agree in every state', () async {
      final InMemoryCommunityAuthService auth = InMemoryCommunityAuthService();
      final StaticCommunityFeatureSource source = StaticCommunityFeatureSource(
        _internalNotAllowed,
      );
      final CommunityGate gate = CommunityGate(
        compileTimeEnabled: true,
        source: source,
        isSignedIn: auth.hasSession,
      );
      Future<void> expectBoth(
        CommunityGateDecision d,
        CommunityUnavailableReason? reason,
      ) async {
        expect(await gate.evaluate(fresh: true), d);
        final CommunityGateResult r = await gate.check(fresh: true);
        expect(r.decision, d);
        expect(r.reason, reason);
      }

      await expectBoth(CommunityGateDecision.signInRequired, null);
      auth.signedIn = true;
      await expectBoth(
        CommunityGateDecision.hidden,
        CommunityUnavailableReason.notAllowed,
      );
      source.features = _internalAllowed;
      await expectBoth(CommunityGateDecision.open, null);
      source.features = CommunityFeatures.disabled;
      await expectBoth(
        CommunityGateDecision.hidden,
        CommunityUnavailableReason.disabled,
      );
      expect(
        (await CommunityGate(
          compileTimeEnabled: false,
          source: source,
        ).check()).reason,
        CommunityUnavailableReason.notConfigured,
      );
    });
  });

  group('clinical and emergency surfaces gain no Community link', () {
    test(
      'assessment/ and results/ sources neither import nor name Community',
      () {
        final List<String> offenders = <String>[];
        for (final String dir in <String>[
          'lib/features/assessment',
          'lib/features/results',
        ]) {
          for (final FileSystemEntity e in Directory(
            dir,
          ).listSync(recursive: true)) {
            if (e is! File || !e.path.endsWith('.dart')) continue;
            final String src = e.readAsStringSync().toLowerCase();
            if (src.contains('community') || src.contains('forum')) {
              offenders.add(e.path);
            }
          }
        }
        expect(offenders, isEmpty);
      },
    );

    testWidgets('the Home emergency row contains no Community link', (
      tester,
    ) async {
      await _pumpHome(
        tester,
        module: _module(StaticCommunityFeatureSource(_internalAllowed)),
      );
      final Finder emergencyRow = find.byWidgetPredicate(
        (Widget w) => w.runtimeType.toString() == '_EmergencyRow',
      );
      expect(emergencyRow, findsOneWidget);
      expect(
        find.descendant(
          of: emergencyRow.first,
          matching: find.byType(CommunityEntryRow),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: emergencyRow.first,
          matching: find.textContaining('Community'),
        ),
        findsNothing,
      );
    });
  });
}
