import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/facilities_v2/facilities_v2_parser.dart';
import 'package:wellapath_mobile/core/facilities_v2/facility_v2.dart';

import 'fixture_support.dart';

void main() {
  const parser = FacilitiesV2Parser();

  group('synthetic fixture parses', () {
    late FacilitiesV2ParseResult result;

    setUpAll(() {
      result = parser.parse(readFixtureJson());
    });

    test('schema version is 2.0 and valid records all survive', () {
      expect(result.schemaVersion, '2.0');
      expect(result.facilities.map((f) => f.id), [
        'SYN-001',
        'SYN-002',
        'SYN-003',
        'SYN-004',
        'SYN-005',
        'SYN-006',
      ]);
    });

    test('the five malformed records are isolated, not fatal', () {
      // Missing coordinates, string latitude, out-of-range latitude, empty
      // id, and a non-map entry: each rejected individually, the artifact
      // still loads, nothing throws.
      expect(result.rejectedRecords, 5);
    });

    test('type = null is unknown — never coerced to a real type', () {
      final f = result.facilities.firstWhere((f) => f.id == 'SYN-003');
      expect(f.rawType, isNull);
      expect(f.type, FacilityTypeV2.unspecified);
      expect(f.type.isUnknown, isTrue);
    });

    test('an unknown future enum value survives with its raw value', () {
      final f = result.facilities.firstWhere((f) => f.id == 'SYN-005');
      expect(f.rawType, 'telehealth_pod_future_value');
      expect(f.type, FacilityTypeV2.unrecognized);
      expect(f.type.isUnknown, isTrue);
    });

    test('emergency_capable = null stays null — unknown, not false', () {
      final f = result.facilities.firstWhere((f) => f.id == 'SYN-003');
      expect(f.emergencyCapable, isNull);
      // And a real false stays false.
      final beta = result.facilities.firstWhere((f) => f.id == 'SYN-002');
      expect(beta.emergencyCapable, isFalse);
    });

    test('coordinates pass through exactly — no repair, snap or inference', () {
      final f = result.facilities.firstWhere((f) => f.id == 'SYN-001');
      expect(f.latitude, 6.51);
      expect(f.longitude, 3.37);
    });

    test('provenance and coordinate-audit fields are carried opaquely', () {
      final f = result.facilities.firstWhere((f) => f.id == 'SYN-001');
      expect(
        f.provenance.keys,
        containsAll(<String>['source_provenance', 'coordinate_audit']),
      );
    });

    test('missing phone and opening hours parse as absent', () {
      final gamma = result.facilities.firstWhere((f) => f.id == 'SYN-003');
      const presentation = FacilitiesV2Presentation(
        phonePublicationApproved: true,
        openingHoursPublicationApproved: true,
      );
      expect(presentation.phoneForDisplay(gamma), isNull);
      expect(
        presentation.openingHoursLabel(gamma).$1,
        OpeningHoursDisplay.unknown,
      );
    });
  });

  group('artifact-level rejection', () {
    test('wrong schema major is refused outright', () {
      expect(
        () => parser.parse({'schema_version': '1.1', 'facilities': <Object>[]}),
        throwsA(isA<FacilitiesV2ParseException>()),
      );
      expect(
        () => parser.parse({'schema_version': '3.0', 'facilities': <Object>[]}),
        throwsA(isA<FacilitiesV2ParseException>()),
      );
    });

    test('a 2.x minor is accepted (additive forward compatibility)', () {
      final result = parser.parse({
        'schema_version': '2.3',
        'facilities': [
          {
            'id': 'SYN-M',
            'name': 'ZZTest Minor (synthetic)',
            'latitude': 6.5,
            'longitude': 3.4,
          },
        ],
      });
      expect(result.facilities, hasLength(1));
    });

    test('missing schema version, non-list facilities, non-map artifact', () {
      for (final bad in <Object?>[
        {'facilities': <Object>[]},
        {'schema_version': '2.0', 'facilities': 'nope'},
        'not a map',
        null,
      ]) {
        expect(
          () => parser.parse(bad),
          throwsA(isA<FacilitiesV2ParseException>()),
          reason: '$bad must be rejected at artifact level',
        );
      }
    });

    test('an empty candidate is unusable, not silently empty', () {
      expect(
        () => parser.parse({'schema_version': '2.0', 'facilities': <Object>[]}),
        throwsA(
          isA<FacilitiesV2ParseException>().having(
            (e) => e.rejection,
            'rejection',
            FacilitiesV2ArtifactRejection.emptyFacilities,
          ),
        ),
      );
    });
  });
}
