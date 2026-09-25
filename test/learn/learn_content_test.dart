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

  test('a negation elsewhere in the sentence does not license a claim', () {
    // Every one of these passed an earlier version of the guard. They are the
    // reason it is now an allowlist of approved shapes rather than a negation
    // detector: the ways one clause can end and another begin are
    // open-ended, so each separator only added another leak to patch.
    for (final String claim in [
      // ...a conjunction
      'WellaPath is not a substitute for a doctor, and it will diagnose '
          'your illness.',
      'There is no account, and WellaPath can diagnose your condition.',
      'Your answers are never stored, but WellaPath will diagnose you.',
      'You do not need an account, so WellaPath can diagnose your condition.',
      'WellaPath does not store your answers, yet it will diagnose your '
          'illness.',
      'WellaPath does not store answers because it diagnoses locally.',
      'It cannot examine you while it diagnoses your illness.',
      // ...punctuation that is not a sentence end
      'WellaPath does not store your answers; it diagnoses your illness.',
      'WellaPath does not store your answers — it diagnoses your illness.',
      // ...a negation with no negating relationship to the word at all
      'No account is needed to get your diagnosis of the problem.',
    ]) {
      expect(
        affirmativeDiagnosisClaim(claim),
        isNotNull,
        reason: '"$claim" must be rejected',
      );
    }
  });

  test('an approved attribution fails if the product claims the role', () {
    expect(
      affirmativeDiagnosisClaim(
        'A diagnosis should come from WellaPath and your doctor.',
      ),
      isNotNull,
    );
  });

  test('the natural attribution phrasing is not a false positive', () {
    // Raised in review: this is correct CDSS copy, and it was being sent to
    // clinical review for nothing.
    expect(
      affirmativeDiagnosisClaim(
        'Only a qualified doctor can give you a diagnosis.',
      ),
      isNull,
    );
  });

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
      // The same leak the diagnosis guard had, reported against this check.
      'WellaPath does not store data, so it can suggest a treatment.',
      'It does not examine you; it will suggest a treatment.',
    ]) {
      expect(
        unnegatedClinicalAction(claim),
        isNotNull,
        reason: '"$claim" must be rejected',
      );
    }
  });

  test('a condition word matches on word boundaries, not substrings', () {
    // Raised in review: "crash" contains "rash", so "if the app crashes" was
    // reported as naming a symptom — in the one Help article most likely to
    // use the word, with a failure message that would mislead whoever hit it.
    for (final String innocent in [
      'If the app crashes, reinstall it.',
      'Close WellaPath fully and open it again.',
    ]) {
      expect(conditionVocabularyHit(innocent), isNull, reason: innocent);
    }
    // The deliberate prefixes still reach the words they were written for.
    expect(conditionVocabularyHit('A rash appeared'), 'rash');
    expect(conditionVocabularyHit('vomiting started'), 'vomit');
    expect(conditionVocabularyHit('signs of pregnancy'), 'pregnan');
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
