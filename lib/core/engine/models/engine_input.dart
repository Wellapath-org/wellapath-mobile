class EngineInput {
  const EngineInput({
    required this.symptomTokens,
    required this.candidateConditionIds,
    this.demographicTokens = const [],
  });

  final List<String> symptomTokens;
  final List<String> candidateConditionIds;

  /// Age / sex / comorbidity / pregnancy tokens used by the scoring engine's
  /// demographic-modifier matching. Distinct from [candidateConditionIds],
  /// which holds condition IDs — the two were previously conflated.
  final List<String> demographicTokens;

  List<String> validate(Set<String> validTokens) {
    return symptomTokens
        .where((token) => !validTokens.contains(token))
        .toList();
  }
}
