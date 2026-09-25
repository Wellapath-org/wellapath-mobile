/// The Learn deck must stay **product education**.
///
/// This is the guard that keeps a friendly content surface from quietly
/// becoming an unreviewed clinical one. Nothing in the deck may name a
/// condition, a symptom, a medicine or a course of action for a person who
/// feels a particular way — that is clinical content, and it does not ship
/// without clinical review.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/learn/learn_content.dart';

import '../support/content_guard.dart';

void main() {
  test('the deck is non-empty and has stable unique ids', () {
    expect(LearnContent.cards, isNotEmpty);
    final ids = LearnContent.cards.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('no card contains clinical vocabulary', () {
    for (final card in LearnContent.cards) {
      final text = '${card.title} ${card.body}'.toLowerCase();
      expect(
        affirmativeDiagnosisClaim(text),
        isNull,
        reason:
            'Learn card "${card.id}" claims to diagnose. Only a denial '
            '("does not diagnose") may ship without clinical review.',
      );
      expect(
        conditionVocabularyHit(text),
        isNull,
        reason:
            'Learn card "${card.id}" names a condition or symptom. That '
            'vocabulary belongs to the engine, and it requires clinical '
            'review before it ships.',
      );
      expect(
        unnegatedClinicalAction(text),
        isNull,
        reason:
            'Learn card "${card.id}" offers a clinical act. It may only '
            'appear as a denial of something WellaPath does not do.',
      );
    }
  });

  test('the diagnosis guard still catches an affirmative claim', () {
    // The narrowing permits denials only. These must all still be caught.
    for (final String claim in [
      'WellaPath will diagnose your illness',
      'Your diagnosis is ready',
      'We diagnose common conditions',
      // A denial in one sentence must not license a claim in the next.
      'We do not store your answers. We diagnose your illness.',
    ]) {
      expect(
        affirmativeDiagnosisClaim(claim),
        isNotNull,
        reason: '"$claim" must be rejected',
      );
    }
    // And denials are allowed.
    for (final String allowed in [
      'It does not diagnose an illness',
      'Guidance, not a diagnosis',
      'WellaPath cannot diagnose you',
      // A warning to the reader, negated at the start of a long sentence.
      'Do not include your name, phone number, symptoms, diagnosis or '
          'other personal health information.',
      // Attribution to a qualified human, not a claim by the product.
      'A diagnosis should come from a qualified healthcare professional '
          'after an appropriate assessment.',
    ]) {
      expect(affirmativeDiagnosisClaim(allowed), isNull, reason: allowed);
    }
  });

  test('the guard blocks claims across every sentence boundary', () {
    // A denial must not license a claim that follows it, whatever separates
    // the two: a full stop, a question or exclamation mark, a line break, or
    // a line break with no punctuation at all.
    for (final String separator in ['. ', '? ', '! ', '\n', '\r\n']) {
      final String text =
          'WellaPath does not store your answers'
          '${separator}It will diagnose your illness';
      expect(
        affirmativeDiagnosisClaim(text),
        isNotNull,
        reason: 'a claim after "${separator.trim()}" must still be caught',
      );
    }
  });

  test(
    'a negation that has moved on to another claim does not license one',
    () {
      // Reported in review: a sentence-wide negation check passed both of
      // these. The negation must still govern the word when it is reached.
      for (final String claim in [
        'WellaPath is not a substitute for a doctor, and it will diagnose '
            'your illness.',
        'There is no account, and WellaPath can diagnose your condition.',
        'Your answers are never stored, but WellaPath will diagnose you.',
      ]) {
        expect(
          affirmativeDiagnosisClaim(claim),
          isNotNull,
          reason: '"$claim" must be rejected',
        );
      }
    },
  );

  test('naming a clinician does not license a claim by the product', () {
    for (final String claim in [
      'Our app can diagnose what a doctor would',
      'WellaPath gives you the diagnosis a clinician would',
      'We diagnose as accurately as a healthcare professional',
      // Reported in review: naming a clinician anywhere in the sentence used
      // to be enough. Attribution now needs an attributing verb too.
      'Based on your answers, a clinician would diagnose the cause.',
      'Your diagnosis from the doctor is ready to view.',
      'The result is the diagnosis a medical professional would reach.',
      'The diagnosis comes from WellaPath and your doctor.',
    ]) {
      expect(
        affirmativeDiagnosisClaim(claim),
        isNotNull,
        reason: '"$claim" must be rejected',
      );
    }
  });

  test('a clinical act is allowed only as a denial', () {
    expect(
      unnegatedClinicalAction(
        'It cannot examine you, diagnose an illness, prescribe treatment or '
        'replace a consultation with a qualified healthcare professional.',
      ),
      isNull,
    );
    for (final String claim in [
      'WellaPath suggests a treatment for you',
      'Check the dosage before you take it',
      'We can prescribe what you need',
      'It does not examine you, and it will suggest a treatment',
    ]) {
      expect(
        unnegatedClinicalAction(claim),
        isNotNull,
        reason: '"$claim" must be rejected',
      );
    }
  });

  group('the myth deck', () {
    test('has stable unique ids and a balance of both answers', () {
      final ids = LearnContent.myths.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(LearnContent.myths.any((m) => m.isFact), isTrue);
      expect(LearnContent.myths.any((m) => !m.isFact), isTrue);
    });

    test('no explanation claims to diagnose', () {
      // The STATEMENT is the misconception the reader is asked to reject; the
      // EXPLANATION is what the app asserts as true, so that is what the
      // tripwire reads.
      for (final myth in LearnContent.myths) {
        expect(
          affirmativeDiagnosisClaim(myth.explanation),
          isNull,
          reason:
              'myth card "${myth.id}" claims to diagnose. Only a denial or '
              'an attribution to a clinician may ship without review.',
        );
      }
    });

    test('no card contains clinical vocabulary', () {
      for (final myth in LearnContent.myths) {
        final text = '${myth.statement} ${myth.explanation}';
        expect(
          conditionVocabularyHit(text),
          isNull,
          reason: 'myth card "${myth.id}" names a condition or symptom',
        );
        expect(
          unnegatedClinicalAction(text),
          isNull,
          reason: 'myth card "${myth.id}" offers a clinical act',
        );
      }
    });

    test('no card makes an absolute promise about identification', () {
      // Rejected in copy review: an unqualified claim could become
      // inaccurate once feedback or engineering diagnostics exist.
      for (final myth in LearnContent.myths) {
        expect(
          myth.explanation.toLowerCase(),
          isNot(contains('nothing identifies you')),
          reason: 'myth card "${myth.id}" over-promises',
        );
      }
    });
  });

  test('cards stay short enough to read in about a minute', () {
    for (final card in LearnContent.cards) {
      expect(card.title.length, lessThanOrEqualTo(60));
      expect(card.body.length, lessThanOrEqualTo(220));
    }
  });

  group('card of the day', () {
    test('is deterministic for a date', () {
      final a = LearnContent.forDate(DateTime(2026, 9, 25));
      final b = LearnContent.forDate(DateTime(2026, 9, 25, 23, 59));
      expect(a.id, b.id);
    });

    test('changes from one day to the next', () {
      final a = LearnContent.forDate(DateTime(2026, 9, 25));
      final b = LearnContent.forDate(DateTime(2026, 9, 26));
      expect(a.id, isNot(b.id));
    });

    test('covers the whole deck over consecutive days', () {
      final seen = <String>{};
      for (var i = 0; i < LearnContent.cards.length; i++) {
        seen.add(
          LearnContent.forDate(DateTime(2026, 9, 1).add(Duration(days: i))).id,
        );
      }
      expect(seen.length, LearnContent.cards.length);
    });

    test('handles dates before the epoch anchor without throwing', () {
      expect(() => LearnContent.forDate(DateTime(2025, 1, 1)), returnsNormally);
    });
  });
}
