/// Compatibility: the candidate must be able to reconstruct token dictionary
/// 1.1 exactly, and must not change what the engine does with any token.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/engine/engine_controller.dart';
import 'package:wellapath_mobile/core/engine/models/engine_input.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_search.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_v2.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_v2_loader.dart';

import '../engine/case_bank/artifact_fixtures.dart';

const String _candidatePath =
    'test/fixtures/vocabulary/candidate/token_dictionary.ng.v2.0.json';
const String _liveDictPath =
    'test/fixtures/artifacts/token_dictionary.ng.v1.1.json';

void main() {
  late VocabularyV2 candidate;
  late Map<String, dynamic> live;

  setUpAll(() {
    candidate = loadVocabularyV2FromBytes(
      File(_candidatePath).readAsBytesSync(),
    ).vocabulary!;
    live =
        jsonDecode(File(_liveDictPath).readAsStringSync())
            as Map<String, dynamic>;
  });

  group('token dictionary 1.1 reconstructs from the candidate', () {
    test('every legacy array reconstructs exactly, in order', () {
      for (final MapEntry<String, dynamic> e in live.entries) {
        if (!e.key.endsWith('_tokens')) continue;
        expect(
          candidate.legacyArrays[e.key],
          e.value,
          reason: 'Legacy array ${e.key} does not reconstruct.',
        );
      }
    });

    test(
      'the reconstructed document is byte-identical to the live 1.1 file',
      () {
        // Rebuild v1.1 from the candidate's frozen arrays plus v1.1's own
        // metadata, then compare bytes against the artifact on disk. This is the
        // strongest available statement that no clinical identity moved.
        final Map<String, dynamic> rebuilt = <String, dynamic>{
          '_metadata': live['_metadata'],
          for (final String key in live.keys)
            if (key.endsWith('_tokens')) key: candidate.legacyArrays[key],
        };

        final String rebuiltJson = const JsonEncoder.withIndent(
          '  ',
        ).convert(rebuilt);
        final String liveJson = const JsonEncoder.withIndent(
          '  ',
        ).convert(live);

        expect(
          sha256.convert(utf8.encode(rebuiltJson)).toString(),
          sha256.convert(utf8.encode(liveJson)).toString(),
          reason:
              'The candidate cannot reconstruct token dictionary 1.1. Some '
              'clinical identity or ordering changed.',
        );
      },
    );

    test('the live artifact hash on disk is unchanged', () {
      expect(
        sha256.convert(File(_liveDictPath).readAsBytesSync()).toString(),
        '0cc47ad9537c0bd4c6ef3aec8f1931eb9b4c62103a8809d16544f94a90b5c019',
      );
    });
  });

  group('breathlessness and shortness_of_breath stay independent', () {
    test('both exist as separate tokens', () {
      expect(candidate.token('breathlessness'), isNotNull);
      expect(candidate.token('shortness_of_breath'), isNotNull);
    });

    test('neither aliases, replaces or merges into the other', () {
      final VocabularyToken b = candidate.token('breathlessness')!;
      final VocabularyToken s = candidate.token('shortness_of_breath')!;

      expect(b.replacedBy, isNull);
      expect(s.replacedBy, isNull);
      expect(b.search.aliases, isEmpty);
      expect(s.search.aliases, isEmpty);
    });

    test('searching one never reaches the other', () {
      final VocabularySearchIndex index = VocabularySearchIndex(candidate);

      final VocabularyResolution b = index.resolve('breathlessness');
      expect(b.resolvedTokenId?.value, 'breathlessness');
      expect(
        b.candidateTokenIds.map((CanonicalTokenId c) => c.value),
        isNot(contains('shortness_of_breath')),
      );

      final VocabularyResolution s = index.resolve('shortness of breath');
      expect(s.resolvedTokenId?.value, 'shortness_of_breath');
      expect(
        s.candidateTokenIds.map((CanonicalTokenId c) => c.value),
        isNot(contains('breathlessness')),
      );
    });
  });

  group('the engine is unaffected by the candidate', () {
    late PinnedArtifacts artifacts;

    setUpAll(() => artifacts = loadPinnedArtifacts());

    EngineOutput run(
      List<String> symptoms, {
      List<String> candidates = const <String>[],
    }) =>
        EngineController(
          rules: artifacts.rules,
          tokenDictionary: artifacts.tokenDictionary,
          knowledgeBase: artifacts.conditions,
          configMetadata: artifacts.configMetadata,
        ).run(
          EngineInput(
            symptomTokens: symptoms,
            candidateConditionIds: candidates,
          ),
        );

    test(
      'the engine still consumes token dictionary 1.1, not the candidate',
      () {
        // The engine is constructed from the pinned v1.1 artifact. Nothing in
        // the vocabulary package is reachable from it.
        final EngineOutput out = run(<String>['fever', 'chills']);
        expect(out.artifactsUsed['token_dict_version'], '1.1');
      },
    );

    test('a red flag token still overrides scoring', () {
      final EngineOutput out = run(<String>['seizures']);
      expect(out.redFlagTriggered, isTrue);
      expect(out.urgency, 'emergency');
      expect(out.topCauses, isEmpty);
    });

    test('an alias string is rejected by the engine outright', () {
      // Proof from the other direction: even if an alias somehow reached the
      // engine, v1.1 does not know it and validation throws rather than
      // scoring it.
      expect(
        () => run(<String>['shared quux']),
        throwsA(isA<ArgumentError>()),
        reason: 'An unknown token must never be silently scored.',
      );
    });

    test('a body-area or severity label is rejected by the engine', () {
      for (final String label in const <String>['Chest', 'Severe', '3 days']) {
        expect(
          () => run(<String>[label]),
          throwsA(isA<ArgumentError>()),
          reason: '"$label" was accepted as a scoring token.',
        );
      }
    });

    test('every candidate token id is known to the live dictionary', () {
      // The candidate cannot introduce a token the engine would reject, which
      // is what makes a future swap a non-event for scoring.
      final Set<String> liveIds = <String>{
        for (final MapEntry<String, dynamic> e in live.entries)
          if (e.key.endsWith('_tokens'))
            ...(e.value as List<dynamic>).cast<String>(),
      };
      expect(candidate.tokenIds.difference(liveIds), isEmpty);
    });
  });
}
