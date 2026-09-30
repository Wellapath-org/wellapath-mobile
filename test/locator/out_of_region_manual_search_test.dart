/// UX-002 — manual area search from the out-of-region state.
///
/// Before this change the out-of-region state was a dead end: an explanation
/// and a Back button, nothing else. The facility data is cached on the device
/// and the location-denied path already offers a manual state/area search, so
/// a user who travelled outside Nigeria lost the locator for no good reason.
///
/// The fix reuses that existing path rather than adding a second one. These
/// tests pin both halves of that claim: the behaviour is identical to the
/// denied path (asserted against the service), and there is genuinely only
/// one implementation (asserted against the source).
///
/// Nothing here asserts ordering, filtering, urgency or coverage detection —
/// none of those changed, and pinning them here would create a second place
/// to update when they legitimately do.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/locator/facility_locator_service.dart';
import 'package:wellapath_mobile/features/locator/nigeria_coverage.dart';

String _source() =>
    File('lib/features/locator/locator_screen.dart').readAsStringSync();

/// The body of `_buildOutsideCoverageView`, so assertions about that state
/// cannot accidentally match something elsewhere in a 1,200-line file.
String _outOfRegionBody() {
  final String src = _source();
  final int start = src.indexOf('Widget _buildOutsideCoverageView()');
  final int end = src.indexOf('\n  Widget _build', start + 10);
  expect(start, greaterThan(-1));
  expect(end, greaterThan(start));
  return src.substring(start, end);
}

Map<String, dynamic> _f({
  required String id,
  required String name,
  required String type,
  required String state,
  required String cityArea,
  bool emergency = false,
}) => <String, dynamic>{
  'facility_id': id,
  'name': name,
  'type': type,
  'state': state,
  'city_area': cityArea,
  'latitude': 6.5,
  'longitude': 3.3,
  'phone': null,
  'opening_hours': null,
  'emergency_capable': emergency,
};

final List<Map<String, dynamic>> _cached = <Map<String, dynamic>>[
  _f(
    id: 'ng_lag_001',
    name: 'Alpha Hospital',
    type: 'hospital',
    state: 'Lagos',
    cityArea: 'Ikeja',
    emergency: true,
  ),
  _f(
    id: 'ng_lag_002',
    name: 'Beta Clinic',
    type: 'clinic',
    state: 'Lagos',
    cityArea: 'Ikeja',
  ),
  _f(
    id: 'ng_lag_003',
    name: 'Gamma Pharmacy',
    type: 'pharmacy',
    state: 'Lagos',
    cityArea: 'Surulere',
  ),
  _f(
    id: 'ng_abj_001',
    name: 'Delta Hospital',
    type: 'hospital',
    state: 'FCT',
    cityArea: 'Garki',
  ),
  _f(
    id: 'ng_kan_001',
    name: 'Epsilon Hospital',
    type: 'hospital',
    state: 'Kano',
    cityArea: 'Nassarawa',
  ),
];

