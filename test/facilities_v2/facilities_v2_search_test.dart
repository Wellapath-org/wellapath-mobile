import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/facilities_v2/facilities_v2_parser.dart';
import 'package:wellapath_mobile/core/facilities_v2/facilities_v2_search.dart';
import 'package:wellapath_mobile/core/facilities_v2/facility_v2.dart';

import 'fixture_support.dart';

void main() {
  const search = FacilitiesV2Search();
  late List<FacilityV2> facilities;

  setUpAll(() {
    facilities = const FacilitiesV2Parser().parse(readFixtureJson()).facilities;
  });

  group('deterministic normalization', () {
    test('case, edge whitespace and internal runs collapse identically', () {
      expect(FacilitiesV2Search.normalize('  LAGOS  '), 'lagos');
      expect(FacilitiesV2Search.normalize('Testville   LGA'), 'testville lga');
      expect(
        FacilitiesV2Search.normalize('Testville\tLGA'),
        FacilitiesV2Search.normalize('testville lga'),
      );
    });

    test('same input always produces the same output', () {
      const input = '  Alpha   QUARTER ';
      final first = FacilitiesV2Search.normalize(input);
      for (var i = 0; i < 100; i++) {
        expect(FacilitiesV2Search.normalize(input), first);
      }
    });
  });

  group('state search', () {
    test('finds by state, case-insensitively', () {
      expect(search.byState(facilities, 'lagos').map((f) => f.id), [
        'SYN-001',
        'SYN-002',
        'SYN-005',
      ]);
      expect(search.byState(facilities, ' KANO '), hasLength(2));
    });

    test('unknown state -> empty, empty query -> empty', () {
      expect(search.byState(facilities, 'Enugu'), isEmpty);
      expect(search.byState(facilities, '  '), isEmpty);
    });
  });

  group('LGA / city / area search', () {
    test('matches by LGA field', () {
      expect(search.byArea(facilities, 'Sampletown LGA').map((f) => f.id), [
        'SYN-003',
        'SYN-006',
      ]);
    });

    test('matches by city_area, optionally scoped to a state', () {
      expect(
        search.byArea(facilities, 'alpha quarter', state: 'Lagos'),
        hasLength(1),
      );
      expect(
        search.byArea(facilities, 'alpha quarter', state: 'Kano'),
        isEmpty,
      );
    });

    test('null-type records are found by area search like any other', () {
      final hits = search.byArea(facilities, 'Gamma Ward');
      expect(hits.single.id, 'SYN-003');
      expect(hits.single.type.isUnknown, isTrue);
    });
  });

  group('distance sorting is local and deterministic', () {
    test('sorts by haversine distance around the given point', () {
      final sorted = search.sortByDistance(
        facilities,
        userLat: 6.51,
        userLon: 3.37,
      );
      expect(sorted.first.$1.id, 'SYN-001');
      expect(sorted.first.$2, closeTo(0, 0.001));
      // Kano records are ~600km+ away and must sort last.
      expect(sorted.last.$1.state, 'Kano');
      // Distances strictly non-decreasing.
      for (var i = 1; i < sorted.length; i++) {
        expect(sorted[i].$2, greaterThanOrEqualTo(sorted[i - 1].$2));
      }
    });

    test('is a pure function — input records are not mutated', () {
      final before = facilities.map((f) => f.id).toList();
      search.sortByDistance(facilities, userLat: 9.0, userLon: 7.5);
      expect(facilities.map((f) => f.id).toList(), before);
    });
  });

  group('null and unknown types stay visible', () {
    test('urgency filters retain unknown-type records', () {
      for (final urgency in const ['urgent', 'non_urgent', 'self_care']) {
        final result = search.filterForUrgency(facilities, urgency);
        final ids = result.map((f) => f.id).toSet();
        expect(
          ids.containsAll(<String>{'SYN-003', 'SYN-005', 'SYN-006'}),
          isTrue,
          reason: 'unknown-type records must remain visible under "$urgency"',
        );
      }
    });

    test(
      'a filter can never come back empty solely because types are null',
      () {
        final allNullType = [
          for (final f in facilities)
            if (f.type.isUnknown) f,
        ];
        expect(allNullType, isNotEmpty, reason: 'fixture precondition');
        for (final urgency in const ['urgent', 'non_urgent', 'self_care']) {
          expect(
            search.filterForUrgency(allNullType, urgency),
            isNotEmpty,
            reason: 'null-only input must not filter to empty under "$urgency"',
          );
        }
      },
    );

    test('typed matches come first, unknown types after — never dropped', () {
      final result = search.filterForUrgency(facilities, 'urgent');
      expect(result.first.type, isNot(FacilityTypeV2.unspecified));
      expect(result.map((f) => f.id), contains('SYN-006'));
    });

    test('type is never inferred from the facility name', () {
      // SYN-006 is named "...Hospital Pharmacy Corner..." with type null.
      // It must stay unknown — not become a hospital or a pharmacy.
      final f = facilities.firstWhere((f) => f.id == 'SYN-006');
      expect(f.type, FacilityTypeV2.unspecified);
      // And it must not be promoted into the typed 'matched' block of any
      // urgency filter: it belongs to the unknown tail.
      final urgent = search.filterForUrgency([f], 'urgent');
      final selfCare = search.filterForUrgency([f], 'self_care');
      expect(urgent.single.type.isUnknown, isTrue);
      expect(selfCare.single.type.isUnknown, isTrue);
    });
  });

  group('offline / cached search', () {
    test('search works over records parsed from a cached raw body', () {
      // Simulates the offline path: raw cached bytes -> parse -> search,
      // no network object anywhere in the chain.
      final cachedRaw = readFixtureRaw();
      final reparsed = const FacilitiesV2Parser()
          .parse(readFixtureJsonFrom(cachedRaw))
          .facilities;
      expect(search.byState(reparsed, 'Lagos'), hasLength(3));
      expect(
        search
            .sortByDistance(reparsed, userLat: 12.0, userLon: 8.5)
            .first
            .$1
            .state,
        'Kano',
      );
    });
  });
}
