/// WP-023: the location-based search has a maximum distance.
///
/// What is pinned here is the technical behaviour only: results beyond the
/// bound are not listed, the bound never reorders what remains, and an empty
/// in-range result shows an explicit "nothing within range" state. The VALUE
/// of the bound is a clinical/product decision that is still open
/// (location_search_radius.dart, CLINICAL DECISION REQUIRED), so the service
/// tests pass their own radius wherever the exact number matters and only
/// one test refers to the placeholder default.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/locator/facility_locator_service.dart';
import 'package:wellapath_mobile/features/locator/location_search_radius.dart';

import 'locator_harness.dart';

// Synthetic coordinates. Lagos Island, Ikeja (~16 km from it), Kano city and
// a point in Sokoto state roughly 400 km from Kano.
const double _lagosLat = 6.4550, _lagosLon = 3.3841;
const double _ikejaLat = 6.6018, _ikejaLon = 3.3515;
const double _kanoLat = 12.0022, _kanoLon = 8.5920;
const double _sokotoLat = 13.0600, _sokotoLon = 5.2400;

final List<Map<String, dynamic>> _facilities = <Map<String, dynamic>>[
  syntheticFacility(
    id: 'syn-la-1',
    name: 'Synthetic Lagos Hospital',
    state: 'Lagos',
    lat: _lagosLat,
    lon: _lagosLon,
    emergencyCapable: true,
  ),
  syntheticFacility(
    id: 'syn-la-2',
    name: 'Synthetic Ikeja Clinic',
    type: 'clinic',
    state: 'Lagos',
    lat: _ikejaLat,
    lon: _ikejaLon,
  ),
  syntheticFacility(
    id: 'syn-ka-1',
    name: 'Synthetic Kano Hospital',
    state: 'Kano',
    lat: _kanoLat,
    lon: _kanoLon,
    emergencyCapable: true,
  ),
];

List<String> _ids(List<Map<String, dynamic>> results) =>
    results.map((f) => f['facility_id'] as String).toList();

