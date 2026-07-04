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

const Color _testUrgentColor = Color(0xFFF59E0B);
const Color _testInactiveDashColor = Color(0xFFE5E7EB);

Future<int> _countDashesOfColor(
  WidgetTester tester,
  int rank,
  Color color,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: ConditionCard(
            condition: const {
              'condition_name': 'Test Condition',
              'urgency': 'urgent',
            },
            rank: rank,
          ),
        ),
      ),
    ),
  );

  final dashFinder = find.byWidgetPredicate((widget) {
    if (widget is! Container) return false;
    final decoration = widget.decoration;
    if (decoration is! BoxDecoration) return false;
    if (widget.constraints?.maxWidth != 14) return false;
    return decoration.color == color;
  });

  return tester.widgetList(dashFinder).length;
}

void main() {
  testWidgets(
    'non_urgent urgency shows NON-URGENT banner and correct care instruction',
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
    'ConditionCard dash indicator reflects rank (1st=4, 2nd=3, 3rd=2 coloured)',
    (tester) async {
      final rank1Colored = await _countDashesOfColor(
        tester,
        1,
        _testUrgentColor,
      );
      final rank2Colored = await _countDashesOfColor(
        tester,
        2,
        _testUrgentColor,
      );
      final rank2Grey = await _countDashesOfColor(
        tester,
        2,
        _testInactiveDashColor,
      );
      final rank3Colored = await _countDashesOfColor(
        tester,
        3,
        _testUrgentColor,
      );
      final rank3Grey = await _countDashesOfColor(
        tester,
        3,
        _testInactiveDashColor,
      );

      expect(rank1Colored, 4);
      expect(rank2Colored, 3);
      expect(rank2Grey, 1);
      expect(rank3Colored, 2);
      expect(rank3Grey, 2);
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

    expect(find.text('Close your assessment result?'), findsOneWidget);
  });
}
