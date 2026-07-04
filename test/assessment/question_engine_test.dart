import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/assessment/models/followup_question.dart';
import 'package:wellapath_mobile/features/assessment/question_engine.dart';

void main() {
  test('fever returns duration and additionalSymptoms only (no severity)', () {
    final questions = QuestionEngine.generateQuestions(['fever']);

    final types = questions.map((q) => q.type).toList();

    expect(types, [QuestionType.duration, QuestionType.additionalSymptoms]);
    expect(types, isNot(contains(QuestionType.severity)));
  });

  test(
    'headache returns severity, duration and additionalSymptoms in that order',
    () {
      final questions = QuestionEngine.generateQuestions(['headache']);

      final types = questions.map((q) => q.type).toList();

      expect(types, [
        QuestionType.severity,
        QuestionType.duration,
        QuestionType.additionalSymptoms,
      ]);
    },
  );

  test('fever and headache produce only one duration question', () {
    final questions = QuestionEngine.generateQuestions(['fever', 'headache']);

    final durationCount = questions
        .where((q) => q.type == QuestionType.duration)
        .length;

    expect(durationCount, 1);
  });

  test('result is capped at 5 questions even for many symptom tokens', () {
    final questions = QuestionEngine.generateQuestions([
      'headache',
      'fever',
      'cough',
      'watery_stool',
      'chills',
      'body_pain',
      'weakness',
      'nausea',
      'sweating',
      'vomiting',
      'abdominal_cramps',
      'dizziness',
      'fatigue',
      'fast_breathing_child',
      'chest_indrawing_severe',
      'dark_urine',
      'pain',
      'swelling',
    ]);

    expect(questions.length, lessThanOrEqualTo(5));
  });
}