void main() {
  final FacilityLocatorService service = FacilityLocatorService(_facilities);

  group('the bound is a single named constant', () {
    test('the default comes from kLocationSearchMaxRadiusKm', () {
      expect(kLocationSearchMaxRadiusKm, greaterThan(0));
      // A user standing in Lagos gets the Lagos records and not Kano's,
      // which is ~830 km away under any plausible radius.
      final results = service.getNearbyFacilities(
        userLat: _lagosLat,
        userLon: _lagosLon,
        urgency: 'urgent',
      );
      expect(
        results.every(
          (f) => (f['distance_km'] as double) <= kLocationSearchMaxRadiusKm,
        ),
        isTrue,
      );
      expect(_ids(results), isNot(contains('syn-ka-1')));
    });

    test('is flagged as an open clinical decision, not a decided value', () {
      final source = File(
        'lib/features/locator/location_search_radius.dart',
      ).readAsStringSync();
      expect(source, contains('CLINICAL DECISION REQUIRED'));
      // The service must take its default from the constant, not a literal.
      final service = File(
        'lib/features/locator/facility_locator_service.dart',
      ).readAsStringSync();
      expect(
        service,
        contains('double maxDistanceKm = kLocationSearchMaxRadiusKm'),
      );
    });
  });

  group('getNearbyFacilities applies the bound as a filter only', () {
    test('a facility beyond the bound is not returned', () {
      final results = service.getNearbyFacilities(
        userLat: _lagosLat,
        userLon: _lagosLon,
        urgency: 'urgent',
        maxDistanceKm: 10,
      );
      // Ikeja is ~16 km away: outside a 10 km bound.
      expect(_ids(results), <String>['syn-la-1']);
    });

    test('a facility exactly on the bound is kept (inclusive)', () {
      final unbounded = service.getNearbyFacilities(
        userLat: _lagosLat,
        userLon: _lagosLon,
        urgency: 'urgent',
        maxDistanceKm: double.infinity,
      );
      final ikejaKm =
          unbounded.firstWhere(
                (f) => f['facility_id'] == 'syn-la-2',
              )['distance_km']
              as double;
      final results = service.getNearbyFacilities(
        userLat: _lagosLat,
        userLon: _lagosLon,
        urgency: 'urgent',
        maxDistanceKm: ikejaKm,
      );
      expect(_ids(results), contains('syn-la-2'));
    });

    test('nothing in range returns an empty list, not distant records', () {
      final results = service.getNearbyFacilities(
        userLat: _sokotoLat,
        userLon: _sokotoLon,
        urgency: 'urgent',
        maxDistanceKm: 100,
      );
      expect(results, isEmpty);
    });

    for (final urgency in const <String>[
      'emergency',
      'urgent',
      'non_urgent',
      'self_care',
    ]) {
      test('$urgency: in-range order is exactly the unbounded order', () {
        // The bound must not change ranking, the type filter or the
        // emergency_capable-first ordering: the bounded list is the
        // unbounded list with the out-of-range entries removed, in place.
        final unbounded = service.getNearbyFacilities(
          userLat: _lagosLat,
          userLon: _lagosLon,
          urgency: urgency,
          maxDistanceKm: double.infinity,
        );
        final bounded = service.getNearbyFacilities(
          userLat: _lagosLat,
          userLon: _lagosLon,
          urgency: urgency,
          maxDistanceKm: 100,
        );
        expect(
          _ids(bounded),
          _ids(
            unbounded
                .where((f) => (f['distance_km'] as double) <= 100)
                .toList(),
          ),
        );
      });
    }

    test('emergency: capable-first ordering is preserved within range', () {
      final results = service.getNearbyFacilities(
        userLat: _ikejaLat,
        userLon: _ikejaLon,
        urgency: 'emergency',
        maxDistanceKm: 100,
      );
      // The capable Lagos hospital still ranks above the closer clinic.
      expect(_ids(results), <String>['syn-la-1', 'syn-la-2']);
    });

    test('a record without coordinates is not listed by distance', () {
      final withMissing = FacilityLocatorService(<Map<String, dynamic>>[
        ..._facilities,
        <String, dynamic>{
          ...syntheticFacility(
            id: 'syn-nocoord',
            name: 'Synthetic No-Coordinates Hospital',
            state: 'Lagos',
            lat: 0,
            lon: 0,
          ),
          'latitude': null,
          'longitude': null,
        },
      ]);
      final results = withMissing.getNearbyFacilities(
        userLat: _lagosLat,
        userLon: _lagosLon,
        urgency: 'urgent',
      );
      expect(_ids(results), isNot(contains('syn-nocoord')));
    });
  });

  group('locator screen', () {
    final LocatorHarness harness = LocatorHarness();

    setUp(() async {
      await harness.setUp();
      await harness.seedFacilities(_facilities);
    });
    tearDown(harness.tearDown);

    testWidgets(
      'no facility in range shows the out-of-range state, not a list',
      (tester) async {
        harness.setLocation(
          FakeLocation(latitude: _sokotoLat, longitude: _sokotoLon),
        );
        await harness.pumpLocator(tester);

        expect(find.text('No facilities found.'), findsOneWidget);
        expect(
          find.textContaining(
            'WellaPath has no facility within '
            '${kLocationSearchMaxRadiusKm.round()} km of your location.',
          ),
          findsOneWidget,
        );
        // Kano is ~400 km away: it must not be presented from the location
        // search, and neither the map nor the Map/List toggle is shown.
        expect(find.text('Synthetic Kano Hospital'), findsNothing);
        expect(find.byType(FlutterMap), findsNothing);
        expect(find.text('Map'), findsNothing);
        expect(find.textContaining('of 30 shown'), findsNothing);
        // The covered-area manual search is offered instead.
        expect(
          find.textContaining('You can still search a covered area.'),
          findsOneWidget,
        );
        expect(find.text('Search'), findsOneWidget);
      },
    );

    testWidgets('manual search from the out-of-range state still works', (
      tester,
    ) async {
      harness.setLocation(
        FakeLocation(latitude: _sokotoLat, longitude: _sokotoLon),
      );
      await harness.pumpLocator(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kano').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      // Chosen knowingly from a state picker; the manual search is not
      // distance-based and is unaffected by the bound.
      expect(find.text('Synthetic Kano Hospital'), findsOneWidget);
    });

    testWidgets('a facility in range is still shown on the map', (
      tester,
    ) async {
      harness.setLocation(
        FakeLocation(latitude: _lagosLat, longitude: _lagosLon),
      );
      await harness.pumpLocator(tester);

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('2 of 30 shown'), findsOneWidget);
      expect(find.text('No facilities found.'), findsNothing);
    });
  });
}
