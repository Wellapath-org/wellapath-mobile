/// Facility search across the three states the active artifact covers.
///
/// `test/locator/facility_locator_service_test.dart` already pins the ranking
/// rules against a hand-built five-record fixture. This file asks a different
/// question, the one release readiness actually needs answered: **does a
/// search return usable results for Lagos, FCT and Kano, and does it degrade
/// honestly for a state the artifact does not hold?**
///
/// The records below carry the real field names and shapes of
/// `facilities.ng.v1.1` (facility_id / name / type / state / city_area /
/// latitude / longitude / emergency_capable). The 1.7MB artifact itself is not
/// vendored — it is downloaded at runtime, hash-pinned by `/config`, and
/// committing a copy would create a second, unversioned source of clinical
/// data. Ranking and emergency behaviour are asserted only where they are
/// already specified; this release changed neither.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/locator/facility_locator_service.dart';
import 'package:wellapath_mobile/features/locator/nigeria_coverage.dart';

Map<String, dynamic> _facility({
  required String id,
  required String name,
  required String type,
  required String state,
  required String cityArea,
  required double lat,
  required double lon,
  bool emergencyCapable = false,
}) => <String, dynamic>{
  'facility_id': id,
  'name': name,
  'type': type,
  'state': state,
  'city_area': cityArea,
  'latitude': lat,
  'longitude': lon,
  'phone': null,
  'opening_hours': null,
  'emergency_capable': emergencyCapable,
};

/// Two records per covered state — one hospital (emergency capable) and one
/// lower tier — so both urgency branches have something to return.
final List<Map<String, dynamic>> _facilities = <Map<String, dynamic>>[
  _facility(
    id: 'LA-001',
    name: 'Lagos Island General Hospital',
    type: 'hospital',
    state: 'Lagos',
    cityArea: 'Lagos Island',
    lat: 6.4550,
    lon: 3.3841,
    emergencyCapable: true,
  ),
  _facility(
    id: 'LA-002',
    name: 'Ikeja Community Health Centre',
    type: 'health_centre',
    state: 'Lagos',
    cityArea: 'Ikeja',
    lat: 6.6018,
    lon: 3.3515,
  ),
  _facility(
    id: 'FC-001',
    name: 'Garki Hospital',
    type: 'hospital',
    state: 'FCT',
    cityArea: 'Garki',
    lat: 9.0333,
    lon: 7.4833,
    emergencyCapable: true,
  ),
  _facility(
    id: 'FC-002',
    name: 'Wuse Pharmacy',
    type: 'pharmacy',
    state: 'FCT',
    cityArea: 'Wuse',
    lat: 9.0765,
    lon: 7.4600,
  ),
  _facility(
    id: 'KN-001',
    name: 'Murtala Muhammed Specialist Hospital',
    type: 'hospital',
    state: 'Kano',
    cityArea: 'Kano Municipal',
    lat: 12.0022,
    lon: 8.5920,
    emergencyCapable: true,
  ),
  _facility(
    id: 'KN-002',
    name: 'Nassarawa Health Centre',
    type: 'health_centre',
    state: 'Kano',
    cityArea: 'Nassarawa',
    lat: 12.0100,
    lon: 8.5500,
  ),
];

/// Approximate city centres, used as the "user is standing here" fix.
const Map<String, (double, double)> _cityCentres = {
  'Lagos': (6.5244, 3.3792),
  'FCT': (9.0765, 7.3986),
  'Kano': (12.0022, 8.5920),
};

