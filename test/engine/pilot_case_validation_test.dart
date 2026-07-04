// ignore_for_file: avoid_print
// print() is intentional here — this is a validation file, not production code.
// Each case prints its full engine output for documentation purposes.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/engine_controller.dart';
import 'package:wellapath_mobile/core/engine/models/engine_input.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';

// Knowledge base from E3.2/E3.4 tests, extended with headache_dizziness for Case 11.
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
      {
        'modifier': 'severe_malnutrition_sam_mam',
        'effect': 'escalate_emergency',
      },
    ],
    'seasonal_modifiers': [],
  },
  {
    'condition_id': 'pneumonia_children',
    'condition_name': 'Pneumonia (Children)',
    'base_weight': 8,
    'urgency_default': 'urgent',
    'explanation_template': 'Your symptoms may be consistent with pneumonia...',
    'symptoms': [
      {'token': 'cough', 'weight': 7},
      {'token': 'fever', 'weight': 6},
      {'token': 'chest_indrawing', 'weight': 9},
    ],
    'demographic_modifiers': [
      {'modifier': 'children_under_5', 'effect': 'increase_urgency'},
    ],
    'seasonal_modifiers': [],
  },
  {
    'condition_id': 'headache_dizziness',
    'condition_name': 'Headache / Dizziness',
    'base_weight': 3,
    'urgency_default': 'self_care',
    'explanation_template':
        'Your symptoms may be consistent with tension headache or mild dizziness. Rest and hydration are recommended.',
    'symptoms': [
      {'token': 'headache', 'weight': 4},
      {'token': 'dizziness', 'weight': 4},
      {'token': 'fatigue', 'weight': 3},
    ],
    'demographic_modifiers': [],
    'seasonal_modifiers': [],
  },
];

// Rules from E3.1/E3.4 tests, extended with condition-specific and additional global rules.
final List<Map<String, dynamic>> _mockRules = [
  {
    'rule_id': 'rf_001',
    'rule_name': 'Inability to Drink or Feed',
    'token': 'inability_to_drink',
    'override_urgency': 'emergency',
    'applies_to': ['all'],
    'priority': 1,
  },
  {
    'rule_id': 'rf_002',
    'rule_name': 'Active Seizures',
    'token': 'seizures',
    'override_urgency': 'emergency',
    'applies_to': ['all'],
    'priority': 2,
  },
  {
    'rule_id': 'rf_006',
    'rule_name': 'Circulatory Collapse',
    'token': 'circulatory_collapse',
    'override_urgency': 'emergency',
    'applies_to': ['all'],
    'priority': 6,
  },
  {
    'rule_id': 'rf_100',
    'rule_name': 'Haemoglobinuria',
    'token': 'haemoglobinuria',
    'override_urgency': 'emergency',
    'applies_to': ['malaria'],
    'priority': 10,
  },
  {
    'rule_id': 'rf_105',
    'rule_name': 'Severe Chest Indrawing',
    'token': 'chest_indrawing_severe',
    'override_urgency': 'emergency',
    'applies_to': ['pneumonia_children'],
    'priority': 10,
  },
  {
    'rule_id': 'rf_108',
    'rule_name': 'Sunken Eyes',
    'token': 'sunken_eyes',
    'override_urgency': 'emergency',
    'applies_to': ['all'],
    'priority': 8,
  },
  {
    'rule_id': 'rf_109',
    'rule_name': 'Severe Dehydration',
    'token': 'severe_dehydration',
    'override_urgency': 'emergency',
    'applies_to': ['all'],
    'priority': 7,
  },
];

