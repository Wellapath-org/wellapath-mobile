import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/facilities_v2/emergency_fallback_policy.dart';
import 'package:wellapath_mobile/core/facilities_v2/facilities_v2_parser.dart';
import 'package:wellapath_mobile/core/facilities_v2/facility_v2.dart';

import 'fixture_support.dart';

void main() {
  const policy = EmergencyFallbackPolicy.pendingApproval;
  late List<FacilityV2> facilities;

  setUpAll(() {
    facilities = const FacilitiesV2Parser().parse(readFixtureJson()).facilities;
  });

  test('only emergency_capable == true earns priority', () {
    final list = policy.build(facilities, userLat: 6.52, userLon: 3.38);
    expect(list.kind, EmergencyListKind.verifiedCapableFirst);
    // SYN-001 is the only capable==true record; SYN-002 (false) and the
    // null records may be closer but must not outrank it.
    expect(list.facilities.first.$1.id, 'SYN-001');
    expect(list.disclosure, isNull);
  });

  test('null is never interpreted as true', () {
    final nullOnly = [
      for (final f in facilities)
        if (f.emergencyCapable == null) f,
    ];
    expect(nullOnly, isNotEmpty, reason: 'fixture precondition');
    final list = policy.build(nullOnly, userLat: 6.52, userLon: 3.38);
    expect(list.kind, EmergencyListKind.nearestNoCapabilityClaim);
  });

  test('no verified facility -> nearest by distance, wording claims no '
      'capability and keeps 112 first', () {
    final withoutVerified = [
      for (final f in facilities)
        if (f.emergencyCapable != true) f,
    ];
    final list = policy.build(withoutVerified, userLat: 6.52, userLon: 3.38);

    expect(list.kind, EmergencyListKind.nearestNoCapabilityClaim);
    expect(list.facilities, isNotEmpty);
    // Ordinary distance order, nothing re-ranked by unknown capability.
    for (var i = 1; i < list.facilities.length; i++) {
      expect(
        list.facilities[i].$2,
        greaterThanOrEqualTo(list.facilities[i - 1].$2),
      );
    }
    final wording = list.disclosure!;
    expect(wording, contains('call 112'));
    expect(wording.toLowerCase(), contains('closest facilities'));
    // The wording must not assert capability.
    expect(wording.toLowerCase(), isNot(contains('emergency-ready')));
    expect(
      wording.toLowerCase(),
      contains('no facility in this list is verified'),
    );
  });

  test('the fallback policy is one named, replaceable decision point', () {
    // FAC-D002: approved wording lands by constructing a new policy, not by
    // editing call sites.
    const approvedLater = EmergencyFallbackPolicy(
      fallbackWording: 'placeholder for the approved wording',
    );
    final list = approvedLater.build(
      [
        for (final f in facilities)
          if (f.emergencyCapable != true) f,
      ],
      userLat: 6.52,
      userLon: 3.38,
    );
    expect(list.disclosure, 'placeholder for the approved wording');
  });
}
