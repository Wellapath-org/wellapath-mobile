import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';
import 'package:wellapath_mobile/features/assessment/assessment_controller.dart';
import 'package:wellapath_mobile/features/results/red_flag_interrupt_screen.dart';
import 'package:wellapath_mobile/features/results/results_screen.dart';

final mockRedFlagOutput = EngineOutput(
  urgency: 'emergency',
  redFlagTriggered: true,
  matchedRuleId: 'rf_002',
  matchedRuleName: 'Active Seizures',
  topCauses: [
    {
      'condition_id': 'malaria',
      'condition_name': 'Malaria',
      'score': 37,
      'explanation': 'Your symptoms may be consistent with malaria.',
      'urgency': 'emergency',
    },
  ],
  explanationPoints: ['Active Seizures'],
  careInstruction: 'Go to emergency now — do not wait.',
  artifactsUsed: {
    'kb_version': '1.0',
    'rules_version': '1.0',
    'token_dict_version': '1.0',
  },
);

final mockNormalOutput = EngineOutput(
  urgency: 'urgent',
  redFlagTriggered: false,
  matchedRuleId: null,
  matchedRuleName: null,
  topCauses: const [],
  explanationPoints: const [],
  careInstruction: 'Visit a clinic or health facility today.',
  artifactsUsed: {
    'kb_version': '1.0',
    'rules_version': '1.0',
    'token_dict_version': '1.0',
  },
);

void main() {
  testWidgets('RedFlagInterruptScreen renders with red flag output', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RedFlagInterruptScreen(
          engineOutput: mockRedFlagOutput,
          assessmentController: AssessmentController(),
        ),
      ),
    );

    expect(find.text('EMERGENCY'), findsOneWidget);
    expect(find.text('Seek medical care immediately'), findsOneWidget);
  });

  testWidgets('matched_rule_name renders on interrupt screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RedFlagInterruptScreen(
          engineOutput: mockRedFlagOutput,
          assessmentController: AssessmentController(),
        ),
      ),
    );

    expect(find.textContaining('Active Seizures'), findsWidgets);
  });

  testWidgets('top_causes render on interrupt screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RedFlagInterruptScreen(
          engineOutput: mockRedFlagOutput,
          assessmentController: AssessmentController(),
        ),
      ),
    );

    expect(find.text('Malaria'), findsOneWidget);
    expect(find.text('Seek emergency care'), findsOneWidget);
  });

  testWidgets('ResultsScreen renders with non-red-flag output', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ResultsScreen(engineOutput: mockNormalOutput)),
    );

    expect(find.textContaining('Results Screen'), findsOneWidget);
  });

  testWidgets(
    'RedFlagInterruptScreen shows EMERGENCY not other urgency levels',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RedFlagInterruptScreen(
            engineOutput: mockRedFlagOutput,
            assessmentController: AssessmentController(),
          ),
        ),
      );

      expect(find.text('EMERGENCY'), findsOneWidget);
      expect(find.textContaining('urgent'), findsNothing);
      expect(find.textContaining('non_urgent'), findsNothing);
      expect(find.textContaining('self_care'), findsNothing);
    },
  );
}
