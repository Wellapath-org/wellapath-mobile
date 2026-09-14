import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/facilities_v2/facilities_v2_parser.dart';
import 'package:wellapath_mobile/core/facilities_v2/facility_v2.dart';

import 'fixture_support.dart';

void main() {
  late List<FacilityV2> facilities;

  setUpAll(() {
    facilities = const FacilitiesV2Parser().parse(readFixtureJson()).facilities;
  });

  group('v2 phone numbers stay hidden pending source authorization', () {
    test('the default presentation exposes no phone for any record', () {
      const pending = FacilitiesV2Presentation.pendingApproval;
      for (final f in facilities) {
        expect(
          pending.phoneForDisplay(f),
          isNull,
          reason:
              '${f.id} must expose no phone CTA while authorization is '
              'unresolved',
        );
      }
    });

    test('approval defaults are off in the type itself', () {
      const fresh = FacilitiesV2Presentation();
      expect(fresh.phonePublicationApproved, isFalse);
      expect(fresh.openingHoursPublicationApproved, isFalse);
    });

    test('even after approval, a missing phone shows nothing', () {
      const approved = FacilitiesV2Presentation(phonePublicationApproved: true);
      final noPhone = facilities.firstWhere((f) => f.id == 'SYN-003');
      expect(approved.phoneForDisplay(noPhone), isNull);
      final withPhone = facilities.firstWhere((f) => f.id == 'SYN-001');
      expect(approved.phoneForDisplay(withPhone), '+234000000001');
    });
  });

  group('opening hours are never presented as open', () {
    test('missing or unknown hours resolve to unknown, not open', () {
      const approved = FacilitiesV2Presentation(
        openingHoursPublicationApproved: true,
      );
      for (final id in const ['SYN-003', 'SYN-004', 'SYN-006']) {
        final f = facilities.firstWhere((f) => f.id == id);
        final (display, label) = approved.openingHoursLabel(f);
        expect(display, OpeningHoursDisplay.unknown);
        expect(label, isNull);
      }
    });

    test('pending approval hides even present hours', () {
      const pending = FacilitiesV2Presentation.pendingApproval;
      final f = facilities.firstWhere((f) => f.id == 'SYN-001');
      expect(pending.openingHoursLabel(f).$1, OpeningHoursDisplay.unknown);
    });

    test('the display enum has no "open" state to misuse', () {
      expect(
        OpeningHoursDisplay.values.map((v) => v.name),
        isNot(contains('open')),
      );
    });
  });
}
