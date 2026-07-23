import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

// Exact copy of LoadingScreen._loadArtifact's logic (loading_screen.dart) —
// verifies the version-aware caching mechanism AND the artifact hash
// integrity check directly, without the widget/Navigator/fake-async layer.
// Reads from the Hive cache first and only downloads (then caches) on a
// cache miss; the cache key is scoped by [version] so a new artifact
// version is never served stale data cached under an older version. Every
// read — cache hit or fresh download — is verified against [expectedHash]
// (format `sha256:<hex>`) when provided; a mismatch on a cache hit discards
// the corrupted entry and re-downloads, a mismatch on a fresh download is
// retried once before being rejected outright.
Future<Map<String, dynamic>> _loadArtifact(
  Dio dio,
  Box<dynamic> box,
  String url,
  String cacheKey,
  String version,
  String? expectedHash,
) async {
  final versionedKey = '${cacheKey}_v$version';
  final cachedRaw = box.get(versionedKey) as String?;

  if (cachedRaw != null) {
    if (_matchesHash(cachedRaw, expectedHash)) {
      return Map<String, dynamic>.from(jsonDecode(cachedRaw) as Map);
    }
    await box.delete(versionedKey);
  }

  for (var attempt = 1; attempt <= 2; attempt++) {
    final response = await dio.get<dynamic>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final rawBody = response.data as String;

    if (_matchesHash(rawBody, expectedHash)) {
      await box.put(versionedKey, rawBody);
      return Map<String, dynamic>.from(jsonDecode(rawBody) as Map);
    }
  }

  throw StateError('Artifact integrity check failed for $cacheKey');
}

bool _matchesHash(String rawBody, String? expectedHash) {
  if (expectedHash == null || expectedHash.isEmpty) return true;
  final expectedHex = expectedHash.startsWith('sha256:')
      ? expectedHash.substring('sha256:'.length)
      : expectedHash;
  final actualHex = sha256.convert(utf8.encode(rawBody)).toString();
  return actualHex.toLowerCase() == expectedHex.toLowerCase();
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
      const stalePlaceholderRaw =
          '{"conditions": [], "_placeholder": "STALE_V1_DATA_SHOULD_NOT_BE_USED"}';

      final box = await Hive.openBox('artifact_cache');
      await box.put('artifact_kb_v1.0', stalePlaceholderRaw);

      // Precondition: cached version present, new version absent.
      expect(box.containsKey('artifact_kb_v1.0'), isTrue);
      expect(box.containsKey('artifact_kb_v2.2'), isFalse);

      final dio = Dio();
      const realKbUrl =
          'https://pub-8bc2ba0d7e7647799d89662d70f23c45.r2.dev/kb.ng.v2.2.json';

      // config now reports version 2.2 — this is exactly what
      // loading_screen.dart's _runAssessment computes as kbVersion and
      // passes into _loadArtifact on every boot. No hash asserted here —
      // this test is about version detection, not integrity (see the
      // dedicated hash-integrity tests below).
      final result = await _loadArtifact(
        dio,
        box,
        realKbUrl,
        'artifact_kb',
        '2.2',
        null,
      );

      // A real download happened and was cached under the NEW version key.
      expect(box.containsKey('artifact_kb_v2.2'), isTrue);
      expect((result['conditions'] as List).isNotEmpty, isTrue);

      // The stale v1.0 entry was never touched or served.
      final staleEntry =
          jsonDecode(box.get('artifact_kb_v1.0') as String) as Map;
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
      const cachedRealKbRaw =
          '{"conditions": [{"condition_id": "already_cached", "urgency_default": "urgent"}]}';

      final box = await Hive.openBox('artifact_cache');
      await box.put('artifact_kb_v2.2', cachedRealKbRaw);

      final dio = Dio();
      // Deliberately bogus URL — if a download were attempted, this would
      // throw a DioException. Since the version already matches what's
      // cached (and the hash matches, since none is asserted here),
      // _loadArtifact must return the cached data without ever calling
      // dio.get.
      final result = await _loadArtifact(
        dio,
        box,
        'https://this-host-does-not-exist.invalid/should-not-be-fetched.json',
        'artifact_kb',
        '2.2',
        null,
      );

      expect(
        (result['conditions'] as List).first['condition_id'],
        equals('already_cached'),
      );

      await box.close();
    },
  );

  test(
    'corrupted cached artifact byte fails the hash check on a version-aware cache hit and is re-downloaded',
    () async {
      final dio = Dio();
      const realKbUrl =
          'https://pub-8bc2ba0d7e7647799d89662d70f23c45.r2.dev/kb.ng.v2.2.json';

      // Fetch the real artifact once to get its genuine raw bytes and hash —
      // this is exactly the hash /config would report for this artifact.
      final response = await dio.get<dynamic>(
        realKbUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final genuineRaw = response.data as String;
      final genuineHash =
          'sha256:${sha256.convert(utf8.encode(genuineRaw)).toString()}';

      // Corrupt a single byte in the middle of the cached copy.
      final midpoint = genuineRaw.length ~/ 2;
      final corruptedChar = genuineRaw[midpoint] == 'a' ? 'b' : 'a';
      final corruptedRaw =
          genuineRaw.substring(0, midpoint) +
          corruptedChar +
          genuineRaw.substring(midpoint + 1);
      expect(corruptedRaw, isNot(equals(genuineRaw)));

      final box = await Hive.openBox('artifact_cache');
      await box.put('artifact_kb_v2.2', corruptedRaw);

      // Version-aware cache hit: the key exists (same version), but the
      // content is corrupted — the hash check must catch it, discard the
      // entry, and re-download a genuine copy.
      final result = await _loadArtifact(
        dio,
        box,
        realKbUrl,
        'artifact_kb',
        '2.2',
        genuineHash,
      );

      expect((result['conditions'] as List).isNotEmpty, isTrue);

      final cachedAfter = box.get('artifact_kb_v2.2') as String;
      expect(cachedAfter, isNot(equals(corruptedRaw)));
      expect(
        sha256.convert(utf8.encode(cachedAfter)).toString(),
        equals(genuineHash.substring('sha256:'.length)),
      );

      await box.close();
    },
  );
}
