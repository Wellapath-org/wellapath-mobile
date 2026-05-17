import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/models/engine_input.dart';
import 'package:wellapath_mobile/core/engine/red_flag_evaluator.dart';

// Tokens sourced from rules.ng.v1.0.json and token_dictionary.ng.v1.0.json.
// Passed directly to avoid Hive dependency in unit tests.
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

final Map<String, dynamic> _mockTokenDictionary = {
  'symptom_tokens': ['fever', 'headache', 'chills', 'weakness', 'watery_stool'],
  'red_flag_tokens': ['seizures', 'inability_to_drink', 'circulatory_collapse'],
};

void main() {
  late RedFlagEvaluator evaluator;

  setUp(() {
    evaluator = RedFlagEvaluator(
      rules: _mockRules,
      tokenDictionary: _mockTokenDictionary,
    );
  });

  group('RedFlagEvaluator', () {
    // TEST 1
    test('fever + seizures triggers red flag with emergency urgency', () {
      final result = evaluator.evaluate(
        const EngineInput(
          symptomTokens: ['fever', 'seizures'],
          candidateConditionIds: [],
        ),
      );

      expect(result.redFlagTriggered, isTrue);
      expect(result.proceedToScoring, isFalse);
      expect(result.overrideUrgency, equals('emergency'));
    });

    // TEST 2
    test('watery_stool + inability_to_drink triggers red flag', () {
      final result = evaluator.evaluate(
        const EngineInput(
          symptomTokens: ['watery_stool', 'inability_to_drink'],
          candidateConditionIds: [],
        ),
      );

      expect(result.redFlagTriggered, isTrue);
      expect(result.proceedToScoring, isFalse);
    });

    // TEST 3
    test('fever + circulatory_collapse + weakness triggers red flag', () {
      final result = evaluator.evaluate(
        const EngineInput(
          symptomTokens: ['fever', 'circulatory_collapse', 'weakness'],
          candidateConditionIds: [],
        ),
      );

      expect(result.redFlagTriggered, isTrue);
      expect(result.proceedToScoring, isFalse);
    });

    // TEST 4
    test(
      'fever + headache + chills returns no red flag, proceeds to scoring',
      () {
        final result = evaluator.evaluate(
          const EngineInput(
            symptomTokens: ['fever', 'headache', 'chills'],
            candidateConditionIds: [],
          ),
        );

        expect(result.redFlagTriggered, isFalse);
        expect(result.proceedToScoring, isTrue);
      },
    );

    // TEST 5
    test('unknown token throws ArgumentError before evaluation', () {
      expect(
        () => evaluator.evaluate(
          const EngineInput(
            symptomTokens: ['fever', 'UNKNOWN_TOKEN_XYZ'],
            candidateConditionIds: [],
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    // TEST 6
    test('empty symptom input returns no red flag, proceeds to scoring', () {
      final result = evaluator.evaluate(
        const EngineInput(symptomTokens: [], candidateConditionIds: []),
      );

      expect(result.redFlagTriggered, isFalse);
      expect(result.proceedToScoring, isTrue);
    });

    // TEST 7
    test(
      'seizures + inability_to_drink matches rf_001 — priority 1 fires before priority 2',
      () {
        final result = evaluator.evaluate(
          const EngineInput(
            symptomTokens: ['seizures', 'inability_to_drink'],
            candidateConditionIds: [],
          ),
        );

        expect(result.redFlagTriggered, isTrue);
        expect(result.matchedRuleId, equals('rf_001'));
      },
    );
  });
}
