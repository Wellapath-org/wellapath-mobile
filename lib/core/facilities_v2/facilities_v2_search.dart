/// Local-only search, filtering and sorting over Facilities 2.0 records.
///
/// Everything here is a pure function over in-memory records: no network,
/// no plugin, no telemetry. The user's location enters as two doubles and
/// never leaves this file — sorting is on-device, matching the v1.1
/// locator's guarantee.
///
/// Null-type safety, by construction:
///  * A record with `type == null` (or an unrecognized future type) is
///    **always** retained by [filterForUrgency] — it is appended after the
///    type-matched records rather than dropped.
///  * A type filter can therefore never return an empty list solely
///    because types are null: if any record exists, unknown-type records
///    survive every filter.
///  * Nothing here reads a facility's *name* to guess its type.
library;

import 'dart:math';

import 'facility_v2.dart';

class FacilitiesV2Search {
  const FacilitiesV2Search();

  /// Deterministic text normalization for all matching: Unicode-aware
  /// lowercase, trimmed, internal whitespace collapsed to single spaces.
  /// No locale-dependent folding, no diacritic stripping — identical input
  /// bytes always produce identical output bytes, on every device.
  static String normalize(String input) =>
      input.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Per-record normalization caches. Re-normalizing every record's text
  /// fields on every query dominated search cost at 51k records (measured:
  /// ~78 ms/query on a desktop host for the contains searches, which
  /// projects far past the 200 ms repeated-search budget on the low-end
  /// Android target). Each record's fields are normalized once on first
  /// use instead; [normalize] is deterministic and [FacilityV2] fields are
  /// final, so a cached value can never go stale. Expando entries are
  /// garbage-collected with their records, so a released dataset frees its
  /// cache with it. The empty string stands in for a null field — the
  /// parser stores trimmed-empty values as null, so no real field
  /// normalizes to ''.
  static final Expando<String> _normNameCache = Expando('fac2NormName');
  static final Expando<String> _normStateCache = Expando('fac2NormState');
  static final Expando<String> _normLgaCache = Expando('fac2NormLga');
  static final Expando<String> _normCityCache = Expando('fac2NormCity');

  static String _normName(FacilityV2 f) =>
      _normNameCache[f] ??= normalize(f.name);
  static String _normState(FacilityV2 f) =>
      _normStateCache[f] ??= normalize(f.state ?? '');
  static String _normLga(FacilityV2 f) =>
      _normLgaCache[f] ??= normalize(f.lga ?? '');
  static String _normCity(FacilityV2 f) =>
      _normCityCache[f] ??= normalize(f.cityArea ?? '');

  /// State search: normalized equality on the record's own `state` field.
  List<FacilityV2> byState(List<FacilityV2> facilities, String state) {
    final wanted = normalize(state);
    if (wanted.isEmpty) return const [];
    return facilities.where((f) => _normState(f) == wanted).toList();
  }

  /// LGA / city / area search within an optional state: a record matches
  /// when its `lga` or `city_area` equals the query, or its `city_area`
  /// or `name` contains it. Field-driven only — never used to infer type.
  List<FacilityV2> byArea(
    List<FacilityV2> facilities,
    String query, {
    String? state,
  }) {
    final wanted = normalize(query);
    if (wanted.isEmpty) return const [];
    final pool = state == null ? facilities : byState(facilities, state);
    return pool.where((f) {
      final lga = _normLga(f);
      final city = _normCity(f);
      // '' stands for a null field and can never match: `wanted` is
      // non-empty here, so equality and contains are both false for ''.
      return lga == wanted ||
          city == wanted ||
          city.contains(wanted) ||
          _normName(f).contains(wanted);
    }).toList();
  }

  /// Distance-sorts [facilities] around the user's position. Pure and
  /// local: the coordinates are used for arithmetic here and nowhere else.
  /// Ties break by id so the ordering is deterministic.
  List<(FacilityV2, double)> sortByDistance(
    List<FacilityV2> facilities, {
    required double userLat,
    required double userLon,
  }) {
    final withDistance =
        [
          for (final f in facilities)
            (f, _haversineKm(userLat, userLon, f.latitude, f.longitude)),
        ]..sort((a, b) {
          final byDistance = a.$2.compareTo(b.$2);
          return byDistance != 0 ? byDistance : a.$1.id.compareTo(b.$1.id);
        });
    return withDistance;
  }

  /// Urgency filter with the null-type guarantee.
  ///
  /// Same urgency→type mapping as the v1.1 locator, plus the 2.0 rule:
  /// records whose type is unknown ([FacilityTypeV2.unspecified] or
  /// [FacilityTypeV2.unrecognized]) are always retained, after the typed
  /// matches. Emergency applies no type filter at all, as in v1.1.
  List<FacilityV2> filterForUrgency(
    List<FacilityV2> facilities,
    String urgency,
  ) {
    if (urgency == 'emergency') return List.of(facilities);

    final allowed = switch (urgency) {
      'urgent' ||
      'non_urgent' => const {FacilityTypeV2.hospital, FacilityTypeV2.clinic},
      'self_care' => const {
        FacilityTypeV2.pharmacy,
        FacilityTypeV2.healthCentre,
      },
      _ => const <FacilityTypeV2>{},
    };

    final matched = <FacilityV2>[];
    final unknownType = <FacilityV2>[];
    for (final f in facilities) {
      if (f.type.isUnknown) {
        unknownType.add(f);
      } else if (allowed.contains(f.type)) {
        matched.add(f);
      }
    }
    return [...matched, ...unknownType];
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    // Same formulation as the v1.1 FacilityLocatorService. Duplicated
    // deliberately: this consumer must have zero inbound coupling with the
    // shipped locator so that the v1.1 path is provably untouched.
    const earthRadiusKm = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * pi / 180;
}
