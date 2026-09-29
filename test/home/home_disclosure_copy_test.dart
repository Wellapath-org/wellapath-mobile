/// COPY-001 — the pre-assessment disclosure's grammar.
///
/// The disclosure read "The results **is** not a diagnosis." Subject and verb
/// disagreed. The clinical meaning was never wrong — WellaPath does not
/// diagnose, and the sentence said so — but this is the one screen where the
/// product states its own limits, and it is read closely by users, reviewers
/// and regulators. Sloppy grammar there undercuts the sentence doing the most
/// important work in the app.
///
/// Found during the build-215 TestFlight baseline on 2026-09-29 and carried
/// into 216 because it was still present on develop.
///
/// This is a one-word correction. These tests pin the corrected wording and,
/// deliberately, that the disclosure is still a blocking gate — so a future
/// copy edit cannot quietly turn it into something dismissible.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellapath_mobile/features/home/home_screen.dart';

Future<void> _openDisclosure(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.tap(find.text('Check your symptoms').first);
  // Not pumpAndSettle: the home screen carries a continuous animation, so it
  // never reaches a settled frame. The existing home tests pump fixed
  // durations for the same reason.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  testWidgets('the disclosure reads "The result is not a diagnosis"', (
    WidgetTester tester,
  ) async {
    await _openDisclosure(tester);
    expect(
      find.textContaining('The result is not a diagnosis'),
      findsOneWidget,
    );
  });

  testWidgets('the ungrammatical form is gone', (WidgetTester tester) async {
    await _openDisclosure(tester);
    expect(find.textContaining('The results is not a diagnosis'), findsNothing);
  });

  testWidgets('the sentence still disclaims a qualified medical opinion', (
    WidgetTester tester,
  ) async {
    // The fix must not have trimmed the clause that carries the meaning.
    await _openDisclosure(tester);
    expect(
      find.textContaining('not a qualified medical opinion'),
      findsOneWidget,
    );
  });

  testWidgets('the disclosure is still a blocking gate with an Okay control', (
    WidgetTester tester,
  ) async {
    await _openDisclosure(tester);
    expect(find.text('Okay'), findsOneWidget);
  });
}
