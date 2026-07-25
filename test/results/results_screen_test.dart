import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';
import 'package:wellapath_mobile/features/assessment/assessment_controller.dart';
import 'package:wellapath_mobile/features/results/condition_card.dart';
import 'package:wellapath_mobile/features/results/results_screen.dart';
import 'package:wellapath_mobile/features/results/symptom_summary_widget.dart';

final mockUrgentOutput = EngineOutput(
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

Future<double> _pumpBarWidth(WidgetTester tester, double barFraction) async {
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

  final barFinder = find.byWidgetPredicate((widget) {
    if (widget is! Container) return false;
    final decoration = widget.decoration;
    if (decoration is! BoxDecoration) return false;
    return decoration.color == const Color(0xFF9CA3AF);
  });

  return tester.getSize(barFinder).width;
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

      expect(find.text('NON_URGENT'), findsWidgets);
      expect(find.text('Visit a clinic within 1-2 days.'), findsOneWidget);
    },
  );

  testWidgets('urgent urgency shows URGENT banner and Find Nearby Care CTA', (
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
    expect(find.text('Find Nearby Care'), findsWidgets);
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

    expect(find.text('Malaria'), findsOneWidget);
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
    'ConditionCard bar width scales with barFraction (full vs proportional)',
    (tester) async {
      final fullWidth = await _pumpBarWidth(tester, 1.0);
      final proportionalWidth = await _pumpBarWidth(tester, 20 / 37);

      expect(fullWidth, isNot(equals(proportionalWidth)));
      expect(fullWidth, greaterThan(proportionalWidth));
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
