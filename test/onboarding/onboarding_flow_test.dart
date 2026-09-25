/// The "Meet Wella" introduction: moving through it, skipping it, replaying
/// it, and the promise that it stores no health information.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellapath_mobile/features/onboarding/onboarding_screen.dart';
import 'package:wellapath_mobile/features/shell/app_shell.dart';
import 'package:wellapath_mobile/shared/widgets/wella.dart';

/// A small Android phone (360x800 logical), which is the shape the brief
/// asks us to design for. The default 800x600 test window is wider and much
/// shorter than any phone, and hides below-the-fold layout problems.
void _useSmallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pump(WidgetTester tester, {bool replay = false}) async {
  _useSmallPhone(tester);
  await tester.pumpWidget(MaterialApp(home: OnboardingScreen(replay: replay)));
  await tester.pump(const Duration(milliseconds: 700));
}

/// Wella breathes continuously, so the scheduler never goes idle and
/// `pumpAndSettle` would time out. Tests advance time explicitly instead —
/// long enough to finish a page transition or a route push.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  // Comfortably longer than a route push (~300ms) plus the entrance fades.
  await tester.pump(const Duration(seconds: 1));
}

/// Taps the page's primary action and advances past the page transition.
Future<void> _tapAndSettle(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
  await _settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('first run', () {
    testWidgets('opens on Meet Wella with Wella present', (tester) async {
      await _pump(tester);
      expect(find.text('Meet Wella'), findsOneWidget);
      expect(find.byType(Wella), findsWidgets);
      expect(find.text('Skip for now'), findsOneWidget);
    });

    testWidgets('walks all five screens to the finish', (tester) async {
      await _pump(tester);

      expect(find.text('Meet Wella'), findsOneWidget);
      await _tapAndSettle(tester, 'Say hello');

      expect(find.text('What brings you here?'), findsOneWidget);
      await _tapAndSettle(tester, 'I’ll decide later');

      expect(find.text('Three simple steps'), findsOneWidget);
      await _tapAndSettle(tester, 'Next');

      expect(find.text('What WellaPath is'), findsOneWidget);
      await _tapAndSettle(tester, 'I understand');

      expect(find.text('You’re all set'), findsOneWidget);
      expect(find.text('Start with WellaPath'), findsOneWidget);
    });

    testWidgets('finishing marks onboarding seen and opens the app shell', (
      tester,
    ) async {
      await _pump(tester);
      for (final String label in [
        'Say hello',
        'I’ll decide later',
        'Next',
        'I understand',
      ]) {
        await _tapAndSettle(tester, label);
      }
      await _tapAndSettle(tester, 'Start with WellaPath');

      expect(find.byType(AppShell), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingScreen.onboardingSeenKey), isTrue);
    });

    testWidgets('the trust screen states the limits plainly', (tester) async {
      await _pump(tester);
      await _tapAndSettle(tester, 'Say hello');
      await _tapAndSettle(tester, 'I’ll decide later');
      await _tapAndSettle(tester, 'Next');

      expect(find.text('It does not replace a doctor'), findsOneWidget);
      expect(
        find.text('If you feel seriously unwell, seek urgent help'),
        findsOneWidget,
      );
    });
  });

  group('skipping', () {
    testWidgets('skip is available on the first screen and finishes', (
      tester,
    ) async {
      await _pump(tester);
      await _tapAndSettle(tester, 'Skip for now');

      expect(find.byType(AppShell), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(OnboardingScreen.onboardingSeenKey),
        isTrue,
        reason: 'skipping is a decision; it must not re-prompt next launch',
      );
    });

    testWidgets('skip stays available on every screen', (tester) async {
      await _pump(tester);
      for (final String label in [
        'Say hello',
        'I’ll decide later',
        'Next',
        'I understand',
      ]) {
        expect(find.text('Skip for now'), findsOneWidget);
        await _tapAndSettle(tester, label);
      }
      expect(find.text('Skip for now'), findsOneWidget);
    });
  });

  group('choices are navigation only', () {
    testWidgets('choosing a start point stores nothing', (tester) async {
      await _pump(tester);
      await _tapAndSettle(tester, 'Say hello');
      await _tapAndSettle(tester, 'I want to understand my symptoms');
      await _tapAndSettle(tester, 'Next');
      await _tapAndSettle(tester, 'I understand');
      await _tapAndSettle(tester, 'Start with WellaPath');

      final prefs = await SharedPreferences.getInstance();
      // Exactly one key may exist: the seen flag. Nothing about the person,
      // their health, or what they picked.
      expect(prefs.getKeys(), {OnboardingScreen.onboardingSeenKey});
    });

    testWidgets('choosing Learn opens the app on the Learn tab', (
      tester,
    ) async {
      await _pump(tester);
      await _tapAndSettle(tester, 'Say hello');
      await _tapAndSettle(tester, 'I want to learn how WellaPath works');
      await _tapAndSettle(tester, 'Next');
      await _tapAndSettle(tester, 'I understand');
      await _tapAndSettle(tester, 'Start with WellaPath');

      final AppShell shell = tester.widget<AppShell>(find.byType(AppShell));
      expect(shell.initialTab, ShellTab.learn);
    });

    testWidgets('choosing symptoms does NOT auto-start an assessment', (
      tester,
    ) async {
      await _pump(tester);
      await _tapAndSettle(tester, 'Say hello');
      await _tapAndSettle(tester, 'I want to understand my symptoms');
      await _tapAndSettle(tester, 'Next');
      await _tapAndSettle(tester, 'I understand');
      await _tapAndSettle(tester, 'Start with WellaPath');

      // It lands on Home, where the assessment's own disclosure sheet gates
      // the flow. Onboarding must never step around that.
      final AppShell shell = tester.widget<AppShell>(find.byType(AppShell));
      expect(shell.initialTab, ShellTab.home);
      expect(find.text('Check your symptoms'), findsOneWidget);
    });
  });

  group('replay', () {
    testWidgets('a replay closes back instead of re-routing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OnboardingScreen(replay: true),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await _tapAndSettle(tester, 'open');

      expect(find.text('Meet Wella'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      await _tapAndSettle(tester, 'Close');

      // Back where we started — no shell pushed, no navigation side effects.
      expect(find.text('open'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('a replay does not write preferences', (tester) async {
      await _pump(tester, replay: true);
      await _tapAndSettle(tester, 'Close');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys(),
        isEmpty,
        reason: 'watching the introduction again is not a state change',
      );
    });

    testWidgets('the final screen offers a return, not a restart', (
      tester,
    ) async {
      await _pump(tester, replay: true);
      for (final String label in [
        'Say hello',
        'I’ll decide later',
        'Next',
        'I understand',
      ]) {
        await _tapAndSettle(tester, label);
      }
      expect(find.text('Back to WellaPath'), findsOneWidget);
      expect(find.text('Start with WellaPath'), findsNothing);
    });
  });
}
