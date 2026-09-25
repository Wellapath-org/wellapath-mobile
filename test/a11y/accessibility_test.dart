/// Accessibility: text that grows without breaking the layout, motion that
/// can be switched off, tap targets that can be hit, and colour that is
/// never the only signal.
///
/// The text-scaling tests are the ones most likely to catch a real
/// regression: a fixed-height row or an unwrapped `Row` looks fine at 1.0×
/// and overflows the moment someone turns their system font up.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellapath_mobile/features/feedback/feedback_screen.dart';
import 'package:wellapath_mobile/features/help/help_screen.dart';
import 'package:wellapath_mobile/features/home/home_screen.dart';
import 'package:wellapath_mobile/features/learn/learn_content.dart';
import 'package:wellapath_mobile/features/learn/learn_screen.dart';
import 'package:wellapath_mobile/features/onboarding/onboarding_screen.dart';
import 'package:wellapath_mobile/shared/theme/brand.dart';

/// Pumps [child] on a small phone at [textScale] and returns any layout
/// exception (an overflow throws during layout, so this catches it).
Future<Object?> _pumpAt(
  WidgetTester tester,
  Widget child, {
  required double textScale,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduceMotion,
      ),
      child: MaterialApp(home: child),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
  return tester.takeException();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('text scaling does not break the layout', () {
    for (final double scale in [1.0, 1.3, 1.6, 2.0]) {
      testWidgets('home at ${scale}x', (tester) async {
        expect(
          await _pumpAt(tester, const HomeScreen(), textScale: scale),
          isNull,
          reason: 'home must not overflow at ${scale}x text',
        );
      });

      testWidgets('learn at ${scale}x', (tester) async {
        expect(
          await _pumpAt(
            tester,
            const Scaffold(body: LearnScreen()),
            textScale: scale,
          ),
          isNull,
        );
      });

      testWidgets('help at ${scale}x', (tester) async {
        expect(
          await _pumpAt(tester, const HelpScreen(), textScale: scale),
          isNull,
        );
      });

      testWidgets('onboarding at ${scale}x', (tester) async {
        expect(
          await _pumpAt(tester, const OnboardingScreen(), textScale: scale),
          isNull,
        );
      });

      testWidgets('feedback at ${scale}x', (tester) async {
        expect(
          await _pumpAt(tester, const FeedbackScreen(), textScale: scale),
          isNull,
        );
      });

      testWidgets('the feedback outcome at ${scale}x keeps Close reachable', (
        tester,
      ) async {
        // Reported in review: only step 1 was ever rendered at large text,
        // so a 606px overflow on the outcome step went unnoticed — and it
        // pushed the only way out of the screen off the bottom.
        await _pumpAt(tester, const FeedbackScreen(), textScale: scale);
        for (final String label in [
          'Needs improvement',
          'Accessibility',
          'Send feedback',
        ]) {
          final Finder target = find.text(label);
          if (target.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              target,
              120,
              scrollable: find.byType(Scrollable).first,
            );
          }
          await tester.ensureVisible(target);
          await tester.pump();
          await tester.tap(target);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
        }

        expect(
          tester.takeException(),
          isNull,
          reason: 'the outcome must not overflow at ${scale}x text',
        );
        expect(find.text('Feedback is not open yet'), findsOneWidget);

        // Close is pinned, not scrolled away with the message.
        final Finder close = find.text('Close');
        expect(close, findsOneWidget);
        final Rect box = tester.getRect(close);
        expect(
          box.bottom,
          lessThanOrEqualTo(800),
          reason: 'Close must stay on screen at ${scale}x text',
        );
      });
    }
  });

  group('reduced motion', () {
    testWidgets('home settles immediately with animations disabled', (
      tester,
    ) async {
      expect(
        await _pumpAt(
          tester,
          const HomeScreen(),
          textScale: 1,
          reduceMotion: true,
        ),
        isNull,
      );

      // Entrance animations are skipped, so content is fully opaque on the
      // first frame rather than fading in.
      final Iterable<Opacity> fades = tester.widgetList<Opacity>(
        find.byType(Opacity),
      );
      for (final Opacity o in fades) {
        expect(o.opacity, 1.0, reason: 'no partial fade under reduce-motion');
      }
    });

    testWidgets('with reduced motion the app still reaches every action', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        const HomeScreen(),
        textScale: 1,
        reduceMotion: true,
      );
      expect(find.text('Check your symptoms'), findsOneWidget);
      expect(find.text('Find a clinic'), findsOneWidget);
      expect(find.text('Need urgent help?'), findsOneWidget);
    });
  });

  group('tap targets', () {
    testWidgets('every home action is at least 48dp tall', (tester) async {
      await _pumpAt(tester, const HomeScreen(), textScale: 1);

      for (final String label in [
        'Check your symptoms',
        'Find a clinic',
        'Need urgent help?',
      ]) {
        final Size size = tester.getSize(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .last,
        );
        expect(
          size.height,
          greaterThanOrEqualTo(Brand.minTapTarget),
          reason: '$label must be at least ${Brand.minTapTarget}dp tall',
        );
      }
    });
  });

  group('screen-reader labels', () {
    testWidgets('the essential actions announce what they do', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pumpAt(tester, const HomeScreen(), textScale: 1);

      expect(
        find.bySemanticsLabel('Check your symptoms. About 2 minutes. Start'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Need urgent help? Call emergency services on 112',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('Wella is described rather than read as decoration', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pumpAt(tester, const HomeScreen(), textScale: 1);
      // Flutter merges a decorative image's label with the text beside it,
      // so match the fragment rather than the whole announcement.
      expect(
        find.bySemanticsLabel(RegExp('Wella, the WellaPath guide')),
        findsWidgets,
      );
      handle.dispose();
    });
  });

  group('colour is never the only signal', () {
    testWidgets('the myth answer states the outcome in words and an icon', (
      tester,
    ) async {
      await _pumpAt(tester, const Scaffold(body: LearnScreen()), textScale: 1);
      await tester.tap(find.text('Fact').first);
      await tester.pump();

      // Words carry the result; the icon reinforces it; colour is third.
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Text &&
              (w.data?.startsWith('Correct') == true ||
                  w.data?.startsWith('Not quite') == true),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Icon &&
              (w.icon == Icons.check_circle_rounded ||
                  w.icon == Icons.info_rounded),
        ),
        findsWidgets,
      );
    });

    testWidgets('the answer, the result and the reason announce in order', (
      tester,
    ) async {
      // The buttons disappear once answered, so the announcement has to carry
      // the choice the reader made — otherwise a screen-reader user hears a
      // verdict with nothing to attach it to.
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pumpAt(tester, const Scaffold(body: LearnScreen()), textScale: 1);

      final MythCard first = LearnContent.myths.first;
      await tester.tap(find.text('Fact').first);
      await tester.pump();

      final String expected =
          'You answered Fact. '
          '${first.isFact ? 'Correct' : 'Not quite'} — it is '
          '${first.isFact ? 'a fact' : 'a myth'}. ${first.explanation}';
      expect(find.bySemanticsLabel(expected), findsOneWidget);

      // One node, so the three parts cannot be read out of order or twice.
      expect(find.bySemanticsLabel(first.explanation), findsNothing);
      handle.dispose();
    });
  });
}