void main() {
  final service = FacilityLocatorService(_facilities);

  group('every covered state returns results by state selection', () {
    for (final state in kCoveredStates) {
      test('$state returns at least one facility for an urgent case', () {
        final results = service.getFacilitiesByLocation(
          state: state,
          cityArea: '',
          urgency: 'urgent',
        );

        expect(results, isNotEmpty, reason: '$state is a covered state');
        expect(
          results.every((f) => f['state'] == state),
          isTrue,
          reason: 'a $state search must not leak other states',
        );
      });

      test('$state returns emergency results ranked capable-first', () {
        final results = service.getFacilitiesByLocation(
          state: state,
          cityArea: '',
          urgency: 'emergency',
        );

        expect(results, isNotEmpty);
        // Pre-existing contract, restated rather than changed: an
        // emergency-capable facility must not sit below one that is not.
        final capableFlags = results
            .map((f) => f['emergency_capable'] == true)
            .toList();
        final firstNonCapable = capableFlags.indexOf(false);
        if (firstNonCapable != -1) {
          expect(
            capableFlags.sublist(firstNonCapable).any((c) => c),
            isFalse,
            reason: 'emergency-capable facilities must rank first',
          );
        }
      });
    }
  });

  group('every covered state returns results by GPS fix', () {
    for (final entry in _cityCentres.entries) {
      test('${entry.key} city centre returns nearby facilities', () {
        final (lat, lon) = entry.value;
        final results = service.getNearbyFacilities(
          userLat: lat,
          userLon: lon,
          urgency: 'urgent',
          maxResults: 30,
        );

        expect(results, isNotEmpty);
        // The nearest result should be in the state the user is standing in.
        expect(results.first['state'], equals(entry.key));
      });
    }
  });

  group('city/area narrowing works inside a covered state', () {
    test('Ikeja narrows the Lagos result set', () {
      final all = service.getFacilitiesByLocation(
        state: 'Lagos',
        cityArea: '',
        urgency: 'self_care',
      );
      final ikeja = service.getFacilitiesByLocation(
        state: 'Lagos',
        cityArea: 'Ikeja',
        urgency: 'self_care',
      );

      expect(ikeja, isNotEmpty);
      expect(ikeja.length, lessThanOrEqualTo(all.length));
      expect(ikeja.every((f) => f['city_area'] == 'Ikeja'), isTrue);
    });

    test('state matching is case-insensitive', () {
      final lower = service.getFacilitiesByLocation(
        state: 'lagos',
        cityArea: '',
        urgency: 'urgent',
      );
      final exact = service.getFacilitiesByLocation(
        state: 'Lagos',
        cityArea: '',
        urgency: 'urgent',
      );

      expect(lower.length, equals(exact.length));
    });
  });

  group('uncovered states degrade honestly, not silently', () {
    test('an uncovered state returns empty rather than another state', () {
      // Enugu holds no records in facilities 1.1. The empty list is correct —
      // and it is exactly why the locator's empty state now carries
      // kCoverageDisclosure instead of a bare "no facilities found".
      final results = service.getFacilitiesByLocation(
        state: 'Enugu',
        cityArea: '',
        urgency: 'urgent',
      );

      expect(results, isEmpty);
    });

    test('an unknown city/area inside a covered state returns empty', () {
      final results = service.getFacilitiesByLocation(
        state: 'Lagos',
        cityArea: 'Nowhere',
        urgency: 'urgent',
      );

      expect(results, isEmpty);
    });

    test(
      'a GPS fix in an uncovered state still returns distant covered records',
      () {
        // Documents current behaviour rather than endorsing it: there is no
        // distance cap, so a user in Enugu is handed Lagos and Kano results.
        // Changing the ranking is out of scope for this release — the
        // disclosure is the release-safe mitigation.
        final results = service.getNearbyFacilities(
          userLat: 6.5244,
          userLon: 7.5102,
          urgency: 'urgent',
          maxResults: 30,
        );

        expect(results, isNotEmpty);
        expect(
          kCoveredStates.contains(results.first['state']),
          isTrue,
          reason: 'results can only ever come from covered states',
        );
        expect(
          results.first['distance_km'] as double,
          greaterThan(100),
          reason:
              'the nearest covered facility really is far away — the reason '
              'the empty/'
              'results wording must name the coverage',
        );
      },
    );
  });

  group('empty artifact does not crash the locator', () {
    test('an empty facility list returns empty for every urgency', () {
      final empty = FacilityLocatorService(const []);

      for (final urgency in const [
        'emergency',
        'urgent',
        'non_urgent',
        'self_care',
      ]) {
        expect(
          empty.getNearbyFacilities(
            userLat: 6.5244,
            userLon: 3.3792,
            urgency: urgency,
          ),
          isEmpty,
        );
        expect(
          empty.getFacilitiesByLocation(
            state: 'Lagos',
            cityArea: '',
            urgency: urgency,
          ),
          isEmpty,
        );
      }
    });
  });
}
