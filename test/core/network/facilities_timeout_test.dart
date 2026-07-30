import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wellapath_mobile/core/network/staged_artifact_loader.dart';

/// Facilities is ~1.7MB against ~102KB for the largest core artifact. At the
/// shared 15s per-attempt cap it could not complete below roughly 900kbps, so
/// EDGE and marginal 3G failed every attempt and the locator showed "could
/// not load" instead of downloading slowly.
///
/// Measured: 384kbps `umts` needs ~35s for 1.7MB, 240kbps `edge` ~56s.
/// Facilities now gets 90s; core artifacts stay at 15s.
///
/// The timings below are the real ratio scaled down 100x so the suite stays
/// fast: 350ms stands in for the 35s download, 150ms for the old 15s cap,
/// 900ms for the new 90s one. `fakeAsync` is not usable here — `_loadFacilities`
/// opens a Hive box, and that real file I/O does not advance under a fake
/// clock.

const String _facilitiesBody = '{"facilities":[]}';

/// Stands in for a slow connection: returns only after [delay].
Future<String> Function(String) _slowDownload(Duration delay) =>
    (String url) async {
      await Future<void>.delayed(delay);
      return _facilitiesBody;
    };

const ArtifactSpec _facilitiesSpec = ArtifactSpec(
  url: 'https://example.test/facilities.ng.v1.1.json',
  cacheKey: ArtifactCacheKeys.facilities,
  version: '1.1',
);

/// Resolves once the background download reports success or failure.
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
  await done.future.timeout(const Duration(seconds: 20));
  loader.facilitiesReady.removeListener(check);
  loader.facilitiesFailed.removeListener(check);
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('facilities_timeout_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'a slow facilities download completes within the longer timeout',
    () async {
      // The case that used to fail: a download longer than the core cap.
      final StagedArtifactLoader loader = StagedArtifactLoader(
        facilitiesPerAttemptTimeout: const Duration(milliseconds: 900),
        downloadOverride: _slowDownload(const Duration(milliseconds: 350)),
      );

      loader.loadFacilitiesInBackground(_facilitiesSpec);
      await _settled(loader);

      expect(
        loader.facilitiesReady.value,
        isTrue,
        reason: 'a 35s-equivalent download must succeed under the 90s cap',
      );
      expect(loader.facilitiesFailed.value, isFalse);
    },
  );

  test('the same download fails at the old core-artifact cap', () async {
    // Pins why the override exists — identical download, 15s-equivalent cap.
    final StagedArtifactLoader loader = StagedArtifactLoader(
      facilitiesPerAttemptTimeout: const Duration(milliseconds: 150),
      backoffDurations: const <Duration>[
        Duration(milliseconds: 10),
        Duration(milliseconds: 10),
        Duration(milliseconds: 10),
      ],
      downloadOverride: _slowDownload(const Duration(milliseconds: 350)),
    );

    loader.loadFacilitiesInBackground(_facilitiesSpec);
    await _settled(loader);

    expect(loader.facilitiesFailed.value, isTrue);
    expect(loader.facilitiesReady.value, isFalse);
  });

  test(
    'a download slower than the cap still fails rather than hanging',
    () async {
      // The E9 indefinite-hang fix must survive the longer cap.
      final StagedArtifactLoader loader = StagedArtifactLoader(
        facilitiesPerAttemptTimeout: const Duration(milliseconds: 100),
        backoffDurations: const <Duration>[
          Duration(milliseconds: 10),
          Duration(milliseconds: 10),
          Duration(milliseconds: 10),
        ],
        downloadOverride: _slowDownload(const Duration(seconds: 30)),
      );

      loader.loadFacilitiesInBackground(_facilitiesSpec);
      await _settled(loader);

      expect(loader.facilitiesFailed.value, isTrue);
    },
  );

  test('core artifacts keep the 15s cap; facilities defaults to 90s', () {
    final StagedArtifactLoader loader = StagedArtifactLoader();

    expect(loader.perAttemptTimeout, const Duration(seconds: 15));
    expect(loader.facilitiesPerAttemptTimeout, const Duration(seconds: 90));
  });
}
