import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/facilities_v2/facilities_v2_gate.dart';
import 'package:wellapath_mobile/core/facilities_v2/facilities_v2_loader.dart';
import 'package:wellapath_mobile/core/network/staged_artifact_loader.dart';

import 'fixture_support.dart';

/// In-memory cache double that records every key ever written, so the
/// tests can assert the v1.1 namespace is never touched — not merely that
/// it survived, but that no write was even attempted.
class _CacheSpy {
  final Map<String, String> store = {
    // Sentinels standing in for the last valid v1.1 cache.
    'artifact_facilities_v1.1': 'V1_SENTINEL_RAW',
    ArtifactCacheKeys.facilityData: 'V1_SENTINEL_LIST',
  };
  final List<String> writtenKeys = [];

  void put(String key, String body) {
    writtenKeys.add(key);
    store[key] = body;
  }

  String? get(String key) => store[key];

  bool get v1Untouched =>
      store['artifact_facilities_v1.1'] == 'V1_SENTINEL_RAW' &&
      store[ArtifactCacheKeys.facilityData] == 'V1_SENTINEL_LIST' &&
      writtenKeys.every((k) => k.startsWith('artifact_facilities_v2'));
}

void main() {
  FacilitiesV2Gate activeGate() => FacilitiesV2Gate.evaluate(
    defines: const {'FACILITIES_V2_EVALUATION': 'true', 'APP_ENV': 'staging'},
    manifest: syntheticApprovedManifest(),
  );

  FacilitiesV2Loader loaderWith(
    _CacheSpy cache, {
    Future<String> Function(String url)? download,
  }) => FacilitiesV2Loader(
    download: download ?? (_) async => readFixtureRaw(),
    cachePut: cache.put,
    cacheGet: cache.get,
  );

  test(
    'gate inactive -> fallback to v1.1, nothing downloaded or written',
    () async {
      final cache = _CacheSpy();
      var downloads = 0;
      final loader = loaderWith(
        cache,
        download: (_) async {
          downloads++;
          return readFixtureRaw();
        },
      );

      final result = await loader.load(
        gate: FacilitiesV2Gate.inactiveDefault,
        manifest: syntheticApprovedManifest(),
      );

      expect(result.status, FacilitiesV2LoadStatus.fallbackToV1);
      expect(result.cause, FacilitiesV2FallbackCause.gateInactive);
      expect(downloads, 0);
      expect(cache.writtenKeys, isEmpty);
      expect(cache.v1Untouched, isTrue);
    },
  );

  test('candidate_unapproved manifest -> fallback, no network', () async {
    final cache = _CacheSpy();
    var downloads = 0;
    final loader = loaderWith(
      cache,
      download: (_) async {
        downloads++;
        return readFixtureRaw();
      },
    );

    final result = await loader.load(
      gate: activeGate(),
      manifest: candidateUnapprovedManifest(),
    );

    expect(result.cause, FacilitiesV2FallbackCause.manifestUnapproved);
    expect(downloads, 0);
    expect(cache.v1Untouched, isTrue);
  });

  test('download failure -> fallback, v1.1 cache intact', () async {
    final cache = _CacheSpy();
    final loader = loaderWith(
      cache,
      download: (_) async => throw Exception('network down'),
    );

    final result = await loader.load(
      gate: activeGate(),
      manifest: syntheticApprovedManifest(),
    );

    expect(result.cause, FacilitiesV2FallbackCause.downloadFailed);
    expect(cache.writtenKeys, isEmpty);
    expect(cache.v1Untouched, isTrue);
  });

  test('hash mismatch -> fallback, nothing cached, v1.1 intact', () async {
    final cache = _CacheSpy();
    final loader = loaderWith(cache); // serves the real fixture bytes
    final wrongHashManifest = syntheticApprovedManifest(
      hash: 'a' * 64, // valid shape, wrong value
    );

    final result = await loader.load(
      gate: FacilitiesV2Gate.evaluate(
        defines: const {'FACILITIES_V2_EVALUATION': 'true'},
        manifest: wrongHashManifest,
      ),
      manifest: wrongHashManifest,
    );

    expect(result.cause, FacilitiesV2FallbackCause.hashMismatch);
    expect(cache.writtenKeys, isEmpty);
    expect(cache.v1Untouched, isTrue);
  });

  test('schema parse failure -> fallback, v1.1 intact', () async {
    const badBody = '{"schema_version":"3.0","facilities":[]}';
    final cache = _CacheSpy();
    final manifest = syntheticApprovedManifest(hash: sha256Of(badBody));
    final loader = loaderWith(cache, download: (_) async => badBody);

    final result = await loader.load(
      gate: FacilitiesV2Gate.evaluate(
        defines: const {'FACILITIES_V2_EVALUATION': 'true'},
        manifest: manifest,
      ),
      manifest: manifest,
    );

    expect(result.cause, FacilitiesV2FallbackCause.schemaRejected);
    expect(cache.v1Untouched, isTrue);
  });

  test('empty candidate -> unusable -> fallback', () async {
    const emptyBody = '{"schema_version":"2.0","facilities":[]}';
    final cache = _CacheSpy();
    final manifest = syntheticApprovedManifest(hash: sha256Of(emptyBody));
    final loader = loaderWith(cache, download: (_) async => emptyBody);

    final result = await loader.load(
      gate: FacilitiesV2Gate.evaluate(
        defines: const {'FACILITIES_V2_EVALUATION': 'true'},
        manifest: manifest,
      ),
      manifest: manifest,
    );

    expect(result.cause, FacilitiesV2FallbackCause.candidateUnusable);
    expect(cache.v1Untouched, isTrue);
  });

  test('success path caches under the v2 namespace only', () async {
    final cache = _CacheSpy();
    final loader = loaderWith(cache);

    final result = await loader.load(
      gate: activeGate(),
      manifest: syntheticApprovedManifest(),
    );

    expect(result.status, FacilitiesV2LoadStatus.loadedFromNetwork);
    expect(result.parse!.facilities, hasLength(6));
    expect(cache.writtenKeys, ['artifact_facilities_v2_v2.0-synthetic-test']);
    expect(cache.v1Untouched, isTrue);
  });

  test('cached v2 copy is verified on read and reused offline', () async {
    final cache = _CacheSpy();
    var downloads = 0;
    final loader = loaderWith(
      cache,
      download: (_) async {
        downloads++;
        return readFixtureRaw();
      },
    );

    await loader.load(
      gate: activeGate(),
      manifest: syntheticApprovedManifest(),
    );
    final second = await loader.load(
      gate: activeGate(),
      manifest: syntheticApprovedManifest(),
    );

    expect(downloads, 1, reason: 'second load must come from cache');
    expect(second.status, FacilitiesV2LoadStatus.loadedFromCache);
    expect(second.parse!.facilities, hasLength(6));
  });

  test('background-isolate parsing is result-identical to a direct parse '
      'of the same fixture', () async {
    // The loader now verifies and parses in a short-lived background
    // isolate (measured on the low-end profile: worst UI frame 897 ms ->
    // <=125 ms). This pins that the moved computation changes nothing:
    // same records in the same order, same rejection count, same
    // attribution.
    final cache = _CacheSpy();
    final loader = loaderWith(cache);
    final viaLoader = await loader.load(
      gate: activeGate(),
      manifest: syntheticApprovedManifest(),
    );
    final direct = parseFixtureDirectly();
    expect(viaLoader.parse!.facilities.length, direct.facilities.length);
    expect(viaLoader.parse!.rejectedRecords, direct.rejectedRecords);
    expect(viaLoader.parse!.schemaVersion, direct.schemaVersion);
    expect(viaLoader.parse!.attribution.citation, direct.attribution.citation);
    for (var i = 0; i < direct.facilities.length; i++) {
      expect(viaLoader.parse!.facilities[i].id, direct.facilities[i].id);
      expect(
        viaLoader.parse!.facilities[i].latitude,
        direct.facilities[i].latitude,
      );
    }
  });

  test('the v2 cache namespace is disjoint from every v1.1 key', () {
    expect(
      FacilitiesV2CacheKeys.artifact,
      isNot(equals(ArtifactCacheKeys.facilities)),
    );
    expect(
      FacilitiesV2CacheKeys.facilityData,
      isNot(equals(ArtifactCacheKeys.facilityData)),
    );
    // Versioned-key prefixing cannot collide either: v1.1 keys never start
    // with the v2 prefix.
    expect(
      ArtifactCacheKeys.facilities.startsWith(FacilitiesV2CacheKeys.artifact),
      isFalse,
    );
  });
}
