/// WP-023: the furthest a facility may be and still be listed by the
/// location-based ("Your location") search.
///
/// Before this bound existed, `getNearbyFacilities` had no maximum distance.
/// A user in a state the facility data does not cover (Sokoto, say) was shown
/// Kano or FCT facilities hundreds of kilometres away in the same list, map
/// and "N of 30 shown" frame as a genuinely close result.
///
/// This file holds the value **only**. The search applies it after its
/// existing filtering and ordering (urgency type filter, sparse-coverage
/// expansion, `emergency_capable`-first ordering), so the bound can remove
/// results but cannot reorder them or change which facility types are
/// considered for which urgency. When nothing is left, the locator shows an
/// explicit "nothing within this distance" state instead.
///
/// The manual state/area search is not distance-based and is not affected.
library;

// CLINICAL DECISION REQUIRED (WP-023): how far is too far to present a
// facility from the location-based search. Engineering has not decided this
// and the value below must not be read as a clinical or product judgement of
// acceptable travel distance. Open questions for clinical/product sign-off:
//
//  * the value itself;
//  * whether emergency results should use a different (e.g. larger) radius
//    than urgent/non-urgent/self-care results — today one value applies to
//    every urgency;
//  * whether a far-but-emergency-capable facility should ever be shown, with
//    a distance warning, rather than removed.
//
// Placeholder default, chosen conservatively in the sense of removing as
// little as possible: 100 km is wide enough to keep every facility a user
// inside Lagos, FCT or Kano could plausibly reach, and still removes the
// cross-state results the blocker describes (Sokoto to Kano is roughly
// 400 km). Change it here and nowhere else.
const double kLocationSearchMaxRadiusKm = 100.0;
