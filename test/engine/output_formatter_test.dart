import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/engine_controller.dart';
import 'package:wellapath_mobile/core/engine/models/engine_input.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';
import 'package:wellapath_mobile/core/engine/output_formatter.dart';

// Knowledge base from E3.2 tests (pilot NG conditions).
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
      {'token': 'headache', 'weight': 6},
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
];

// Rules from E3.1 tests.
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
];

// Token dictionary from E3.1 tests, extended with all KB symptom tokens.
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
  ],
  'red_flag_tokens': ['seizures', 'inability_to_drink', 'circulatory_collapse'],
};

// configMetadata as specified for E3.4 tests.
final Map<String, dynamic> _mockConfigMetadata = {
  'artifacts': {
    'knowledge_base': {'version': '1.0'},
    'rules': {'version': '1.0'},
    'token_dictionary': {'version': '1.0'},
  },
};

EngineController _buildController() => EngineController(
  rules: _mockRules,
  tokenDictionary: _mockTokenDictionary,
  knowledgeBase: _mockKnowledgeBase,
  configMetadata: _mockConfigMetadata,
);

void main() {
  group('OutputFormatter + EngineController', () {
    // TEST 1: Red flag scenario (seizures)
    test(
      'seizures input — urgency emergency, redFlagTriggered true, matchedRuleId not null',
      () {
        final output = _buildController().run(
          const EngineInput(
            symptomTokens: ['seizures'],
            candidateConditionIds: [],
          ),
        );

        expect(output.urgency, equals('emergency'));
        expect(output.redFlagTriggered, isTrue);
        expect(output.matchedRuleId, isNotNull);
        expect(output.topCauses, isNotNull);
      },
    );

    // TEST 2: Non-red-flag (fever + headache + chills)
    test(
      'fever + headache + chills — redFlagTriggered false, matchedRuleId null, urgency matches malaria urgency_default',
      () {
        final output = _buildController().run(
          const EngineInput(
            symptomTokens: ['fever', 'headache', 'chills'],
            candidateConditionIds: [],
          ),
        );

        expect(output.redFlagTriggered, isFalse);
        expect(output.matchedRuleId, isNull);
        expect(output.urgency, equals('urgent')); // malaria urgency_default
      },
    );

    // TEST 3: Explanation field integrity
    test(
      'malaria symptoms — explanationPoints[0] exactly matches explanation_template from KB',
      () {
        const malariaTemplate =
            'Your symptoms may be consistent with malaria...';

        final output = _buildController().run(
          const EngineInput(
            symptomTokens: ['fever', 'chills', 'headache'],
            candidateConditionIds: [],
          ),
        );

        expect(output.explanationPoints, isNotEmpty);
        expect(output.explanationPoints[0], equals(malariaTemplate));
      },
    );

    // TEST 4: careInstruction fixed strings — all 4 urgency values
    test(
      'careInstruction — all 4 urgency values produce exact locked strings',
      () {
        final formatter = OutputFormatter(_mockConfigMetadata);

        const noRedFlag = RedFlagResult(
          redFlagTriggered: false,
          proceedToScoring: true,
        );
        const emptyScoring = ScoringResult(scoredConditions: []);

        final expectations = {
          'emergency': 'Go to emergency now — do not wait.',
          'urgent': 'Visit a clinic or health facility today.',
          'non_urgent': 'Visit a clinic within 1-2 days.',
          'self_care':
              'Rest, stay hydrated, use OTC care if needed. Seek help if symptoms worsen.',
        };

        for (final entry in expectations.entries) {
          final urgencyResult = UrgencyResult(
            finalUrgency: entry.key,
            urgencySource: 'urgency_default',
            redFlagTriggered: false,
          );

          final output = formatter.format(
            noRedFlag,
            emptyScoring,
            urgencyResult,
          );
          expect(
            output.careInstruction,
            equals(entry.value),
            reason: 'Wrong string for urgency: ${entry.key}',
          );
        }
      },
    );

    // TEST 5: topCauses constraints
    test(
      'valid symptoms — topCauses is not empty, max 3 items, ranked by score descending',
      () {
        final output = _buildController().run(
          const EngineInput(
            symptomTokens: ['fever', 'chills', 'headache'],
            candidateConditionIds: [],
          ),
        );

        expect(output.topCauses, isNotEmpty);
        expect(output.topCauses.length, lessThanOrEqualTo(3));

        for (int i = 0; i < output.topCauses.length - 1; i++) {
          final currentScore = output.topCauses[i]['score'] as int;
          final nextScore = output.topCauses[i + 1]['score'] as int;
          expect(
            currentScore,
            greaterThanOrEqualTo(nextScore),
            reason: 'topCauses not sorted descending at index $i',
          );
        }
      },
    );

    // TEST 6: artifactsUsed always present
    test(
      'any valid input — artifactsUsed contains kb_version, rules_version, token_dict_version, none null or empty',
      () {
        final output = _buildController().run(
          const EngineInput(
            symptomTokens: ['fever'],
            candidateConditionIds: [],
          ),
        );

        expect(output.artifactsUsed.containsKey('kb_version'), isTrue);
        expect(output.artifactsUsed.containsKey('rules_version'), isTrue);
        expect(output.artifactsUsed.containsKey('token_dict_version'), isTrue);
        expect(output.artifactsUsed['kb_version'], isNotEmpty);
        expect(output.artifactsUsed['rules_version'], isNotEmpty);
        expect(output.artifactsUsed['token_dict_version'], isNotEmpty);
      },
    );

    // TEST 7: Full pipeline — malaria symptom set, no red flags
    test(
      'full pipeline — fever + chills + headache + body_pain: all required fields present, malaria in topCauses',
      () {
        final output = _buildController().run(
          const EngineInput(
            symptomTokens: ['fever', 'chills', 'headache', 'body_pain'],
            candidateConditionIds: [],
          ),
        );

        expect(output.urgency, isNotEmpty);
        expect(output.topCauses, isNotEmpty);
        expect(output.explanationPoints, isNotEmpty);
        expect(output.careInstruction, isNotEmpty);
        expect(output.artifactsUsed, isNotEmpty);

        final hasMalaria = output.topCauses.any(
          (c) => c['condition_id'] == 'malaria',
        );
        expect(hasMalaria, isTrue);
      },
    );

    // TEST 8: Full pipeline — seizures (scoring never called, topCauses empty)
    test(
      'full pipeline — seizures: urgency emergency, redFlagTriggered true, topCauses empty (scoring skipped)',
      () {
        final output = _buildController().run(
          const EngineInput(
            symptomTokens: ['seizures'],
            candidateConditionIds: [],
          ),
        );

        expect(output.urgency, equals('emergency'));
        expect(output.redFlagTriggered, isTrue);
        // Scoring engine is never called on the red flag path — topCauses is empty.
        expect(output.topCauses, isEmpty);
      },
    );
  });
}
