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
    required this.redFlagTriggered,
    this.matchedRuleId,
    this.matchedRuleName,
    required this.topCauses,
    required this.explanationPoints,
    required this.careInstruction,
    required this.artifactsUsed,
  });

  final String urgency;
  final bool redFlagTriggered;
  final String? matchedRuleId;
  final String? matchedRuleName;
  final List<Map<String, dynamic>> topCauses;
  final List<String> explanationPoints;
  final String careInstruction;
  final Map<String, String> artifactsUsed;
}
