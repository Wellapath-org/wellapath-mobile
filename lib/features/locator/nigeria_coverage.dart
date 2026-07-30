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
