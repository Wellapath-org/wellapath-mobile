/// "Nearby" wording — RC-BLK-008, mitigated by truthful wording.
///
/// `getNearbyFacilities` applies **no distance cap**. A user in an uncovered
/// state is handed the 30 nearest records from Lagos, FCT or Kano, which can be
/// hundreds of kilometres away. Calling that list "nearby" is not true.
///
/// This step does **not** add a distance cap and does **not** change ranking,
/// filtering, emergency logic or facility selection — that is a Product
/// decision about geographic search, and changing ranking is out of scope for a
/// release-safe fix. What changes is the claim the UI makes: neutral wording
/// plus a prominent distance on every result, so the user judges proximity from
/// the number rather than from an adjective.
///
/// RC-BLK-008 is therefore **mitigated, not resolved**. The tests below pin the
/// wording; they deliberately assert nothing about ordering, because nothing
/// about ordering changed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screens whose user-visible strings must not promise proximity.
const List<String> _userFacingSources = [
  'lib/features/locator/locator_screen.dart',
  'lib/features/locator/facility_card.dart',
  'lib/features/home/home_screen.dart',
  'lib/features/results/results_screen.dart',
  'lib/features/results/red_flag_interrupt_screen.dart',
];

/// Strips `//` line comments so a comment explaining the history of the word
/// "nearby" does not read as a user-visible claim.
String _codeOnly(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('no user-visible copy promises proximity', () {
    for (final path in _userFacingSources) {
      test('${path.split('/').last} contains no "nearby" claim', () {
        final code = _codeOnly(File(path).readAsStringSync());

        // Quoted strings only — this is about what the user reads.
        final quoted = RegExp(
          r"'([^']*)'",
        ).allMatches(code).map((m) => m.group(1)!);

        for (final literal in quoted) {
          final lower = literal.toLowerCase();
          // 'nearby' is also a fixed telemetry enum value in the backend
          // contract; it is never rendered, and renaming it would break the
          // contract. Only exclude that exact standalone token.
          if (lower == 'nearby') continue;

          expect(
            lower.contains('nearby') || lower.contains('near me'),
            isFalse,
            reason:
                '$path still shows "$literal" — the result list can span '
                'hundreds of kilometres, so it may not be called nearby',
          );
        }
      });
    }
  });

  group('neutral replacements are in place', () {
    late String locator;

    setUpAll(() {
      locator = File(
        'lib/features/locator/locator_screen.dart',
      ).readAsStringSync();
    });

    test('the empty state is neutral and keeps the coverage disclosure', () {
      expect(locator, contains("'No facilities found.'"));
      expect(locator, isNot(contains("'No nearby facilities found.'")));
      expect(
        locator,
        contains('kCoverageDisclosure'),
        reason: 'coverage must still be named alongside an empty result',
      );
    });

    test('the loading state is neutral', () {
      expect(locator, contains('Finding available facilities'));
      expect(locator, isNot(contains('Checking nearby care centers')));
    });

    test('the load-failure message is neutral', () {
      expect(locator, contains('could not load available facilities'));
    });

    test('the location rationale explains sorting, not proximity', () {
      // The permission prompt must justify the location request honestly:
      // location orders the list, it does not mean a facility is close.
      expect(locator, contains('sort available health facilities'));
      expect(locator, contains('never leaves your device'));
    });
  });

  group('distance stays prominent', () {
    test('the facility card renders a distance in km', () {
      final card = File(
        'lib/features/locator/facility_card.dart',
      ).readAsStringSync();

      expect(card, contains('km away'));
      expect(card, contains("facility['distance_km']"));
    });

    test('the distance is emphasised, not incidental', () {
      final card = File(
        'lib/features/locator/facility_card.dart',
      ).readAsStringSync();

      // With the adjective gone, the number is what tells the user how far a
      // facility is — it must not be styled as a throwaway detail.
      final distanceBlock = card.substring(card.indexOf('km away'));
      expect(distanceBlock, contains('FontWeight.w600'));
    });
  });

  group('ranking and selection are untouched by this wording change', () {
    late String service;

    setUpAll(() {
      service = File(
        'lib/features/locator/facility_locator_service.dart',
      ).readAsStringSync();
    });

    test('no distance cap was introduced', () {
      // The mitigation is wording. A cap would change which facilities are
      // returned, which this step is explicitly not allowed to do.
      expect(service, isNot(contains('maxDistanceKm')));
      expect(service, isNot(contains('_maxDistance')));
    });

    test('emergency-capable ordering is still present', () {
      expect(service, contains("facility['emergency_capable'] == true"));
      expect(service, contains('emergencyCapable'));
    });

    test('the sparse-coverage tier fallback is unchanged', () {
      expect(service, contains('_sparseCoverageRadiusKm'));
      expect(service, contains('_sparseCoverageMinResults'));
      expect(service, contains('_typeChain'));
    });

    test('distance sorting is still what orders the list', () {
      expect(service, contains('_sortedByDistance'));
      expect(service, contains('_haversineDistance'));
    });
  });
}
