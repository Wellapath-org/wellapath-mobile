import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/home/home_screen.dart';

/// E9 — the home screen offers three services directly instead of a single
/// assessment entry point.
///
/// The disclaimer assertions matter most: two of the three services skip the
/// assessment flow entirely, so a user can reach care without ever seeing the
/// modal that used to carry the CDSS wording. LOCKED PRINCIPLE #1 requires
/// WellaPath never read as a diagnosis engine, so that copy has to live on
/// the home screen itself.

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await tester.pump();
}

void main() {
  testWidgets('all three services are offered', (WidgetTester tester) async {
    await _pumpHome(tester);

    expect(find.text('Check your symptoms'), findsOneWidget);
    expect(find.text('Find a clinic'), findsOneWidget);
    expect(find.text('Call emergency — 112'), findsOneWidget);
  });

  testWidgets('each service is tappable', (WidgetTester tester) async {
    await _pumpHome(tester);

    for (final String title in <String>[
      'Check your symptoms',
      'Find a clinic',
      'Call emergency — 112',
    ]) {
      expect(
        find.ancestor(of: find.text(title), matching: find.byType(InkWell)),
        findsOneWidget,
        reason: '$title must be tappable',
      );
    }
  });

  testWidgets('the CDSS disclaimer is on the home screen itself', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester);

    final Finder disclaimer = find.textContaining('not a diagnosis');
    expect(disclaimer, findsOneWidget);
    expect(
      find.textContaining('not a substitute for emergency'),
      findsOneWidget,
    );
  });

  testWidgets('the emergency service is visually distinct', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester);

    const Color emergencyRed = Color(0xFFDC2626);
    final Text emergencyTitle = tester.widget<Text>(
      find.text('Call emergency — 112'),
    );
    final Text symptomsTitle = tester.widget<Text>(
      find.text('Check your symptoms'),
    );

    expect(emergencyTitle.style?.color, emergencyRed);
    expect(symptomsTitle.style?.color, isNot(emergencyRed));
  });

  testWidgets('emergency says no assessment is needed', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester);

    expect(find.textContaining('No assessment needed'), findsOneWidget);
  });

  testWidgets('the old single entry point is gone', (
    WidgetTester tester,
  ) async {
    await _pumpHome(tester);

    expect(find.text('Start Symptom Assessment'), findsNothing);
  });
}
