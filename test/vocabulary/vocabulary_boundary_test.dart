/// The canonical-token boundary, the feature gate, and the proof that
/// non-clinical data cannot reach scoring.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/vocabulary/canonical_token_boundary.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_config.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_search.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_v2.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_v2_loader.dart';
import 'package:wellapath_mobile/features/assessment/assessment_controller.dart';

const String _root = 'test/fixtures/vocabulary';
const String _candidatePath = '$_root/candidate/token_dictionary.ng.v2.0.json';
const String _syntheticPath = '$_root/search/synthetic_vocabulary_v1.json';

VocabularyV2 _load(String path) {
  final VocabularyLoadResult r = loadVocabularyV2FromBytes(
    File(path).readAsBytesSync(),
  );
  expect(r.isSuccess, isTrue, reason: '${r.failure}');
  return r.vocabulary!;
}

void main() {
  group('canonical token identity cannot be forged', () {
    late VocabularyV2 vocab;

    setUpAll(() => vocab = _load(_candidatePath));

    test('a real token id mints an identity', () {
      expect(vocab.canonicalTokenId('fever')?.value, 'fever');
      expect(vocab.canonicalTokenId('chest_pain')?.value, 'chest_pain');
    });

    test('nothing else does', () {
      // These are exactly the classes of value the brief requires be unable to
      // enter clinical state. Each returns null, so there is no identity to
      // pass on.
      const List<String> forbidden = <String>[
        'fever and chills', // raw query text
        'chest pain', // normalized query text
        'shared quux', // alias text
        'Chest', // body-area label
        'Respiratory', // complaint-group label
        'Severe', // severity *label* — note `severe` is a genuine severity
        // token id and does mint; what must not mint is its display label.
        // Whether a severity token may enter *symptom* state is then governed
        // by the boundary's approved-vocabulary check, tested below.
        '3 days', // duration label
        'Fever', // display label
        'not_a_real_token', // unknown id
        '', // empty
        'FEVER', // wrong case
      ];
      for (final String value in forbidden) {
        expect(
          vocab.canonicalTokenId(value),
          isNull,
          reason: '"$value" must not mint a canonical token identity',
        );
      }
    });

    test('metadata values are never token ids', () {
      // Body area ids are metadata. Even where one happens to be a string in
      // the vocabulary, it must not be mintable as a *symptom* identity unless
      // it is genuinely a token — and the boundary below rejects any id absent
      // from the active approved vocabulary regardless.
      for (final String area in vocab.bodyAreas) {
        final CanonicalTokenId? minted = vocab.canonicalTokenId(area);
        if (minted != null) {
          expect(
            vocab.token(minted.value),
            isNotNull,
            reason: 'A body area minted an id that is not a token.',
          );
        }
      }
    });
  });

  group('the boundary only admits approved canonical tokens', () {
    late VocabularySearchIndex index;
    late CanonicalTokenBoundary boundary;
    late AssessmentController controller;

    // The active *approved* vocabulary. In every current build this is token
    // dictionary 1.1, modelled here by a small explicit set.
    const Set<String> approved = <String>{'fever', 'chest_pain', 'headache'};

    setUp(() {
      index = VocabularySearchIndex(_load(_candidatePath));
      boundary = CanonicalTokenBoundary(
        activeVocabularyTokenIds: approved,
        searchIndex: index,
      );
      controller = AssessmentController();
    });

    test('an approved canonical token is committed', () {
      final SelectionOutcome outcome = boundary.resolveAndCommit(
        'fever',
        controller,
      );
      expect(outcome.accepted, isTrue);
      expect(outcome.tokenId?.value, 'fever');
      expect(controller.symptomTokens, <String>['fever']);
    });

    test('a token absent from the approved vocabulary is refused', () {
      // `haemoglobinuria` exists in the candidate but not in this approved set.
      // Loading a candidate must never widen what scoring accepts.
      final SelectionOutcome outcome = boundary.resolveAndCommit(
        'haemoglobinuria',
        controller,
      );
      expect(outcome.accepted, isFalse);
      expect(outcome.rejection, SelectionRejection.notInActiveVocabulary);
      expect(controller.symptomTokens, isEmpty);
    });

    test('an unresolved query never touches assessment state', () {
      for (final String q in const <String>[
        'no fever',
        'feve',
        'fevers',
        'zzzznotatoken',
        '',
        '!!!',
        'i have a fever today',
      ]) {
        final SelectionOutcome outcome = boundary.resolveAndCommit(
          q,
          controller,
        );
        expect(outcome.accepted, isFalse, reason: q);
        expect(outcome.rejection, SelectionRejection.unresolved, reason: q);
      }
      expect(controller.symptomTokens, isEmpty);
    });

    test('an ambiguous query never auto-selects a token', () {
      final VocabularySearchIndex synthetic = VocabularySearchIndex(
        _load(_syntheticPath),
      );
      final CanonicalTokenBoundary syntheticBoundary = CanonicalTokenBoundary(
        activeVocabularyTokenIds: const <String>{'zorble_alpha', 'zorble_beta'},
        searchIndex: synthetic,
      );

      final SelectionOutcome outcome = syntheticBoundary.resolveAndCommit(
        'shared quux',
        controller,
      );
      expect(outcome.accepted, isFalse);
      expect(outcome.rejection, SelectionRejection.ambiguous);
      expect(
        controller.symptomTokens,
        isEmpty,
        reason:
            'An ambiguous term reached scoring. The app must never choose '
            'between two clinical tokens on the user\'s behalf.',
      );
    });

    test('an alias commits the canonical id, never the alias string', () {
      final VocabularySearchIndex synthetic = VocabularySearchIndex(
        _load(_syntheticPath),
      );
      final CanonicalTokenBoundary syntheticBoundary = CanonicalTokenBoundary(
        activeVocabularyTokenIds: const <String>{'zorble_beta'},
        searchIndex: synthetic,
      );

      final SelectionOutcome outcome = syntheticBoundary.resolveAndCommit(
        'beta only',
        controller,
      );
      expect(outcome.accepted, isTrue);
      expect(controller.symptomTokens, <String>['zorble_beta']);
      expect(
        controller.symptomTokens,
        isNot(contains('beta only')),
        reason: 'The alias string itself entered clinical state.',
      );
    });

    test('every search result carries a canonical id and nothing else', () {
      // Sweep the whole vocabulary: for each token, resolving its id must
      // yield that id, and the resolution must expose no free-text identity.
      for (final VocabularyToken t in index.vocabulary.tokens) {
        final VocabularyResolution r = index.resolve(t.tokenId);
        expect(r.resolvedTokenId?.value, t.tokenId);
        for (final CanonicalTokenId c in r.candidateTokenIds) {
          expect(index.vocabulary.token(c.value), isNotNull);
        }
      }
    });
  });

  group('metadata is filter-only and never scored', () {
    late VocabularySearchIndex index;

    setUpAll(() => index = VocabularySearchIndex(_load(_candidatePath)));

    test('body-area filtering returns canonical ids, not labels', () {
      for (final String area in index.vocabulary.bodyAreas) {
        for (final CanonicalTokenId id in index.tokensInBodyArea(area)) {
          expect(index.vocabulary.token(id.value), isNotNull);
        }
      }
    });

    test('complaint-group filtering returns canonical ids, not labels', () {
      for (final String g in index.vocabulary.complaintGroups) {
        for (final CanonicalTokenId id in index.tokensInComplaintGroup(g)) {
          expect(index.vocabulary.token(id.value), isNotNull);
        }
      }
    });

    test('no candidate label is display safe, so none is exposed', () {
      for (final VocabularyToken t in index.vocabulary.tokens) {
        final CanonicalTokenId id = index.vocabulary.canonicalTokenId(
          t.tokenId,
        )!;
        expect(
          index.displaySafeLabel(id),
          isNull,
          reason:
              '${t.tokenId} exposed an unreviewed candidate label as UI '
              'content.',
        );
      }
    });
  });

  group('feature gate defaults off and is blocked in production', () {
    test('no defines at all means disabled', () {
      expect(
        VocabularyConfig.fromEnvironment(
          defines: const <String, String>{},
        ).evaluationEnabled,
        isFalse,
      );
    });

    test('the real build this test runs in has it disabled', () {
      // No --dart-define is passed by `flutter test`, so this exercises the
      // shipped default path, not an injected map.
      expect(VocabularyConfig.fromEnvironment().evaluationEnabled, isFalse);
    });

    test('the candidate being present does not enable anything', () {
      expect(File(_candidatePath).existsSync(), isTrue);
      expect(VocabularyConfig.fromEnvironment().evaluationEnabled, isFalse);
    });

    test('the explicit internal-evaluation flag enables it', () {
      expect(
        VocabularyConfig.fromEnvironment(
          defines: const <String, String>{'VOCABULARY_V2_EVALUATION': 'true'},
        ).evaluationEnabled,
        isTrue,
      );
    });

    test('production is blocked even with the flag set', () {
      for (final String env in const <String>['production', 'prod', 'PROD']) {
        expect(
          VocabularyConfig.fromEnvironment(
            defines: <String, String>{
              'VOCABULARY_V2_EVALUATION': 'true',
              'APP_ENV': env,
            },
          ).evaluationEnabled,
          isFalse,
          reason: 'APP_ENV=$env must block the evaluation path',
        );
      }
    });

    test('the production block needs its own separate key to lift', () {
      expect(
        VocabularyConfig.fromEnvironment(
          defines: const <String, String>{
            'VOCABULARY_V2_EVALUATION': 'true',
            'APP_ENV': 'production',
            'VOCABULARY_V2_PRODUCTION_APPROVED': 'true',
          },
        ).evaluationEnabled,
        isTrue,
      );
    });

    test('a truthy-looking value that is not "true" does not enable', () {
      for (final String v in const <String>['1', 'yes', 'TRUE ', 'on', '']) {
        final bool enabled = VocabularyConfig.fromEnvironment(
          defines: <String, String>{'VOCABULARY_V2_EVALUATION': v},
        ).evaluationEnabled;
        if (v.trim().toLowerCase() == 'true') continue;
        expect(enabled, isFalse, reason: 'value "$v" enabled the gate');
      }
    });

    test('diagnostics never claim the candidate is the scoring vocabulary', () {
      final Map<String, Object?> d = VocabularyConfig.fromEnvironment(
        defines: const <String, String>{'VOCABULARY_V2_EVALUATION': 'true'},
      ).toDiagnostics();
      expect(d['is_scoring_vocabulary'], isFalse);
      expect(d['live_token_dictionary_version'], '1.1');
    });
  });
}
