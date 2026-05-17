import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/models/engine_input.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';
import 'package:wellapath_mobile/core/engine/scoring_engine.dart';

// Pilot conditions from the NG knowledge base — passed directly to avoid Hive.
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

// Valid pass-through result used for all tests except test 6.
const _proceedResult = RedFlagResult(
  redFlagTriggered: false,
  proceedToScoring: true,
);

void main() {
  late ScoringEngine engine;

  setUp(() {
    engine = ScoringEngine(knowledgeBase: _mockKnowledgeBase);
  });

  group('ScoringEngine', () {
    // TEST 1
    test(
      'fever + chills + headache + body_pain — malaria ranks #1 with score 37',
      () {
        final result = engine.score(
          const EngineInput(
            symptomTokens: ['fever', 'chills', 'headache', 'body_pain'],
            candidateConditionIds: [],
          ),
          _proceedResult,
        );

        expect(result.scoredConditions.first.conditionId, equals('malaria'));
        // baseWeight(10) + fever(9) + chills(7) + headache(6) + body_pain(5)
        expect(result.scoredConditions.first.score, equals(37));
      },
    );

    // TEST 2
    test(
      'fever + chills + children_under_5 demographic — malaria score +2, urgencyOverride set',
      () {
        final result = engine.score(
          const EngineInput(
            symptomTokens: ['fever', 'chills'],
            candidateConditionIds: ['children_under_5'],
          ),
          _proceedResult,
        );

        final malaria = result.scoredConditions.firstWhere(
          (c) => c.conditionId == 'malaria',
        );
        // baseWeight(10) + fever(9) + chills(7) + increase_urgency(+2) = 28
        expect(malaria.score, equals(28));
        expect(malaria.urgencyOverride, isNotNull);
        expect(malaria.urgencyOverride, equals('urgent'));
      },
    );

    // TEST 3
    test(
      'fever + chills + rainy_season — malaria score +1 from seasonal modifier',
      () {
        final seasonalEngine = ScoringEngine(
          knowledgeBase: _mockKnowledgeBase,
          currentSeason: 'rainy_season',
        );

        final result = seasonalEngine.score(
          const EngineInput(
            symptomTokens: ['fever', 'chills'],
            candidateConditionIds: [],
          ),
          _proceedResult,
        );

        final malaria = result.scoredConditions.firstWhere(
          (c) => c.conditionId == 'malaria',
        );
        // baseWeight(10) + fever(9) + chills(7) + increase_base_weight(+1) = 27
        expect(malaria.score, equals(27));
      },
    );

    // TEST 4
    test(
      'watery_stool + severe_malnutrition_sam_mam — acute_diarrhoea score +5, urgencyOverride emergency',
      () {
        final result = engine.score(
          const EngineInput(
            symptomTokens: ['watery_stool'],
            candidateConditionIds: ['severe_malnutrition_sam_mam'],
          ),
          _proceedResult,
        );

        final diarrhoea = result.scoredConditions.firstWhere(
          (c) => c.conditionId == 'acute_diarrhoea',
        );
        // baseWeight(6) + watery_stool(8) + escalate_emergency(+5) = 19
        expect(diarrhoea.score, equals(19));
        expect(diarrhoea.urgencyOverride, equals('emergency'));
      },
    );

    // TEST 5
    test(
      'empty symptom input — engine does not crash, ranked by base_weight only',
      () {
        final result = engine.score(
          const EngineInput(symptomTokens: [], candidateConditionIds: []),
          _proceedResult,
        );

        expect(result.scoredConditions.length, equals(3));
        expect(result.scoredConditions[0].conditionId, equals('malaria'));
        expect(result.scoredConditions[0].score, equals(10));
        expect(
          result.scoredConditions[1].conditionId,
          equals('pneumonia_children'),
        );
        expect(result.scoredConditions[1].score, equals(8));
        expect(
          result.scoredConditions[2].conditionId,
          equals('acute_diarrhoea'),
        );
        expect(result.scoredConditions[2].score, equals(6));
      },
    );

    // TEST 6
    test('proceedToScoring false — throws StateError', () {
      const blockedResult = RedFlagResult(
        redFlagTriggered: true,
        proceedToScoring: false,
      );

      expect(
        () => engine.score(
          const EngineInput(
            symptomTokens: ['fever'],
            candidateConditionIds: [],
          ),
          blockedResult,
        ),
        throwsA(isA<StateError>()),
      );
    });

    // TEST 7
    test(
      'fever + chills + headache + body_pain — exactly 3 results, first score is highest',
      () {
        final result = engine.score(
          const EngineInput(
            symptomTokens: ['fever', 'chills', 'headache', 'body_pain'],
            candidateConditionIds: [],
          ),
          _proceedResult,
        );

        expect(result.scoredConditions.length, equals(3));
        expect(
          result.scoredConditions.first.score,
          greaterThanOrEqualTo(result.scoredConditions[1].score),
        );
        expect(
          result.scoredConditions[1].score,
          greaterThanOrEqualTo(result.scoredConditions[2].score),
        );
      },
    );
  });
}
