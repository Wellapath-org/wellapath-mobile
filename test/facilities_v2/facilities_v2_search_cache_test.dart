/// The per-record normalization cache must be a pure speedup: identical
/// results to freshly-computed normalization, on every field and query
/// shape, including records that share instances across datasets.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/facilities_v2/facilities_v2_parser.dart';
import 'package:wellapath_mobile/core/facilities_v2/facilities_v2_search.dart';
import 'package:wellapath_mobile/core/facilities_v2/facility_v2.dart';

FacilityV2 _record(
  String id, {
  required String name,
  String? state,
  String? lga,
  String? cityArea,
}) => FacilityV2(
  id: id,
  name: name,
  latitude: 1.0,
  longitude: 1.0,
  rawType: null,
  emergencyCapable: null,
  state: state,
  lga: lga,
  cityArea: cityArea,
  phone: null,
  openingHours: null,
);

void main() {
  const search = FacilitiesV2Search();

  final facilities = [
    _record('a', name: 'ZZTest  Weird   Spacing Clinic', state: ' Lagos '),
    _record('b', name: 'ZZTest UPPER CASE HOSPITAL', state: 'LAGOS'),
    _record('c', name: 'ZZTest Kano Centre', state: 'Kano', lga: 'Nassarawa'),
    _record('d', name: 'ZZTest No State'),
    _record('e', name: 'ZZTest Area Match', state: 'Lagos', cityArea: 'Ikeja'),
    _record('f', name: 'ZZTest ikeja in name only', state: 'Kano'),
  ];

  test('byState matches normalized equality identically across repeats', () {
    // Note: ' Lagos ' is stored as-is here because this test constructs the
    // model directly; the parser trims. Normalization must still match it.
    for (var run = 0; run < 3; run++) {
      final lagos = search.byState(facilities, 'lagos');
      expect(lagos.map((f) => f.id), ['a', 'b', 'e'], reason: 'run $run');
      expect(search.byState(facilities, '  KANO '), hasLength(2));
      expect(search.byState(facilities, ''), isEmpty);
      expect(search.byState(facilities, 'nowhere'), isEmpty);
    }
  });

  test('byArea semantics unchanged: lga equality, city equality/contains, '
      'name contains — stable across repeated (cached) queries', () {
    for (var run = 0; run < 3; run++) {
      expect(
        search.byArea(facilities, 'ikeja').map((f) => f.id),
        ['e', 'f'],
        reason: 'run $run: city equality + name contains',
      );
      expect(search.byArea(facilities, 'Nassarawa').single.id, 'c');
      expect(search.byArea(facilities, 'ikeja', state: 'Lagos').single.id, 'e');
      expect(search.byArea(facilities, 'zz-none'), isEmpty);
      expect(search.byArea(facilities, ''), isEmpty);
    }
  });

  test('cached results equal a fresh normalization pass over every record', () {
    final wanted = FacilitiesV2Search.normalize('weird spacing');
    final fresh = facilities
        .where((f) => FacilitiesV2Search.normalize(f.name).contains(wanted))
        .map((f) => f.id)
        .toList();
    final viaSearch = search
        .byArea(facilities, 'weird spacing')
        .map((f) => f.id)
        .toList();
    expect(viaSearch, fresh);
    expect(viaSearch, ['a']);
  });

  test('null fields never match a non-empty query through the cache', () {
    // 'd' has null state/lga/cityArea; the '' sentinel must not leak.
    expect(search.byState(facilities, 'd'), isEmpty);
    final hits = search.byArea(facilities, 'no state');
    expect(hits.single.id, 'd', reason: 'name contains still works');
  });

  test('parser keeps a shared const map for empty provenance — artifact '
      'metadata and record parsing add no per-record baggage', () {
    final result = const FacilitiesV2Parser().parse({
      'schema_version': '2.0',
      '_metadata': {
        'source': {'attribution_citation': 'ZZTest Synthetic Citation.'},
      },
      'facilities': [
        {
          'id': 'zz1',
          'name': 'ZZTest One (synthetic)',
          'latitude': 1.0,
          'longitude': 1.0,
        },
        {
          'id': 'zz2',
          'name': 'ZZTest Two (synthetic)',
          'latitude': 2.0,
          'longitude': 2.0,
          'future_field': 'kept',
        },
      ],
    });
    final one = result.facilities[0].provenance;
    final two = result.facilities[1].provenance;
    expect(one, isEmpty);
    expect(identical(one, result.facilities[0].provenance), isTrue);
    // Empty provenance maps are the shared const instance.
    expect(identical(one, const <String, Object?>{}), isTrue);
    // Non-consumed fields still survive opaquely.
    expect(two, {'future_field': 'kept'});
  });
}
