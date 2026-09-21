/// Version-aware Facilities 2.0 parser.
///
/// Fails closed at the artifact level (wrong schema, wrong shape → typed
/// failure, nothing partially consumed) and fails *open per record*: a
/// structurally invalid record is isolated into [FacilitiesV2ParseResult
/// .rejectedRecords] and the rest of the artifact still loads, so one bad
/// row can never crash or empty the locator.
///
/// This parser never repairs data. Out-of-range or non-numeric coordinates
/// reject the record; they are not clamped, snapped, swapped or inferred —
/// Data Engineering owns coordinate transformations.
library;

import 'facilities_v2_attribution.dart';
import 'facility_v2.dart';

/// Why a whole artifact was refused. Fixed vocabulary, safe to log.
enum FacilitiesV2ArtifactRejection {
  notAMap,
  missingSchemaVersion,
  incompatibleSchemaVersion,
  facilitiesNotAList,
  emptyFacilities,
}

class FacilitiesV2ParseException implements Exception {
  const FacilitiesV2ParseException(this.rejection);
  final FacilitiesV2ArtifactRejection rejection;

  @override
  String toString() => 'FacilitiesV2ParseException: ${rejection.name}';
}

class FacilitiesV2ParseResult {
  const FacilitiesV2ParseResult({
    required this.schemaVersion,
    required this.facilities,
    required this.rejectedRecords,
    required this.attribution,
  });

  final String schemaVersion;
  final List<FacilityV2> facilities;

  /// Count only — rejected records are not retained, so a malformed record
  /// cannot leak partial data anywhere downstream.
  final int rejectedRecords;

  /// Source attribution for the artifact, built once per artifact from
  /// `_metadata` under [FacilitiesV2Attribution]'s validation rules (plain
  /// text only, HTTPS links only, vendored fallback). Artifact-level: it
  /// never touches the per-record memory footprint.
  final FacilitiesV2Attribution attribution;
}

class FacilitiesV2Parser {
  const FacilitiesV2Parser();

  /// Keys of schema 2.0 a record consumer reads. Anything else (provenance,
  /// coordinate-audit and future fields) is carried opaquely.
  static const Set<String> _consumedKeys = {
    'id',
    'name',
    'latitude',
    'longitude',
    'type',
    'emergency_capable',
    'state',
    'lga',
    'city_area',
    'phone',
    'opening_hours',
  };

  FacilitiesV2ParseResult parse(Object? artifact) {
    if (artifact is! Map) {
      throw const FacilitiesV2ParseException(
        FacilitiesV2ArtifactRejection.notAMap,
      );
    }
    final schemaVersion = artifact['schema_version'];
    if (schemaVersion is! String || schemaVersion.isEmpty) {
      throw const FacilitiesV2ParseException(
        FacilitiesV2ArtifactRejection.missingSchemaVersion,
      );
    }
    // Major version 2 only. 2.x minors are additive by contract, so they
    // parse; anything else is a different contract and is refused outright
    // rather than half-read.
    if (!schemaVersion.startsWith('2.')) {
      throw const FacilitiesV2ParseException(
        FacilitiesV2ArtifactRejection.incompatibleSchemaVersion,
      );
    }
    final rawList = artifact['facilities'];
    if (rawList is! List) {
      throw const FacilitiesV2ParseException(
        FacilitiesV2ArtifactRejection.facilitiesNotAList,
      );
    }
    if (rawList.isEmpty) {
      // An empty candidate is unusable: activating v2 on it would blank the
      // locator. Treated as an artifact-level failure so the loader falls
      // back to v1.1.
      throw const FacilitiesV2ParseException(
        FacilitiesV2ArtifactRejection.emptyFacilities,
      );
    }

    final facilities = <FacilityV2>[];
    var rejected = 0;
    for (final raw in rawList) {
      final parsed = _tryParseRecord(raw);
      if (parsed == null) {
        rejected++;
      } else {
        facilities.add(parsed);
      }
    }

    return FacilitiesV2ParseResult(
      schemaVersion: schemaVersion,
      facilities: facilities,
      rejectedRecords: rejected,
      attribution: FacilitiesV2Attribution.fromArtifactMetadata(
        artifact['_metadata'],
      ),
    );
  }

  FacilityV2? _tryParseRecord(Object? raw) {
    if (raw is! Map) return null;

    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.trim().isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;

    final lat = _finiteDouble(raw['latitude']);
    final lon = _finiteDouble(raw['longitude']);
    if (lat == null || lon == null) return null;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;

    // `type` may be null (unknown) or any string (future values allowed).
    // A non-string, non-null type is structural corruption -> reject.
    final type = raw['type'];
    if (type != null && type is! String) return null;

    final emergencyCapable = raw['emergency_capable'];
    if (emergencyCapable != null && emergencyCapable is! bool) return null;

    Map<String, Object?> provenance = const {};
    for (final entry in raw.entries) {
      if (entry.key is String && !_consumedKeys.contains(entry.key)) {
        if (provenance.isEmpty) provenance = <String, Object?>{};
        provenance[entry.key as String] = entry.value;
      }
    }

    return FacilityV2(
      id: id.trim(),
      name: name.trim(),
      latitude: lat,
      longitude: lon,
      rawType: type as String?,
      emergencyCapable: emergencyCapable as bool?,
      state: _optionalString(raw['state']),
      lga: _optionalString(raw['lga']),
      cityArea: _optionalString(raw['city_area']),
      phone: _optionalString(raw['phone']),
      openingHours: _optionalString(raw['opening_hours']),
      provenance: provenance,
    );
  }

  static double? _finiteDouble(Object? value) {
    if (value is! num) return null;
    final asDouble = value.toDouble();
    return asDouble.isFinite ? asDouble : null;
  }

  static String? _optionalString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
