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

/// Diagnosis words are only acceptable as a DENIAL — "does not diagnose",
/// "not a diagnosis". That is the CDSS disclaimer, and it is the opposite
/// of clinical content. An affirmative use ("we diagnose", "your diagnosis
/// is") is exactly what must never ship without clinical review.
///
/// Returns the offending excerpt, or null when every occurrence is negated.
String? affirmativeDiagnosisClaim(String text) {
  final String lower = text.toLowerCase();
  const List<String> negations = [
    'not ',
    'never ',
    'cannot ',
    "can't ",
    'without ',
    'no ',
  ];
  for (final Match m in RegExp('diagnos').allMatches(lower)) {
    final int from = m.start - 40 < 0 ? 0 : m.start - 40;
    final String before = lower.substring(from, m.start);
    if (!negations.any(before.contains)) {
      final int to = m.end + 30 > lower.length ? lower.length : m.end + 30;
      return text.substring(from, to);
    }
  }
  return null;
}

void main() {
  test('the deck is non-empty and has stable unique ids', () {
    expect(LearnContent.cards, isNotEmpty);
    final ids = LearnContent.cards.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('no card contains clinical vocabulary', () {
    // Condition names, symptom words and treatment language. The app's own
    // clinical vocabulary lives in the engine; the Learn tab must not repeat
    // any of it.
    const forbidden = [
      'malaria',
      'typhoid',
      'cholera',
      'meningitis',
      'sepsis',
      'pregnan',
      'fever',
      'headache',
      'cough',
      'vomit',
      'diarrh',
      'rash',
      'bleeding',
      'seizure',
      'chest pain',
      'dosage',
      'medicine',
      'tablet',
      'antibiotic',
      'treatment',
      'you should take',
      'you may have',
      'we think you',
    ];

    for (final card in LearnContent.cards) {
      final text = '${card.title} ${card.body}'.toLowerCase();
      expect(
        affirmativeDiagnosisClaim(text),
        isNull,
        reason:
            'Learn card "${card.id}" claims to diagnose. Only a denial '
            '("does not diagnose") may ship without clinical review.',
      );
      for (final term in forbidden) {
        expect(
          text.contains(term),
          isFalse,
          reason:
              'Learn card "${card.id}" contains clinical term "$term". '
              'Clinical content requires clinical review before it ships.',
        );
      }
    }
  });

  test('the diagnosis guard still catches an affirmative claim', () {
    // The narrowing permits denials only. These must all still be caught.
    for (final String claim in [
      'WellaPath will diagnose your illness',
      'Your diagnosis is ready',
      'We diagnose common conditions',
    ]) {
      expect(
        affirmativeDiagnosisClaim(claim),
        isNotNull,
        reason: '"$claim" must be rejected',
      );
    }
    // And denials are allowed.
    for (final String denial in [
      'It does not diagnose an illness',
      'Guidance, not a diagnosis',
      'WellaPath cannot diagnose you',
    ]) {
      expect(affirmativeDiagnosisClaim(denial), isNull, reason: denial);
    }
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
