import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

// Exact copy of LoadingScreen._loadArtifact's logic (loading_screen.dart) —
// verifies the version-aware caching mechanism directly, without the
// widget/Navigator/fake-async layer. Reads from the Hive cache first and
// only downloads (then caches) on a cache miss; the cache key is scoped by
// [version] so a new artifact version is never served stale data cached
// under an older version.
Future<Map<String, dynamic>> _loadArtifact(
  Dio dio,
  Box<dynamic> box,
  String url,
  String cacheKey,
  String version,
) async {
  final versionedKey = '${cacheKey}_v$version';
  final cached = box.get(versionedKey);
  if (cached != null) {
    return Map<String, dynamic>.from(cached as Map);
  }

  final response = await dio.get<dynamic>(url);
  final data = Map<String, dynamic>.from(response.data as Map);
  await box.put(versionedKey, data);
  return data;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hive_version_cache_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'stale cached KB v1.0 + config reporting v2.2 triggers a fresh download of v2.2, leaving v1.0 untouched',
    () async {
      const stalePlaceholder = {
        'conditions': <dynamic>[],
        '_placeholder': 'STALE_V1_DATA_SHOULD_NOT_BE_USED',
      };

      final box = await Hive.openBox('artifact_cache');
      await box.put('artifact_kb_v1.0', stalePlaceholder);

      // Precondition: cached version present, new version absent.
      expect(box.containsKey('artifact_kb_v1.0'), isTrue);
      expect(box.containsKey('artifact_kb_v2.2'), isFalse);

      final dio = Dio();
      const realKbUrl =
          'https://pub-8bc2ba0d7e7647799d89662d70f23c45.r2.dev/kb.ng.v2.2.json';

      // config now reports version 2.2 — this is exactly what
      // loading_screen.dart's _runAssessment computes as kbVersion and
      // passes into _loadArtifact on every boot.
      final result = await _loadArtifact(
        dio,
        box,
        realKbUrl,
        'artifact_kb',
        '2.2',
      );

      // A real download happened and was cached under the NEW version key.
      expect(box.containsKey('artifact_kb_v2.2'), isTrue);
      expect((result['conditions'] as List).isNotEmpty, isTrue);

      // The stale v1.0 entry was never touched or served.
      final staleEntry = Map<String, dynamic>.from(
        box.get('artifact_kb_v1.0') as Map,
      );
      expect(
        staleEntry['_placeholder'],
        equals('STALE_V1_DATA_SHOULD_NOT_BE_USED'),
      );
      expect(staleEntry['conditions'], isEmpty);

      await box.close();
    },
  );

  test(
    'cached version matching config version is served from cache — no download',
    () async {
      const cachedRealKb = {
        'conditions': [
          {'condition_id': 'already_cached', 'urgency_default': 'urgent'},
        ],
      };

      final box = await Hive.openBox('artifact_cache');
      await box.put('artifact_kb_v2.2', cachedRealKb);

      final dio = Dio();
      // Deliberately bogus URL — if a download were attempted, this would
      // throw a DioException. Since the version already matches what's
      // cached, _loadArtifact must return the cached data without ever
      // calling dio.get.
      final result = await _loadArtifact(
        dio,
        box,
        'https://this-host-does-not-exist.invalid/should-not-be-fetched.json',
        'artifact_kb',
        '2.2',
      );

      expect(
        (result['conditions'] as List).first['condition_id'],
        equals('already_cached'),
      );

      await box.close();
    },
  );
}
