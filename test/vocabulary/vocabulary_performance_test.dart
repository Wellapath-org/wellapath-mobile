// ignore_for_file: avoid_print
// print() is intentional here: this file's console output IS the performance
// evidence recorded in docs/VOCABULARY_V2_CONSUMER.md. debugPrint truncates.

/// Performance, memory and offline-determinism measurements for the
/// Vocabulary 2.0 consumer.
///
/// Thresholds here are **ceilings set well above measured values on this
/// machine**, not targets. They exist to catch an order-of-magnitude
/// regression, and are deliberately loose because a single developer laptop is
/// not evidence about a low-end Nigerian handset. The measured numbers are
/// printed and recorded; the documented low-end profile is NOT covered here
/// and is reported as a gap.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_search.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_v2.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_v2_loader.dart';

const String _candidatePath =
    'test/fixtures/vocabulary/candidate/token_dictionary.ng.v2.0.json';

/// Queries spanning the resolution paths: exact id, normalized, and no-match.
const List<String> _queryMix = <String>[
  'fever',
  'chest_pain',
  'Chest Pain',
  '  chest   pain  ',
  'no fever',
  'zzzznotatoken',
  'blood_in_stool',
  'blood in stool',
];

double _medianMicros(List<int> samples) {
  final List<int> sorted = List<int>.from(samples)..sort();
  final int mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid].toDouble()
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

void main() {
  test('vocabulary 2.0 performance and memory baseline', () {
    final List<int> bytes = File(_candidatePath).readAsBytesSync();

    // ── parse / load ──────────────────────────────────────────────────────
    final Stopwatch loadWatch = Stopwatch()..start();
    final VocabularyLoadResult result = loadVocabularyV2FromBytes(bytes);
    loadWatch.stop();
    expect(result.isSuccess, isTrue, reason: '${result.failure}');
    final VocabularyV2 vocab = result.vocabulary!;

    // Repeat to get a stable median rather than reporting one cold sample.
    final List<int> loadSamples = <int>[];
    for (int i = 0; i < 10; i++) {
      final Stopwatch w = Stopwatch()..start();
      loadVocabularyV2FromBytes(bytes);
      w.stop();
      loadSamples.add(w.elapsedMicroseconds);
    }

    // ── index build ───────────────────────────────────────────────────────
    final List<int> indexSamples = <int>[];
    late VocabularySearchIndex index;
    for (int i = 0; i < 10; i++) {
      final Stopwatch w = Stopwatch()..start();
      index = VocabularySearchIndex(vocab);
      w.stop();
      indexSamples.add(w.elapsedMicroseconds);
    }

    // ── cold first query ──────────────────────────────────────────────────
    final VocabularySearchIndex coldIndex = VocabularySearchIndex(vocab);
    final Stopwatch coldWatch = Stopwatch()..start();
    coldIndex.resolve('chest_pain');
    coldWatch.stop();

    // ── warm queries ──────────────────────────────────────────────────────
    for (int i = 0; i < 200; i++) {
      index.resolve(_queryMix[i % _queryMix.length]);
    }
    final List<int> warmSamples = <int>[];
    for (int i = 0; i < 2000; i++) {
      final Stopwatch w = Stopwatch()..start();
      index.resolve(_queryMix[i % _queryMix.length]);
      w.stop();
      warmSamples.add(w.elapsedMicroseconds);
    }

    // ── memory ────────────────────────────────────────────────────────────
    // RSS is a coarse process-level figure, not a precise heap measurement of
    // the vocabulary alone. Reported as an order of magnitude, not a budget.
    final int rssBefore = ProcessInfo.currentRss;
    final List<VocabularySearchIndex> held = <VocabularySearchIndex>[
      for (int i = 0; i < 5; i++)
        VocabularySearchIndex(loadVocabularyV2FromBytes(bytes).vocabulary!),
    ];
    final int rssAfter = ProcessInfo.currentRss;
    expect(held, hasLength(5)); // keep them alive across the measurement

    final double loadMedian = _medianMicros(loadSamples);
    final double indexMedian = _medianMicros(indexSamples);
    final double warmMedian = _medianMicros(warmSamples);
    final List<int> warmSorted = List<int>.from(warmSamples)..sort();
    final int warmP95 = warmSorted[(warmSorted.length * 0.95).floor()];

    print('');
    print('=== VOCABULARY 2.0 PERFORMANCE BASELINE ===');
    print('  artifact bytes        : ${bytes.length}');
    print('  tokens                : ${vocab.tokens.length}');
    print('  indexed normalized forms: ${index.indexedFormCount}');
    print('  parse + validate (first): ${loadWatch.elapsedMicroseconds} us');
    print(
      '  parse + validate (median of 10): ${loadMedian.toStringAsFixed(0)} us',
    );
    print('  index build (median of 10): ${indexMedian.toStringAsFixed(0)} us');
    print('  cold first query      : ${coldWatch.elapsedMicroseconds} us');
    print('  warm query (median of 2000): ${warmMedian.toStringAsFixed(1)} us');
    print('  warm query p95        : $warmP95 us');
    print(
      '  RSS delta holding 5 vocabularies+indexes: '
      '${((rssAfter - rssBefore) / 1024 / 1024).toStringAsFixed(1)} MB',
    );
    print('  (RSS is process-level and coarse; not a per-vocabulary budget.)');
    print('');
    print('  NOT MEASURED: the documented low-end Android emulator profile.');
    print('  These numbers are from a developer machine and are not evidence');
    print('  about low-end handset behaviour.');
    print('');

    // Order-of-magnitude ceilings, far above measured values.
    expect(
      loadMedian,
      lessThan(2000000),
      reason: 'Parsing + validating 340KB should not take over 2s.',
    );
    expect(
      indexMedian,
      lessThan(500000),
      reason: 'Index build should not take over 0.5s.',
    );
    expect(
      warmMedian,
      lessThan(1000),
      reason: 'A warm whole-string lookup should be well under 1ms.',
    );
  });

  test('repeated queries are byte-identical, so results are cacheable', () {
    final VocabularySearchIndex index = VocabularySearchIndex(
      loadVocabularyV2FromBytes(
        File(_candidatePath).readAsBytesSync(),
      ).vocabulary!,
    );

    for (final String q in _queryMix) {
      final String first = jsonEncode(index.resolve(q).toJson());
      for (int i = 0; i < 100; i++) {
        expect(jsonEncode(index.resolve(q).toJson()), first, reason: q);
      }
    }
  });

  test('two separately built indexes agree on every token', () {
    final List<int> bytes = File(_candidatePath).readAsBytesSync();
    final VocabularySearchIndex a = VocabularySearchIndex(
      loadVocabularyV2FromBytes(bytes).vocabulary!,
    );
    final VocabularySearchIndex b = VocabularySearchIndex(
      loadVocabularyV2FromBytes(bytes).vocabulary!,
    );

    for (final VocabularyToken t in a.vocabulary.tokens) {
      expect(
        jsonEncode(b.resolve(t.tokenId).toJson()),
        jsonEncode(a.resolve(t.tokenId).toJson()),
      );
    }
  });
}
