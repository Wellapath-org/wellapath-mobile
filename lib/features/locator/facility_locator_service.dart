import 'dart:math';

class FacilityLocatorService {
  final List<Map<String, dynamic>> facilities;

  FacilityLocatorService(this.facilities);

  static const double _sparseCoverageRadiusKm = 20.0;
  static const int _sparseCoverageMinResults = 3;

  static const Map<String, String> _typeChain = {
    'pharmacy': 'health_centre',
    'health_centre': 'clinic',
    'clinic': 'hospital',
  };

  Set<String> _typesForUrgency(String urgency) {
    switch (urgency) {
      case 'urgent':
      case 'non_urgent':
        return {'hospital', 'clinic'};
      case 'self_care':
        return {'pharmacy', 'health_centre'};
      default:
        return <String>{};
    }
  }

  List<Map<String, dynamic>> _sortedByDistance(
    List<Map<String, dynamic>> input,
  ) {
    final sorted = List<Map<String, dynamic>>.from(input);
    sorted.sort(
      (a, b) =>
          (a['distance_km'] as double).compareTo(b['distance_km'] as double),
    );
    return sorted;
  }

  List<Map<String, dynamic>> getNearbyFacilities({
    required double userLat,
    required double userLon,
    required String urgency,
    int maxResults = 30,
  }) {
    final withDistance = facilities.map((facility) {
      final lat = (facility['latitude'] as num?)?.toDouble();
      final lon = (facility['longitude'] as num?)?.toDouble();
      final distance = (lat != null && lon != null)
          ? _haversineDistance(userLat, userLon, lat, lon)
          : double.infinity;
      return {...facility, 'distance_km': distance};
    }).toList();

    final isEmergency = urgency == 'emergency';
    final allowedTypes = _typesForUrgency(urgency);

    List<Map<String, dynamic>> filtered = isEmergency
        ? List<Map<String, dynamic>>.from(withDistance)
        : withDistance
              .where((facility) => allowedTypes.contains(facility['type']))
              .toList();

    if (isEmergency) {
      final emergencyCapable = _sortedByDistance(
        filtered
            .where((facility) => facility['emergency_capable'] == true)
            .toList(),
      );
      final others = _sortedByDistance(
        filtered
            .where((facility) => facility['emergency_capable'] != true)
            .toList(),
      );
      filtered = [...emergencyCapable, ...others];
    } else {
      filtered = _sortedByDistance(filtered);

      final nearbyCount = filtered
          .where(
            (facility) =>
                (facility['distance_km'] as double) <= _sparseCoverageRadiusKm,
          )
          .length;

      if (nearbyCount < _sparseCoverageMinResults) {
        final expandedTypes = Set<String>.from(allowedTypes);
        for (final type in allowedTypes) {
          final nextTier = _typeChain[type];
          if (nextTier != null) expandedTypes.add(nextTier);
        }

        filtered = _sortedByDistance(
          withDistance
              .where((facility) => expandedTypes.contains(facility['type']))
              .toList(),
        );
      }
    }

    return filtered.take(maxResults).toList();
  }

  List<Map<String, dynamic>> getFacilitiesByLocation({
    required String state,
    required String cityArea,
    required String urgency,
  }) {
    var results = facilities.where((facility) {
      final facilityState = (facility['state'] as String?)?.toLowerCase();
      return facilityState != null && facilityState == state.toLowerCase();
    }).toList();

    if (cityArea.isNotEmpty) {
      results = results.where((facility) {
        final facilityCityArea = (facility['city_area'] as String?)
            ?.toLowerCase();
        return facilityCityArea != null &&
            facilityCityArea == cityArea.toLowerCase();
      }).toList();
    }

    if (urgency != 'emergency') {
      final allowedTypes = _typesForUrgency(urgency);
      results = results
          .where((facility) => allowedTypes.contains(facility['type']))
          .toList();
    }

    results.sort((a, b) {
      final aCapable = a['emergency_capable'] == true;
      final bCapable = b['emergency_capable'] == true;
      if (aCapable != bCapable) return aCapable ? -1 : 1;

      final aName = (a['name'] as String?) ?? '';
      final bName = (b['name'] as String?) ?? '';
      return aName.compareTo(bName);
    });

    return results.take(30).toList();
  }

  double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * pi / 180;
}
