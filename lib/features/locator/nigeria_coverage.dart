/// Geographic coverage check for the clinic locator.
///
/// The facilities artifact is Nigeria-only. Without this gate a user outside
/// Nigeria is shown Nigerian clinics with distances in the thousands of
/// kilometres — worse than showing nothing, because a populated list reads as
/// a real recommendation.
///
/// Kept out of the screen so it can be unit tested directly: it decides
/// whether the locator is usable at all, which is worth pinning.
library;

const double kNigeriaMinLat = 4.0;
const double kNigeriaMaxLat = 14.0;
const double kNigeriaMinLon = 2.5;
const double kNigeriaMaxLon = 15.0;

/// Whether [latitude]/[longitude] fall inside the Nigeria bounding box.
///
/// A coarse rectangle, so it includes some neighbouring territory near the
/// borders. That is the safe direction to err: a user just inside a
/// neighbouring country sees the same list they would have seen anyway,
/// whereas clipping tightly would cut off users in genuine Nigerian border
/// areas. Bounds are inclusive.
bool isWithinNigeria(double latitude, double longitude) =>
    latitude >= kNigeriaMinLat &&
    latitude <= kNigeriaMaxLat &&
    longitude >= kNigeriaMinLon &&
    longitude <= kNigeriaMaxLon;

/// The states the active facilities artifact actually covers.
///
/// `facilities.ng.v1.1` — the version `/config` currently publishes — holds
/// 5,344 records and every one of them is in Lagos, FCT or Kano. It is not a
/// national dataset, so nothing in the UI may imply national coverage.
///
/// Declared here rather than in the screen so the locator's state picker and
/// its user-facing disclosure read from one list: if a later artifact adds a
/// state, the picker and the wording cannot drift apart.
const List<String> kCoveredStates = ['Lagos', 'FCT', 'Kano'];

/// Coverage sentence shown wherever the user could otherwise infer that
/// WellaPath lists facilities across the whole country.
///
/// Product wording. It states the limit plainly and does not promise an
/// expansion date. `isWithinNigeria` stays a separate, coarser gate: it keeps
/// out-of-country users from seeing Nigerian clinics at all, while this
/// sentence tells in-country users which states the data actually holds.
const String kCoverageDisclosure =
    'Facility data currently covers Lagos, FCT (Abuja) and Kano only.';
