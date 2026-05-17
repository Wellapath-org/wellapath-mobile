import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';
import 'package:wellapath_mobile/core/engine/urgency_determiner.dart';

const _determiner = UrgencyDeterminer();

const _noRedFlag = RedFlagResult(
  redFlagTriggered: false,
  proceedToScoring: true,
);

// Builds a minimal ScoredCondition for urgency tests.
ScoredCondition _condition({
  required String id,
  required String urgencyDefault,
  String? demographicEffect,
}) {
  return ScoredCondition(
    conditionId: id,
    conditionName: id,
    score: 10,
    baseWeight: 10,
    matchedSymptoms: const [],
    matchedSymptomScore: 0,
    urgencyDefault: urgencyDefault,
    demographicEffect: demographicEffect,
  );
}

ScoringResult _result(ScoredCondition top) {
  return ScoringResult(scoredConditions: [top]);
}

void main() {
  group('UrgencyDeterminer', () {
    // TEST 1 — CRITICAL SAFETY: global red flag beats self_care
    test(
      'global red flag (seizures) — emergency wins even when urgency_default is self_care',
      () {
        final redFlag = RedFlagResult(
          redFlagTriggered: true,
          proceedToScoring: false,
          redFlagType: 'global',
          matchedRuleId: 'rf_002',
          matchedRuleName: 'Active Seizures',
          overrideUrgency: 'emergency',
        );
        final scoring = _result(
          _condition(id: 'viral_fever', urgencyDefault: 'self_care'),
        );

        final result = _determiner.determine(redFlag, scoring);

        expect(result.finalUrgency, equals('emergency'));
        expect(result.urgencySource, equals('global_red_flag'));
        expect(result.redFlagTriggered, isTrue);
      },
    );

    // TEST 2 — CRITICAL SAFETY: global red flag beats urgent condition
    test(
      'global red flag (inability_to_drink) — emergency wins even when urgency_default is urgent',
      () {
        final redFlag = RedFlagResult(
          redFlagTriggered: true,
          proceedToScoring: false,
          redFlagType: 'global',
          matchedRuleId: 'rf_001',
          matchedRuleName: 'Inability to Drink or Feed',
          overrideUrgency: 'emergency',
        );
        final scoring = _result(
          _condition(id: 'malaria', urgencyDefault: 'urgent'),
        );

        final result = _determiner.determine(redFlag, scoring);

        expect(result.finalUrgency, equals('emergency'));
        expect(result.urgencySource, equals('global_red_flag'));
        expect(result.redFlagTriggered, isTrue);
      },
    );

    // TEST 3: condition-specific red flag
    test(
      'condition-specific red flag (chest_indrawing_severe) on pneumonia_children — emergency',
      () {
        final redFlag = RedFlagResult(
          redFlagTriggered: false,
          proceedToScoring: true,
          conditionSpecificOverrides: [
            {
              'condition_id': 'pneumonia_children',
              'override_urgency': 'emergency',
              'rule_id': 'rf_chest_001',
            },
          ],
        );
        final scoring = _result(
          _condition(id: 'pneumonia_children', urgencyDefault: 'urgent'),
        );

        final result = _determiner.determine(redFlag, scoring);

        expect(result.finalUrgency, equals('emergency'));
        expect(result.urgencySource, equals('condition_specific_red_flag'));
        expect(result.redFlagTriggered, isFalse);
      },
    );

    // TEST 4: escalate_emergency demographic (SAM on acute_diarrhoea)
    test(
      'escalate_emergency demographic on acute_diarrhoea — emergency, demographic_escalation',
      () {
        final scoring = _result(
          _condition(
            id: 'acute_diarrhoea',
            urgencyDefault: 'non_urgent',
            demographicEffect: 'escalate_emergency',
          ),
        );

        final result = _determiner.determine(_noRedFlag, scoring);

        expect(result.finalUrgency, equals('emergency'));
        expect(result.urgencySource, equals('demographic_escalation'));
        expect(result.redFlagTriggered, isFalse);
      },
    );

    // TEST 5: escalate_urgent demographic
    test(
      'escalate_urgent demographic modifier — urgent, demographic_escalation',
      () {
        final scoring = _result(
          _condition(
            id: 'malaria',
            urgencyDefault: 'urgent',
            demographicEffect: 'escalate_urgent',
          ),
        );

        final result = _determiner.determine(_noRedFlag, scoring);

        expect(result.finalUrgency, equals('urgent'));
        expect(result.urgencySource, equals('demographic_escalation'));
      },
    );

    // TEST 6: no red flags, urgency_default urgent
    test(
      'no red flags or modifiers — malaria urgency_default urgent returned',
      () {
        final scoring = _result(
          _condition(id: 'malaria', urgencyDefault: 'urgent'),
        );

        final result = _determiner.determine(_noRedFlag, scoring);

        expect(result.finalUrgency, equals('urgent'));
        expect(result.urgencySource, equals('urgency_default'));
        expect(result.redFlagTriggered, isFalse);
      },
    );

    // TEST 7: self_care urgency_default
    test('no red flags or modifiers — self_care urgency_default returned', () {
      final scoring = _result(
        _condition(id: 'viral_fever', urgencyDefault: 'self_care'),
      );

      final result = _determiner.determine(_noRedFlag, scoring);

      expect(result.finalUrgency, equals('self_care'));
      expect(result.urgencySource, equals('urgency_default'));
    });

    // TEST 8: non_urgent — completes all 4 urgency enum values across the suite
    test(
      'no red flags or modifiers — non_urgent urgency_default returned (completes all 4 urgency values)',
      () {
        final scoring = _result(
          _condition(id: 'mild_infection', urgencyDefault: 'non_urgent'),
        );

        final result = _determiner.determine(_noRedFlag, scoring);

        expect(result.finalUrgency, equals('non_urgent'));
        expect(result.urgencySource, equals('urgency_default'));
      },
    );
  });
}
