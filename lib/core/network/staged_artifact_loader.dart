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

  /// `<version>|<hash>` of the facilities artifact [facilityData] was decoded
  /// from. The decoded list is served only while this matches what the
  /// cached `/config` currently names (WP-025).
  static const String facilityStamp = 'facilities_stamp';
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

  /// Builds a spec from one `/config` `artifacts` entry.
  ///
  /// Returns null only when the entry has no `url` (nothing to fetch). A
  /// missing or non-string `version`/`hash` is carried through as-is —
  /// never defaulted — so [StagedArtifactLoader] rejects it as an
  /// [ArtifactMetadataError] instead of caching an unverified artifact under
  /// an invented version (RC-BLK-011).
  static ArtifactSpec? fromConfigEntry(
    Object? entry, {
    required String cacheKey,
  }) {
    if (entry is! Map) return null;
    final url = entry['url'];
    if (url is! String) return null;
    final version = entry['version'];
    final hash = entry['hash'];
    return ArtifactSpec(
      url: url,
      cacheKey: cacheKey,
      version: version is String ? version : '',
      hash: hash is String ? hash : null,
    );
  }

  /// `sha256:<64 hex>` (the form `/config` serves) or bare 64-char hex.
  static final RegExp _hashPattern = RegExp(r'^(sha256:)?[0-9a-fA-F]{64}$');

  /// Dotted numeric version, e.g. `1.2` or `2.4.1`.
  static final RegExp _versionPattern = RegExp(r'^[0-9]+(\.[0-9]+)*$');

  /// Why this spec cannot be trusted, or null when its integrity metadata is
  /// well-formed. A missing, empty or malformed hash or version is never
  /// acceptable: the artifact would be used without verification.
  String? get metadataProblem {
    final h = hash;
    if (h == null || h.isEmpty) return 'missing hash';
    if (!_hashPattern.hasMatch(h)) return 'malformed hash';
    if (version.isEmpty) return 'missing version';
    if (!_versionPattern.hasMatch(version)) return 'malformed version';
    return null;
  }
}

/// Thrown when a `/config` artifact entry lacks a well-formed integrity hash
/// or version. A [StateError] so it takes the same path as a hash mismatch:
/// the artifact is neither cached nor used, and the caller shows its
/// existing integrity-failure state — never the "please connect" one.
class ArtifactMetadataError extends StateError {
  ArtifactMetadataError(String cacheKey, String problem)
    : super('Artifact metadata invalid for $cacheKey: $problem');
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
    this.firstByteTimeout = const Duration(seconds: 20),
    Future<String> Function(String url)? downloadOverride,
    Future<String> Function(String url, void Function(int, int) emitProgress)?
    progressDownloadOverride,
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
       _downloadOverride = downloadOverride,
       _progressDownloadOverride = progressDownloadOverride;

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

  /// How long an attempt may go without receiving a single byte.
  ///
  /// The 90s facilities cap is there so a transfer that is genuinely moving
  /// has time to finish. On a dead connection nothing moves, and waiting out
  /// 3 x 90s plus backoff means ~4.5 minutes before the user is told
  /// anything. This separates the two cases: no bytes at all inside this
  /// window fails the attempt straight away, while a transfer that has
  /// started keeps the full cap.
  ///
  /// Distinct from Dio's `receiveTimeout`, which measures the gap *between*
  /// chunks and so only covers a stall after the first byte has arrived.
  /// Nothing covered the never-starts case.
  final Duration firstByteTimeout;

  final Future<String> Function(String url)? _downloadOverride;

  /// Test seam for a fake download that reports byte progress, so the
  /// first-byte guard can be exercised. [_downloadOverride] cannot report
  /// progress, which means a download faked through it looks like a
  /// zero-progress connection to the guard.
  final Future<String> Function(String url, void Function(int, int))?
  _progressDownloadOverride;

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

  /// Stamp of the spec the current/last facilities download was started for.
  /// A start for a different version+hash is not deduplicated against it.
  String? _facilitiesStartedStamp;
  final ValueNotifier<bool> facilitiesFailed = ValueNotifier(false);

