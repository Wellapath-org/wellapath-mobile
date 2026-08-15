// ignore_for_file: avoid_print
// print() is intentional: this file's console output IS the internal
// evaluation surface. It is a test harness rather than a screen, which is the
// only form that cannot be reached in a normal or production build.

/// Internal, non-clinical evaluation surface for Vocabulary 2.0.
///
/// Demonstrates the whole consumer end to end and prints the per-case evidence
/// table the brief asks for. It is a **test harness, not a screen**: there is
/// no route, no widget and no entry point, so there is nothing to reach in a
/// normal or production build even by accident.
///
/// **No candidate label is printed as UI content.** Every token in the current
/// candidate is `display_safe: false`, so this surface shows token ids and
/// status only. Where a human-readable label is wanted, the existing approved
/// Mobile display map is used and its provenance is stated.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/constants/symptom_display_map.dart';
import 'package:wellapath_mobile/core/vocabulary/canonical_token_boundary.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_config.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_search.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_v2.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_v2_loader.dart';
import 'package:wellapath_mobile/features/assessment/assessment_controller.dart';

const String _root = 'test/fixtures/vocabulary';
const String _candidatePath = '$_root/candidate/token_dictionary.ng.v2.0.json';
const String _syntheticPath = '$_root/search/synthetic_vocabulary_v1.json';

/// The approved display label for a token, from the existing Mobile map.
/// Returns null when the map does not cover the token — deliberately, rather
/// than falling back to the candidate's unreviewed label.
String? _approvedLabel(String tokenId) {
  for (final MapEntry<String, String> e in kSymptomDisplayMap.entries) {
    if (e.value == tokenId) return e.key;
  }
  return null;
}

void _row(VocabularySearchIndex index, String query) {
  final VocabularyResolution r = index.resolve(query);
  final String resolved = r.resolvedTokenId?.value ?? '—';
  final String candidates = r.candidateTokenIds.isEmpty
      ? '—'
      : r.candidateTokenIds.map((CanonicalTokenId c) => c.value).join(', ');
  final String label = r.resolvedTokenId == null
      ? '—'
      : (_approvedLabel(r.resolvedTokenId!.value) ?? '(no approved label)');

  final String col1 = '  ${query.isEmpty ? '(empty)' : query}'.padRight(30);
  final String col2 =
      '→ ${r.queryNormalized.isEmpty ? '(empty)' : r.queryNormalized}'.padRight(
        28,
      );
  final String col3 = vocabularyMatchStatusName(r.status).padRight(18);
  final String col4 = resolved.padRight(24);
  final String col5 = (r.matchSource ?? '—').padRight(16);
  final String col6 = candidates.padRight(30);

  print('$col1$col2$col3$col4$col5$col6$label');
}

