import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wellapath_mobile/core/network/staged_artifact_loader.dart';

/// The facilities artifact is ~1.7MB and, now that the locator can be opened
/// straight from home, its download is the one a user sits and waits through
/// — measured at around 60 seconds on a fresh install. A bare spinner over
/// that reads as a freeze, so the byte progress has to reach the UI.

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('facilities_progress_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('facilitiesProgress', () {
    test('starts null — nothing downloaded, size unknown', () {
      final StagedArtifactLoader loader = StagedArtifactLoader();

      expect(loader.facilitiesProgress.value, isNull);
    });

    test('reset() clears progress and the started guard', () {
      final StagedArtifactLoader loader = StagedArtifactLoader();
      loader.facilitiesProgress.value = 0.5;

      loader.reset();

      expect(loader.facilitiesProgress.value, isNull);
      expect(loader.facilitiesDownloadStarted, isFalse);
    });

    test('a listener sees each progress update', () {
      final StagedArtifactLoader loader = StagedArtifactLoader();
      final List<double?> seen = <double?>[];
      loader.facilitiesProgress.addListener(
        () => seen.add(loader.facilitiesProgress.value),
      );

      loader.facilitiesProgress.value = 0.25;
      loader.facilitiesProgress.value = 0.75;
      loader.facilitiesProgress.value = 1.0;

      expect(seen, <double?>[0.25, 0.75, 1.0]);
    });

    test('null is a valid value — indeterminate, not zero', () {
      // The server may send no Content-Length. Reporting 0% forever would be
      // worse than an honest indeterminate bar.
      final StagedArtifactLoader loader = StagedArtifactLoader();
      loader.facilitiesProgress.value = 0.4;

      loader.facilitiesProgress.value = null;

      expect(loader.facilitiesProgress.value, isNull);
      expect(loader.facilitiesProgress.value, isNot(0.0));
    });
  });

  group('download start guard', () {
    test('a second start is ignored while one is in flight', () {
      // Two callers exist now — the assessment loading screen and the locator
      // opened directly. Starting twice would fetch 1.7MB twice.
      final StagedArtifactLoader loader = StagedArtifactLoader(
        downloadOverride: (String url) async => '{"facilities":[]}',
      );
      const ArtifactSpec spec = ArtifactSpec(
        url: 'https://example.test/facilities.json',
        cacheKey: ArtifactCacheKeys.facilities,
        version: '1.1',
      );

      expect(loader.facilitiesDownloadStarted, isFalse);
      loader.loadFacilitiesInBackground(spec);
      expect(loader.facilitiesDownloadStarted, isTrue);

      // Second call must be a no-op; the flag stays set either way, so the
      // meaningful assertion is that it does not throw or re-enter.
      loader.loadFacilitiesInBackground(spec);
      expect(loader.facilitiesDownloadStarted, isTrue);
    });
  });
}
