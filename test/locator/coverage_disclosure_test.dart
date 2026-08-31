/// Coverage disclosure — the app must not imply national facility coverage.
///
/// The active artifact is `facilities.ng.v1.1`, published by `/config` at the
/// frozen Backend baseline. Every one of its 5,344 records is in Lagos, FCT or
/// Kano. Before this release the locator told an out-of-region user "We are
/// currently serving Nigeria", which reads as national coverage and is not
/// true of the data the app actually ships against.
///
/// These tests pin the correction. They are deliberately about *wording and
/// the covered-state list only* — no ranking, no emergency behaviour, no
/// clinical logic is asserted here, because none of it was changed.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/locator/nigeria_coverage.dart';

void main() {
  group('covered states match the active facilities artifact', () {
    test(
      'exactly Lagos, FCT and Kano — the three states in facilities 1.1',
      () {
        expect(kCoveredStates, equals(const ['Lagos', 'FCT', 'Kano']));
      },
    );

    test('no state appears twice', () {
      expect(kCoveredStates.toSet(), hasLength(kCoveredStates.length));
    });

    test('the list is not empty — an empty picker would offer nothing', () {
      expect(kCoveredStates, isNotEmpty);
    });
  });

  group('disclosure wording', () {
    test('names every covered state', () {
      // FCT is written "FCT (Abuja)" in the sentence, so match on the token
      // each entry contributes rather than the raw entry.
      for (final state in kCoveredStates) {
        expect(
          kCoverageDisclosure,
          contains(state),
          reason: '$state is covered but is not named in the disclosure',
        );
      }
    });

    test('spells out Abuja alongside FCT — users search for the city name', () {
      expect(kCoverageDisclosure, contains('Abuja'));
    });

    test('does not claim national coverage', () {
      final lower = kCoverageDisclosure.toLowerCase();
      for (final phrase in const [
        'nationwide',
        'nation-wide',
        'across nigeria',
        'all of nigeria',
        'anywhere in nigeria',
        'throughout nigeria',
        'every state',
        'all states',
      ]) {
        expect(
          lower,
          isNot(contains(phrase)),
          reason: 'disclosure must not imply national coverage: "$phrase"',
        );
      }
    });

    test('does not promise an expansion date', () {
      // The replaced wording said "will expand ... soon". A promise the
      // roadmap has not committed to is exactly the kind of claim this
      // disclosure exists to remove.
      expect(kCoverageDisclosure.toLowerCase(), isNot(contains('soon')));
    });

    test('is a single plain sentence, not a paragraph', () {
      expect(kCoverageDisclosure.trim(), endsWith('.'));
      expect(kCoverageDisclosure, isNot(contains('\n')));
    });
  });

  group('locator source has no surviving national-coverage claim', () {
    // Reads the shipped screen source directly. A wording regression is a
    // Product-visible defect that no widget test would necessarily catch,
    // because the offending string sits on a branch (out-of-region) that only
    // renders for a user physically outside Nigeria.
    late String source;

    setUpAll(() {
      source = File(
        'lib/features/locator/locator_screen.dart',
      ).readAsStringSync();
    });

    test('the retired "serving Nigeria ... expand" sentence is gone', () {
      expect(source, isNot(contains('We are currently serving Nigeria')));
      expect(source, isNot(contains('will expand')));
    });

    test('the state picker reads from kCoveredStates, not its own literal', () {
      expect(source, contains('_states = kCoveredStates'));
      expect(
        source,
        isNot(contains("_states = ['Lagos', 'FCT', 'Kano']")),
        reason: 'a second hardcoded list can drift from the artifact',
      );
    });

    test('the disclosure is referenced, not re-typed', () {
      expect(source, contains('kCoverageDisclosure'));
    });
  });

  group('coverage gate is unchanged by this correction', () {
    // The bounding box is a separate, coarser gate and this release does not
    // touch it. Pinned here so a future wording edit cannot quietly widen or
    // narrow who is allowed into the locator at all.
    test('the three covered state capitals remain inside the box', () {
      expect(isWithinNigeria(6.5244, 3.3792), isTrue, reason: 'Lagos');
      expect(isWithinNigeria(9.0765, 7.3986), isTrue, reason: 'Abuja (FCT)');
      expect(isWithinNigeria(12.0022, 8.5920), isTrue, reason: 'Kano');
    });

    test('a location outside Nigeria is still refused', () {
      expect(isWithinNigeria(51.5074, -0.1278), isFalse, reason: 'London');
      expect(isWithinNigeria(-1.2921, 36.8219), isFalse, reason: 'Nairobi');
    });

    test('an uncovered Nigerian state still passes the box gate', () {
      // Enugu is inside Nigeria but holds no facilities in the 1.1 artifact.
      // It must NOT be refused by the box — that gate is about country, not
      // data coverage — which is precisely why the disclosure is needed.
      expect(isWithinNigeria(6.5244, 7.5102), isTrue, reason: 'Enugu');
    });
  });
}
