/// Facilities 2.0 load pipeline — gate-checked, hash-verified, and
/// guaranteed to leave the approved v1.1 cache untouched on any failure.
///
/// Every failure mode resolves to [FacilitiesV2LoadStatus.fallbackToV1]:
/// gate inactive, manifest unapproved, download failed, hash mismatch,
/// schema/parse failure, or an empty/unusable candidate. The v1.1 cache
/// keys (`ArtifactCacheKeys.facilities`, `ArtifactCacheKeys.facilityData`)
/// are never written, deleted or read here — v2 uses its own namespace —
/// so a failed v2 attempt cannot erase the last valid v1.1 data.
///
/// Networking is injected as a plain `Future<String> Function(String url)`;
/// this file imports no HTTP client and sends nothing anywhere itself.
/// Integrity uses the same trusted verification as every shipped artifact:
/// [StagedArtifactLoader.verifyArtifactHash].
library;

import 'dart:convert';

import '../network/staged_artifact_loader.dart';
import 'facilities_v2_gate.dart';
import 'facilities_v2_manifest.dart';
import 'facilities_v2_parser.dart';

/// v2-only cache names. Deliberately disjoint from [ArtifactCacheKeys]'
/// v1.1 names so the two datasets can never collide.
class FacilitiesV2CacheKeys {
  static const String artifact = 'artifact_facilities_v2';
  static const String facilityData = 'facilities_v2_data';
}

enum FacilitiesV2LoadStatus {
  loadedFromCache,
  loadedFromNetwork,

  /// Use the v1.1 path exactly as today. Always safe.
  fallbackToV1,
}

enum FacilitiesV2FallbackCause {
  gateInactive,
  manifestUnapproved,
  downloadFailed,
  hashMismatch,
  schemaRejected,
  candidateUnusable,
}

class FacilitiesV2LoadResult {
  const FacilitiesV2LoadResult._({
    required this.status,
    this.cause,
    this.parse,
  });

  const FacilitiesV2LoadResult.fallback(FacilitiesV2FallbackCause cause)
    : this._(status: FacilitiesV2LoadStatus.fallbackToV1, cause: cause);

  final FacilitiesV2LoadStatus status;
  final FacilitiesV2FallbackCause? cause;
  final FacilitiesV2ParseResult? parse;
}

class FacilitiesV2Loader {
  const FacilitiesV2Loader({
    required Future<String> Function(String url) download,
    required void Function(String key, String rawBody) cachePut,
    required String? Function(String key) cacheGet,
  }) : _download = download,
       _cachePut = cachePut,
       _cacheGet = cacheGet;

  final Future<String> Function(String url) _download;

  /// Cache seams rather than a Hive box so tests prove the write-set
  /// exactly: the only keys ever passed are the [FacilitiesV2CacheKeys]
  /// namespace, versioned like v1.1's `<key>_v<version>`.
  final void Function(String key, String rawBody) _cachePut;
  final String? Function(String key) _cacheGet;

  Future<FacilitiesV2LoadResult> load({
    required FacilitiesV2Gate gate,
    required FacilitiesV2Manifest? manifest,
  }) async {
    if (!gate.active) {
      return const FacilitiesV2LoadResult.fallback(
        FacilitiesV2FallbackCause.gateInactive,
      );
    }
    // The gate already required an approved manifest; re-checked here so a
    // future refactor of gate construction cannot silently drop the check.
    if (manifest == null || !manifest.isApprovedForConsumption) {
      return const FacilitiesV2LoadResult.fallback(
        FacilitiesV2FallbackCause.manifestUnapproved,
      );
    }
    final url = manifest.url;
    if (url == null || url.isEmpty) {
      return const FacilitiesV2LoadResult.fallback(
        FacilitiesV2FallbackCause.manifestUnapproved,
      );
    }

    final versionedKey =
        '${FacilitiesV2CacheKeys.artifact}_v${manifest.artifactVersion}';

    // Cached copy first — verified on every read, like v1.1.
    final cached = _cacheGet(versionedKey);
    if (cached != null &&
        StagedArtifactLoader.verifyArtifactHash(cached, manifest.sha256)) {
      final parsed = _tryParse(cached);
      if (parsed != null) {
        return FacilitiesV2LoadResult._(
          status: FacilitiesV2LoadStatus.loadedFromCache,
          parse: parsed,
        );
      }
    }

    final String rawBody;
    try {
      rawBody = await _download(url);
    } catch (_) {
      return const FacilitiesV2LoadResult.fallback(
        FacilitiesV2FallbackCause.downloadFailed,
      );
    }

    if (!StagedArtifactLoader.verifyArtifactHash(rawBody, manifest.sha256)) {
      return const FacilitiesV2LoadResult.fallback(
        FacilitiesV2FallbackCause.hashMismatch,
      );
    }

    final FacilitiesV2ParseResult parsed;
    try {
      parsed = const FacilitiesV2Parser().parse(jsonDecode(rawBody));
    } on FacilitiesV2ParseException catch (e) {
      return FacilitiesV2LoadResult.fallback(
        e.rejection == FacilitiesV2ArtifactRejection.emptyFacilities
            ? FacilitiesV2FallbackCause.candidateUnusable
            : FacilitiesV2FallbackCause.schemaRejected,
      );
    } on FormatException {
      return const FacilitiesV2LoadResult.fallback(
        FacilitiesV2FallbackCause.schemaRejected,
      );
    }

    if (parsed.facilities.isEmpty) {
      // Every record was individually rejected: technically parseable,
      // practically unusable.
      return const FacilitiesV2LoadResult.fallback(
        FacilitiesV2FallbackCause.candidateUnusable,
      );
    }

    // Cache only after hash + schema both held (locked principle #4: a new
    // version gets a new key; nothing is overwritten).
    _cachePut(versionedKey, rawBody);
    return FacilitiesV2LoadResult._(
      status: FacilitiesV2LoadStatus.loadedFromNetwork,
      parse: parsed,
    );
  }

  FacilitiesV2ParseResult? _tryParse(String rawBody) {
    try {
      return const FacilitiesV2Parser().parse(jsonDecode(rawBody));
    } on Object {
      return null;
    }
  }
}
