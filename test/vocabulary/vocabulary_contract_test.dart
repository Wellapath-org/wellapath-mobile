/// Contract-drift protection for the vendored Vocabulary 2.0 fixtures.
///
/// Never skips. A missing fixture is a CI failure, and so is a changed one:
/// the whole point of vendoring byte-for-byte is that the bytes can be checked.
///
/// The publication-state assertions here are the load-bearing ones. The
/// candidate is clinically unreviewed with zero approved labels, so a change
/// to `release_status`, `may_publish` or the review status is not a routine
/// data update — it is a decision that has to be made by people, and this
/// file makes sure it cannot arrive silently in a fixture bump.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vocabulary_contract.dart';

const String _fixtureRoot = 'test/fixtures/vocabulary';
const String _candidatePath =
    '$_fixtureRoot/candidate/token_dictionary.ng.v2.0.json';
const String _liveDictPath =
    'test/fixtures/artifacts/token_dictionary.ng.v1.1.json';

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('vendored contract integrity', () {
    test('every contract file is present', () {
      final List<String> missing = <String>[
        for (final VocabContractFile f in kVocabContractFiles)
          if (!File('$_fixtureRoot/${f.destinationPath}').existsSync())
            f.destinationPath,
      ];
      expect(
        missing,
        isEmpty,
        reason:
            'Missing vendored contract files: ${missing.join(', ')}. Re-vendor '
            'byte-for-byte from $kVocabSourceRepository@$kVocabSourceCommit.',
      );
    });

    test('every contract file matches its authoritative sha256 and size', () {
      final List<String> drift = <String>[];
      for (final VocabContractFile f in kVocabContractFiles) {
        final File file = File('$_fixtureRoot/${f.destinationPath}');
        if (!file.existsSync()) continue;
        final List<int> bytes = file.readAsBytesSync();
        final String actual = sha256.convert(bytes).toString();
        if (actual != f.sha256 || bytes.length != f.bytes) {
          drift.add(
            '${f.destinationPath}: expected ${f.sha256} (${f.bytes}B), '
            'got $actual (${bytes.length}B)',
          );
        }
      }
      expect(
        drift,
        isEmpty,
        reason:
            'Vendored contract files drifted from '
            '$kVocabSourceRepository@$kVocabSourceCommit:\n${drift.join('\n')}',
      );
    });

    test('the candidate matches the handoff hash and byte count exactly', () {
      final List<int> bytes = File(_candidatePath).readAsBytesSync();
      expect(
        sha256.convert(bytes).toString(),
        '07f935967acb1d5515cb53ffd1c8e39b59b8daf85c67cf36fa3e25094e34cd2d',
      );
      expect(bytes.length, 339948);
    });

    test('all 21 invalid fixtures named by the index are vendored', () {
      final Map<String, dynamic> index = _readJson(
        '$_fixtureRoot/invalid/index.json',
      );
      final List<String> files = (index['fixtures'] as List<dynamic>)
          .map((dynamic f) => (f as Map<String, dynamic>)['file'] as String)
          .toList();

      expect(files, hasLength(21));
      for (final String f in files) {
        expect(
          File('$_fixtureRoot/invalid/$f').existsSync(),
          isTrue,
          reason: 'Invalid fixture $f named by the index is not vendored.',
        );
      }
    });
  });

  group('candidate publication state', () {
    late Map<String, dynamic> metadata;

    setUpAll(() {
      metadata = _readJson(_candidatePath)['_metadata'] as Map<String, dynamic>;
    });

    test('version and schema version are unchanged', () {
      expect(metadata['version'], kCandidateVersion);
      expect(metadata['schema_version'], kCandidateSchemaVersion);
    });

    test('release_status is still candidate_unapproved', () {
      expect(
        metadata['release_status'],
        kCandidateReleaseStatus,
        reason:
            'The candidate changed release status. Publication is a separately '
            'reviewed decision and cannot arrive through a fixture update.',
      );
    });

    test('may_publish is never true', () {
      // The current candidate carries null rather than false. Absence is not
      // permission, so the assertion is "not true" rather than "== false" —
      // and a later explicit `true` still fails here.
      expect(
        metadata['may_publish'],
        isNot(true),
        reason: 'The candidate claims it may be published.',
      );
    });

    test('clinical review has not become approved', () {
      final Map<String, dynamic> review =
          metadata['clinical_review'] as Map<String, dynamic>;
      expect(
        review['status'],
        kCandidateClinicalReviewStatus,
        reason:
            'Clinical review status changed. An approved review changes what '
            'this consumer is allowed to do and requires a separately '
            'reviewed contract update, not a fixture bump.',
      );
    });

    test('the candidate still declares 295 tokens', () {
      expect(metadata['total_tokens'], kCandidateTokenCount);
    });

    test('no token is display_safe while the labels are unreviewed', () {
      final List<dynamic> tokens =
          _readJson(_candidatePath)['tokens'] as List<dynamic>;
      final List<String> displaySafe = <String>[
        for (final dynamic t in tokens)
          if (((t as Map<String, dynamic>)['display']
                  as Map<String, dynamic>)['display_safe'] ==
              true)
            t['token_id'] as String,
      ];
      expect(
        displaySafe,
        isEmpty,
        reason:
            'Tokens became display_safe: ${displaySafe.take(5).join(', ')}. '
            'Candidate labels must not reach the UI before label approval.',
      );
    });

    test('the candidate carries zero approved aliases', () {
      final List<dynamic> tokens =
          _readJson(_candidatePath)['tokens'] as List<dynamic>;
      final int aliasCount = tokens.fold<int>(
        0,
        (int sum, dynamic t) =>
            sum +
            (((t as Map<String, dynamic>)['search']
                        as Map<String, dynamic>)['aliases']
                    as List<dynamic>)
                .length,
      );
      expect(
        aliasCount,
        0,
        reason:
            'Aliases appeared in the real candidate. Aliases are authored, '
            'clinically reviewed data — they must not be added to make a test '
            'pass. Alias behaviour is exercised against the synthetic fixture.',
      );
    });
  });

  group('clinical identity parity with the live token dictionary', () {
    late Set<String> liveIds;
    late Set<String> candidateIds;
    late Map<String, dynamic> live;
    late Map<String, dynamic> candidate;

    setUpAll(() {
      live = _readJson(_liveDictPath);
      candidate = _readJson(_candidatePath);
      liveIds = <String>{
        for (final MapEntry<String, dynamic> e in live.entries)
          if (e.key.endsWith('_tokens'))
            ...(e.value as List<dynamic>).cast<String>(),
      };
      candidateIds = <String>{
        for (final dynamic t in candidate['tokens'] as List<dynamic>)
          (t as Map<String, dynamic>)['token_id'] as String,
      };
    });

    test('the live dictionary hash is unchanged', () {
      expect(
        sha256.convert(File(_liveDictPath).readAsBytesSync()).toString(),
        kLiveTokenDictionarySha256,
        reason:
            'The live token dictionary $kLiveTokenDictionaryVersion changed.',
      );
    });

    test('no canonical token id is added, removed or renamed', () {
      expect(liveIds, hasLength(kCandidateTokenCount));
      expect(candidateIds, hasLength(kCandidateTokenCount));
      expect(
        candidateIds.difference(liveIds),
        isEmpty,
        reason: 'Candidate adds token ids not in the live dictionary.',
      );
      expect(
        liveIds.difference(candidateIds),
        isEmpty,
        reason: 'Candidate drops token ids present in the live dictionary.',
      );
    });

    test('no token is deprecated or merged', () {
      final List<String> notActive = <String>[
        for (final dynamic t in candidate['tokens'] as List<dynamic>)
          if (((t as Map<String, dynamic>)['clinical_identity']
                  as Map<String, dynamic>)['status'] !=
              'active')
            t['token_id'] as String,
      ];
      expect(notActive, isEmpty);

      final List<String> replaced = <String>[
        for (final dynamic t in candidate['tokens'] as List<dynamic>)
          if (((t as Map<String, dynamic>)['clinical_identity']
                  as Map<String, dynamic>)['replaced_by'] !=
              null)
            t['token_id'] as String,
      ];
      expect(replaced, isEmpty);
    });

    test('every frozen legacy clinical array is identical, in order', () {
      for (final MapEntry<String, dynamic> e in live.entries) {
        if (!e.key.endsWith('_tokens')) continue;
        expect(
          candidate[e.key],
          e.value,
          reason:
              'Legacy array ${e.key} differs between the live dictionary and '
              'the candidate. These arrays are what reconstruct v1.1.',
        );
      }
    });
  });

  group('the candidate is not wired into the app', () {
    test('it is not declared as a Flutter asset', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec.contains('token_dictionary.ng.v2.0'),
        isFalse,
        reason:
            'The candidate appears in pubspec.yaml. It must not ship in the '
            'asset bundle — a normal build must be unable to read it at all.',
      );
      expect(pubspec.contains('test/fixtures/vocabulary'), isFalse);
    });

    test('it lives only under test fixtures', () {
      expect(
        Directory('assets').existsSync()
            ? Directory('assets')
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((File f) => f.path.contains('token_dictionary'))
                  .map((File f) => f.path)
                  .toList()
            : <String>[],
        isEmpty,
        reason: 'A token dictionary appeared under assets/.',
      );
    });

    test('no lib/ source references the candidate file or a v2 URL', () {
      final List<String> offenders = <String>[];
      for (final FileSystemEntity e in Directory(
        'lib',
      ).listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final String src = e.readAsStringSync();
        if (src.contains('token_dictionary.ng.v2.0') ||
            src.contains('v2.0.json')) {
          offenders.add(e.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Application source references the candidate artifact: '
            '${offenders.join(', ')}',
      );
    });

    test('the vocabulary consumer performs no network I/O', () {
      // Structural, not behavioural: the consumer cannot reach the network
      // because it does not import anything that can.
      const List<String> consumerFiles = <String>[
        'lib/core/vocabulary/vocabulary_v2_loader.dart',
        'lib/core/vocabulary/vocabulary_search.dart',
        'lib/core/vocabulary/vocabulary_normalizer.dart',
        'lib/core/vocabulary/canonical_token_boundary.dart',
      ];
      for (final String path in consumerFiles) {
        final String src = File(path).readAsStringSync();
        for (final String forbidden in const <String>[
          'package:dio',
          'dart:io',
          'HttpClient',
          'api_client',
          'staged_artifact_loader',
          'telemetry',
        ]) {
          expect(
            src.contains(forbidden),
            isFalse,
            reason: '$path imports or references "$forbidden".',
          );
        }
      }
    });
  });
}
