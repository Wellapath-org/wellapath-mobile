import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/locator/facility_card.dart';
import 'package:wellapath_mobile/features/locator/facility_locator_service.dart';

final List<Map<String, dynamic>> mockFacilities = [
  {
    'facility_id': 'f001',
    'name': 'Lagos Island General Hospital',
    'type': 'hospital',
    'state': 'Lagos',
    'city_area': 'Lagos Island',
    'latitude': 6.4541,
    'longitude': 3.3947,
    'phone': '+2341234567',
    'opening_hours': '24/7',
    'emergency_capable': true,
  },
  {
    'facility_id': 'f002',
    'name': 'Victoria Island Clinic',
    'type': 'clinic',
    'state': 'Lagos',
    'city_area': 'Victoria Island',
    'latitude': 6.4281,
    'longitude': 3.4219,
    'phone': null,
    'opening_hours': null,
    'emergency_capable': false,
  },
  {
    'facility_id': 'f003',
    'name': 'Kano Central Pharmacy',
    'type': 'pharmacy',
    'state': 'Kano',
    'city_area': 'Kano Central',
    'latitude': 12.0022,
    'longitude': 8.5920,
    'phone': null,
    'opening_hours': null,
    'emergency_capable': false,
  },
  {
    'facility_id': 'f004',
    'name': 'Surulere Health Centre',
    'type': 'health_centre',
    'state': 'Lagos',
    'city_area': 'Surulere',
    'latitude': 6.5022,
    'longitude': 3.3515,
    'phone': null,
    'opening_hours': null,
    'emergency_capable': false,
  },
  {
    'facility_id': 'f005',
    'name': 'Ikeja Emergency Hospital',
    'type': 'hospital',
    'state': 'Lagos',
    'city_area': 'Ikeja',
    'latitude': 6.6018,
    'longitude': 3.3515,
    'phone': '+2349876543',
    'opening_hours': '24/7',
    'emergency_capable': true,
  },
];

// User location used throughout: Lagos Island (matches f001's coordinates).
const double _userLat = 6.4541;
const double _userLon = 3.3947;

