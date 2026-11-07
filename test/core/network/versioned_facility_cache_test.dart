import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wellapath_mobile/core/network/staged_artifact_loader.dart';

/// WP-025: the decoded facility list used to be cached under the unversioned
/// key `facility_cache/facilities_data` and read by the locator with no
/// reference to `/config`. A device that had decoded the withdrawn facilities
/// v1.1 kept showing it after `/config` moved to v1.2.
///
/// All facility data below is synthetic. No real facility names or phone
/// numbers appear in this public repository.

const String _v11Body =
    '{"facilities": [{"name": "Withdrawn Clinic", "phone": "+000-WITHDRAWN"}]}';
const String _v12Body =
    '{"facilities": [{"name": "Current Clinic", "phone": "+000-CURRENT"}]}';

String _hashOf(String body) =>
    'sha256:${sha256.convert(utf8.encode(body)).toString()}';

ArtifactSpec _facilitiesSpec(String version, String body) => ArtifactSpec(
  url: 'https://example.invalid/facilities.ng.v$version.json',
  cacheKey: ArtifactCacheKeys.facilities,
  version: version,
  hash: _hashOf(body),
);

Map<String, dynamic> _configNaming(String version, String body) =>
    <String, dynamic>{
      'version': '1.0',
      'artifacts': <String, dynamic>{
        'facilities': <String, dynamic>{
          'version': version,
          'url': 'https://example.invalid/facilities.ng.v$version.json',
          'hash': _hashOf(body),
        },
      },
    };

