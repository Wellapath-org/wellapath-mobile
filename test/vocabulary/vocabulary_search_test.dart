/// Conformance against the authoritative search and ambiguity fixtures, plus
/// the adversarial cases the specification calls out by name.
///
/// The fixtures are the contract. Every case records the query, the expected
/// normalized form, the expected status, the resolved token and the candidate
/// list — so a divergence in *any* of those fails, not just a wrong answer.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_normalizer.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_search.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_v2.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_v2_loader.dart';

const String _root = 'test/fixtures/vocabulary';
const String _candidatePath = '$_root/candidate/token_dictionary.ng.v2.0.json';
const String _syntheticPath = '$_root/search/synthetic_vocabulary_v1.json';
const String _searchCasesPath = '$_root/search/search_cases_v1.json';
const String _ambiguityCasesPath = '$_root/search/ambiguity_cases_v1.json';

VocabularySearchIndex _indexFor(String path) {
  final VocabularyLoadResult result = loadVocabularyV2FromBytes(
    File(path).readAsBytesSync(),
  );
  expect(
    result.isSuccess,
    isTrue,
    reason: 'Fixture $path failed to load: ${result.failure}',
  );
  return VocabularySearchIndex(result.vocabulary!);
}

List<Map<String, dynamic>> _cases(String path) =>
    ((jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>)['cases']
            as List<dynamic>)
        .cast<Map<String, dynamic>>();

/// Runs one fixture case and returns a per-case record for the evidence table.
Map<String, Object?> _runCase(
  VocabularySearchIndex index,
  Map<String, dynamic> testCase,
) {
  final String query = testCase['query'] as String;
  final Map<String, dynamic> expected =
      testCase['expected'] as Map<String, dynamic>;
  final VocabularyResolution r = index.resolve(query);

  final bool normalizedOk = r.queryNormalized == expected['query_normalized'];
  final bool statusOk =
      vocabularyMatchStatusName(r.status) == expected['status'];
  final bool resolvedOk =
      r.resolvedTokenId?.value == expected['resolved_token_id'];
  final List<String> expectedCandidates =
      (expected['candidate_token_ids'] as List<dynamic>).cast<String>();
  final List<String> actualCandidates = r.candidateTokenIds
      .map((CanonicalTokenId c) => c.value)
      .toList();
  final bool candidatesOk = _listEq(actualCandidates, expectedCandidates);
  final bool eligibleOk = r.scoringEligible == expected['scoring_eligible'];

  return <String, Object?>{
    'query': query,
    'tests': testCase['tests'],
    'normalized': r.queryNormalized,
    'status': vocabularyMatchStatusName(r.status),
    'resolved_token_id': r.resolvedTokenId?.value,
    'candidate_token_ids': actualCandidates,
    'match_source': r.matchSource,
    'scoring_eligible': r.scoringEligible,
    'pass':
        normalizedOk && statusOk && resolvedOk && candidatesOk && eligibleOk,
    'expected': expected,
  };
}

bool _listEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _expectCase(Map<String, Object?> record) {
  final Map<String, dynamic> expected =
      record['expected']! as Map<String, dynamic>;
  final String label = '${record['query']} — ${record['tests']}';

  expect(
    record['normalized'],
    expected['query_normalized'],
    reason: 'normalized form: $label',
  );
  expect(record['status'], expected['status'], reason: 'status: $label');
  expect(
    record['resolved_token_id'],
    expected['resolved_token_id'],
    reason: 'resolved token: $label',
  );
  expect(
    record['candidate_token_ids'],
    expected['candidate_token_ids'],
    reason: 'candidates (order matters): $label',
  );
  expect(
    record['scoring_eligible'],
    expected['scoring_eligible'],
    reason: 'scoring eligibility: $label',
  );
}

