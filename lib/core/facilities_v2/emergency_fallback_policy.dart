/// FAC-D002 decision point: what the locator does when no *verified*
/// emergency-capable facility exists.
///
/// Product and Clinical have not yet approved an emergency-fallback
/// behaviour for Facilities 2.0, so the pending policy is deliberately
/// conservative and lives behind this single, named configuration:
///
///  * A facility counts as emergency-capable **only** when
///    `emergency_capable == true`. Null is unknown, never true.
///  * The 112 action stays primary regardless of facility data.
///  * With zero verified facilities, the nearest facilities are shown
///    using the ordinary distance behaviour, under wording that claims no
///    emergency capability.
///
/// Replacing this behaviour after approval means replacing
/// [EmergencyFallbackPolicy.pendingApproval] with an approved instance —
/// one reviewable site, no scattered conditionals. Emergency Hub 2.0 is
/// out of scope here and nothing in this file starts it.
library;

import 'facility_v2.dart';
import 'facilities_v2_search.dart';

enum EmergencyListKind { verifiedCapableFirst, nearestNoCapabilityClaim }

class EmergencyFacilityList {
  const EmergencyFacilityList({
    required this.kind,
    required this.facilities,
    required this.disclosure,
  });

  final EmergencyListKind kind;
  final List<(FacilityV2, double)> facilities;

  /// Wording shown above the list. For the fallback case it must not claim
  /// emergency capability — see [EmergencyFallbackPolicy.fallbackWording].
  final String? disclosure;
}

class EmergencyFallbackPolicy {
  const EmergencyFallbackPolicy({required this.fallbackWording});

  /// The unapproved-default policy (FAC-D002 pending).
  static const EmergencyFallbackPolicy pendingApproval =
      EmergencyFallbackPolicy(
        fallbackWording:
            'No facility in this list is verified for emergency care. '
            'These are the closest facilities by distance. '
            'In an emergency, call 112 first.',
      );

  final String fallbackWording;

  /// Builds the emergency list. Only `emergencyCapable == true` records are
  /// prioritized as capable; null and false are both non-capable here and
  /// null is additionally never labelled "not capable" anywhere — it simply
  /// earns no priority.
  EmergencyFacilityList build(
    List<FacilityV2> facilities, {
    required double userLat,
    required double userLon,
    int maxResults = 30,
  }) {
    const search = FacilitiesV2Search();
    final sorted = search.sortByDistance(
      facilities,
      userLat: userLat,
      userLon: userLon,
    );

    final verified = [
      for (final entry in sorted)
        if (entry.$1.emergencyCapable == true) entry,
    ];

    if (verified.isEmpty) {
      return EmergencyFacilityList(
        kind: EmergencyListKind.nearestNoCapabilityClaim,
        facilities: sorted.take(maxResults).toList(),
        disclosure: fallbackWording,
      );
    }

    final others = [
      for (final entry in sorted)
        if (entry.$1.emergencyCapable != true) entry,
    ];
    return EmergencyFacilityList(
      kind: EmergencyListKind.verifiedCapableFirst,
      facilities: [...verified, ...others].take(maxResults).toList(),
      disclosure: null,
    );
  }
}