// Token dictionary from E3.1/E3.4 tests, extended with all pilot case tokens.
final Map<String, dynamic> _mockTokenDictionary = {
  'symptom_tokens': [
    'fever',
    'headache',
    'chills',
    'weakness',
    'watery_stool',
    'body_pain',
    'vomiting',
    'cough',
    'chest_indrawing',
    'sweating',
    'dark_urine',
    'fast_breathing_child',
    'nausea',
    'abdominal_cramps',
    'dizziness',
    'fatigue',
  ],
  'red_flag_tokens': [
    'seizures',
    'inability_to_drink',
    'circulatory_collapse',
    'haemoglobinuria',
    'chest_indrawing_severe',
    'severe_dehydration',
    'sunken_eyes',
  ],
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
    'matchedRuleId': output.matchedRuleId,
    'matchedRuleName': output.matchedRuleName,
    'topCauses': output.topCauses,
    'explanationPoints': output.explanationPoints,
    'careInstruction': output.careInstruction,
    'artifactsUsed': output.artifactsUsed,
  };
  print('\n=== $label ===');
  print(const JsonEncoder.withIndent('  ').convert(map));
}

void main() {
  group('E3.5 — Pilot Case Validation', () {
    // CASE 01 — Global red flag: seizures
    test('case_01 — seizures (global red flag) → emergency', () {
      final output = _buildController().run(
        const EngineInput(
          symptomTokens: ['fever', 'chills', 'seizures', 'weakness'],
          candidateConditionIds: [],
        ),
      );
      _printOutput('Case 01 — Seizures (global red flag)', output);
      expect(output.urgency, equals('emergency'));
    });

    // CASE 02 — Condition-specific red flag: haemoglobinuria
    // NOTE: rf_100 has applies_to: ["malaria"] — RedFlagEvaluator only fires on
    // applies_to: ["all"] rules. This case exposes a gap: condition-specific red
    // flags are not evaluated in the current engine pipeline.
    test(
      'case_02 — haemoglobinuria (condition-specific red flag) → emergency',
      () {
        final output = _buildController().run(
          const EngineInput(
            symptomTokens: [
              'fever',
              'chills',
              'dark_urine',
              'haemoglobinuria',
              'weakness',
            ],
            candidateConditionIds: ['malaria'],
          ),
        );
        _printOutput('Case 02 — Haemoglobinuria (malaria red flag)', output);
        expect(output.urgency, equals('emergency'));
      },
    );

    // CASE 03 — Malaria classic presentation, no red flags
    test('case_03 — malaria classic presentation → urgent', () {
      final output = _buildController().run(
        const EngineInput(
          symptomTokens: [
            'fever',
            'chills',
            'headache',
            'body_pain',
            'sweating',
          ],
          candidateConditionIds: [],
        ),
      );
      _printOutput('Case 03 — Malaria classic (no red flags)', output);
      expect(output.urgency, equals('urgent'));
    });

    // CASE 04 — Malaria + children_under_5 + rainy season
    // NOTE: children_under_5 produces effect: increase_urgency (+2 score,
    // urgencyOverride = urgencyDefault). UrgencyDeterminer Priority 3/4 only
    // fires on escalate_emergency / escalate_urgent. increase_urgency falls
    // through to urgency_default ('urgent'). This case exposes a gap: the engine
    // does not further escalate increase_urgency to emergency even with rainy season.
    test('case_04 — malaria + children_under_5 + rainy_season → emergency', () {
      final output = _buildController(currentSeason: 'rainy_season').run(
        const EngineInput(
          symptomTokens: ['fever', 'chills', 'headache', 'weakness'],
          candidateConditionIds: ['children_under_5'],
        ),
      );
      _printOutput(
        'Case 04 — Malaria + children_under_5 + rainy_season',
        output,
      );
      expect(output.urgency, equals('emergency'));
    });

    // CASE 05 — Severe chest indrawing (pneumonia condition-specific red flag)
    // NOTE: rf_105 has applies_to: ["pneumonia_children"] — not a global rule.
    // Same gap as Case 02: condition-specific red flags not evaluated by engine.
    test(
      'case_05 — chest_indrawing_severe (pneumonia red flag) → emergency',
      () {
        final output = _buildController().run(
          const EngineInput(
            symptomTokens: [
              'fast_breathing_child',
              'chest_indrawing_severe',
              'fever',
              'cough',
            ],
            candidateConditionIds: ['children_under_5', 'pneumonia_children'],
          ),
        );
        _printOutput(
          'Case 05 — Chest indrawing severe (pneumonia red flag)',
          output,
        );
        expect(output.urgency, equals('emergency'));
      },
    );

    // CASE 06 — Pneumonia children, standard presentation
    test('case_06 — pneumonia children standard presentation → urgent', () {
      final output = _buildController().run(
        const EngineInput(
          symptomTokens: ['fast_breathing_child', 'fever', 'cough'],
          candidateConditionIds: ['children_under_5'],
        ),
      );
      _printOutput('Case 06 — Pneumonia children standard', output);
      expect(output.urgency, equals('urgent'));
    });

    // CASE 07 — Global red flag: inability_to_drink
    test('case_07 — inability_to_drink (global red flag) → emergency', () {
      final output = _buildController().run(
        const EngineInput(
          symptomTokens: [
            'fast_breathing_child',
            'fever',
            'inability_to_drink',
          ],
          candidateConditionIds: ['children_under_5'],
        ),
      );
      _printOutput('Case 07 — Inability to drink (global red flag)', output);
      expect(output.urgency, equals('emergency'));
    });

    // CASE 08 — Acute diarrhoea, no red flags, no demographics
    test('case_08 — acute diarrhoea no red flags → non_urgent', () {
      final output = _buildController().run(
        const EngineInput(
          symptomTokens: ['watery_stool', 'nausea', 'abdominal_cramps'],
          candidateConditionIds: [],
        ),
      );
      _printOutput('Case 08 — Acute diarrhoea standard', output);
      expect(output.urgency, equals('non_urgent'));
    });

    // CASE 09 — Global red flags: severe_dehydration + sunken_eyes
    // rf_109 (priority 7) fires before rf_108 (priority 8).
    test(
      'case_09 — severe_dehydration + sunken_eyes (global red flags) → emergency',
      () {
        final output = _buildController().run(
          const EngineInput(
            symptomTokens: [
              'watery_stool',
              'severe_dehydration',
              'sunken_eyes',
              'vomiting',
            ],
            candidateConditionIds: [],
          ),
        );
        _printOutput(
          'Case 09 — Severe dehydration + sunken eyes (global red flags)',
          output,
        );
        expect(output.urgency, equals('emergency'));
      },
    );

    // CASE 10 — Acute diarrhoea + severe_malnutrition_sam_mam demographic escalation
    test('case_10 — diarrhoea + severe_malnutrition_sam_mam → emergency', () {
      final output = _buildController().run(
        const EngineInput(
          symptomTokens: ['watery_stool', 'vomiting'],
          candidateConditionIds: ['severe_malnutrition_sam_mam'],
        ),
      );
      _printOutput(
        'Case 10 — Diarrhoea + SAM/MAM (demographic escalation)',
        output,
      );
      expect(output.urgency, equals('emergency'));
    });

    // CASE 11 — Headache + dizziness + fatigue
    // NOTE: malaria (base 10 + headache 6 = 16) outscores headache_dizziness
    // (base 3 + headache 4 + dizziness 4 + fatigue 3 = 14). The mock KB's malaria
    // base_weight and headache symptom weight cause malaria to rank #1, producing
    // 'urgent' instead of 'self_care'. This exposes a gap in the mock KB weights
    // for non-overlapping presentation differentiation.
    test('case_11 — headache + dizziness + fatigue → self_care', () {
      final output = _buildController().run(
        const EngineInput(
          symptomTokens: ['headache', 'dizziness', 'fatigue'],
          candidateConditionIds: [],
        ),
      );
      _printOutput('Case 11 — Headache / Dizziness self-care', output);
      expect(output.urgency, equals('self_care'));
    });

    // CASE 12 — Empty input must not crash
    test(
      'case_12 — empty input: must not crash, any valid urgency returned',
      () {
        final output = _buildController().run(
          const EngineInput(symptomTokens: [], candidateConditionIds: []),
        );
        _printOutput('Case 12 — Empty input (must not crash)', output);
        expect(
          [
            'emergency',
            'urgent',
            'non_urgent',
            'self_care',
          ].contains(output.urgency),
          isTrue,
        );
      },
    );
  });
}
