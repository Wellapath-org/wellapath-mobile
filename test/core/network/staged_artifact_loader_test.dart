import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wellapath_mobile/core/network/staged_artifact_loader.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('staged_loader_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  ArtifactSpec specFor(String url, String cacheKey, {String? hash}) =>
      ArtifactSpec(url: url, cacheKey: cacheKey, version: '1.0', hash: hash);

  group('exponential backoff retry on network failure', () {
    test(
      'retries the configured number of times with the configured backoff before succeeding',
      () async {
        var callCount = 0;

        final loader = StagedArtifactLoader(
          maxRetries: 3,
          backoffDurations: const [
            Duration(milliseconds: 1),
            Duration(milliseconds: 1),
            Duration(milliseconds: 1),
          ],
          downloadOverride: (url) async {
            callCount++;
            if (callCount < 3) {
              throw Exception('simulated network failure');
            }
            return '{"rules": []}';
          },
        );

        final result = await loader.loadCoreArtifacts(
          tokenDict: specFor(
            'https://example.invalid/token.json',
            'artifact_token_dict',
          ),
          rules: specFor(
            'https://example.invalid/rules.json',
            'artifact_rules',
          ),
          kb: specFor('https://example.invalid/kb.json', 'artifact_kb'),
        );

        // 3 specs download concurrently. The failure threshold (callCount < 3)
        // means exactly 2 of the first 3 concurrent attempts fail and 1
        // succeeds; the 2 that failed each retry once and succeed on that
        // retry — 3 initial attempts + 2 retries = 5 total calls, regardless
        // of which of the 3 specs happened to hit which global call index.
        expect(callCount, equals(5));
        expect(result.rules, isEmpty);
      },
    );

    test(
      'gives up after maxRetries and throws FirstLaunchOfflineException, not the raw network error',
      () async {
        final loader = StagedArtifactLoader(
          maxRetries: 3,
          backoffDurations: const [
            Duration(milliseconds: 1),
            Duration(milliseconds: 1),
            Duration(milliseconds: 1),
          ],
          downloadOverride: (url) async {
            throw Exception('simulated permanent network failure');
          },
        );

        await expectLater(
          () => loader.loadCoreArtifacts(
            tokenDict: specFor(
              'https://example.invalid/token.json',
              'artifact_token_dict',
            ),
            rules: specFor(
              'https://example.invalid/rules.json',
              'artifact_rules',
            ),
            kb: specFor('https://example.invalid/kb.json', 'artifact_kb'),
          ),
          throwsA(isA<FirstLaunchOfflineException>()),
        );
      },
    );

    test(
      'a request that never resolves (trickling connection, no Dio timeout ever fires) '
      'is still cut off by perAttemptTimeout and does not hang forever',
      () async {
        // Regression test for the E8.4 finding: Dio's receiveTimeout only
        // measures the gap between received chunks, not total transfer
        // time, so a connection that keeps trickling data (or, as here, a
        // download that simply never completes) never throws on its own.
        // Without a hard per-attempt wall-clock cap, this hangs forever —
        // no success, no failure, no retry ever engages.
        final loader = StagedArtifactLoader(
          maxRetries: 1,
          backoffDurations: const [Duration(milliseconds: 1)],
          perAttemptTimeout: const Duration(milliseconds: 50),
          downloadOverride: (url) =>
              Completer<String>().future, // never completes
        );

        await expectLater(
          () => loader.loadCoreArtifacts(
            tokenDict: specFor(
              'https://example.invalid/token.json',
              'artifact_token_dict',
            ),
            rules: specFor(
              'https://example.invalid/rules.json',
              'artifact_rules',
            ),
            kb: specFor('https://example.invalid/kb.json', 'artifact_kb'),
          ),
          throwsA(isA<FirstLaunchOfflineException>()),
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail(
            'loadCoreArtifacts hung instead of being cut off by perAttemptTimeout',
          ),
        );
      },
    );

    test(
      'a hash-integrity failure surfaces as StateError, distinct from a network failure',
      () async {
        const wrongHash =
            'sha256:0000000000000000000000000000000000000000000000000000000000000000';

        final loader = StagedArtifactLoader(
          downloadOverride: (url) async => '{"rules": []}',
        );

        await expectLater(
          () => loader.loadCoreArtifacts(
            tokenDict: specFor(
              'https://example.invalid/token.json',
              'artifact_token_dict',
            ),
            rules: specFor(
              'https://example.invalid/rules.json',
              'artifact_rules',
              hash: wrongHash,
            ),
            kb: specFor('https://example.invalid/kb.json', 'artifact_kb'),
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('staged download ordering', () {
    test(
      'loadCoreArtifacts resolves without requiring facilities to be requested at all',
      () async {
        final loader = StagedArtifactLoader(
          downloadOverride: (url) async {
            if (url.contains('rules')) return '{"rules": [{"id": "r1"}]}';
            if (url.contains('kb')) {
              return '{"conditions": [{"condition_id": "c1"}]}';
            }
            return '{"tokens": {}}';
          },
        );

        final result = await loader.loadCoreArtifacts(
          tokenDict: specFor(
            'https://example.invalid/token.json',
            'artifact_token_dict',
          ),
          rules: specFor(
            'https://example.invalid/rules.json',
            'artifact_rules',
          ),
          kb: specFor('https://example.invalid/kb.json', 'artifact_kb'),
        );

        expect(result.rules.single['id'], equals('r1'));
        expect(result.conditions.single['condition_id'], equals('c1'));
        expect(loader.facilitiesReady.value, isFalse);
        expect(loader.facilitiesFailed.value, isFalse);
      },
    );

    test(
      'loadFacilitiesInBackground does not block the caller and flips facilitiesReady once done',
      () async {
        final loader = StagedArtifactLoader(
          downloadOverride: (url) async =>
              '{"facilities": [{"name": "Test Clinic"}]}',
        );

        expect(loader.facilitiesReady.value, isFalse);
        loader.loadFacilitiesInBackground(
          specFor(
            'https://example.invalid/facilities.json',
            'artifact_facilities',
          ),
        );
        // Fire-and-forget: returns immediately, before the download settles.
        expect(loader.facilitiesReady.value, isFalse);

        final completer = Completer<void>();
        loader.facilitiesReady.addListener(() {
          if (loader.facilitiesReady.value && !completer.isCompleted) {
            completer.complete();
          }
        });
        await completer.future.timeout(const Duration(seconds: 5));

        expect(loader.facilitiesReady.value, isTrue);

        final facilityBox = Hive.isBoxOpen(ArtifactCacheKeys.facilityBox)
            ? Hive.box(ArtifactCacheKeys.facilityBox)
            : await Hive.openBox(ArtifactCacheKeys.facilityBox);
        final stored = facilityBox.get(ArtifactCacheKeys.facilityData) as List;
        expect((stored.first as Map)['name'], equals('Test Clinic'));
      },
    );

    test(
      'loadFacilitiesInBackground flips facilitiesFailed (not facilitiesReady) when the download never succeeds',
      () async {
        final loader = StagedArtifactLoader(
          maxRetries: 1,
          backoffDurations: const [Duration(milliseconds: 1)],
          downloadOverride: (url) async {
            throw Exception('simulated failure');
          },
        );

        loader.loadFacilitiesInBackground(
          specFor(
            'https://example.invalid/facilities.json',
            'artifact_facilities',
          ),
        );

        final completer = Completer<void>();
        loader.facilitiesFailed.addListener(() {
          if (loader.facilitiesFailed.value && !completer.isCompleted) {
            completer.complete();
          }
        });
        await completer.future.timeout(const Duration(seconds: 5));

        expect(loader.facilitiesFailed.value, isTrue);
        expect(loader.facilitiesReady.value, isFalse);
      },
    );
  });

  group('progress notifier', () {
    test('reaches step 3 once all core artifacts are cached', () async {
      final loader = StagedArtifactLoader(
        downloadOverride: (url) async {
          if (url.contains('rules')) return '{"rules": []}';
          if (url.contains('kb')) return '{"conditions": []}';
          return '{"tokens": {}}';
        },
      );

      expect(loader.progress.value.step, equals(0));

      await loader.loadCoreArtifacts(
        tokenDict: specFor(
          'https://example.invalid/token.json',
          'artifact_token_dict',
        ),
        rules: specFor('https://example.invalid/rules.json', 'artifact_rules'),
        kb: specFor('https://example.invalid/kb.json', 'artifact_kb'),
      );

      expect(loader.progress.value.step, equals(3));
    });
  });

  group('cache hit / hash verification (still correct after the refactor)', () {
    test(
      'serves from cache without downloading when version+hash match',
      () async {
        const cachedRaw = '{"rules": [{"id": "cached_rule"}]}';
        final box = await Hive.openBox(ArtifactCacheKeys.artifactBox);
        await box.put('artifact_rules_v1.0', cachedRaw);
        await box.put('artifact_token_dict_v1.0', '{"tokens": {}}');
        await box.put('artifact_kb_v1.0', '{"conditions": []}');

        final loader = StagedArtifactLoader(
          downloadOverride: (url) async {
            fail('should not download — cache hit expected');
          },
        );

        final result = await loader.loadCoreArtifacts(
          tokenDict: specFor(
            'https://example.invalid/token.json',
            'artifact_token_dict',
          ),
          rules: specFor(
            'https://example.invalid/rules.json',
            'artifact_rules',
          ),
          kb: specFor('https://example.invalid/kb.json', 'artifact_kb'),
        );

        expect(result.rules.single['id'], equals('cached_rule'));
      },
    );

    test('a corrupted cache entry is discarded and re-downloaded', () async {
      const genuineRaw = '{"rules": [{"id": "genuine_rule"}]}';
      final genuineHash =
          'sha256:${sha256.convert(utf8.encode(genuineRaw)).toString()}';

      final box = await Hive.openBox(ArtifactCacheKeys.artifactBox);
      await box.put('artifact_rules_v1.0', '{"rules": [{"id": "corrupted"}]}');

      final loader = StagedArtifactLoader(
        downloadOverride: (url) async => genuineRaw,
      );

      final result = await loader.loadCoreArtifacts(
        tokenDict: specFor(
          'https://example.invalid/token.json',
          'artifact_token_dict',
        ),
        rules: specFor(
          'https://example.invalid/rules.json',
          'artifact_rules',
          hash: genuineHash,
        ),
        kb: specFor('https://example.invalid/kb.json', 'artifact_kb'),
      );

      expect(result.rules.single['id'], equals('genuine_rule'));
    });
  });
}
