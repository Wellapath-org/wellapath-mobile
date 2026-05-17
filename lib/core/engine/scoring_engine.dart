import 'models/engine_input.dart';
import 'models/engine_output.dart';

class ScoringEngine {
  ScoringEngine({required this.knowledgeBase, this.currentSeason});

  final List<Map<String, dynamic>> knowledgeBase;
  final String? currentSeason;

  ScoringResult score(EngineInput input, RedFlagResult redFlagResult) {
    if (!redFlagResult.proceedToScoring) {
      throw StateError('Scoring engine called with proceed_to_scoring false');
    }

    final symptomSet = input.symptomTokens.toSet();
    final candidateSet = input.candidateConditionIds.toSet();
    final scored = <ScoredCondition>[];

    for (final condition in knowledgeBase) {
      final conditionId = condition['condition_id'] as String? ?? '';
      final conditionName = condition['condition_name'] as String? ?? '';
      final baseWeight = (condition['base_weight'] as num?)?.toInt() ?? 0;
      final urgencyDefault =
          condition['urgency_default'] as String? ?? 'routine';

      // Symptom matching
      var matchedSymptomScore = 0;
      final matchedSymptoms = <String>[];

      final symptoms = condition['symptoms'];
      if (symptoms is List) {
        for (final symptom in symptoms) {
          if (symptom is Map) {
            final token = symptom['token'] as String?;
            final weight = (symptom['weight'] as num?)?.toInt() ?? 0;
            if (token != null && symptomSet.contains(token)) {
              matchedSymptomScore += weight;
              matchedSymptoms.add(token);
            }
          }
        }
      }

      // Demographic modifiers
      var modifierPoints = 0;
      String? demographicModifierApplied;
      String? demographicEffect;
      String? urgencyOverride;

      final demographicModifiers = condition['demographic_modifiers'];
      if (demographicModifiers is List) {
        for (final modifier in demographicModifiers) {
          if (modifier is Map) {
            final field = modifier['modifier'] as String?;
            final effect = modifier['effect'] as String?;
            if (field != null &&
                effect != null &&
                candidateSet.contains(field)) {
              if (effect == 'increase_urgency') {
                modifierPoints += 2;
                urgencyOverride = urgencyDefault;
              } else if (effect == 'increase_base_weight') {
                modifierPoints += 2;
              } else if (effect == 'escalate_emergency') {
                modifierPoints += 5;
                urgencyOverride = 'emergency';
              } else if (effect == 'escalate_urgent') {
                modifierPoints += 3;
                urgencyOverride = 'urgent';
              } else if (effect == 'monitor_and_escalate') {
                modifierPoints += 1;
              }
              // routine_caution → +0, no action needed
              demographicModifierApplied = field;
              demographicEffect = effect;
            }
          }
        }
      }

      // Seasonal modifier — match first entry for currentSeason only
      String? seasonalModifierApplied;
      if (currentSeason != null) {
        final seasonalModifiers = condition['seasonal_modifiers'];
        if (seasonalModifiers is List) {
          for (final seasonal in seasonalModifiers) {
            if (seasonal is Map) {
              final season = seasonal['season'] as String?;
              final effect = seasonal['effect'] as String?;
              if (season != null && season == currentSeason) {
                if (effect == 'increase_base_weight') {
                  modifierPoints += 1;
                  seasonalModifierApplied = effect;
                } else if (effect == 'increase_urgency') {
                  modifierPoints += 2;
                  seasonalModifierApplied = effect;
                } else if (effect == 'epidemic_alert') {
                  modifierPoints += 3;
                  seasonalModifierApplied = effect;
                }
                break;
              }
            }
          }
        }
      }

      final totalScore = baseWeight + matchedSymptomScore + modifierPoints;

      scored.add(
        ScoredCondition(
          conditionId: conditionId,
          conditionName: conditionName,
          score: totalScore,
          baseWeight: baseWeight,
          matchedSymptoms: matchedSymptoms,
          matchedSymptomScore: matchedSymptomScore,
          urgencyDefault: urgencyDefault,
          demographicModifierApplied: demographicModifierApplied,
          demographicEffect: demographicEffect,
          seasonalModifierApplied: seasonalModifierApplied,
          urgencyOverride: urgencyOverride,
          explanationTemplate: condition['explanation_template'] as String?,
        ),
      );
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    return ScoringResult(scoredConditions: scored.take(3).toList());
  }
}
