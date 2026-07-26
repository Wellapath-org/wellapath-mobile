class RedFlagResult {
  const RedFlagResult({
    required this.redFlagTriggered,
    required this.proceedToScoring,
    this.redFlagType,
    this.matchedRuleId,
    this.matchedRuleName,
    this.overrideUrgency,
    this.conditionSpecificOverrides = const [],
  });

  final bool redFlagTriggered;
  final bool proceedToScoring;
  final String? redFlagType;
  final String? matchedRuleId;
  final String? matchedRuleName;
  final String? overrideUrgency;
  final List<Map<String, dynamic>> conditionSpecificOverrides;
}

class ScoredCondition {
  const ScoredCondition({
    required this.conditionId,
    required this.conditionName,
    required this.score,
    required this.baseWeight,
    required this.matchedSymptoms,
    required this.matchedSymptomScore,
    required this.urgencyDefault,
    this.demographicModifierApplied,
    this.demographicEffect,
    this.seasonalModifierApplied,
    this.urgencyOverride,
    this.explanationTemplate,
  });

  final String conditionId;
  final String conditionName;
  final int score;
  final int baseWeight;
  final List<String> matchedSymptoms;
  final int matchedSymptomScore;
  final String? demographicModifierApplied;
  final String? demographicEffect;
  final String? seasonalModifierApplied;
  final String urgencyDefault;
  final String? urgencyOverride;
  final String? explanationTemplate;
}

class ScoringResult {
  const ScoringResult({required this.scoredConditions});

  final List<ScoredCondition> scoredConditions;
}

class UrgencyResult {
  const UrgencyResult({
    required this.finalUrgency,
    required this.urgencySource,
    required this.redFlagTriggered,
    this.matchedRuleId,
    this.topCondition,
    this.urgencyDefaultWas,
  });

  final String finalUrgency;
  final String urgencySource;
  final bool redFlagTriggered;
  final String? matchedRuleId;
  final String? topCondition;
  final String? urgencyDefaultWas;
}

class EngineOutput {
  const EngineOutput({
    required this.urgency,
    required this.urgencySource,
    required this.redFlagTriggered,
    this.matchedRuleId,
    this.matchedRuleName,
    required this.topCauses,
    required this.explanationPoints,
    required this.careInstruction,
    required this.artifactsUsed,
  });

  final String urgency;

  /// Why [urgency] came out the way it did: one of `global_red_flag`,
  /// `condition_specific_red_flag`, `demographic_escalation` or
  /// `urgency_default`.
  ///
  /// Carried straight through from [UrgencyResult.urgencySource]. Exposed so a
  /// caller can verify the engine reached the right answer for the right
  /// reason — without it, a case that returns the correct urgency via the
  /// wrong priority path is indistinguishable from a correct one. The E8.1
  /// case bank asserts this per case.
  final String urgencySource;

  final bool redFlagTriggered;
  final String? matchedRuleId;
  final String? matchedRuleName;
  final List<Map<String, dynamic>> topCauses;
  final List<String> explanationPoints;
  final String careInstruction;
  final Map<String, String> artifactsUsed;
}