void main() {
  group('authoritative search fixtures — real candidate', () {
    late VocabularySearchIndex index;
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      index = _indexFor(_candidatePath);
      cases = _cases(_searchCasesPath);
    });

    test('the fixture set is bound to this candidate', () {
      final Map<String, dynamic> fixture =
          jsonDecode(File(_searchCasesPath).readAsStringSync())
              as Map<String, dynamic>;
      final Map<String, dynamic> vocab =
          fixture['vocabulary'] as Map<String, dynamic>;
      expect(
        vocab['sha256'],
        '07f935967acb1d5515cb53ffd1c8e39b59b8daf85c67cf36fa3e25094e34cd2d',
      );
      expect(fixture['normalization_version'], kNormalizationVersion);
      expect(cases, hasLength(34));
    });

    test('every one of the 34 cases matches the contract exactly', () {
      final List<Map<String, Object?>> records = <Map<String, Object?>>[
        for (final Map<String, dynamic> c in cases) _runCase(index, c),
      ];

      final List<Map<String, Object?>> failures = records
          .where((Map<String, Object?> r) => r['pass'] != true)
          .toList();

      // Assert each case individually so the first failure names itself.
      for (final Map<String, Object?> r in records) {
        _expectCase(r);
      }
      expect(failures, isEmpty);
    });

    test('search hit rate over the authoritative fixture set', () {
      int resolved = 0;
      for (final Map<String, dynamic> c in cases) {
        if (index.resolve(c['query'] as String).resolvedTokenId != null) {
          resolved++;
        }
      }
      // 20 of the 34 cases are designed to resolve; the other 14 are negative
      // cases that must NOT resolve. A higher number here would mean the
      // resolver started matching things the contract forbids.
      expect(
        resolved,
        20,
        reason:
            'Hit rate changed. On this fixture set a *higher* count is a '
            'failure, not an improvement: the remaining cases are negation, '
            'prefix, typo and plural queries that must never resolve.',
      );
    });
  });

  group('authoritative ambiguity fixtures — synthetic vocabulary', () {
    late VocabularySearchIndex index;
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      index = _indexFor(_syntheticPath);
      cases = _cases(_ambiguityCasesPath);
    });

    test('the fixture is explicitly synthetic and non-clinical', () {
      final Map<String, dynamic> fixture =
          jsonDecode(File(_ambiguityCasesPath).readAsStringSync())
              as Map<String, dynamic>;
      expect(fixture['synthetic'], isTrue);
      expect(cases, hasLength(11));
    });

    test('every ambiguity case matches the contract exactly', () {
      for (final Map<String, dynamic> c in cases) {
        _expectCase(_runCase(index, c));
      }
    });

    test('an ambiguous query never resolves to a token', () {
      for (final Map<String, dynamic> c in cases) {
        final Map<String, dynamic> expected =
            c['expected'] as Map<String, dynamic>;
        if (expected['status'] != 'ambiguous') continue;

        final VocabularyResolution r = index.resolve(c['query'] as String);
        expect(r.resolvedTokenId, isNull);
        expect(r.scoringEligible, isFalse);
        expect(
          r.candidateTokenIds.length,
          greaterThan(1),
          reason: 'An ambiguous result must still report what it reached.',
        );
      }
    });

    test('an exact token id outranks a colliding label', () {
      // `quibble widget` is ambiguous, but typing the id resolves to itself.
      expect(index.resolve('quibble widget').isAmbiguous, isTrue);
      final VocabularyResolution exact = index.resolve('quibble_widget');
      expect(exact.status, VocabularyMatchStatus.exactCanonical);
      expect(exact.resolvedTokenId?.value, 'quibble_widget');
    });

    test('an exact token id outranks a shared alias', () {
      expect(index.resolve('shared quux').isAmbiguous, isTrue);
      expect(
        index.resolve('zorble_alpha').resolvedTokenId?.value,
        'zorble_alpha',
      );
    });

    test('alias matches report alias as the source, never the alias text', () {
      final VocabularyResolution r = index.resolve('beta only');
      expect(r.status, VocabularyMatchStatus.exactAlias);
      expect(r.matchSource, 'alias');
      // The returned identity is the canonical id — the alias string is not
      // anywhere in the resolved value.
      expect(r.resolvedTokenId?.value, 'zorble_beta');
    });
  });

  group('adversarial — the resolver must not be clever', () {
    late VocabularySearchIndex index;

    setUpAll(() => index = _indexFor(_candidatePath));

    void expectNoMatch(String query, String why) {
      final VocabularyResolution r = index.resolve(query);
      expect(
        r.status,
        VocabularyMatchStatus.noMatch,
        reason: '$query must not match — $why',
      );
      expect(r.resolvedTokenId, isNull);
      expect(r.scoringEligible, isFalse);
    }

    test('negation is never stripped', () {
      expectNoMatch('no fever', 'negation must survive');
      expectNoMatch('not fever', 'negation must survive');
      expectNoMatch('without fever', 'negation must survive');
      expectNoMatch('denies fever', 'negation must survive');
      expectNoMatch('no chest pain', 'negation must survive');
      expectNoMatch('fever: no', 'negation must survive');
    });

    test('no prefix, substring or suffix matching', () {
      expectNoMatch('feve', 'prefix');
      expectNoMatch('ever', 'substring');
      expectNoMatch('feverish', 'suffix');
      expectNoMatch('i have a fever today', 'phrase containing a token');
      // NB: 'chest' is itself a body-area token id in the candidate, so it
      // legitimately resolves. Prefix behaviour is proven with a string that
      // is a prefix of a token and not a token: 'chest p'.
      expectNoMatch('chest p', 'prefix of chest_pain');
    });

    test('no stemming, plural folding or spelling correction', () {
      expectNoMatch('fevers', 'plural');
      expectNoMatch('fver', 'typo');
      expectNoMatch('feaver', 'typo');
      expectNoMatch('coughing', 'inflection');
    });

    test('no separator collapsing that fabricates a token', () {
      expectNoMatch('chestpain', 'hyphens become spaces, not nothing');
    });

    test('multi-token phrases never partially match', () {
      expectNoMatch('fever and chills', 'two tokens in one query');
      expectNoMatch('fever, headache', 'two tokens in one query');
    });

    test('empty and punctuation-only queries resolve to nothing', () {
      expectNoMatch('', 'empty');
      expectNoMatch('   ', 'whitespace only');
      expectNoMatch('!!!', 'punctuation only');
      expectNoMatch('...', 'punctuation only');
    });

    test('resolution is deterministic across repeated calls', () {
      for (final String q in const <String>[
        'fever',
        'Chest Pain',
        'no fever',
        'zzzznotatoken',
      ]) {
        final String first = jsonEncode(index.resolve(q).toJson());
        for (int i = 0; i < 25; i++) {
          expect(jsonEncode(index.resolve(q).toJson()), first);
        }
      }
    });
  });

  group('current v1.1 picker search vs the v2 resolver', () {
    // The live picker filters `kSymptomDisplayMap` with a case-insensitive
    // substring test. This documents the difference rather than asserting one
    // is better: they answer different questions, and only the v2 side is
    // bound to the authoritative contract.
    late VocabularySearchIndex index;

    setUpAll(() => index = _indexFor(_candidatePath));

    test(
      'substring queries differ: the current picker matches, v2 does not',
      () {
        // 'ever' is a substring of the label 'Fever', so the current picker
        // would offer Fever. The v2 resolver returns no_match by contract.
        const String query = 'ever';
        expect('Fever'.toLowerCase().contains(query), isTrue);
        expect(index.resolve(query).status, VocabularyMatchStatus.noMatch);
      },
    );

    test('both refuse a negated query, for different reasons', () {
      // The current picker refuses it incidentally — 'Fever' does not contain
      // 'no fever'. The v2 resolver refuses it by explicit contract.
      const String query = 'no fever';
      expect('Fever'.toLowerCase().contains(query), isFalse);
      expect(index.resolve(query).status, VocabularyMatchStatus.noMatch);
    });

    test('v2 reaches token ids the current display map does not expose', () {
      // The display map exposes 129 labels; the candidate carries 295 ids.
      // This is reach, not approval: the labels are still unreviewed.
      expect(index.vocabulary.tokenIds.length, 295);
      expect(
        index.resolve('haemoglobinuria').resolvedTokenId?.value,
        'haemoglobinuria',
      );
    });
  });
}