Future<void> _settled(StagedArtifactLoader loader) async {
  final Completer<void> done = Completer<void>();
  void check() {
    if ((loader.facilitiesReady.value || loader.facilitiesFailed.value) &&
        !done.isCompleted) {
      done.complete();
    }
  }

  loader.facilitiesReady.addListener(check);
  loader.facilitiesFailed.addListener(check);
  check();
  await done.future.timeout(const Duration(seconds: 5));
  loader.facilitiesReady.removeListener(check);
  loader.facilitiesFailed.removeListener(check);
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('versioned_facility_cache_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<Box<dynamic>> facilityBox() =>
      Hive.openBox(ArtifactCacheKeys.facilityBox);
  Future<Box<dynamic>> artifactBox() =>
      Hive.openBox(ArtifactCacheKeys.artifactBox);

  List<Map<String, dynamic>> decoded(String body) =>
      ((jsonDecode(body) as Map)['facilities'] as List)
          .map((Object? e) => Map<String, dynamic>.from(e as Map))
          .toList();

  group('facilityStampFromConfig', () {
    test('is version|hash of the facilities entry', () {
      expect(
        StagedArtifactLoader.facilityStampFromConfig(
          _configNaming('1.2', _v12Body),
        ),
        '1.2|${_hashOf(_v12Body)}',
      );
    });

    test('is null when config, entry, version or hash is missing', () {
      expect(StagedArtifactLoader.facilityStampFromConfig(null), isNull);
      expect(
        StagedArtifactLoader.facilityStampFromConfig(<String, dynamic>{}),
        isNull,
      );
      final Map<String, dynamic> noHash = _configNaming('1.2', _v12Body);
      ((noHash['artifacts'] as Map)['facilities'] as Map).remove('hash');
      expect(StagedArtifactLoader.facilityStampFromConfig(noHash), isNull);
      final Map<String, dynamic> noVersion = _configNaming('1.2', _v12Body);
      ((noVersion['artifacts'] as Map)['facilities'] as Map).remove('version');
      expect(StagedArtifactLoader.facilityStampFromConfig(noVersion), isNull);
    });
  });

  group('the v1.1-persists scenario', () {
    test(
      'a legacy unstamped v1.1 decoded cache is discarded once /config names v1.2',
      () async {
        // Exactly what a pre-WP-025 build leaves on disk: the decoded list
        // under the unversioned key, nothing recording its version.
        final Box<dynamic> box = await facilityBox();
        await box.put(ArtifactCacheKeys.facilityData, decoded(_v11Body));

        final List<Map<String, dynamic>> served =
            await StagedArtifactLoader.readFacilityCache(
              expectedStamp: StagedArtifactLoader.facilityStampFromConfig(
                _configNaming('1.2', _v12Body),
              ),
            );

        expect(served, isEmpty);
        expect(box.containsKey(ArtifactCacheKeys.facilityData), isFalse);
      },
    );

    test(
      'a v1.1-stamped decoded cache is discarded for a v1.2 config',
      () async {
        final Box<dynamic> box = await facilityBox();
        await box.put(ArtifactCacheKeys.facilityData, decoded(_v11Body));
        await box.put(
          ArtifactCacheKeys.facilityStamp,
          '1.1|${_hashOf(_v11Body)}',
        );

        final List<Map<String, dynamic>> served =
            await StagedArtifactLoader.readFacilityCache(
              expectedStamp: '1.2|${_hashOf(_v12Body)}',
            );

        expect(served, isEmpty);
        expect(box.containsKey(ArtifactCacheKeys.facilityData), isFalse);
        expect(box.containsKey(ArtifactCacheKeys.facilityStamp), isFalse);
      },
    );

    test(
      'same version, different hash (re-published artifact) is discarded',
      () async {
        final Box<dynamic> box = await facilityBox();
        await box.put(ArtifactCacheKeys.facilityData, decoded(_v11Body));
        await box.put(
          ArtifactCacheKeys.facilityStamp,
          '1.2|${_hashOf(_v11Body)}',
        );

        expect(
          await StagedArtifactLoader.readFacilityCache(
            expectedStamp: '1.2|${_hashOf(_v12Body)}',
          ),
          isEmpty,
        );
      },
    );

    test(
      'nothing is served when there is no /config to validate against',
      () async {
        final Box<dynamic> box = await facilityBox();
        await box.put(ArtifactCacheKeys.facilityData, decoded(_v12Body));
        await box.put(
          ArtifactCacheKeys.facilityStamp,
          '1.2|${_hashOf(_v12Body)}',
        );

        expect(
          await StagedArtifactLoader.readFacilityCache(expectedStamp: null),
          isEmpty,
        );
      },
    );

    test('end to end: v1.1 cached, /config moves to v1.2 → v1.2 is downloaded, '
        'decoded, stamped and served; v1.1 raw is purged', () async {
      // Device state left by a build that ran against facilities v1.1.
      final Box<dynamic> fBox = await facilityBox();
      await fBox.put(ArtifactCacheKeys.facilityData, decoded(_v11Body));
      final Box<dynamic> aBox = await artifactBox();
      await aBox.put('${ArtifactCacheKeys.facilities}_v1.1', _v11Body);

      final String expected = StagedArtifactLoader.facilityStampFromConfig(
        _configNaming('1.2', _v12Body),
      )!;

      // Locator: cache does not match → nothing served → download starts.
      expect(
        await StagedArtifactLoader.readFacilityCache(expectedStamp: expected),
        isEmpty,
      );

      final List<String> fetched = <String>[];
      final StagedArtifactLoader loader = StagedArtifactLoader(
        downloadOverride: (String url) async {
          fetched.add(url);
          return url.contains('v1.2') ? _v12Body : _v11Body;
        },
      );
      loader.loadFacilitiesInBackground(_facilitiesSpec('1.2', _v12Body));
      await _settled(loader);
      expect(loader.facilitiesReady.value, isTrue);
      expect(fetched.single, contains('v1.2'));

      final List<Map<String, dynamic>> served =
          await StagedArtifactLoader.readFacilityCache(expectedStamp: expected);
      expect(served.single['name'], 'Current Clinic');
      expect(
        served.where(
          (Map<String, dynamic> f) => f['name'] == 'Withdrawn Clinic',
        ),
        isEmpty,
      );
      expect(aBox.containsKey('${ArtifactCacheKeys.facilities}_v1.1'), isFalse);
      expect(aBox.containsKey('${ArtifactCacheKeys.facilities}_v1.2'), isTrue);
    });
  });

  group('raw artifact purge', () {
    test(
      'purges superseded facilities versions only — clinical versions are kept for rollback',
      () async {
        final Box<dynamic> aBox = await artifactBox();
        await aBox.putAll(<String, dynamic>{
          '${ArtifactCacheKeys.facilities}_v1.0': 'old',
          '${ArtifactCacheKeys.facilities}_v1.1': _v11Body,
          '${ArtifactCacheKeys.kb}_v2.3': '{"conditions": []}',
          '${ArtifactCacheKeys.kb}_v2.4': '{"conditions": []}',
          '${ArtifactCacheKeys.rules}_v2.1': '{"rules": []}',
          '${ArtifactCacheKeys.tokenDict}_v1.0': '{"tokens": {}}',
        });

        final StagedArtifactLoader loader = StagedArtifactLoader(
          downloadOverride: (String url) async => _v12Body,
        );
        loader.loadFacilitiesInBackground(_facilitiesSpec('1.2', _v12Body));
        await _settled(loader);

        expect(aBox.keys.toSet(), <String>{
          '${ArtifactCacheKeys.facilities}_v1.2',
          '${ArtifactCacheKeys.kb}_v2.3',
          '${ArtifactCacheKeys.kb}_v2.4',
          '${ArtifactCacheKeys.rules}_v2.1',
          '${ArtifactCacheKeys.tokenDict}_v1.0',
        });
      },
    );

    test('a failed download purges nothing and leaves no stamp', () async {
      final Box<dynamic> aBox = await artifactBox();
      await aBox.put('${ArtifactCacheKeys.facilities}_v1.1', _v11Body);

      final StagedArtifactLoader loader = StagedArtifactLoader(
        maxRetries: 1,
        backoffDurations: const <Duration>[Duration(milliseconds: 1)],
        downloadOverride: (String url) async => throw Exception('offline'),
      );
      loader.loadFacilitiesInBackground(_facilitiesSpec('1.2', _v12Body));
      await _settled(loader);

      expect(loader.facilitiesFailed.value, isTrue);
      expect(aBox.containsKey('${ArtifactCacheKeys.facilities}_v1.1'), isTrue);
      final Box<dynamic> fBox = await facilityBox();
      expect(fBox.containsKey(ArtifactCacheKeys.facilityStamp), isFalse);
    });
  });

  group('download deduplication is per version+hash', () {
    test(
      'a start for a new version after a finished one downloads again',
      () async {
        final List<String> fetched = <String>[];
        final StagedArtifactLoader loader = StagedArtifactLoader(
          downloadOverride: (String url) async {
            fetched.add(url);
            return url.contains('v1.2') ? _v12Body : _v11Body;
          },
        );

        loader.loadFacilitiesInBackground(_facilitiesSpec('1.1', _v11Body));
        await _settled(loader);
        // Same spec again: ignored, as before.
        loader.loadFacilitiesInBackground(_facilitiesSpec('1.1', _v11Body));
        expect(fetched, hasLength(1));

        // /config moved on within the same run (e.g. locator opened later).
        loader.loadFacilitiesInBackground(_facilitiesSpec('1.2', _v12Body));
        expect(loader.facilitiesReady.value, isFalse);
        await _settled(loader);

        expect(fetched, hasLength(2));
        final List<Map<String, dynamic>> served =
            await StagedArtifactLoader.readFacilityCache(
              expectedStamp: '1.2|${_hashOf(_v12Body)}',
            );
        expect(served.single['name'], 'Current Clinic');
      },
    );

    test(
      'a superseded in-flight download cannot overwrite the newer one',
      () async {
        final Completer<String> slowV11 = Completer<String>();
        final StagedArtifactLoader loader = StagedArtifactLoader(
          downloadOverride: (String url) => url.contains('v1.1')
              ? slowV11.future
              : Future<String>.value(_v12Body),
        );

        loader.loadFacilitiesInBackground(_facilitiesSpec('1.1', _v11Body));
        loader.loadFacilitiesInBackground(_facilitiesSpec('1.2', _v12Body));
        await _settled(loader);
        slowV11.complete(_v11Body);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final Box<dynamic> fBox = await facilityBox();
        expect(
          fBox.get(ArtifactCacheKeys.facilityStamp),
          '1.2|${_hashOf(_v12Body)}',
        );
        expect(
          ((fBox.get(ArtifactCacheKeys.facilityData) as List).single
              as Map)['name'],
          'Current Clinic',
        );
      },
    );
  });
}
