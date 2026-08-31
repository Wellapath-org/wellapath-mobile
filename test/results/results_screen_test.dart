import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';
import 'package:wellapath_mobile/features/assessment/assessment_controller.dart';
import 'package:wellapath_mobile/features/results/condition_card.dart';
import 'package:wellapath_mobile/features/results/results_screen.dart';
import 'package:wellapath_mobile/features/results/symptom_summary_widget.dart';

// NOTE: Result screen copy was updated for the Figma redesign (see
// PROGRESS.md) — the urgency label is now "NON-URGENT" (hyphen, matching
// the design) rather than "NON_URGENT", and each condition card now shows
// "{rank}. {name}" as a single line (no separate numbered-circle avatar) —
// the tests below were updated to match.

final mockUrgentOutput = EngineOutput(
  urgencySource: 'urgency_default',
  urgency: 'urgent',
  redFlagTriggered: false,
  matchedRuleId: null,
  matchedRuleName: null,
  topCauses: [
    {
      'condition_id': 'malaria',
      'condition_name': 'Malaria',
      'score': 37,
      'explanation': 'Your symptoms may be consistent with malaria.',
      'urgency': 'urgent',
    },
    {
      'condition_id': 'pneumonia_children',
      'condition_name': 'Pneumonia',
      'score': 20,
      'explanation': 'Your symptoms may be consistent with pneumonia.',
      'urgency': 'urgent',
    },
  ],
  explanationPoints: ['Your symptoms may be consistent with malaria.'],
  careInstruction: 'Visit a clinic or health facility today.',
  artifactsUsed: {
    'kb_version': '1.0',
    'rules_version': '1.0',
    'token_dict_version': '1.0',
  },
);

final mockNonUrgentOutput = EngineOutput(
  urgencySource: 'urgency_default',
  urgency: 'non_urgent',
  redFlagTriggered: false,
  matchedRuleId: null,
  matchedRuleName: null,
  topCauses: [
    {
      'condition_id': 'acute_diarrhoea',
      'condition_name': 'Acute Diarrhoea',
      'score': 14,
      'explanation': 'Your symptoms may be consistent with acute diarrhoea.',
      'urgency': 'non_urgent',
    },
  ],
  explanationPoints: ['Your symptoms may be consistent with acute diarrhoea.'],
  careInstruction: 'Visit a clinic within 1-2 days.',
  artifactsUsed: {
    'kb_version': '1.0',
    'rules_version': '1.0',
    'token_dict_version': '1.0',
  },
);

final mockEmergencyOutput = EngineOutput(
  urgencySource: 'global_red_flag',
  urgency: 'emergency',
  redFlagTriggered: false,
  matchedRuleId: null,
  matchedRuleName: null,
  topCauses: [
    {
      'condition_id': 'malaria',
      'condition_name': 'Malaria',
      'score': 42,
      'explanation': 'Your symptoms may be consistent with malaria.',
      'urgency': 'emergency',
    },
  ],
  explanationPoints: ['Your symptoms may be consistent with malaria.'],
  careInstruction: 'Go to emergency now — do not wait.',
  artifactsUsed: {
    'kb_version': '1.0',
    'rules_version': '1.0',
    'token_dict_version': '1.0',
  },
);

Future<int> _pumpFilledSegmentCount(
  WidgetTester tester,
  double barFraction,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: ConditionCard(
            condition: const {'condition_name': 'Test Condition', 'score': 1},
            rank: 1,
            barFraction: barFraction,
          ),
        ),
      ),
    ),
  );

  final segments = tester.widgetList<Container>(
    find.descendant(
      of: find.byType(MatchStrengthBar),
      matching: find.byType(Container),
    ),
  );
  return segments.where((c) {
    final decoration = c.decoration;
    return decoration is BoxDecoration &&
        decoration.color == const Color(0xFF9CA3AF);
  }).length;
}

void main() {
  testWidgets(
    'non_urgent urgency shows NON_URGENT banner and correct care instruction',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResultsScreen(
            engineOutput: mockNonUrgentOutput,
            assessmentController: AssessmentController(),
          ),
        ),
      );

      expect(find.text('NON-URGENT'), findsWidgets);
      expect(find.text('Visit a clinic within 1-2 days.'), findsOneWidget);
    },
  );

  testWidgets('urgent urgency shows URGENT banner and Find Care CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen(
          engineOutput: mockUrgentOutput,
          assessmentController: AssessmentController(),
        ),
      ),
    );

    expect(find.text('URGENT'), findsWidgets);
    expect(find.text('Find Care'), findsWidgets);
  });

  testWidgets(
    'emergency urgency (non-red-flag path) shows EMERGENCY banner and Call Emergency CTA',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResultsScreen(
            engineOutput: mockEmergencyOutput,
            assessmentController: AssessmentController(),
          ),
        ),
      );

      expect(find.text('EMERGENCY'), findsWidgets);
      expect(find.text('Call Emergency'), findsWidgets);
    },
  );

  testWidgets('top_causes[0].condition_name renders from engine output', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen(
          engineOutput: mockUrgentOutput,
          assessmentController: AssessmentController(),
        ),
      ),
    );

    expect(find.text('1. Malaria'), findsOneWidget);
  });

  testWidgets('top_causes[0].explanation renders from engine output', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen(
          engineOutput: mockUrgentOutput,
          assessmentController: AssessmentController(),
        ),
      ),
    );

    expect(
      find.text('Your symptoms may be consistent with malaria.'),
      findsWidgets,
    );
    expect(find.text('No explanation available'), findsNothing);
  });

  testWidgets(
    'ConditionCard match-strength bar fills more segments for a higher barFraction',
    (tester) async {
      final fullLevelSegments = await _pumpFilledSegmentCount(tester, 1.0);
      final lowerLevelSegments = await _pumpFilledSegmentCount(tester, 20 / 37);

      expect(fullLevelSegments, isNot(equals(lowerLevelSegments)));
      expect(fullLevelSegments, greaterThan(lowerLevelSegments));
    },
  );

  testWidgets('SymptomSummaryWidget shows correct display names', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SymptomSummaryWidget(symptomTokens: ['fever', 'headache']),
        ),
      ),
    );

    await tester.tap(find.text('Symptom summary'));
    await tester.pumpAndSettle();

    expect(find.text('Fever'), findsOneWidget);
    expect(find.text('Headache'), findsOneWidget);
  });

  testWidgets('X button shows close confirmation dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen(
          engineOutput: mockUrgentOutput,
          assessmentController: AssessmentController(),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Close Assessment Result'), findsOneWidget);
  });
}
