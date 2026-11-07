import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wellapath_mobile/core/network/staged_artifact_loader.dart';
import 'package:wellapath_mobile/core/storage/storage_service.dart';
import 'package:wellapath_mobile/features/assessment/assessment_controller.dart';
import 'package:wellapath_mobile/features/assessment/loading_screen.dart';

/// RC-BLK-011 / WP-003: a `/config` artifact entry with a missing, empty or
/// malformed hash, or a missing version, is a hard failure. Before this the
/// loader's hash check returned true for a null/empty hash and the loading
/// screen and locator defaulted a missing version to '1.0', so such an
/// artifact was downloaded, cached and used without any integrity check.

const String _body = '{"rules": []}';

String _hashOf(String body) =>
    'sha256:${sha256.convert(utf8.encode(body)).toString()}';

/// The shape production `/config` serves today (GET
/// https://api.wellapath.org/config, 2026-11-07): every artifact has a dotted
/// numeric version and a `sha256:`-prefixed 64-hex hash.
const Map<String, dynamic> _productionShapedArtifacts = <String, dynamic>{
  'token_dictionary': <String, dynamic>{
    'version': '1.1',
    'url': 'https://example.invalid/token_dictionary.ng.v1.1.json',
    'hash':
        'sha256:0cc47ad9537c0bd4c6ef3aec8f1931eb9b4c62103a8809d16544f94a90b5c019',
  },
  'knowledge_base': <String, dynamic>{
    'version': '2.4',
    'url': 'https://example.invalid/kb.ng.v2.4.json',
    'hash':
        'sha256:6c00d8257f8417e86bd5e237630bf8a4623ad72e2e46b1b071dd447c067cec2b',
  },
  'rules': <String, dynamic>{
    'version': '2.2',
    'url': 'https://example.invalid/rules.ng.v2.2.json',
    'hash':
        'sha256:1d27e854cba95b179577a88f92445400f494a7fe8e6a53a60fcaa98b3870d1c4',
  },
  'facilities': <String, dynamic>{
    'version': '1.2',
    'url': 'https://example.invalid/facilities.ng.v1.2.json',
    'hash':
        'sha256:94f162e492fa91f7d9d3cf2ca33fcf0598a031a2510aa900aa717a581bdb7788',
  },
};

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('integrity_hard_fail_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ArtifactSpec spec(String cacheKey, {String? hash, String version = '1.0'}) =>
      ArtifactSpec(
        url: 'https://example.invalid/$cacheKey.json',
        cacheKey: cacheKey,
        version: version,
        hash: hash,
      );

  group('ArtifactSpec.fromConfigEntry never defaults metadata', () {
    test('a missing url still means "no artifact" (null), as before', () {
      expect(
        ArtifactSpec.fromConfigEntry(<String, dynamic>{
          'version': '1.0',
          'hash': _hashOf(_body),
        }, cacheKey: 'k'),
        isNull,
      );
      expect(ArtifactSpec.fromConfigEntry(null, cacheKey: 'k'), isNull);
    });

    test('a missing version is carried as empty, not defaulted to 1.0', () {
      final ArtifactSpec? s = ArtifactSpec.fromConfigEntry(<String, dynamic>{
        'url': 'https://example.invalid/a.json',
        'hash': _hashOf(_body),
      }, cacheKey: 'k');
      expect(s!.version, isEmpty);
      expect(s.metadataProblem, 'missing version');
    });

    test('non-string version/hash are treated as missing', () {
      final ArtifactSpec? s = ArtifactSpec.fromConfigEntry(<String, dynamic>{
        'url': 'https://example.invalid/a.json',
        'version': 1.2,
        'hash': 42,
      }, cacheKey: 'k');
      expect(s!.metadataProblem, isNotNull);
    });

    test(
      'every production-shaped /config entry passes validation unchanged',
      () {
        // Evidence that today's user-visible behaviour is unaffected: live
        // /config supplies a well-formed version and sha256 for all four.
        for (final MapEntry<String, dynamic> e
            in _productionShapedArtifacts.entries) {
          final ArtifactSpec? s = ArtifactSpec.fromConfigEntry(
            e.value,
            cacheKey: e.key,
          );
          expect(s, isNotNull, reason: e.key);
          expect(s!.metadataProblem, isNull, reason: e.key);
          expect(s.version, (e.value as Map)['version'], reason: e.key);
        }
      },
    );
  });

  group('metadataProblem', () {
    test('accepts sha256:-prefixed and bare 64-hex hashes', () {
      expect(spec('k', hash: _hashOf(_body)).metadataProblem, isNull);
      expect(
        spec('k', hash: _hashOf(_body).substring(7)).metadataProblem,
        isNull,
      );
    });

    test('rejects missing, empty and malformed hashes and versions', () {
      expect(spec('k').metadataProblem, 'missing hash');
      expect(spec('k', hash: '').metadataProblem, 'missing hash');
      expect(spec('k', hash: 'sha256:abc').metadataProblem, 'malformed hash');
      expect(
        spec('k', hash: 'md5:${'0' * 64}').metadataProblem,
        'malformed hash',
      );
      expect(
        spec('k', hash: _hashOf(_body), version: '').metadataProblem,
        'missing version',
      );
      expect(
        spec('k', hash: _hashOf(_body), version: 'latest').metadataProblem,
        'malformed version',
      );
    });
  });

  group('core artifacts hard-fail on bad metadata', () {
    for (final String? badHash in <String?>[null, '', 'sha256:nothex']) {
      test('rules hash ${badHash == null ? 'null' : '"$badHash"'} → '
          'ArtifactMetadataError, no download, nothing cached', () async {
        var downloads = 0;
        final StagedArtifactLoader loader = StagedArtifactLoader(
          downloadOverride: (String url) async {
            downloads++;
            return _body;
          },
        );

        await expectLater(
          () => loader.loadCoreArtifacts(
            tokenDict: spec('artifact_token_dict', hash: _hashOf(_body)),
            rules: spec('artifact_rules', hash: badHash),
            kb: spec('artifact_kb', hash: _hashOf(_body)),
          ),
          // A StateError subtype, so loading_screen.dart routes it to its
          // existing integrity-failure view, not the offline one.
          throwsA(
            isA<ArtifactMetadataError>().having(
              (ArtifactMetadataError e) => e,
              'is StateError',
              isA<StateError>(),
            ),
          ),
        );
        expect(downloads, 0);
        final Box<dynamic> box = await Hive.openBox(
          ArtifactCacheKeys.artifactBox,
        );
        expect(box.isEmpty, isTrue);
      });
    }

    test('a missing version is rejected rather than cached as v1.0', () async {
      final StagedArtifactLoader loader = StagedArtifactLoader(
        downloadOverride: (String url) async => _body,
      );
      await expectLater(
        () => loader.loadCoreArtifacts(
          tokenDict: spec('artifact_token_dict', hash: _hashOf(_body)),
          rules: spec('artifact_rules', hash: _hashOf(_body)),
          kb: spec('artifact_kb', hash: _hashOf(_body), version: ''),
        ),
        throwsA(isA<ArtifactMetadataError>()),
      );
      final Box<dynamic> box = await Hive.openBox(
        ArtifactCacheKeys.artifactBox,
      );
      expect(box.containsKey('artifact_kb_v1.0'), isFalse);
      expect(box.containsKey('artifact_kb_v'), isFalse);
    });

    test(
      'an already-cached copy is not served when /config has no hash',
      () async {
        final Box<dynamic> box = await Hive.openBox(
          ArtifactCacheKeys.artifactBox,
        );
        await box.put('artifact_rules_v1.0', _body);

        final StagedArtifactLoader loader = StagedArtifactLoader(
          downloadOverride: (String url) async => _body,
        );
        await expectLater(
          () => loader.loadCoreArtifacts(
            tokenDict: spec('artifact_token_dict', hash: _hashOf(_body)),
            rules: spec('artifact_rules'),
            kb: spec('artifact_kb', hash: _hashOf(_body)),
          ),
          throwsA(isA<ArtifactMetadataError>()),
        );
      },
    );
  });

  group('facilities hard-fail on bad metadata', () {
    Future<void> settled(StagedArtifactLoader loader) async {
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
    }

    for (final String? badHash in <String?>[null, '', 'sha256:zz']) {
      test(
        'hash ${badHash == null ? 'null' : '"$badHash"'} → facilitiesFailed, '
        'decoded list not written',
        () async {
          var downloads = 0;
          final StagedArtifactLoader loader = StagedArtifactLoader(
            downloadOverride: (String url) async {
              downloads++;
              return '{"facilities": [{"name": "Unverified Clinic"}]}';
            },
          );

          loader.loadFacilitiesInBackground(
            spec(ArtifactCacheKeys.facilities, hash: badHash),
          );
          await settled(loader);

          expect(loader.facilitiesFailed.value, isTrue);
          expect(loader.facilitiesReady.value, isFalse);
          expect(downloads, 0);
          final Box<dynamic> facilityBox = await Hive.openBox(
            ArtifactCacheKeys.facilityBox,
          );
          expect(facilityBox.get(ArtifactCacheKeys.facilityData), isNull);
        },
      );
    }

    test(
      'the locator path (spec built from a config entry with no version) fails closed',
      () async {
        // locator_screen.dart builds its spec through fromConfigEntry; this is
        // the exact entry shape that used to be defaulted to version '1.0'.
        final ArtifactSpec? s = ArtifactSpec.fromConfigEntry(<String, dynamic>{
          'url': 'https://example.invalid/facilities.json',
          'hash': _hashOf('{"facilities": []}'),
        }, cacheKey: ArtifactCacheKeys.facilities);
        final StagedArtifactLoader loader = StagedArtifactLoader(
          downloadOverride: (String url) async => '{"facilities": []}',
        );
        loader.loadFacilitiesInBackground(s!);
        await settled(loader);
        expect(loader.facilitiesFailed.value, isTrue);
      },
    );
  });

  group(
    'loading screen surfaces bad metadata through the existing error view',
    () {
      late StagedArtifactLoader previous;

      setUp(() => previous = StagedArtifactLoader.instance);
      tearDown(() => StagedArtifactLoader.instance = previous);

      testWidgets('missing rules hash in cached /config → existing error view', (
        WidgetTester tester,
      ) async {
        await tester.runAsync(() async {
          await Hive.openBox('config_cache');
          final Map<String, dynamic> artifacts = <String, dynamic>{
            for (final MapEntry<String, dynamic> e
                in _productionShapedArtifacts.entries)
              e.key: Map<String, dynamic>.from(e.value as Map),
          };
          (artifacts['rules'] as Map<String, dynamic>).remove('hash');
          await StorageService.saveConfig(<String, dynamic>{
            'version': '1.0',
            'artifacts': artifacts,
          });
        });

        var downloads = 0;
        StagedArtifactLoader.instance = StagedArtifactLoader(
          downloadOverride: (String url) async {
            downloads++;
            return '{}';
          },
        );

        final AssessmentController controller = AssessmentController()
          ..addSymptomToken('fever');

        await tester.pumpWidget(
          MaterialApp(
            home: LoadingScreen(
              assessmentController: controller,
              onCancel: () {},
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 800)),
        );
        await tester.pump(const Duration(seconds: 2));

        expect(
          find.text(
            'Something went wrong running your assessment.\nPlease try again.',
          ),
          findsOneWidget,
        );
        expect(downloads, 0);
      });
    },
  );
}
