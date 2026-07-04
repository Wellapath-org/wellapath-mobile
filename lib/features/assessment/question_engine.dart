import '../../core/constants/followup_question_map.dart';
import 'models/followup_question.dart';

class QuestionEngine {
  const QuestionEngine._();

  static List<FollowupQuestion> generateQuestions(List<String> symptomTokens) {
    FollowupQuestion? severityQuestion;
    FollowupQuestion? durationQuestion;
    String? additionalQuestionText;
    final List<String> additionalOptions = [];
    bool needsDefaultDuration = false;

    for (final token in symptomTokens) {
      final questions = kFollowupQuestionMap[token];
      if (questions == null) {
        needsDefaultDuration = true;
        continue;
      }
      for (final question in questions) {
        switch (question.type) {
          case QuestionType.severity:
            severityQuestion ??= question;
          case QuestionType.duration:
            durationQuestion ??= question;
          case QuestionType.additionalSymptoms:
            additionalQuestionText ??= question.questionText;
            for (final option in question.options) {
              if (!additionalOptions.contains(option)) {
                additionalOptions.add(option);
              }
            }
        }
      }
    }

    if (needsDefaultDuration) {
      durationQuestion ??= kDefaultFollowupQuestion;
    }

    final List<FollowupQuestion> result = [
      ?severityQuestion,
      ?durationQuestion,
      if (additionalOptions.isNotEmpty)
        FollowupQuestion(
          type: QuestionType.additionalSymptoms,
          questionText: additionalQuestionText!,
          options: additionalOptions,
        ),
    ];

    return result.length > 5 ? result.sublist(0, 5) : result;
  }
}
