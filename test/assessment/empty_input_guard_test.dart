import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/assessment/assessment_controller.dart';
import 'package:wellapath_mobile/features/assessment/loading_screen.dart';
import 'package:wellapath_mobile/features/assessment/symptom_selection_screen.dart';

/// Verification for the E8 empty-input guard.
///
/// With no symptoms selected the engine still scores every condition on
/// `base_weight` alone and returns the highest-weighted one, presenting a
/// result the user never described (see engine_wiring_test.dart, which pins
/// that behaviour). The symptom selection screen already disables its
/// Continue button when nothing is selected, so this guard is defence in
/// depth on the last step before `EngineController.run()`.

const String _emptyMessage = 'Please select at least one symptom to continue.';

void main() {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Future<void> pumpFlow(
    WidgetTester tester,
    AssessmentController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('body area')),
      ),
    );

    // Rebuild the stack the real flow produces: body area -> symptom
    // selection (named) -> follow-up -> loading.
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: kSymptomSelectionRouteName),
        builder: (_) => const Scaffold(body: Text('symptom selection')),
      ),
    );
    await tester.pumpAndSettle();

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('follow-up')),
      ),
    );
    await tester.pumpAndSettle();

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            LoadingScreen(assessmentController: controller, onCancel: () {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no symptoms selected shows the guard instead of running', (
    WidgetTester tester,
  ) async {
    await pumpFlow(tester, AssessmentController());

    expect(find.text(_emptyMessage), findsOneWidget);
    expect(find.text('Select symptoms'), findsOneWidget);
    // The engine never started: the loading view's copy is absent.
    expect(
      find.text('We are running your assessment right now!'),
      findsNothing,
    );
  });

  testWidgets('the guard returns the user to symptom selection', (
    WidgetTester tester,
  ) async {
    await pumpFlow(tester, AssessmentController());

    await tester.tap(find.text('Select symptoms'));
    await tester.pumpAndSettle();

    expect(find.text('symptom selection'), findsOneWidget);
    expect(find.text(_emptyMessage), findsNothing);
    expect(find.text('follow-up'), findsNothing);
  });

  testWidgets('a symptom selected proceeds past the guard', (
    WidgetTester tester,
  ) async {
    final AssessmentController controller = AssessmentController()
      ..addSymptomToken('fever');

    await pumpFlow(tester, controller);
    await tester.pump();

    // The assessment itself needs Hive and a cached config, neither of which
    // this test provides — reaching the loading view at all proves the guard
    // let it through.
    expect(find.text(_emptyMessage), findsNothing);
    expect(
      find.text('We are running your assessment right now!'),
      findsOneWidget,
    );

    // Let the run's own timers drain so the test does not tear down with one
    // pending. Without a config it lands on the generic error view.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