void main() {
  test('internal Vocabulary 2.0 evaluation surface', () {
    final VocabularyLoadResult loaded = loadVocabularyV2FromBytes(
      File(_candidatePath).readAsBytesSync(),
    );
    expect(loaded.isSuccess, isTrue, reason: '${loaded.failure}');
    final VocabularyV2 vocab = loaded.vocabulary!;
    final VocabularySearchIndex index = VocabularySearchIndex(vocab);

    print('');
    print('=== VOCABULARY 2.0 — INTERNAL EVALUATION SURFACE ===');
    print(
      '  NOT CLINICAL UI. NOT REACHABLE IN ANY NORMAL OR PRODUCTION BUILD.',
    );
    print('');
    print('  artifact            : token_dictionary.ng.v2.0.json');
    print('  artifact version    : ${vocab.metadata.version}');
    print('  schema version      : ${vocab.metadata.schemaVersion}');
    print('  release status      : ${vocab.metadata.releaseStatus}');
    print('  clinical review     : ${vocab.metadata.clinicalReviewStatus}');
    print('  may publish         : ${vocab.metadata.claimsPublishable}');
    print('  tokens loaded       : ${vocab.tokens.length}');
    print('  normalization ver   : ${vocab.normalizationVersion}');
    print('  resolver version    : ${vocab.resolverVersion}');
    print(
      '  display-safe tokens : '
      '${vocab.tokens.where((VocabularyToken t) => t.display.displaySafe).length}'
      ' of ${vocab.tokens.length}',
    );
    print(
      '  approved aliases    : '
      '${vocab.tokens.fold<int>(0, (int s, VocabularyToken t) => s + t.search.aliases.length)}',
    );
    print(
      '  evaluation gate     : '
      '${VocabularyConfig.fromEnvironment().evaluationEnabled ? 'ENABLED' : 'disabled (default)'}',
    );
    print('  live scoring artifact: token_dictionary 1.1 (unchanged)');
    print('');

    print(
      '${'  QUERY'.padRight(32)}${'NORMALIZED'.padRight(28)}'
      '${'STATUS'.padRight(18)}${'RESOLVED TOKEN'.padRight(24)}'
      '${'SOURCE'.padRight(16)}${'CANDIDATES'.padRight(30)}APPROVED LABEL',
    );
    print('  ${'─' * 160}');

    print('  -- canonical matches, real candidate --');
    for (final String q in const <String>[
      'chest_pain',
      'fever',
      'Chest Pain',
      '  chest   pain  ',
      'chest-pain',
      'blood in stool',
    ]) {
      _row(index, q);
    }

    print('');
    print('  -- no-match behaviour (negation, prefix, typo, plural) --');
    for (final String q in const <String>[
      'no fever',
      'not fever',
      'feve',
      'fevers',
      'fver',
      'chestpain',
      'fever and chills',
      '',
    ]) {
      _row(index, q);
    }

    print('');
    print('  -- metadata filtering (search/filter only, never scored) --');
    for (final String area in vocab.bodyAreas.take(3)) {
      final List<CanonicalTokenId> inArea = index.tokensInBodyArea(area);
      print(
        '  body area "$area": ${inArea.length} associated token(s) '
        '${inArea.isEmpty ? '(candidate ships zero associations)' : ''}',
      );
    }

    // ── alias + ambiguity, on the synthetic vocabulary ────────────────────
    final VocabularySearchIndex synthetic = VocabularySearchIndex(
      loadVocabularyV2FromBytes(
        File(_syntheticPath).readAsBytesSync(),
      ).vocabulary!,
    );

    print('');
    print('  -- alias and ambiguity, SYNTHETIC non-clinical vocabulary --');
    print('     (the real candidate has zero aliases and zero collisions,');
    print('      so it cannot demonstrate these paths at all)');
    for (final String q in const <String>[
      'beta only',
      'frob nitz',
      'shared quux',
      'quibble widget',
      'quibble_widget',
      'nothing here',
    ]) {
      _row(synthetic, q);
    }

    // ── the boundary ──────────────────────────────────────────────────────
    print('');
    print('  -- canonical token boundary --');
    final AssessmentController controller = AssessmentController();
    final CanonicalTokenBoundary boundary = CanonicalTokenBoundary(
      activeVocabularyTokenIds: const <String>{'fever', 'chest_pain'},
      searchIndex: index,
    );

    for (final String q in const <String>[
      'fever',
      'Chest Pain',
      'haemoglobinuria',
      'no fever',
    ]) {
      final SelectionOutcome o = boundary.resolveAndCommit(q, controller);
      print(
        '  ${q.padRight(24)} → '
        '${o.accepted ? 'ACCEPTED ${o.tokenId!.value}' : 'REFUSED (${o.rejection!.name})'}',
      );
    }
    print('  assessment state now: ${controller.symptomTokens}');
    print('  (only canonical token ids — no query text, no alias, no label)');

    final SelectionOutcome ambiguous = CanonicalTokenBoundary(
      activeVocabularyTokenIds: const <String>{'zorble_alpha', 'zorble_beta'},
      searchIndex: synthetic,
    ).resolveAndCommit('shared quux', AssessmentController());
    print(
      '  ambiguous "shared quux" → '
      'REFUSED (${ambiguous.rejection!.name}) — no token auto-selected',
    );

    print('');
    print('=== END INTERNAL EVALUATION SURFACE ===');
    print('');

    // The surface is evidence, but it still has to hold its invariants.
    expect(controller.symptomTokens, <String>['fever', 'chest_pain']);
    expect(ambiguous.accepted, isFalse);
    expect(VocabularyConfig.fromEnvironment().evaluationEnabled, isFalse);
    expect(vocab.metadata.claimsPublishable, isFalse);
  });

  test('the harness never prints an unreviewed candidate label', () {
    final VocabularyV2 vocab = loadVocabularyV2FromBytes(
      File(_candidatePath).readAsBytesSync(),
    ).vocabulary!;
    final VocabularySearchIndex index = VocabularySearchIndex(vocab);

    // Every label this surface could show comes from displaySafeLabel, which
    // returns null for the whole candidate.
    for (final VocabularyToken t in vocab.tokens) {
      expect(
        index.displaySafeLabel(vocab.canonicalTokenId(t.tokenId)!),
        isNull,
      );
    }
  });

  test('the evaluation surface has no route and no widget', () {
    // Structural: nothing under lib/ registers a vocabulary evaluation screen.
    final List<String> offenders = <String>[];
    for (final FileSystemEntity e in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String src = e.readAsStringSync();
      if (src.contains('VocabularyEvaluationScreen') ||
          src.contains('vocabulary_evaluation_screen')) {
        offenders.add(e.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A vocabulary evaluation screen exists in lib/: '
          '${offenders.join(', ')}. The surface must stay a test harness.',
    );
  });

  test('evidence: the fixture results are recorded as JSON', () {
    // Written for the PR record, mirroring how the case bank run writes its
    // results file.
    final VocabularySearchIndex index = VocabularySearchIndex(
      loadVocabularyV2FromBytes(
        File(_candidatePath).readAsBytesSync(),
      ).vocabulary!,
    );

    final Map<String, dynamic> searchFixture =
        jsonDecode(
              File('$_root/search/search_cases_v1.json').readAsStringSync(),
            )
            as Map<String, dynamic>;

    final List<Map<String, Object?>> records = <Map<String, Object?>>[
      for (final dynamic c in searchFixture['cases'] as List<dynamic>)
        () {
          final Map<String, dynamic> tc = c as Map<String, dynamic>;
          final VocabularyResolution r = index.resolve(tc['query'] as String);
          final Map<String, dynamic> exp =
              tc['expected'] as Map<String, dynamic>;
          return <String, Object?>{
            ...r.toJson(),
            'tests': tc['tests'],
            'pass':
                r.queryNormalized == exp['query_normalized'] &&
                vocabularyMatchStatusName(r.status) == exp['status'] &&
                r.resolvedTokenId?.value == exp['resolved_token_id'],
          };
        }(),
    ];

    const String outDir = 'build/vocabulary_v2';
    Directory(outDir).createSync(recursive: true);
    File('$outDir/search_fixture_results.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'artifact': 'token_dictionary.ng.v2.0.json',
        'artifact_sha256':
            '07f935967acb1d5515cb53ffd1c8e39b59b8daf85c67cf36fa3e25094e34cd2d',
        'normalization_version': searchFixture['normalization_version'],
        'total': records.length,
        'passed': records
            .where((Map<String, Object?> r) => r['pass'] == true)
            .length,
        'results': records,
      }),
    );

    expect(
      records.where((Map<String, Object?> r) => r['pass'] != true),
      isEmpty,
    );
    print('');
    print('Fixture results written to $outDir/search_fixture_results.json');
  });
}
