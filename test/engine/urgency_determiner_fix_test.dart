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
  String? seasonalModifierApplied,
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
    seasonalModifierApplied: seasonalModifierApplied,
  );
}

ScoringResult _result(ScoredCondition top) {
  return ScoringResult(scoredConditions: [top]);
}

void main() {
  group('UrgencyDeterminer — E8 Priority 4a fix', () {
    // TEST 1 — watery_stool + moderate_malnutrition_mam → urgent
    // acute_diarrhoea urgency_default: non_urgent. increase_urgency alone
    // (no seasonal modifier) escalates one level up to urgent — this is the
    // clinical safety fix: a moderately malnourished child with diarrhoea
    // must not be told non_urgent.
    test(
      'acute_diarrhoea (non_urgent) + increase_urgency (moderate_malnutrition_mam) → urgent',
      () {
        final scoring = _result(
          _condition(
            id: 'acute_diarrhoea',
            urgencyDefault: 'non_urgent',
            demographicEffect: 'increase_urgency',
          ),
        );

        final result = _determiner.determine(_noRedFlag, scoring);

        expect(result.finalUrgency, equals('urgent'));
        expect(result.urgencySource, equals('demographic_escalation'));
      },
    );

    // TEST 2 — regression: watery_stool + severe_malnutrition_sam → emergency
    // escalate_emergency (Priority 3) must still fire correctly and is
    // unaffected by the Priority 4a addition.
    test(
      'acute_diarrhoea (non_urgent) + escalate_emergency (severe_malnutrition_sam) → emergency',
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
      },
    );

    // TEST 3 — self_care condition + increase_urgency modifier → non_urgent
    // _escalateOne('self_care') == 'non_urgent'.
    test(
      'self_care condition + increase_urgency modifier → escalates to non_urgent',
      () {
        final scoring = _result(
          _condition(
            id: 'mild_condition',
            urgencyDefault: 'self_care',
            demographicEffect: 'increase_urgency',
          ),
        );

        final result = _determiner.determine(_noRedFlag, scoring);

        expect(result.finalUrgency, equals('non_urgent'));
        expect(result.urgencySource, equals('demographic_escalation'));
      },
    );

    // TEST 4 — urgent condition + increase_urgency (no seasonal) → urgent
    // malaria urgency_default: urgent. _escalateOne('urgent') == 'urgent'
    // (default case — urgent and emergency stay as-is, no change).
    test(
      'malaria (urgent) + increase_urgency (children_under_5) → stays urgent',
      () {
        final scoring = _result(
          _condition(
            id: 'malaria',
            urgencyDefault: 'urgent',
            demographicEffect: 'increase_urgency',
          ),
        );

        final result = _determiner.determine(_noRedFlag, scoring);

        expect(result.finalUrgency, equals('urgent'));
        expect(result.urgencySource, equals('demographic_escalation'));
      },
    );

    // TEST 5 — fever + children_under_5 + rainy_season → urgent
    // Founder policy decision (Case 04, Option B): Priority 4c (increase_urgency
    // + seasonal modifier) still fires and takes precedence over Priority 4a's
    // one-level escalation, but now resolves to urgent, not emergency.
    test(
      'malaria (urgent) + increase_urgency + seasonal modifier → urgent (Priority 4c)',
      () {
        final scoring = _result(
          _condition(
            id: 'malaria',
            urgencyDefault: 'urgent',
            demographicEffect: 'increase_urgency',
            seasonalModifierApplied: 'rainy_season',
          ),
        );

        final result = _determiner.determine(_noRedFlag, scoring);

        expect(result.finalUrgency, equals('urgent'));
        expect(result.urgencySource, equals('demographic_escalation'));
      },
    );
  });
}
