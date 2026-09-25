/// The home screen's offer: one obvious primary action, emergency help always
/// visible, and the CDSS disclaimer on the screen itself.
///
/// Updated for the 2026-09 home/onboarding redesign. The assertions that
/// matter for safety are unchanged in substance: emergency help is present
/// and visually distinct, the disclaimer cannot be dropped, and the internal
/// build marker still shows on internal builds.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/config/build_environment.dart';
import 'package:wellapath_mobile/features/home/home_screen.dart';
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

Future<void> _pumpHome(WidgetTester tester) async {
  _useSmallPhone(tester);
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await tester.pump();
  // Entrance animations are decorative; settle them before asserting.
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('every offered service is a working one', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester);

    // Above the fold on a small phone: the greeting, the primary action and
    // emergency help.
    expect(find.text('Check your symptoms'), findsOneWidget);
    expect(find.text('Need urgent help?'), findsOneWidget);
    expect(find.text('Find a clinic'), findsOneWidget);

    // The fourth card is one short scroll away, which is fine — what must
    // never require scrolling is the disclaimer and the primary action.
    await tester.scrollUntilVisible(find.text('How WellaPath works'), 120);
    await tester.pump();
    expect(find.text('How WellaPath works'), findsOneWidget);

    // Nothing that leads nowhere: the prototype's search, filter, "Talk to
    // Us" and "Why Us" are deliberately absent until they do something.
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Talk to'), findsNothing);
    expect(find.text('Why Us'), findsNothing);
  });

  testWidgets('the greeting is a warm question, not a form header', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester);
    expect(find.text('How can WellaPath help you today?'), findsOneWidget);
  });

  testWidgets('the primary action explains what will happen', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester);
    expect(
      find.text('Answer a few simple questions to understand what to do next.'),
      findsOneWidget,
    );
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('every service is tappable', (WidgetTester tester) async {
    await _pumpHome(tester);

    for (final String title in <String>[
      'Check your symptoms',
      'Need urgent help?',
      'Find a clinic',
      'How WellaPath works',
    ]) {
      await tester.scrollUntilVisible(find.text(title), 120);
      await tester.pump();
      final Finder tappable = find.ancestor(
        of: find.text(title),
        matching: find.byWidgetPredicate(
          (Widget w) => w is InkWell || w is GestureDetector,
        ),
      );
      expect(tappable, findsWidgets, reason: '$title must be tappable');
    }
  });

  testWidgets('the CDSS disclaimer is on the home screen itself', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester);

    expect(find.textContaining('not a diagnosis'), findsOneWidget);
    expect(
      find.textContaining('not a substitute for emergency'),
      findsOneWidget,
    );
  });

  testWidgets('emergency help is distinct but not the loudest element', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester);

    final Text emergencyTitle = tester.widget<Text>(
      find.text('Need urgent help?'),
    );
    expect(emergencyTitle.style?.color, Brand.emergency);

    // The emergency card is a tinted surface with a red accent, NOT a
    // full-bleed red panel: a permanently alarming home screen teaches people
    // to ignore the colour that should mean "act now".
    final Container card = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('Need urgent help?'),
            matching: find.byType(Container),
          )
          .last,
    );
    final BoxDecoration decoration = card.decoration! as BoxDecoration;
    expect(decoration.color, Brand.emergencyTint);
  });

  testWidgets('emergency names the number it will dial', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester);
    expect(find.textContaining('112'), findsOneWidget);
  });

  testWidgets('the internal-build marker is visible on internal builds', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester);

    // Asserted unconditionally, as it was before the redesign: dotenv is not
    // initialised in widget tests, so BuildEnvironment resolves to the
    // internal default and the marker MUST render. Wrapping this in an
    // `if (isInternal())` would let a regression that drops the marker pass
    // silently, and this is the only test that proves it renders at all.
    expect(
      BuildEnvironment.isInternal(),
      isTrue,
      reason: 'widget tests run without dotenv, which resolves to internal',
    );
    expect(
      find.text(BuildEnvironment.kInternalBuildMarker),
      findsOneWidget,
      reason: 'testers and reviewers must be able to tell this is internal',
    );
  });
}
