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
