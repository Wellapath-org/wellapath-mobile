/// Loader behaviour: the valid candidate, every authoritative invalid fixture,
/// and the fail-closed guarantees.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_normalizer.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_v2.dart';
import 'package:wellapath_mobile/core/vocabulary/vocabulary_v2_loader.dart';

const String _root = 'test/fixtures/vocabulary';
const String _candidatePath = '$_root/candidate/token_dictionary.ng.v2.0.json';
const String _syntheticPath = '$_root/search/synthetic_vocabulary_v1.json';
const String _liveDictPath =
    'test/fixtures/artifacts/token_dictionary.ng.v1.1.json';

void main() {
  group('the real candidate loads and validates', () {
    late VocabularyV2 vocab;

    setUpAll(() {
      final VocabularyLoadResult r = loadVocabularyV2FromBytes(
        File(_candidatePath).readAsBytesSync(),
      );
      expect(r.isSuccess, isTrue, reason: '${r.failure}');
      vocab = r.vocabulary!;
    });

    test('metadata reflects an unapproved candidate', () {
      expect(vocab.metadata.version, '2.0');
      expect(vocab.metadata.schemaVersion, '2.0');
      expect(vocab.metadata.releaseStatus, 'candidate_unapproved');
      expect(vocab.metadata.isCandidateUnapproved, isTrue);
      expect(vocab.metadata.isClinicallyReviewed, isFalse);
      expect(vocab.metadata.claimsPublishable, isFalse);
      expect(vocab.metadata.totalTokens, 295);
    });

    test('all 295 tokens are present, active and uniquely identified', () {
      expect(vocab.tokens, hasLength(295));
      expect(vocab.tokenIds, hasLength(295));
      expect(
        vocab.tokens.every((VocabularyToken t) => t.status == 'active'),
        isTrue,
      );
    });

    test('every normalized_form is reproducible from the token id', () {
      for (final VocabularyToken t in vocab.tokens) {
        expect(t.search.normalizedForm, normalizeTokenId(t.tokenId));
      }
    });

    test('no token is display safe, and no label is exposed', () {
      expect(
        vocab.tokens.where((VocabularyToken t) => t.display.displaySafe),
        isEmpty,
      );
    });

    test('the index carries the normalization version this app implements', () {
      expect(vocab.normalizationVersion, kNormalizationVersion);
      expect(vocab.normalizedForms, hasLength(295));
    });

    test('metadata associations are present but empty in this candidate', () {
      expect(vocab.bodyAreas, hasLength(18));
      expect(vocab.complaintGroups, isEmpty);
      for (final VocabularyToken t in vocab.tokens) {
        expect(t.associations.complaintGroups, isEmpty);
      }
    });
  });

  group('every authoritative invalid fixture is rejected', () {
    late List<Map<String, dynamic>> fixtures;

    setUpAll(() {
      fixtures =
          ((jsonDecode(File('$_root/invalid/index.json').readAsStringSync())
                      as Map<String, dynamic>)['fixtures']
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
    });

    test('the index names 21 fixtures', () => expect(fixtures, hasLength(21)));

    test('none of them loads, and each names why', () {
      final List<String> accepted = <String>[];
      final List<String> rejected = <String>[];

      for (final Map<String, dynamic> f in fixtures) {
        final String name = f['file'] as String;
        final File file = File('$_root/invalid/$name');
        final VocabularyLoadResult r = loadVocabularyV2FromBytes(
          file.readAsBytesSync(),
        );

        if (r.isSuccess) {
          accepted.add('$name (expected ${f['expected_failing_check']})');
        } else {
          rejected.add('$name -> ${r.failure!.error.name}');
        }
      }

      expect(
        accepted,
        isEmpty,
        reason:
            'These defective fixtures were accepted by the loader:\n'
            '${accepted.join('\n')}',
      );
      expect(rejected, hasLength(21));
    });
  });

  group('fails closed', () {
    test('malformed JSON returns a typed failure, not an exception', () {
      final VocabularyLoadResult r = loadVocabularyV2FromString('{"tokens": [');
      expect(r.isSuccess, isFalse);
      expect(r.failure!.error, VocabularyLoadError.malformedJson);
      expect(r.vocabulary, isNull);
    });

    test('an empty payload fails', () {
      expect(loadVocabularyV2FromString('').isSuccess, isFalse);
      expect(loadVocabularyV2FromString('[]').isSuccess, isFalse);
      expect(loadVocabularyV2FromString('null').isSuccess, isFalse);
    });

    test('an unsupported major schema version is refused, not parsed', () {
      final Map<String, dynamic> doc =
          jsonDecode(File(_candidatePath).readAsStringSync())
              as Map<String, dynamic>;
      (doc['_metadata'] as Map<String, dynamic>)['schema_version'] = '3.0';

      final VocabularyLoadResult r = loadVocabularyV2FromString(
        jsonEncode(doc),
      );
      expect(r.failure!.error, VocabularyLoadError.unsupportedSchemaVersion);
    });

    test('a normalization version mismatch is refused', () {
      final Map<String, dynamic> doc =
          jsonDecode(File(_candidatePath).readAsStringSync())
              as Map<String, dynamic>;
      (doc['search_index'] as Map<String, dynamic>)['normalization_version'] =
          '2.0.0';

      final VocabularyLoadResult r = loadVocabularyV2FromString(
        jsonEncode(doc),
      );
      expect(
        r.failure!.error,
        VocabularyLoadError.normalizationVersionMismatch,
        reason:
            'Searching an index built by a different normalizer could '
            'silently change which token a query resolves to.',
      );
    });

    test('a publication claim without clinical review is refused', () {
      final Map<String, dynamic> doc =
          jsonDecode(File(_candidatePath).readAsStringSync())
              as Map<String, dynamic>;
      (doc['_metadata'] as Map<String, dynamic>)['may_publish'] = true;

      final VocabularyLoadResult r = loadVocabularyV2FromString(
        jsonEncode(doc),
      );
      expect(
        r.failure!.error,
        VocabularyLoadError.publicationClaimWithoutReview,
      );
    });

    test('a failure never yields partial data', () {
      for (final String path in <String>[
        '$_root/invalid/duplicate_token_id.json',
        '$_root/invalid/stale_search_index.json',
        '$_root/invalid/replacement_cycle.json',
      ]) {
        final VocabularyLoadResult r = loadVocabularyV2FromBytes(
          File(path).readAsBytesSync(),
        );
        expect(r.vocabulary, isNull, reason: '$path leaked partial data');
        expect(r.failure, isNotNull);
      }
    });
  });

  group('offline and restart behaviour', () {
    test('loading and searching need no network and no plugins', () {
      // This test binding has no platform channels and no HTTP client wired.
      // Reaching for either would throw; the load completing proves neither is
      // touched. This is the airplane-mode case.
      final VocabularyLoadResult r = loadVocabularyV2FromBytes(
        File(_candidatePath).readAsBytesSync(),
      );
      expect(r.isSuccess, isTrue);
    });

    test('repeated loads from the same bytes are identical', () {
      final List<int> bytes = File(_candidatePath).readAsBytesSync();
      final VocabularyV2 a = loadVocabularyV2FromBytes(bytes).vocabulary!;
      final VocabularyV2 b = loadVocabularyV2FromBytes(bytes).vocabulary!;

      expect(a.tokenIds, b.tokenIds);
      expect(
        a.tokens.map((VocabularyToken t) => t.tokenId).toList(),
        b.tokens.map((VocabularyToken t) => t.tokenId).toList(),
      );
    });

    test('the live v1.1 dictionary is untouched by a candidate failure', () {
      // A malformed candidate must not disturb the live artifact in any way.
      final List<int> before = File(_liveDictPath).readAsBytesSync();
      final VocabularyLoadResult r = loadVocabularyV2FromString('{"broken":');
      expect(r.isSuccess, isFalse);
      expect(File(_liveDictPath).readAsBytesSync(), before);
    });
  });

  group('the synthetic fixture is usable and clearly non-clinical', () {
    test('it loads and declares itself synthetic', () {
      final VocabularyLoadResult r = loadVocabularyV2FromBytes(
        File(_syntheticPath).readAsBytesSync(),
      );
      expect(r.isSuccess, isTrue, reason: '${r.failure}');

      final Map<String, dynamic> meta =
          (jsonDecode(File(_syntheticPath).readAsStringSync())
                  as Map<String, dynamic>)['_metadata']
              as Map<String, dynamic>;
      expect(meta['SYNTHETIC_FIXTURE'], isTrue);
      expect(meta['release_status'], 'candidate_unapproved');
    });

    test('its tokens are nonsense words, not clinical vocabulary', () {
      final VocabularyV2 v = loadVocabularyV2FromBytes(
        File(_syntheticPath).readAsBytesSync(),
      ).vocabulary!;
      final VocabularyV2 real = loadVocabularyV2FromBytes(
        File(_candidatePath).readAsBytesSync(),
      ).vocabulary!;

      expect(
        v.tokenIds.intersection(real.tokenIds),
        isEmpty,
        reason:
            'A synthetic token id collides with a real clinical token id. The '
            'synthetic fixture must stay entirely non-clinical.',
      );
    });
  });
}
