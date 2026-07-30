import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/locator/nigeria_coverage.dart';

/// The facilities artifact is Nigeria-only. Without this gate a user abroad
/// is shown Nigerian clinics with distances in the thousands of kilometres,
/// which reads as a real recommendation rather than an empty result.
///
/// Box: latitude 4.0–14.0, longitude 2.5–15.0.

bool _inside(double lat, double lon) => isWithinNigeria(lat, lon);

void main() {
  group('inside Nigeria', () {
    test('Lagos', () => expect(_inside(6.5244, 3.3792), isTrue));
    test('Abuja (FCT)', () => expect(_inside(9.0765, 7.3986), isTrue));
    test('Kano', () => expect(_inside(12.0022, 8.5920), isTrue));
    test('Port Harcourt', () => expect(_inside(4.8156, 7.0498), isTrue));
    test('Maiduguri, near the eastern edge', () {
      expect(_inside(11.8311, 13.1510), isTrue);
    });
  });

  group('outside Nigeria', () {
    test('London', () => expect(_inside(51.5074, -0.1278), isFalse));
    test('Nairobi — east of the box', () {
      expect(_inside(-1.2921, 36.8219), isFalse);
    });
    test('Accra — west of the box', () {
      expect(_inside(5.6037, -0.1870), isFalse);
    });
    test('Algiers — north of the box', () {
      expect(_inside(36.7538, 3.0588), isFalse);
    });
    test('Cape Town — south of the box', () {
      expect(_inside(-33.9249, 18.4241), isFalse);
    });
    test('null island', () => expect(_inside(0, 0), isFalse));
  });

  group('boundaries are inclusive', () {
    test('each corner is inside', () {
      expect(_inside(4.0, 2.5), isTrue);
      expect(_inside(14.0, 2.5), isTrue);
      expect(_inside(4.0, 15.0), isTrue);
      expect(_inside(14.0, 15.0), isTrue);
    });

    test('just outside each edge is excluded', () {
      expect(_inside(3.99, 8.0), isFalse, reason: 'below min latitude');
      expect(_inside(14.01, 8.0), isFalse, reason: 'above max latitude');
      expect(_inside(9.0, 2.49), isFalse, reason: 'west of min longitude');
      expect(_inside(9.0, 15.01), isFalse, reason: 'east of max longitude');
    });
  });

  group('sign errors are caught', () {
    test('a negated latitude falls outside', () {
      // Lagos with the sign flipped lands in the South Atlantic. A dropped
      // minus sign is the classic geo bug; it must not read as in-coverage.
      expect(_inside(-6.5244, 3.3792), isFalse);
    });

    test('swapped lat/lon for Lagos falls outside', () {
      // Lagos is (6.52, 3.38). Swapped, (3.38, 6.52) is below the box.
      expect(_inside(3.3792, 6.5244), isFalse);
    });
  });
}
