import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'retry_with_backoff.dart';

/// Hive box/key names shared by [StagedArtifactLoader] and any screen that
/// reads the artifacts it caches (loading_screen.dart, locator_screen.dart).
class ArtifactCacheKeys {
  static const String artifactBox = 'artifact_cache';
  static const String kb = 'artifact_kb';
  static const String rules = 'artifact_rules';
  static const String tokenDict = 'artifact_token_dict';
  static const String facilities = 'artifact_facilities';

  static const String facilityBox = 'facility_cache';
  static const String facilityData = 'facilities_data';
}

/// One entry from `/config`'s `artifacts` map: where to fetch it, which
/// version/hash to cache it under, and the integrity hash to verify against.
class ArtifactSpec {
  final String url;
  final String cacheKey;
  final String version;
  final String? hash;

  const ArtifactSpec({
    required this.url,
    required this.cacheKey,
    required this.version,
    this.hash,
  });
}

/// The three artifacts the engine needs to run a single assessment.
/// Facilities are intentionally not part of this — they are the largest
/// artifact and are not needed until the user taps "Find Nearby Care", so
/// they are loaded separately in the background (see
/// [StagedArtifactLoader.loadFacilitiesInBackground]).
class CoreArtifacts {
  final List<Map<String, dynamic>> conditions;
  final List<Map<String, dynamic>> rules;
  final Map<String, dynamic> tokenDictionary;

  const CoreArtifacts({
    required this.conditions,
    required this.rules,
    required this.tokenDictionary,
  });
}

/// Thrown when a core artifact could not be downloaded after all retries —
/// i.e. this is the user's first launch (or first assessment after a version
/// bump) and there is no usable network. Distinct from a hash-integrity
/// failure ([StateError]), which is a corrupted artifact, not a connectivity
/// problem, and should not show the same "please connect" messaging.
class FirstLaunchOfflineException implements Exception {
  final String message;

  const FirstLaunchOfflineException([
    this.message =
        'WellaPath needs a brief internet connection the first time. '
        'Please connect and try again.',
  ]);

  @override
  String toString() => message;
}

/// Progress through the 4-artifact staged download: token dictionary, rules
/// and knowledge base (the 3 "core" artifacts, downloaded in parallel) count
/// as steps 1-3; facilities (downloaded last, in the background, non-blocking
/// for the assessment) is step 4.
class BootProgress {
  final int step;
  final int totalSteps;

  const BootProgress({required this.step, this.totalSteps = 4});

  String get label => 'Setting up WellaPath... ($step of $totalSteps)';

  @override
  bool operator ==(Object other) =>
      other is BootProgress &&
      other.step == step &&
      other.totalSteps == totalSteps;

  @override
  int get hashCode => Object.hash(step, totalSteps);
}

