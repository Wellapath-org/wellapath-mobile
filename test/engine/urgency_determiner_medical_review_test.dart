// ignore_for_file: avoid_print
// print() is intentional here — this is a validation file, not production code.
// Each case prints its full engine output for documentation purposes.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/engine_controller.dart';
import 'package:wellapath_mobile/core/engine/models/engine_input.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';

// Mock KB reused from E3.2/E3.4/E3.5 pilot case conventions, extended with
// the TB condition and headache_dizziness's increase_urgency modifier
// required for this medical review's Priority 4a test cases.
final List<Map<String, dynamic>> _mockKnowledgeBase = [
  {
    'condition_id': 'malaria',
    'condition_name': 'Malaria',
    'base_weight': 10,
    'urgency_default': 'urgent',
    'explanation_template': 'Your symptoms may be consistent with malaria...',
    'symptoms': [
      {'token': 'fever', 'weight': 9},
      {'token': 'chills', 'weight': 7},
      {'token': 'headache', 'weight': 3},
      {'token': 'body_pain', 'weight': 5},
    ],
    'demographic_modifiers': [
      {'modifier': 'children_under_5', 'effect': 'increase_urgency'},
      {'modifier': 'pregnancy', 'effect': 'escalate_emergency'},
    ],
    'seasonal_modifiers': [
      {'season': 'rainy_season', 'effect': 'increase_base_weight'},
    ],
  },
  {
    'condition_id': 'acute_diarrhoea',
    'condition_name': 'Acute Diarrhoea',
    'base_weight': 6,
    'urgency_default': 'non_urgent',
    'explanation_template':
        'Your symptoms may be consistent with acute diarrhoea...',
    'symptoms': [
      {'token': 'watery_stool', 'weight': 8},
      {'token': 'vomiting', 'weight': 5},
    ],
    'demographic_modifiers': [
      {'modifier': 'severe_malnutrition_sam', 'effect': 'escalate_emergency'},
      {'modifier': 'moderate_malnutrition_mam', 'effect': 'increase_urgency'},
    ],
    'seasonal_modifiers': [],
  },
  {
    'condition_id': 'headache_dizziness',
    'condition_name': 'Headache / Dizziness',
    // base_weight calibrated 3 -> 5 (same precedent as the E3.5 mock KB
    // calibration note) so this condition doesn't tie with malaria's score
    // once headache + dizziness + the increase_urgency modifier are summed —
    // a tie would make the "top" condition non-deterministic.
    'base_weight': 5,
    'urgency_default': 'self_care',
    'explanation_template':
        'Your symptoms may be consistent with tension headache or mild dizziness. Rest and hydration are recommended.',
    'symptoms': [
      {'token': 'headache', 'weight': 4},
      {'token': 'dizziness', 'weight': 4},
      {'token': 'fatigue', 'weight': 3},
    ],
    'demographic_modifiers': [
      {
        'modifier': 'increase_urgency_headache_test',
        'effect': 'increase_urgency',
      },
    ],
    'seasonal_modifiers': [],
  },
  {
    'condition_id': 'tb',
    'condition_name': 'Tuberculosis',
    'base_weight': 7,
    'urgency_default': 'urgent',
    'explanation_template': 'Your symptoms may be consistent with TB.',
    'symptoms': [
      {'token': 'cough', 'weight': 8},
      {'token': 'weakness', 'weight': 5},
      {'token': 'fatigue', 'weight': 4},
    ],
    'demographic_modifiers': [
      {'modifier': 'increase_urgency_test', 'effect': 'increase_urgency'},
    ],
    'seasonal_modifiers': [],
  },
];

final List<Map<String, dynamic>> _mockRules = [];

final Map<String, dynamic> _mockTokenDictionary = {
  'symptom_tokens': [
    'fever',
    'chills',
    'headache',
    'body_pain',
    'watery_stool',
    'vomiting',
    'dizziness',
    'fatigue',
    'cough',
    'weakness',
  ],
  'red_flag_tokens': [],
};

final Map<String, dynamic> _mockConfigMetadata = {
  'artifacts': {
    'knowledge_base': {'version': '1.0'},
    'rules': {'version': '1.0'},
    'token_dictionary': {'version': '1.0'},
  },
};