  Future<String> _attemptDownload(
    String url, {
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    if (_progressDownloadOverride != null) {
      return await _progressDownloadOverride(
        url,
        (int received, int total) => onReceiveProgress?.call(received, total),
      );
    }
    if (_downloadOverride != null) return await _downloadOverride(url);
    final response = await _dio.get<dynamic>(
      url,
      options: Options(responseType: ResponseType.plain),
      onReceiveProgress: onReceiveProgress,
    );
    return response.data as String;
  }

  /// Runs one attempt, failing early if not a single byte arrives within
  /// [firstByteTimeout]. Once any byte has been received the guard stands
  /// down and the outer per-attempt cap takes over.
  Future<String> _attemptWithFirstByteGuard(
    String url, {
    void Function(int received, int total)? onReceiveProgress,
  }) {
    var receivedAnyBytes = false;
    final completer = Completer<String>();

    final guard = Timer(firstByteTimeout, () {
      if (!receivedAnyBytes && !completer.isCompleted) {
        completer.completeError(
          TimeoutException('No data received within $firstByteTimeout'),
        );
      }
    });

    unawaited(
      _attemptDownload(
        url,
        onReceiveProgress: (int received, int total) {
          if (received > 0) receivedAnyBytes = true;
          onReceiveProgress?.call(received, total);
        },
      ).then(
        (String body) {
          if (!completer.isCompleted) completer.complete(body);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
      ),
    );

    return completer.future.whenComplete(guard.cancel);
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
          _attemptWithFirstByteGuard(url, onReceiveProgress: onReceiveProgress),
      maxRetries: maxRetries,
      backoffDurations: backoffDurations,
      perAttemptTimeout: timeoutOverride ?? perAttemptTimeout,
    );
  }

  /// Fails closed: a null, empty or malformed expected hash never matches.
  /// Before RC-BLK-011 a null/empty hash returned true, so an artifact whose
  /// `/config` entry carried no hash was cached and used unverified.
  bool _matchesHash(String rawBody, String? expectedHash) {
    if (expectedHash == null ||
        !ArtifactSpec._hashPattern.hasMatch(expectedHash)) {
      return false;
    }
    final expectedHex = expectedHash.startsWith('sha256:')
        ? expectedHash.substring('sha256:'.length)
        : expectedHash;
    final actualHex = sha256.convert(utf8.encode(rawBody)).toString();
    return actualHex.toLowerCase() == expectedHex.toLowerCase();
  }

  /// Throws [ArtifactMetadataError] before any cache read or download when
  /// [spec] has no well-formed hash/version, so nothing unverifiable is ever
  /// cached or served.
  void _requireValidMetadata(ArtifactSpec spec) {
    final problem = spec.metadataProblem;
    if (problem == null) return;
    debugPrint('Artifact metadata invalid for ${spec.cacheKey} — rejecting');
    throw ArtifactMetadataError(spec.cacheKey, problem);
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
    _requireValidMetadata(spec);
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
    // Checked up front, not inside the parallel downloads, so a bad /config
    // entry deterministically surfaces as an integrity failure rather than
    // racing a network error on another artifact.
    _requireValidMetadata(tokenDict);
    _requireValidMetadata(rules);
    _requireValidMetadata(kb);
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
  ///
  /// A repeat call for the same version+hash is ignored (the artifact is
  /// ~1.7MB). A call for a different version+hash — `/config` moved on since
  /// the last download in this run — starts afresh, and the older download's
  /// result is discarded when it lands.
  void loadFacilitiesInBackground(ArtifactSpec spec) {
    final stamp = _stampOf(spec);
    if (_facilitiesDownloadStarted && stamp == _facilitiesStartedStamp) return;
    _facilitiesDownloadStarted = true;
    _facilitiesStartedStamp = stamp;
    facilitiesReady.value = false;
    facilitiesFailed.value = false;
    facilitiesProgress.value = null;
    unawaited(_loadFacilities(spec));
  }

  static String _stampOf(ArtifactSpec spec) =>
      '${spec.version}|${spec.hash ?? ''}';

  /// The stamp the decoded facility cache must carry to be served, derived
  /// from a `/config` map. Null — meaning "nothing may be served" — when the
  /// config, its facilities entry, or that entry's version or hash is
  /// missing: without both there is nothing to validate the cache against.
  static String? facilityStampFromConfig(Map<String, dynamic>? config) {
    final artifacts = config?['artifacts'];
    if (artifacts is! Map) return null;
    final entry = artifacts['facilities'];
    if (entry is! Map) return null;
    final version = entry['version'];
    final hash = entry['hash'];
    if (version is! String || version.isEmpty) return null;
    if (hash is! String || hash.isEmpty) return null;
    return '$version|$hash';
  }

  /// Reads the decoded facility list, but only if it was decoded from the
  /// artifact [expectedStamp] names. A mismatching, unstamped (written by a
  /// build before WP-025) or unvalidatable cache is deleted and an empty list
  /// returned, so the caller falls through to a fresh, hash-verified load.
  ///
  /// This is what stops a device that decoded withdrawn facilities v1.1 from
  /// showing those entries forever after `/config` moved to v1.2.
  static Future<List<Map<String, dynamic>>> readFacilityCache({
    required String? expectedStamp,
  }) async {
    final box = Hive.isBoxOpen(ArtifactCacheKeys.facilityBox)
        ? Hive.box(ArtifactCacheKeys.facilityBox)
        : await Hive.openBox(ArtifactCacheKeys.facilityBox);
    final stamp = box.get(ArtifactCacheKeys.facilityStamp);
    if (expectedStamp == null || stamp != expectedStamp) {
      if (box.containsKey(ArtifactCacheKeys.facilityData) ||
          box.containsKey(ArtifactCacheKeys.facilityStamp)) {
        debugPrint(
          'Decoded facility cache does not match /config — discarding',
        );
        await box.delete(ArtifactCacheKeys.facilityData);
        await box.delete(ArtifactCacheKeys.facilityStamp);
      }
      return <Map<String, dynamic>>[];
    }
    final raw = box.get(ArtifactCacheKeys.facilityData) as List?;
    return raw?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
        <Map<String, dynamic>>[];
  }

  /// Deletes every raw facilities version in [artifactBox] except
  /// [keepKey], so a superseded (e.g. withdrawn) facilities artifact is not
  /// kept on the device.
  ///
  /// Deliberately facilities-only. Superseded *clinical* artifact versions
  /// (knowledge base, rules, token dictionary) are kept: locked principle #4
  /// versions every artifact so `/config` can be rolled back to a previous
  /// clinical version, and a device that still holds it keeps working
  /// offline after such a rollback. Facilities carry no clinical logic, and
  /// a withdrawn facilities version (wrong phone numbers) must not linger.
  static Future<void> _purgeSupersededFacilityVersions(
    Box<dynamic> artifactBox,
    String keepKey,
  ) async {
    final prefix = '${ArtifactCacheKeys.facilities}_v';
    final stale = artifactBox.keys
        .whereType<String>()
        .where((String k) => k.startsWith(prefix) && k != keepKey)
        .toList();
    if (stale.isEmpty) return;
    await artifactBox.deleteAll(stale);
  }

  Future<void> _loadFacilities(ArtifactSpec spec) async {
    final stamp = _stampOf(spec);
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

      // A newer download (different version+hash) was started while this
      // one was in flight: drop this result rather than overwrite it.
      if (stamp != _facilitiesStartedStamp) return;

      final facilityBox = Hive.isBoxOpen(ArtifactCacheKeys.facilityBox)
          ? Hive.box(ArtifactCacheKeys.facilityBox)
          : await Hive.openBox(ArtifactCacheKeys.facilityBox);
      // Stamp removed first and written last: an interrupted write leaves an
      // unstamped list, which readFacilityCache discards, never a list
      // carrying a stamp it was not decoded from.
      await facilityBox.delete(ArtifactCacheKeys.facilityStamp);
      await facilityBox.put(ArtifactCacheKeys.facilityData, list);
      final hash = spec.hash;
      if (hash != null && hash.isNotEmpty) {
        await facilityBox.put(ArtifactCacheKeys.facilityStamp, stamp);
      }
      await _purgeSupersededFacilityVersions(
        artifactBox,
        '${spec.cacheKey}_v${spec.version}',
      );
      facilitiesProgress.value = 1.0;
      facilitiesReady.value = true;
    } catch (_) {
      if (stamp != _facilitiesStartedStamp) return;
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
    _facilitiesStartedStamp = null;
  }
}
