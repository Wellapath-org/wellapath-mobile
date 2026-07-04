class EngineInput {
  const EngineInput({
    required this.symptomTokens,
    required this.candidateConditionIds,
  });

  final List<String> symptomTokens;
  final List<String> candidateConditionIds;

  List<String> validate(Set<String> validTokens) {
    return symptomTokens
        .where((token) => !validTokens.contains(token))
        .toList();
  }
}