void main() {
  group('an outside-Nigeria location is still out of region', () {
    test('Kampala is outside the coverage box on both axes', () {
      // The founder's own test location. Latitude below the minimum and
      // longitude above the maximum, so this is not a borderline case.
      expect(isWithinNigeria(0.3136, 32.5811), isFalse);
    });

    test('coverage detection is unchanged by this work', () {
      expect(kNigeriaMinLat, 4.0);
      expect(kNigeriaMaxLat, 14.0);
      expect(kNigeriaMinLon, 2.5);
      expect(kNigeriaMaxLon, 15.0);
      expect(isWithinNigeria(6.5, 3.3), isTrue); // Lagos
    });

    test('the out-of-region explanation is preserved, not replaced', () {
      final String src = _source();
      expect(
        src,
        contains('WellaPath Clinic Locator is not yet available in your '),
      );
      // It must still come before the search, so the user learns why first.
      // Scoped to the method and matched on the call name alone: an
      // indentation-sensitive match would break on a reformat and silently
      // stop checking the ordering this test exists for.
      final String body = _outOfRegionBody();
      final int explanation = body.indexOf('not yet available in your ');
      final int search = body.indexOf('_manualSearchBody(');
      expect(explanation, greaterThan(-1));
      expect(search, greaterThan(explanation));
    });
  });

  group('manual search is reachable from the out-of-region state', () {
    test('the out-of-region view invokes the shared manual search body', () {
      final String src = _source();
      final int view = src.indexOf('Widget _buildOutsideCoverageView()');
      final int nextMethod = src.indexOf('\n  Widget _build', view + 10);
      final String body = src.substring(view, nextMethod);
      expect(body, contains('_manualSearchBody('));
    });

    test('both states share one predicate rather than branching apart', () {
      final String src = _source();
      expect(
        src,
        contains(
          'bool get _usingManualSearch => _locationDenied || _outsideCoverage;',
        ),
      );
      expect(src, contains('_usingManualSearch ? _manualResults.length'));
      expect(src, contains('if (_usingManualSearch) {'));
    });

    test('there is exactly one manual-search implementation', () {
      final String src = _source();
      // A second copy of the selector would drift from the first.
      expect("labelText: 'State'".allMatches(src).length, 1);
      expect("labelText: 'City / Area'".allMatches(src).length, 1);
      expect("child: const Text('Search')".allMatches(src).length, 1);
      expect(
        'Widget _manualSearchBody('.allMatches(src).length,
        1,
        reason: 'one definition',
      );
      expect(
        '_manualSearchBody('.allMatches(src).length,
        3,
        reason: 'one definition plus exactly two call sites',
      );
    });
  });

  group('results match the existing denied-location path', () {
    test('the same state and area return the same facilities', () {
      final service = FacilityLocatorService(_cached);
      // There is only one method, so both entry points cannot diverge. This
      // asserts the result a user actually gets.
      final denied = service.getFacilitiesByLocation(
        state: 'Lagos',
        cityArea: 'Ikeja',
        urgency: 'non_urgent',
      );
      final outOfRegion = service.getFacilitiesByLocation(
        state: 'Lagos',
        cityArea: 'Ikeja',
        urgency: 'non_urgent',
      );
      expect(outOfRegion, equals(denied));
      expect(
        denied.map((f) => f['facility_id']),
        containsAll(<String>['ng_lag_001', 'ng_lag_002']),
      );
    });

    test('every covered state is reachable', () {
      final service = FacilityLocatorService(_cached);
      for (final state in <String>['Lagos', 'FCT', 'Kano']) {
        final r = service.getFacilitiesByLocation(
          state: state,
          cityArea: '',
          urgency: 'non_urgent',
        );
        expect(r, isNotEmpty, reason: state);
      }
    });
  });

  group('the path works offline, on cached data', () {
    test('search runs against the in-memory list with no network call', () {
      // The service is constructed from the cached artifact and exposes no
      // network seam, so a manual search cannot depend on connectivity.
      final service = FacilityLocatorService(_cached);
      final r = service.getFacilitiesByLocation(
        state: 'Kano',
        cityArea: 'Nassarawa',
        urgency: 'non_urgent',
      );
      expect(r.single['facility_id'], 'ng_kan_001');
    });

    test('an empty cache degrades to an empty list, not an error', () {
      final service = FacilityLocatorService(<Map<String, dynamic>>[]);
      expect(
        service.getFacilitiesByLocation(
          state: 'Lagos',
          cityArea: '',
          urgency: 'non_urgent',
        ),
        isEmpty,
      );
    });
  });

  group('no distance is fabricated for a manual search', () {
    test('manual results carry no distance_km', () {
      final service = FacilityLocatorService(_cached);
      final r = service.getFacilitiesByLocation(
        state: 'Lagos',
        cityArea: '',
        urgency: 'non_urgent',
      );
      expect(r, isNotEmpty);
      for (final f in r) {
        expect(
          f.containsKey('distance_km'),
          isFalse,
          reason: 'there is no user position to measure from',
        );
      }
    });
  });

  group('usability is preserved', () {
    test('the search control keeps its 48px target', () {
      expect(_source(), contains('height: 48,'));
    });

    test('the manual lead text is a parameter, not a duplicated literal', () {
      final String src = _source();
      expect(src, contains('Widget _manualSearchBody({required String lead})'));
      expect(src, contains('We could not access your location.'));
      expect(src, contains('You can still search a covered area.'));
    });

    test('the out-of-region view scrolls, so large text cannot clip it', () {
      final String src = _source();
      final int view = src.indexOf('Widget _buildOutsideCoverageView()');
      final int nextMethod = src.indexOf('\n  Widget _build', view + 10);
      expect(
        src.substring(view, nextMethod),
        contains('SingleChildScrollView'),
      );
    });

    test('back navigation from the out-of-region state is preserved', () {
      final String src = _source();
      final int view = src.indexOf('Widget _buildOutsideCoverageView()');
      final int nextMethod = src.indexOf('\n  Widget _build', view + 10);
      final String body = src.substring(view, nextMethod);
      expect(body, contains('Navigator.of(context).pop()'));
      expect(body, contains('Back to Results'));
    });
  });
  group('nothing was added that this change must not add', () {
    test('the out-of-region view adds no dependency or stored preference', () {
      // Scoped and specific. An earlier version banned the bare substring
      // 'record', which would fail on the word "recorded" in any future
      // comment, and banned 'Telemetry', which read as "this path emits
      // none" — untrue, see the next test. These are the identifiers that
      // would actually indicate a new dependency.
      final String body = _outOfRegionBody();
      for (final banned in <String>[
        'SharedPreferences',
        'Dio(',
        'http.',
        'Analytics',
      ]) {
        expect(
          body,
          isNot(contains(banned)),
          reason: '$banned must not appear in the out-of-region view',
        );
      }
    });

    test('no NEW telemetry event type is introduced', () {
      // An honest statement of what is and is not true.
      //
      // The manual search already emitted FacilitySearchEvent(manualArea)
      // before this change, from the location-denied path. Reusing that path
      // means the same event can now also fire from the out-of-region state,
      // so its frequency changes even though nothing new was added.
      //
      // What must not change is the contract: one event type, payload of
      // search mode plus a clamped result count. No coordinates, no state or
      // area, no free text. _runManualSearch already documents why the
      // selected state and city/area are deliberately not recorded.
      final String src = _source();
      // Three emit sites exist and existed before: two nearby, one
      // manualArea. Pinning the count is what catches a fourth being added.
      expect('FacilitySearchEvent('.allMatches(src).length, 3);
      expect(
        'FacilitySearchMode.manualArea'.allMatches(src).length,
        1,
        reason: 'the manual path emits from exactly one place',
      );
      expect(src, contains('resultCount: results.length.clamp(0, 500)'));
      // The emitting method is untouched; only its reachability widened.
      expect(_outOfRegionBody(), isNot(contains('Telemetry.capture')));
    });
  });
}
