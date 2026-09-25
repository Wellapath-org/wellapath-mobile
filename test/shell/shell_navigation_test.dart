/// The bottom bar: three labelled tabs, every one a finished screen, and the
/// replay entry point the brief asks for under *How WellaPath works*.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellapath_mobile/features/learn/learn_content.dart';
import 'package:wellapath_mobile/features/learn/learn_screen.dart';
import 'package:wellapath_mobile/features/more/more_screen.dart';
import 'package:wellapath_mobile/features/onboarding/onboarding_screen.dart';
import 'package:wellapath_mobile/features/shell/app_shell.dart';
import 'package:wellapath_mobile/shared/theme/brand.dart';

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

Future<void> _pumpShell(
  WidgetTester tester, {
  ShellTab tab = ShellTab.home,
}) async {
  _useSmallPhone(tester);
  await tester.pumpWidget(MaterialApp(home: AppShell(initialTab: tab)));
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

/// Brings [finder] into view and lets the scroll settle before it is tapped:
/// tapping straight after `scrollUntilVisible` can resolve a stale position
/// and land on whatever is underneath.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 120);
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('three tabs, each with a visible text label', (tester) async {
    await _pumpShell(tester);

    final NavigationBar bar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(bar.destinations, hasLength(3));
    expect(
      bar.labelBehavior,
      NavigationDestinationLabelBehavior.alwaysShow,
      reason: 'icon-only navigation asks unwell people to guess',
    );
    for (final String label in ['Home', 'Learn', 'More']) {
      expect(find.text(label), findsWidgets);
    }
  });

  testWidgets('tabs switch and keep their state', (tester) async {
    await _pumpShell(tester);
    expect(find.text('How can WellaPath help you today?'), findsOneWidget);

    await tester.tap(find.text('Learn'));
    await _settle(tester);
    expect(find.byType(LearnScreen), findsOneWidget);
    expect(find.text('LEARN IN ONE MINUTE'), findsOneWidget);

    await tester.tap(find.text('More'));
    await _settle(tester);
    expect(find.byType(MoreScreen), findsOneWidget);
    expect(find.text('About WellaPath'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await _settle(tester);
    expect(find.text('How can WellaPath help you today?'), findsOneWidget);
  });

  testWidgets('android back returns to Home instead of leaving the app', (
    tester,
  ) async {
    await _pumpShell(tester, tab: ShellTab.learn);
    expect(find.byType(LearnScreen), findsOneWidget);

    // The system back gesture, as Android delivers it.
    final bool popped = await tester.binding.handlePopRoute();
    await _settle(tester);

    expect(
      popped,
      isTrue,
      reason: 'the shell must consume back rather than let the app close',
    );
    expect(find.text('How can WellaPath help you today?'), findsOneWidget);
  });

  testWidgets('android back from Home is not swallowed', (tester) async {
    await _pumpShell(tester);
    final bool popped = await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(
      popped,
      isFalse,
      reason: 'on Home, back belongs to the system as usual',
    );
  });

  testWidgets('an initial tab can be requested', (tester) async {
    await _pumpShell(tester, tab: ShellTab.learn);
    expect(find.byType(LearnScreen), findsOneWidget);
  });

  testWidgets('home\'s How WellaPath works switches to the Learn tab', (
    tester,
  ) async {
    await _pumpShell(tester);
    await _scrollTo(tester, find.text('How WellaPath works'));
    await tester.tap(find.text('How WellaPath works'));
    await _settle(tester);

    // Switched tabs rather than stacking a second copy on top.
    expect(find.byType(LearnScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('Learn replays the introduction', (tester) async {
    await _pumpShell(tester, tab: ShellTab.learn);

    // Scoped to the Learn subtree: IndexedStack keeps every tab built (that
    // is how tab state survives switching), so an unscoped finder can match
    // an identical control on a tab that is not on screen.
    final Finder replay = find.descendant(
      of: find.byType(LearnScreen),
      matching: find.text('Replay introduction'),
    );
    await _scrollTo(tester, replay);
    await tester.tap(replay);
    await _settle(tester);

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Meet Wella'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await _settle(tester);
    expect(find.byType(LearnScreen), findsOneWidget);
  });

  testWidgets('More replays the introduction too', (tester) async {
    await _pumpShell(tester, tab: ShellTab.more);

    final Finder replay = find.descendant(
      of: find.byType(MoreScreen),
      matching: find.text('Replay introduction'),
    );
    await _scrollTo(tester, replay);
    await tester.tap(replay);
    await _settle(tester);
    expect(find.text('Meet Wella'), findsOneWidget);
  });

  testWidgets('the Learn card of the day is deterministic by date', (
    tester,
  ) async {
    final card = LearnContent.forDate(DateTime(2026, 9, 25));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LearnScreen(today: DateTime(2026, 9, 25))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text(card.title), findsWidgets);
  });

  testWidgets('every tap target meets the 48dp minimum', (tester) async {
    await _pumpShell(tester);

    for (final String label in ['Check your symptoms', 'Find a clinic']) {
      await _scrollTo(tester, find.text(label));
      final Size size = tester.getSize(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .last,
      );
      expect(
        size.height,
        greaterThanOrEqualTo(Brand.minTapTarget),
        reason: '$label must be comfortably tappable',
      );
    }
  });
}
