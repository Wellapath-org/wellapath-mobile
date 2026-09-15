/// Facilities 2.0 record model.
///
/// Design rules this model enforces by type:
///
///  * **Nullable means unknown, never false.** `type` and
///    `emergency_capable` are tri-state: a null survives as null/
///    [FacilityTypeV2.unspecified], it is never coerced.
///  * **Unknown future enum values survive.** A `type` string this build
///    does not recognise maps to [FacilityTypeV2.unrecognized] with the
///    raw value preserved — the record stays fully visible and searchable.
///  * **Coordinates pass through untouched.** Mobile never exchanges,
///    repairs, snaps or infers coordinates; Data Engineering owns those
///    transformations. A record without finite, in-range coordinates is
///    rejected by the parser, not fixed here.
///  * **Phone and opening hours are approval-gated.** Source public-use
///    authorization is unresolved, so raw values are held privately and
///    only reachable through [FacilitiesV2Presentation].
library;

/// Facility type under schema 2.0. [unspecified] is a null in the data —
/// the type is unknown, NOT absent-from-search. [unrecognized] is a value
/// this build has never heard of — a future schema addition, kept visible.
enum FacilityTypeV2 {
  hospital('hospital'),
  clinic('clinic'),
  healthCentre('health_centre'),
  pharmacy('pharmacy'),
  unspecified(null),
  unrecognized(null);

  const FacilityTypeV2(this.wire);
  final String? wire;

  static FacilityTypeV2 fromRaw(String? raw) {
    if (raw == null) return FacilityTypeV2.unspecified;
    for (final t in FacilityTypeV2.values) {
      if (t.wire != null && t.wire == raw) return t;
    }
    return FacilityTypeV2.unrecognized;
  }

  /// True for the two states a type filter must never exclude.
  bool get isUnknown =>
      this == FacilityTypeV2.unspecified || this == FacilityTypeV2.unrecognized;
}

class FacilityV2 {
  const FacilityV2({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.rawType,
    required this.emergencyCapable,
    required this.state,
    required this.lga,
    required this.cityArea,
    required String? phone,
    required String? openingHours,
    this.provenance = const <String, Object?>{},
  }) : _phone = phone,
       _openingHours = openingHours;

  final String id;
  final String name;

  /// Verbatim from the artifact. Never adjusted — see the library comment.
  final double latitude;
  final double longitude;

  /// The wire value of `type`, preserved even when unrecognized. Null when
  /// the artifact says null.
  final String? rawType;

  FacilityTypeV2 get type => FacilityTypeV2.fromRaw(rawType);

  /// Tri-state: true = verified capable, false = verified not capable,
  /// null = unknown. **Null must never be read as true** (FAC-D002) — and
  /// nothing in this consumer reads it as false either; it stays unknown.
  final bool? emergencyCapable;

  final String? state;
  final String? lga;
  final String? cityArea;

  /// Held privately: source public-use authorization for v2 phone numbers
  /// is unresolved, so no UI may read this directly. Go through
  /// [FacilitiesV2Presentation.phoneForDisplay].
  final String? _phone;

  /// Held privately for the same reason; unknown hours must never render
  /// as "open". Go through [FacilitiesV2Presentation.openingHoursLabel].
  final String? _openingHours;

  /// Provenance / coordinate-audit fields carried by schema 2.0. Retained
  /// opaquely for diagnostics; never interpreted, never shown to users.
  final Map<String, Object?> provenance;
}

/// Opening-hours display states. There is deliberately no `open` value —
/// this consumer has no reliable open/closed source, and unknown must
/// never be presented as open.
enum OpeningHoursDisplay { unknown, raw }

/// The single place v2 phone numbers and opening hours can be turned into
/// UI values, so the pending source-authorization decision has exactly one
/// enforcement point.
class FacilitiesV2Presentation {
  const FacilitiesV2Presentation({
    this.phonePublicationApproved = false,
    this.openingHoursPublicationApproved = false,
  });

  /// Both default false and nothing in the product sets them true. When the
  /// source authorization lands, the approved configuration replaces this
  /// default — a one-line, reviewable change.
  final bool phonePublicationApproved;
  final bool openingHoursPublicationApproved;

  static const FacilitiesV2Presentation pendingApproval =
      FacilitiesV2Presentation();

  /// Null = show no phone CTA. Always null until approval; null for
  /// missing numbers even after it.
  String? phoneForDisplay(FacilityV2 facility) {
    if (!phonePublicationApproved) return null;
    final phone = facility._phone?.trim();
    return (phone == null || phone.isEmpty) ? null : phone;
  }

  /// Missing or unapproved hours are [OpeningHoursDisplay.unknown] — the UI
  /// renders "Hours unavailable"-class wording, never "open".
  (OpeningHoursDisplay, String?) openingHoursLabel(FacilityV2 facility) {
    if (!openingHoursPublicationApproved) {
      return (OpeningHoursDisplay.unknown, null);
    }
    final hours = facility._openingHours?.trim();
    if (hours == null || hours.isEmpty) {
      return (OpeningHoursDisplay.unknown, null);
    }
    return (OpeningHoursDisplay.raw, hours);
  }
}