/// Drives the staged, progressive artifact download pipeline used at
/// assessment time:
///
/// 1. The 3 core artifacts (token dictionary, rules, knowledge base) are
///    downloaded in parallel — small files, needed before the engine can
///    run a single assessment.
/// 2. Facilities (the largest artifact, only needed if the user opens the
///    locator) are downloaded afterwards, in the background, and never
///    block [loadCoreArtifacts] from returning.
/// 3. Every network download retries with exponential backoff (2s/4s/8s)
///    before giving up — a single slow/dropped request on a poor
///    connection should not immediately fail the whole assessment.
/// 4. If all retries on a core artifact are exhausted, [loadCoreArtifacts]
///    throws [FirstLaunchOfflineException] so the caller can show a
///    dedicated first-launch-offline screen instead of the generic error.
///
/// A single instance is shared across the app (see [instance]) so that a
/// screen opened after [loadCoreArtifacts] returns (e.g. the facility
/// locator) can observe whether the background facilities download is
/// still in flight, already done, or has failed.
class StagedArtifactLoader {
  StagedArtifactLoader({
    Dio? dio,
    this.maxRetries = 3,
    List<Duration>? backoffDurations,
    this.perAttemptTimeout = const Duration(seconds: 15),
    this.facilitiesPerAttemptTimeout = const Duration(seconds: 90),
    Future<String> Function(String url)? downloadOverride,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 30),
             ),
           ),
       backoffDurations =
           backoffDurations ??
           const [
             Duration(seconds: 2),
             Duration(seconds: 4),
             Duration(seconds: 8),
           ],
       _downloadOverride = downloadOverride;

  /// Shared app-wide instance. `loading_screen.dart` kicks off the download
  /// through this instance; `locator_screen.dart` observes
  /// [facilitiesReady]/[facilitiesFailed] on the same instance to know
  /// whether it can show the map immediately or must show a loading state.
  static StagedArtifactLoader instance = StagedArtifactLoader();

  final Dio _dio;
  final int maxRetries;
  final List<Duration> backoffDurations;

  /// A hard wall-clock cap on a single download attempt, independent of
  /// Dio's own `receiveTimeout`. `receiveTimeout` only measures the gap
  /// *between* received chunks, not total transfer duration — a connection
  /// trickling data very slowly under heavy throttling can keep resetting
  /// that gap forever and never actually time out. Without this, a single
  /// stalled-but-technically-still-receiving request can hang indefinitely,
  /// which is exactly what E8.4 found under a throttled 3G profile: a ~7
  /// minute hang with no eventual success or failure. Wrapping every
  /// attempt in this timeout guarantees the retry loop (and eventually
  /// [FirstLaunchOfflineException]) actually engages instead of hanging
  /// forever.
  ///
  /// Default of 15s gives the largest of the 3 core artifacts (the
  /// knowledge base, ~100KB) a realistic window under a contended
  /// `umts`-class 384kbps link shared across 3 parallel downloads — pure
  /// bandwidth math puts that around 6-8s, plus TLS/latency overhead. An
  /// 8s cap measured on-device was too tight even for the ~29KB rules
  /// file. See PROGRESS.md (Phase E9) for the on-device measurements this
  /// value is based on, including a finding that the harshest observed
  /// `umts` conditions still exceeded 15s for artifacts above ~10KB.
  final Duration perAttemptTimeout;

  /// Per-attempt cap for the facilities artifact alone.
  ///
  /// Facilities is ~1.7MB against ~102KB for the largest core artifact — 17x
  /// bigger, inheriting a cap tuned for the small ones. At 15s it cannot
  /// complete below roughly 900kbps, so EDGE and marginal 3G failed every
  /// attempt and the locator showed "could not load" rather than downloading
  /// slowly. Measured: 384kbps `umts` needs ~35s, 240kbps `edge` ~56s.
  ///
  /// 90s covers real Nigerian 3G with headroom. It is safe to wait that long
  /// here in a way it is not for the core artifacts: facilities downloads in
  /// the background and blocks only the locator, which now shows a
  /// determinate progress bar, so the user can see the wait is productive.
  /// The core artifacts stay at 15s — they gate the assessment result, and
  /// the E9 hang fix depends on that cap staying tight.
  final Duration facilitiesPerAttemptTimeout;

  final Future<String> Function(String url)? _downloadOverride;

  final ValueNotifier<BootProgress> progress = ValueNotifier(
    const BootProgress(step: 0),
  );

  /// Download progress for the facilities artifact, 0.0–1.0.
  ///
  /// Null means the size is not known yet — either the download has not
  /// started, or the server sent no `Content-Length`, in which case the UI
  /// should stay indeterminate rather than invent a number.
  ///
  /// Only facilities are tracked: it is ~1.7MB and, since the locator can now
  /// be opened directly from home, its download is the one a user actually
  /// sits and waits through. The three core artifacts total ~140KB and are
  /// already covered by the step-based [progress].
  final ValueNotifier<double?> facilitiesProgress = ValueNotifier(null);

  final ValueNotifier<bool> facilitiesReady = ValueNotifier(false);

  /// True once a facilities download has been kicked off in this app run.
  ///
  /// Facilities can now be started from two places — the assessment loading
  /// screen, and the locator opened directly from home — and the artifact is
  /// ~1.7MB, so starting it twice is worth avoiding.
  bool get facilitiesDownloadStarted => _facilitiesDownloadStarted;
  bool _facilitiesDownloadStarted = false;
  final ValueNotifier<bool> facilitiesFailed = ValueNotifier(false);

  Future<String> _attemptDownload(
    String url, {
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    if (_downloadOverride != null) return await _downloadOverride(url);
    final response = await _dio.get<dynamic>(
      url,
      options: Options(responseType: ResponseType.plain),
      onReceiveProgress: onReceiveProgress,
    );
    return response.data as String;
  }

  Future<String> _downloadWithBackoff(
    String url, {
    void Function(int received, int total)? onReceiveProgress,
    Duration? timeoutOverride,
  }) {
    return retryWithBackoff<String>(
      // Each retry restarts the transfer, so the byte count restarts too —
      // the callback naturally reports from 0 again on a new attempt.
      attempt: () =>
          _attemptDownload(url, onReceiveProgress: onReceiveProgress),
      maxRetries: maxRetries,
      backoffDurations: backoffDurations,
      perAttemptTimeout: timeoutOverride ?? perAttemptTimeout,
    );
  }

  bool _matchesHash(String rawBody, String? expectedHash) {
    if (expectedHash == null || expectedHash.isEmpty) return true;
    final expectedHex = expectedHash.startsWith('sha256:')
        ? expectedHash.substring('sha256:'.length)
        : expectedHash;
    final actualHex = sha256.convert(utf8.encode(rawBody)).toString();
    return actualHex.toLowerCase() == expectedHex.toLowerCase();
  }

  /// Reads [spec] from [box], falling back to a network download (with
  /// backoff retry on network failure, and a single retry on hash-integrity
  /// failure) when there is no valid cached copy. Mirrors the pre-E9
  /// `_loadArtifact` behaviour in `loading_screen.dart` — same cache-key
  /// versioning, same hash-verification-on-every-read semantics — with
  /// network retries layered on top.
  Future<Map<String, dynamic>> _loadArtifact(
    Box<dynamic> box,
    ArtifactSpec spec, {
    void Function(int received, int total)? onReceiveProgress,
    Duration? timeoutOverride,
  }) async {
    final versionedKey = '${spec.cacheKey}_v${spec.version}';
    final cachedRaw = box.get(versionedKey) as String?;

    if (cachedRaw != null) {
      if (_matchesHash(cachedRaw, spec.hash)) {
        return Map<String, dynamic>.from(jsonDecode(cachedRaw) as Map);
      }
      debugPrint(
        'Artifact integrity check failed for cached ${spec.cacheKey} — discarding and re-downloading',
      );
      await box.delete(versionedKey);
    }

    for (var attempt = 1; attempt <= 2; attempt++) {
      final rawBody = await _downloadWithBackoff(
        spec.url,
        onReceiveProgress: onReceiveProgress,
        timeoutOverride: timeoutOverride,
      );

      if (_matchesHash(rawBody, spec.hash)) {
        await box.put(versionedKey, rawBody);
        return Map<String, dynamic>.from(jsonDecode(rawBody) as Map);
      }

      debugPrint(
        'Artifact integrity check failed for downloaded ${spec.cacheKey} (attempt $attempt) — rejecting',
      );
    }

    throw StateError('Artifact integrity check failed for ${spec.cacheKey}');
  }

  /// Downloads the 3 core artifacts in parallel. Throws
  /// [FirstLaunchOfflineException] if any of them exhausts its network
  /// retries — a hash-integrity failure ([StateError]) is left to propagate
  /// as-is, since that is a corrupted artifact, not a connectivity problem.
  Future<CoreArtifacts> loadCoreArtifacts({
    required ArtifactSpec tokenDict,
    required ArtifactSpec rules,
    required ArtifactSpec kb,
  }) async {
    progress.value = const BootProgress(step: 1);
    final box = Hive.isBoxOpen(ArtifactCacheKeys.artifactBox)
        ? Hive.box(ArtifactCacheKeys.artifactBox)
        : await Hive.openBox(ArtifactCacheKeys.artifactBox);

    var completedSteps = 0;
    Future<Map<String, dynamic>> tracked(ArtifactSpec spec) async {
      final result = await _loadArtifact(box, spec);
      completedSteps++;
      progress.value = BootProgress(step: completedSteps.clamp(1, 3));
      return result;
    }

    try {
      final results = await Future.wait([
        tracked(tokenDict),
        tracked(rules),
        tracked(kb),
      ]);

      return CoreArtifacts(
        tokenDictionary: results[0],
        rules:
            (results[1]['rules'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            const [],
        conditions:
            (results[2]['conditions'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            const [],
      );
    } on StateError {
      rethrow;
    } catch (_) {
      throw const FirstLaunchOfflineException();
    }
  }

  /// Downloads facilities in the background — does not block the caller.
  /// Flips [facilitiesReady] or [facilitiesFailed] when done, so any screen
  /// observing this same [instance] (namely the locator) can react.
  void loadFacilitiesInBackground(ArtifactSpec spec) {
    if (_facilitiesDownloadStarted) return;
    _facilitiesDownloadStarted = true;
    unawaited(_loadFacilities(spec));
  }

  Future<void> _loadFacilities(ArtifactSpec spec) async {
    progress.value = const BootProgress(step: 4);
    try {
      final artifactBox = Hive.isBoxOpen(ArtifactCacheKeys.artifactBox)
          ? Hive.box(ArtifactCacheKeys.artifactBox)
          : await Hive.openBox(ArtifactCacheKeys.artifactBox);
      final data = await _loadArtifact(
        artifactBox,
        spec,
        timeoutOverride: facilitiesPerAttemptTimeout,
        onReceiveProgress: (int received, int total) {
          // total is -1 when the server sends no Content-Length. Leave the
          // notifier null in that case so the UI stays indeterminate rather
          // than showing a bar that cannot fill.
          facilitiesProgress.value = total > 0 ? received / total : null;
        },
      );
      final list =
          (data['facilities'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[];

      final facilityBox = Hive.isBoxOpen(ArtifactCacheKeys.facilityBox)
          ? Hive.box(ArtifactCacheKeys.facilityBox)
          : await Hive.openBox(ArtifactCacheKeys.facilityBox);
      await facilityBox.put(ArtifactCacheKeys.facilityData, list);
      facilitiesProgress.value = 1.0;
      facilitiesReady.value = true;
    } catch (_) {
      debugPrint(
        'Facilities background download failed — locator will show empty state',
      );
      facilitiesFailed.value = true;
    }
  }

  /// Resets progress/ready/failed state for a new assessment run. Does not
  /// touch cached data — only the in-memory notifiers driving UI.
  void reset() {
    progress.value = const BootProgress(step: 0);
    facilitiesReady.value = false;
    facilitiesFailed.value = false;
    facilitiesProgress.value = null;
    _facilitiesDownloadStarted = false;
  }
}
