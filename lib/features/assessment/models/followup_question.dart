enum QuestionType { severity, duration, additionalSymptoms }

class FollowupQuestion {
  final QuestionType type;
  final String questionText;
  final List<String> options;

  const FollowupQuestion({
    required this.type,
    required this.questionText,
    this.options = const [],
  });
}
