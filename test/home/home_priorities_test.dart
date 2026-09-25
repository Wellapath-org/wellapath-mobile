/// The home screen's contract: what is offered, in what order, and what a
/// 360 × 800 phone can see without scrolling.
///
/// These are the assertions that stop a future redesign quietly demoting the
/// clinic locator into a menu, pushing emergency help below the fold, or
/// letting the disclaimer scroll away.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellapath_mobile/features/home/home_screen.dart';
import 'package:wellapath_mobile/shared/theme/brand.dart';

/// A small Android phone — the shape the brief targets.
void _useSmallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpHome(WidgetTester tester, {Size? size}) async {
  if (size == null) {
    _useSmallPhone(tester);
  } else {
    tester.view.physicalSize = Size(size.width * 3, size.height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

/// True when the widget's box sits fully inside the viewport.
bool _fullyOnScreen(WidgetTester tester, Finder finder) {
  final Rect rect = tester.getRect(finder);
  final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  return rect.top >= 0 &&
      rect.bottom <= screen.height &&
      rect.left >= 0 &&
      rect.right <= screen.width;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('the three essential actions', () {
    testWidgets('are all visible without scrolling at 360x800', (tester) async {
      await _pumpHome(tester);

      for (final String label in [
        'Check your symptoms',
        'Find a clinic',
        'Need urgent help?',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label must exist');
        expect(
          _fullyOnScreen(tester, find.text(label)),
          isTrue,
          reason: '$label must be reachable without scrolling',
        );
      }
    });

    testWidgets('keep their order: symptoms, clinic, emergency', (
      tester,
    ) async {
      await _pumpHome(tester);

      final double symptoms = tester
          .getTopLeft(find.text('Check your symptoms'))
          .dy;
      final double clinic = tester.getTopLeft(find.text('Find a clinic')).dy;
      final double emergency = tester
          .getTopLeft(find.text('Need urgent help?'))
          .dy;

      expect(symptoms, lessThan(clinic));
      expect(clinic, lessThan(emergency));
    });

    testWidgets('are still visible on a larger phone', (tester) async {
      await _pumpHome(tester, size: const Size(412, 915));
      for (final String label in [
        'Check your symptoms',
        'Find a clinic',
        'Need urgent help?',
      ]) {
        expect(_fullyOnScreen(tester, find.text(label)), isTrue);
      }
    });

    testWidgets('the locator is a home action, not a menu item', (
      tester,
    ) async {
      await _pumpHome(tester);
      expect(
        find.text('Health facilities, sorted by distance.'),
        findsOneWidget,
      );
      // Not inside a horizontal carousel.
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is ListView && w.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
      );
    });
  });

  group('primary action', () {
    testWidgets('carries title, explanation, duration and a Start control', (
      tester,
    ) async {
      await _pumpHome(tester);
      expect(find.text('Check your symptoms'), findsOneWidget);
      expect(
        find.text(
          'Answer a few simple questions to understand what to do next.',
        ),
        findsOneWidget,
      );
      expect(find.text('About 2 minutes'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('opens the existing assessment disclosure sheet', (
      tester,
    ) async {
      await _pumpHome(tester);
      await tester.tap(find.text('Check your symptoms'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // The clinical gate, unchanged: its own wording, its own sheet.
      expect(find.textContaining('not a diagnosis'), findsWidgets);
      expect(find.text('Okay'), findsOneWidget);
    });
  });

  group('emergency help', () {
    testWidgets('is a calm tinted surface, not a red panel', (tester) async {
      await _pumpHome(tester);

      final Container card = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Need urgent help?'),
              matching: find.byType(Container),
            )
            .last,
      );
      final BoxDecoration decoration = card.decoration! as BoxDecoration;
      expect(decoration.color, Brand.emergencySurface);
    });

    testWidgets('says what the control will do', (tester) async {
      await _pumpHome(tester);
      expect(find.text('Calls emergency services on 112.'), findsOneWidget);
    });

    testWidgets('carries no pulsing or flashing animation', (tester) async {
      await _pumpHome(tester);
      // Nothing in the emergency row repeats: the only animations on home
      // are one-shot entrances plus Wella's breathing, which lives in the
      // greeting.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Need urgent help?'),
            matching: find.byType(Container),
          ),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    });
  });

  group('everyday layer', () {
    testWidgets('Wella Today sits after the three essentials', (tester) async {
      await _pumpHome(tester);
      await tester.scrollUntilVisible(find.text('WELLA TODAY'), 120);
      await tester.pump();

      expect(find.text('WELLA TODAY'), findsOneWidget);
      expect(find.text('Show me another'), findsOneWidget);
    });

    testWidgets('Show me another changes the card without storing anything', (
      tester,
    ) async {
      await _pumpHome(tester);
      await tester.scrollUntilVisible(find.text('Show me another'), 120);
      await tester.pump();

      final String before = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .join('|');

      await tester.tap(find.text('Show me another'));
      await tester.pump();

      final String after = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .join('|');
      expect(after, isNot(before), reason: 'a different card must appear');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys(),
        isEmpty,
        reason: 'reading history must not be stored',
      );
    });

    testWidgets('Learn and Help are offered below the essentials', (
      tester,
    ) async {
      await _pumpHome(tester);
      await tester.scrollUntilVisible(find.text('Help and support'), 120);
      await tester.pump();
      expect(find.text('Learn'), findsOneWidget);
      expect(find.text('Help and support'), findsOneWidget);
    });
  });

  group('the disclaimer', () {
    // Matched exactly: a Wella Today card also carries the phrase "not a
    // diagnosis", and the point of these tests is the pinned footer.
    final Finder disclaimer = find.text(
      'WellaPath helps you decide what to do next. It is not a diagnosis '
      'and not a substitute for emergency services.',
    );

    testWidgets('is visible without scrolling', (tester) async {
      await _pumpHome(tester);
      expect(disclaimer, findsOneWidget);
      expect(_fullyOnScreen(tester, disclaimer), isTrue);
    });

    testWidgets('stays visible after scrolling the content', (tester) async {
      await _pumpHome(tester);
      final Rect before = tester.getRect(disclaimer);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();

      expect(
        _fullyOnScreen(tester, disclaimer),
        isTrue,
        reason: 'pinned, not part of the scroll',
      );
      expect(
        tester.getRect(disclaimer),
        before,
        reason: 'it must not move with the content',
      );
    });
  });
}
