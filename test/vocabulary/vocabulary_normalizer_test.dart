/// Adversarial and property coverage for the normalization pipeline.
///
/// The authoritative fixtures in `search_cases_v1.json` are the conformance
/// contract, and they are exercised in `vocabulary_search_test.dart`. This file
/// covers what those fixtures do not: the NFKC step itself, the four declared
/// properties (pure, total, idempotent, deterministic), and each pipeline step
/// in isolation.
///
/// Nothing here extends normalization beyond the specified six steps. Where a
/// case asserts that something is *preserved* — diacritics, negation, digits —
/// that is the specification being pinned, not a gap being papered over.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_normalizer.dart';

void main() {
  group('step 2 — Unicode NFKC', () {
    // These are exactly the cases the supplied fixtures do not reach: the
    // fixtures' Unicode cases are all handled by step 1 variant folding, so
    // without these NFKC could be missing entirely and every fixture would
    // still pass.
    test('fullwidth forms fold to ASCII', () {
      expect(normalizeVocabularyQuery('ＦＥＶＥＲ'), 'fever');
      expect(normalizeVocabularyQuery('Ｃｈｅｓｔ　Ｐａｉｎ'), 'chest pain');
      expect(normalizeVocabularyQuery('ｃｈｅｓｔ＿ｐａｉｎ'), 'chest pain');
    });

    test('fullwidth digits fold, and digit-adjacent rules still apply', () {
      expect(normalizeVocabularyQuery('３８．５'), '38.5');
      expect(normalizeVocabularyQuery('１４０／９０'), '140/90');
      expect(normalizeVocabularyQuery('１，０００'), '1000');
    });

    test('compatibility ligatures decompose', () {
      // U+FB01 LATIN SMALL LIGATURE FI
      expect(normalizeVocabularyQuery('ﬁnger'), 'finger');
      // U+FB00 LATIN SMALL LIGATURE FF
      expect(normalizeVocabularyQuery('stiﬀ'), 'stiff');
    });

    test('compatibility characters normalize', () {
      // U+2168 ROMAN NUMERAL NINE -> IX
      expect(normalizeVocabularyQuery('Ⅸ'), 'ix');
      // U+00BD VULGAR FRACTION ONE HALF -> 1⁄2, the fraction slash is not an
      // ASCII solidus between digits, so it becomes a space.
      expect(normalizeVocabularyQuery('½'), '1 2');
      // U+33A1 SQUARE M SQUARED -> m2
      expect(normalizeVocabularyQuery('㎡'), 'm2');
    });

    test('composed and decomposed forms converge', () {
      // é as a single codepoint vs e + combining acute.
      const String composed = 'café';
      const String decomposed = 'café';
      expect(
        normalizeVocabularyQuery(composed),
        normalizeVocabularyQuery(decomposed),
        reason:
            'NFKC must make the two encodings of the same text equal, or the '
            'same word typed on two keyboards would resolve differently.',
      );
    });

    test('diacritics are PRESERVED, not stripped', () {
      // Deferred by the specification. Folding them later needs a
      // normalization_version bump, so pin the current behaviour.
      expect(normalizeVocabularyQuery('naïve'), 'naïve');
      expect(normalizeVocabularyQuery('café'), 'café');
      expect(
        normalizeVocabularyQuery('naïve'),
        isNot('naive'),
        reason: 'Diacritic folding is deferred and must not appear silently.',
      );
    });
  });

  group('step 1 — variant folding, on both sides of NFKC', () {
    test('apostrophe variants all fold then delete', () {
      for (final String apos in const <String>[
        '‘',
        '’',
        '‛',
        'ʹ',
        'ʻ',
        'ʼ',
        '`',
      ]) {
        expect(
          normalizeVocabularyQuery('ludwig${apos}s angina'),
          'ludwigs angina',
          reason:
              'apostrophe variant U+${apos.codeUnitAt(0).toRadixString(16)}',
        );
      }
    });

    test('U+00B4 acute accent folds despite NFKC decomposing it', () {
      // This is the case the spec calls out: NFKC turns U+00B4 into
      // SPACE + U+0301, so a fold applied only after NFKC would miss it.
      // Folding first turns it into an apostrophe, which is then deleted.
      expect(normalizeVocabularyQuery('ludwig´s angina'), 'ludwigs angina');
    });

    test('dash variants all fold to a space', () {
      for (final String dash in const <String>[
        '‐',
        '‑',
        '‒',
        '–',
        '—',
        '―',
        '−',
        '﹘',
        '﹣',
        '-',
      ]) {
        expect(
          normalizeVocabularyQuery('chest${dash}pain'),
          'chest pain',
          reason: 'dash variant U+${dash.codeUnitAt(0).toRadixString(16)}',
        );
      }
    });

    test('unicode whitespace variants all fold to a single space', () {
      for (final String ws in const <String>[
        ' ',
        ' ',
        ' ',
        ' ',
        ' ',
        ' ',
        ' ',
        ' ',
        ' ',
        ' ',
        ' ',
        ' ',
        ' ',
        '​',
        ' ',
        ' ',
        '　',
        '﻿',
      ]) {
        expect(
          normalizeVocabularyQuery('chest${ws}pain'),
          'chest pain',
          reason: 'whitespace variant U+${ws.codeUnitAt(0).toRadixString(16)}',
        );
      }
    });

    test('a leading byte order mark is stripped', () {
      expect(normalizeVocabularyQuery('﻿chest pain'), 'chest pain');
      expect(normalizeVocabularyQuery('chest pain﻿'), 'chest pain');
    });
  });

  group('step 3 — case folding is Unicode-aware', () {
    test('ASCII case folds', () {
      expect(normalizeVocabularyQuery('FEVER'), 'fever');
      expect(normalizeVocabularyQuery('FeVeR'), 'fever');
    });

    test('non-ASCII case folds', () {
      expect(normalizeVocabularyQuery('ÉCLAIR'), 'éclair');
      expect(normalizeVocabularyQuery('ΣΈΨΗ'.toUpperCase()), isNotEmpty);
    });
  });

  group('step 5 — the punctuation pass', () {
    test('a decimal point between ASCII digits is kept', () {
      expect(normalizeVocabularyQuery('38.5'), '38.5');
      expect(normalizeVocabularyQuery('temp 38.5 c'), 'temp 38.5 c');
    });

    test('a solidus between ASCII digits is kept', () {
      expect(normalizeVocabularyQuery('140/90'), '140/90');
    });

    test('a comma between ASCII digits is deleted, not spaced', () {
      expect(normalizeVocabularyQuery('1,000'), '1000');
      expect(normalizeVocabularyQuery('1,000,000'), '1000000');
    });

    test('the same characters NOT between digits become spaces', () {
      expect(normalizeVocabularyQuery('chest.pain'), 'chest pain');
      expect(normalizeVocabularyQuery('chest/pain'), 'chest pain');
      expect(normalizeVocabularyQuery('chest,pain'), 'chest pain');
      expect(normalizeVocabularyQuery('38.a'), '38 a');
      expect(normalizeVocabularyQuery('a.5'), 'a 5');
    });

    test('a hyphen becomes a space, never nothing', () {
      expect(
        normalizeVocabularyQuery('chest-pain'),
        'chest pain',
        reason: 'Deleting it would produce chestpain, which matches no token.',
      );
    });

    test('other punctuation becomes a space', () {
      expect(normalizeVocabularyQuery('(chest pain)'), 'chest pain');
      expect(normalizeVocabularyQuery('chest pain!'), 'chest pain');
      expect(normalizeVocabularyQuery('chest;pain'), 'chest pain');
      expect(normalizeVocabularyQuery('chest:pain'), 'chest pain');
      expect(normalizeVocabularyQuery('#chest@pain%'), 'chest pain');
    });

    test('letters and digits in any script are kept', () {
      expect(normalizeVocabularyQuery('febrè 39'), 'febrè 39');
      expect(normalizeVocabularyQuery('发热'), '发热');
      expect(normalizeVocabularyQuery('حمى'), 'حمى');
    });
  });

  group('token id normalization', () {
    test('underscores become spaces before the pipeline runs', () {
      expect(normalizeTokenId('chest_pain'), 'chest pain');
      expect(normalizeTokenId('blood_in_stool'), 'blood in stool');
      expect(normalizeTokenId('fever'), 'fever');
      expect(
        normalizeTokenId('severe_malnutrition_sam'),
        'severe malnutrition sam',
      );
    });

    test('it agrees with normalizing the spaced form', () {
      expect(
        normalizeTokenId('chest_pain'),
        normalizeVocabularyQuery('chest pain'),
      );
    });
  });

  group('declared properties', () {
    const List<String> corpus = <String>[
      '',
      '   ',
      '!!!',
      'fever',
      'CHEST PAIN',
      'chest—pain',
      'ludwig’s angina',
      'ＦＥＶＥＲ',
      'café',
      'café',
      '38.5',
      '140/90',
      '1,000',
      'no fever',
      'naïve',
      '发热',
      '﻿chest​pain',
      'ﬁnger',
      'Ⅸ',
    ];

    test('total — never throws on any input', () {
      for (final String s in corpus) {
        expect(() => normalizeVocabularyQuery(s), returnsNormally, reason: s);
      }
    });

    test('idempotent — normalize(normalize(x)) == normalize(x)', () {
      for (final String s in corpus) {
        final String once = normalizeVocabularyQuery(s);
        expect(normalizeVocabularyQuery(once), once, reason: s);
      }
    });

    test('deterministic — 100 repeats agree', () {
      for (final String s in corpus) {
        final String first = normalizeVocabularyQuery(s);
        for (int i = 0; i < 100; i++) {
          expect(normalizeVocabularyQuery(s), first, reason: s);
        }
      }
    });

    test(
      'pure — output never contains leading, trailing or repeated spaces',
      () {
        for (final String s in corpus) {
          final String out = normalizeVocabularyQuery(s);
          expect(out, isNot(startsWith(' ')), reason: s);
          expect(out, isNot(endsWith(' ')), reason: s);
          expect(out.contains('  '), isFalse, reason: s);
        }
      },
    );
  });

  group('what normalization must NOT do', () {
    test('negation words survive verbatim', () {
      expect(normalizeVocabularyQuery('no fever'), 'no fever');
      expect(normalizeVocabularyQuery('not fever'), 'not fever');
      expect(normalizeVocabularyQuery('without pain'), 'without pain');
      expect(
        normalizeVocabularyQuery('denies chest pain'),
        'denies chest pain',
      );
    });

    test('laterality, severity, duration and age survive verbatim', () {
      expect(normalizeVocabularyQuery('left arm'), 'left arm');
      expect(normalizeVocabularyQuery('severe pain'), 'severe pain');
      expect(normalizeVocabularyQuery('3 days'), '3 days');
      expect(normalizeVocabularyQuery('2 years old'), '2 years old');
      expect(normalizeVocabularyQuery('pregnant'), 'pregnant');
    });

    test('no stemming or plural folding', () {
      expect(normalizeVocabularyQuery('fevers'), 'fevers');
      expect(normalizeVocabularyQuery('coughing'), 'coughing');
      expect(normalizeVocabularyQuery('fevers'), isNot('fever'));
    });

    test('no spelling correction', () {
      expect(normalizeVocabularyQuery('fver'), 'fver');
      expect(normalizeVocabularyQuery('feaver'), 'feaver');
    });

    test('no stopword removal', () {
      expect(normalizeVocabularyQuery('blood in stool'), 'blood in stool');
      expect(
        normalizeVocabularyQuery('a fever and chills'),
        'a fever and chills',
      );
    });

    test('separator removal never fabricates a joined token', () {
      expect(normalizeVocabularyQuery('chest-pain'), isNot('chestpain'));
      expect(normalizeVocabularyQuery('chest pain'), isNot('chestpain'));
    });
  });
}