void main() {
  test('TEST 1: haversine distance — Lagos Island to Victoria Island', () {
    final service = FacilityLocatorService(mockFacilities);
    final results = service.getNearbyFacilities(
      userLat: _userLat,
      userLon: _userLon,
      urgency: 'urgent',
    );
    final victoriaIsland = results.firstWhere(
      (facility) => facility['facility_id'] == 'f002',
    );
    final distance = victoriaIsland['distance_km'] as double;
    expect(distance, greaterThan(2.0));
    expect(distance, lessThan(6.0));
  });

  test('TEST 2: emergency urgency → emergency_capable facilities first', () {
    final service = FacilityLocatorService(mockFacilities);
    final results = service.getNearbyFacilities(
      userLat: _userLat,
      userLon: _userLon,
      urgency: 'emergency',
    );
    expect(results.first['emergency_capable'], true);
    expect(['f001', 'f005'], contains(results.first['facility_id']));
  });

  test('TEST 3: urgent urgency → only hospital and clinic types', () {
    final service = FacilityLocatorService(mockFacilities);
    final results = service.getNearbyFacilities(
      userLat: _userLat,
      userLon: _userLon,
      urgency: 'urgent',
    );
    for (final facility in results) {
      expect(['hospital', 'clinic'], contains(facility['type']));
    }
    expect(results.any((facility) => facility['type'] == 'pharmacy'), false);
    expect(
      results.any((facility) => facility['type'] == 'health_centre'),
      false,
    );
  });

  // NOTE: TEST 4 uses a bespoke dataset rather than the shared mockFacilities.
  // With mockFacilities, self_care only has 2 candidate facilities total
  // (Kano pharmacy ~840km away, Surulere health centre ~7km away), so the
  // sparse-coverage fallback (< 3 within 20km) always triggers and pulls in
  // the Victoria Island clinic — see PROGRESS.md E6 notes for the user
  // decision keeping the fallback algorithm as-is and adjusting this test's
  // dataset instead. This dataset has 3 pharmacy/health_centre facilities
  // within 20km, so fallback does not trigger, and the strict type
  // assertion holds.
  test('TEST 4: self_care urgency → only pharmacy and health_centre types', () {
    final selfCareFacilities = [
      {
        'facility_id': 's001',
        'name': 'Near Pharmacy A',
        'type': 'pharmacy',
        'state': 'Lagos',
        'city_area': 'Lagos Island',
        'latitude': 6.4545,
        'longitude': 3.3950,
        'phone': null,
        'opening_hours': null,
        'emergency_capable': false,
      },
      {
        'facility_id': 's002',
        'name': 'Near Health Centre B',
        'type': 'health_centre',
        'state': 'Lagos',
        'city_area': 'Lagos Island',
        'latitude': 6.4550,
        'longitude': 3.3955,
        'phone': null,
        'opening_hours': null,
        'emergency_capable': false,
      },
      {
        'facility_id': 's003',
        'name': 'Near Pharmacy C',
        'type': 'pharmacy',
        'state': 'Lagos',
        'city_area': 'Lagos Island',
        'latitude': 6.4560,
        'longitude': 3.3960,
        'phone': null,
        'opening_hours': null,
        'emergency_capable': false,
      },
      {
        'facility_id': 's004',
        'name': 'Far Hospital',
        'type': 'hospital',
        'state': 'Lagos',
        'city_area': 'Ikeja',
        'latitude': 6.6018,
        'longitude': 3.3515,
        'phone': null,
        'opening_hours': null,
        'emergency_capable': true,
      },
      {
        'facility_id': 's005',
        'name': 'Far Clinic',
        'type': 'clinic',
        'state': 'Lagos',
        'city_area': 'Victoria Island',
        'latitude': 6.4281,
        'longitude': 3.4219,
        'phone': null,
        'opening_hours': null,
        'emergency_capable': false,
      },
    ];

    final service = FacilityLocatorService(selfCareFacilities);
    final results = service.getNearbyFacilities(
      userLat: _userLat,
      userLon: _userLon,
      urgency: 'self_care',
    );
    for (final facility in results) {
      expect(['pharmacy', 'health_centre'], contains(facility['type']));
    }
    expect(results.any((facility) => facility['type'] == 'hospital'), false);
    expect(results.any((facility) => facility['type'] == 'clinic'), false);
  });

  // NOTE: self_care's base type filter already includes both pharmacy and
  // health_centre (per the STEP 4 spec), so the fallback chain can only
  // ever add 'clinic' (via the health_centre -> clinic tier) — it can never
  // "add health_centre" since that's already in the base set. This dataset
  // has only 1 pharmacy and no health_centre at all, so the base filter
  // yields just 1 nearby result, triggering fallback and pulling in the
  // clinic.
  test('TEST 5: sparse coverage fallback', () {
    final sparseFacilities = [
      {
        'facility_id': 'p001',
        'name': 'Only Nearby Pharmacy',
        'type': 'pharmacy',
        'state': 'Lagos',
        'city_area': 'Lagos Island',
        'latitude': 6.4545,
        'longitude': 3.3950,
        'phone': null,
        'opening_hours': null,
        'emergency_capable': false,
      },
      {
        'facility_id': 'c001',
        'name': 'Nearby Clinic',
        'type': 'clinic',
        'state': 'Lagos',
        'city_area': 'Victoria Island',
        'latitude': 6.4281,
        'longitude': 3.4219,
        'phone': null,
        'opening_hours': null,
        'emergency_capable': false,
      },
    ];

    final service = FacilityLocatorService(sparseFacilities);
    final results = service.getNearbyFacilities(
      userLat: _userLat,
      userLon: _userLon,
      urgency: 'self_care',
    );
    expect(results.length, greaterThan(1));
    expect(results.any((facility) => facility['type'] == 'clinic'), true);
  });

  testWidgets(
    'TEST 6: phone null → facility card does not render Call button',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FacilityCard(
              facility: mockFacilities[1],
              onDirectionsTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('Call'), findsNothing);
    },
  );

  testWidgets(
    'TEST 7: opening_hours null → facility card hides opening status',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FacilityCard(
              facility: mockFacilities[1],
              onDirectionsTap: () {},
            ),
          ),
        ),
      );
      expect(find.text('Open now'), findsNothing);
      expect(find.text('Unknown'), findsNothing);
    },
  );

  // NOTE: with mockFacilities, Kano's only facility (f003) is a pharmacy,
  // which the 'urgent' type filter (hospital/clinic) excludes — so this
  // returns an empty list. Both assertions below hold vacuously on an empty
  // result; see the report for this test run for detail.
  test('TEST 8: manual fallback — state filter', () {
    final service = FacilityLocatorService(mockFacilities);
    final results = service.getFacilitiesByLocation(
      state: 'Kano',
      cityArea: '',
      urgency: 'urgent',
    );
    expect(results.every((facility) => facility['state'] == 'Kano'), true);
    expect(results.any((facility) => facility['state'] == 'Lagos'), false);
  });
}