EngineController _buildController({String? currentSeason}) => EngineController(
  rules: _mockRules,
  tokenDictionary: _mockTokenDictionary,
  knowledgeBase: _mockKnowledgeBase,
  configMetadata: _mockConfigMetadata,
  currentSeason: currentSeason,
);

void _printOutput(String label, EngineOutput output) {
  final map = <String, dynamic>{
    'urgency': output.urgency,
    'redFlagTriggered': output.redFlagTriggered,
    'topCauses': output.topCauses,
    'careInstruction': output.careInstruction,
  };
  print('\n=== $label ===');
  print(const JsonEncoder.withIndent('  ').convert(map));
}

void main() {
  group('Medical Review — Priority 4a increase_urgency escalation', () {
    // TEST 1 — watery_stool + moderate_malnutrition_mam → urgent
    test('TEST 1: watery_stool + moderate_malnutrition_mam → urgent', () {
      final output = _buildController().run(
        const EngineInput(
          symptomTokens: ['watery_stool'],
          candidateConditionIds: ['moderate_malnutrition_mam'],
        ),
      );
      _printOutput('TEST 1 — Diarrhoea + MAM', output);
      expect(output.urgency, equals('urgent'));
    });

    // TEST 2 — fever + chills + children_under_5 (no seasonal) → urgent
    test(
      'TEST 2: fever + chills + children_under_5 (no seasonal) → urgent',
      () {
        final output = _buildController().run(
          const EngineInput(
            symptomTokens: ['fever', 'chills'],
            candidateConditionIds: ['children_under_5'],
          ),
        );
        _printOutput('TEST 2 — Malaria + children_under_5, no season', output);
        expect(output.urgency, equals('urgent'));
      },
    );

    // TEST 3 — fever + chills + children_under_5 + rainy_season → emergency
    test(
      'TEST 3: fever + chills + children_under_5 + rainy_season → emergency',
      () {
        final output = _buildController(currentSeason: 'rainy_season').run(
          const EngineInput(
            symptomTokens: ['fever', 'chills'],
            candidateConditionIds: ['children_under_5'],
          ),
        );
        _printOutput(
          'TEST 3 — Malaria + children_under_5 + rainy_season',
          output,
        );
        expect(output.urgency, equals('emergency'));
      },
    );

    // TEST 4 — headache + dizziness + increase_urgency modifier → non_urgent
    // headache_dizziness urgency_default is self_care, escalated one level
    // -> non_urgent.
    test(
      'TEST 4: headache + dizziness + increase_urgency modifier → non_urgent',
      () {
        final output = _buildController().run(
          const EngineInput(
            symptomTokens: ['headache', 'dizziness'],
            candidateConditionIds: ['increase_urgency_headache_test'],
          ),
        );
        _printOutput('TEST 4 — Headache/Dizziness + increase_urgency', output);
        expect(output.urgency, equals('non_urgent'));
      },
    );

    // TEST 5 — cough + weakness + increase_urgency_test modifier on TB →
    // urgent stays urgent (urgent -> urgent, no change).
    test(
      'TEST 5: cough + weakness + increase_urgency_test (TB) → urgent (no change)',
      () {
        final output = _buildController().run(
          const EngineInput(
            symptomTokens: ['cough', 'weakness'],
            candidateConditionIds: ['increase_urgency_test'],
          ),
        );
        _printOutput('TEST 5 — TB + increase_urgency_test', output);
        expect(output.urgency, equals('urgent'));
      },
    );

    // TEST 6 — regression: watery_stool + severe_malnutrition_sam → emergency
    test(
      'TEST 6: watery_stool + severe_malnutrition_sam → emergency (regression)',
      () {
        final output = _buildController().run(
          const EngineInput(
            symptomTokens: ['watery_stool'],
            candidateConditionIds: ['severe_malnutrition_sam'],
          ),
        );
        _printOutput('TEST 6 — Diarrhoea + SAM (regression)', output);
        expect(output.urgency, equals('emergency'));
      },
    );
  });
}
