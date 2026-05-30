class AssessmentInput {
  final List<String> symptomTokens;
  final List<String> demographicTokens;
  final List<String> severityTokens;
  final List<String> durationTokens;
  final String? season;

  const AssessmentInput({
    required this.symptomTokens,
    required this.demographicTokens,
    required this.severityTokens,
    required this.durationTokens,
    this.season,
  });
}
