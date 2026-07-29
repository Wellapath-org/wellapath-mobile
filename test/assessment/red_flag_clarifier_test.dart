import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/constants/red_flag_clarifiers.dart';
import 'package:wellapath_mobile/core/constants/symptom_display_map.dart';
import 'package:wellapath_mobile/features/assessment/models/followup_question.dart';
import 'package:wellapath_mobile/features/assessment/question_engine.dart';

/// E9 — clarifying questions for "needs-clarifying-question" near-misses.
///
/// Engineering lead ruling: escalate-safe near-misses are handled by adding
/// the red flag token to the picker directly (see red_flag_reachability_test).
/// These must NOT auto-escalate — a milder selection raises one question, and
/// only an explicit yes adds the red flag token.

List<FollowupQuestion> _clarifiers(List<String> tokens) =>
    QuestionEngine.generateQuestions(tokens)
        .where((FollowupQuestion q) => q.type == QuestionType.redFlagClarifier)
        .toList();

void main() {
  group('clarifier is raised only when warranted', () {
    test('a near-miss selection raises its clarifier', () {
      final List<FollowupQuestion> qs = _clarifiers(<String>[
        'difficulty_breathing',
      ]);

      expect(qs, hasLength(1));
      expect(qs.single.redFlagToken, 'breathlessness_at_rest');
      expect(qs.single.options, <String>['Yes', 'No']);
    });

    test('an unrelated selection raises none', () {
      expect(_clarifiers(<String>['headache', 'fever']), isEmpty);
    });

    test('selecting the red flag directly raises no clarifier', () {
      // Nothing left to clarify — the user already reported the danger sign.
      expect(
        _clarifiers(<String>['difficulty_breathing', 'breathlessness_at_rest']),
        isEmpty,
      );
    });

    test('two different near-misses raise two clarifiers', () {
      final List<FollowupQuestion> qs = _clarifiers(<String>[
        'difficulty_breathing',
        'bleeding',
      ]);

      expect(qs.map((FollowupQuestion q) => q.redFlagToken).toSet(), <String>{
        'breathlessness_at_rest',
        'abnormal_bleeding',
      });
    });

    test('two triggers for the same red flag raise only one clarifier', () {
      expect(
        _clarifiers(<String>['difficulty_breathing', 'shortness_of_breath']),
        hasLength(1),
      );
    });
  });

  group('clarifiers come first', () {
    test('a clarifier precedes severity and duration questions', () {
      final List<FollowupQuestion> qs = QuestionEngine.generateQuestions(
        <String>['difficulty_breathing'],
      );

      expect(qs.first.type, QuestionType.redFlagClarifier);
    });
  });

  group('every clarifier is coherent', () {
    test('its red flag token is selectable in the picker', () {
      final Set<String> tokens = kSymptomDisplayMap.values.toSet();
      for (final RedFlagClarifier c in kRedFlagClarifiers) {
        expect(
          tokens,
          contains(c.redFlagToken),
          reason: '${c.redFlagToken} must be reachable directly too',
        );
      }
    });

    test('its trigger tokens are selectable in the picker', () {
      // A clarifier hung off a token no user can select would never fire.
      // This is what ruled out the dehydration -> severe_dehydration
      // clarifier: `dehydration` is not in kSymptomDisplayMap.
      final Set<String> tokens = kSymptomDisplayMap.values.toSet();
      for (final RedFlagClarifier c in kRedFlagClarifiers) {
        for (final String trigger in c.triggerTokens) {
          expect(
            tokens,
            contains(trigger),
            reason: '$trigger triggers a clarifier but cannot be selected',
          );
        }
      }
    });

    test('no trigger token is also its own red flag token', () {
      for (final RedFlagClarifier c in kRedFlagClarifiers) {
        expect(c.triggerTokens, isNot(contains(c.redFlagToken)));
      }
    });
  });
}
