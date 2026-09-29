// Attribution is a licence condition of CC BY 4.0 and ODbL 1.0, so these
// tests guard a legal obligation rather than a presentation preference.
// They are deliberately literal: each asserts a specific string a licensor
// would look for.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/locator/facility_attribution.dart';

import 'dart:io';

void main() {
  group('attribution content', () {
    test('credits OpenStreetMap contributors in the required form', () {
      expect(FacilityAttribution.osmCredit, '© OpenStreetMap contributors');
    });

    test('names both licences', () {
      expect(FacilityAttribution.grid3Licence, 'CC BY 4.0');
      expect(FacilityAttribution.osmLicence, 'ODbL 1.0');
    });

    test('links both licences and both sources over https', () {
      const List<String> urls = <String>[
        FacilityAttribution.grid3LicenceUrl,
        FacilityAttribution.grid3SourceUrl,
        FacilityAttribution.osmLicenceUrl,
        FacilityAttribution.osmSourceUrl,
      ];
      for (final String url in urls) {
        final Uri uri = Uri.parse(url);
        expect(uri.scheme, 'https', reason: url);
        expect(uri.host, isNotEmpty, reason: url);
      }
    });

    test('cites GRID3 by its producer', () {
      expect(FacilityAttribution.grid3Citation, contains('CIESIN'));
      expect(
        FacilityAttribution.grid3Citation,
        contains('Columbia University'),
      );
    });

    test('discloses modification, as both licences require', () {
      expect(
        FacilityAttribution.modificationStatement.toLowerCase(),
        contains('modified'),
      );
    });

    test('states non-endorsement and names every source', () {
      const String s = FacilityAttribution.nonEndorsementStatement;
      expect(s, contains('do not'));
      expect(s, contains('endorse'));
      expect(s, contains('GRID3'));
      expect(s, contains('OpenStreetMap'));
    });

    test('the collapsed summary alone carries both credits', () {
      // The footer is collapsed by default, so the summary has to stand on
      // its own as the attribution a user actually sees.
      const String s = FacilityAttribution.summary;
      expect(s, contains('GRID3'));
      expect(s, contains('CC BY 4.0'));
      expect(s, contains('© OpenStreetMap contributors'));
      expect(s, contains('ODbL 1.0'));
    });
  });

  group('attribution reachability', () {
    testWidgets('both credits are visible without any interaction', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FacilityAttributionFooter())),
      );
      expect(find.text('Facility data sources'), findsOneWidget);
      expect(find.textContaining('© OpenStreetMap contributors'), findsWidgets);
      expect(find.textContaining('CC BY 4.0'), findsWidgets);
    });

    testWidgets('expanding reveals the citation, licences and disclaimers', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: FacilityAttributionFooter()),
          ),
        ),
      );
      await tester.tap(find.text('Licences and credits'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('GRID3 NGA Health Facilities v2.0'),
        findsOneWidget,
      );
      expect(find.textContaining('do not endorse'), findsOneWidget);
      expect(
        find.textContaining('modified from the originals'),
        findsOneWidget,
      );
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('every tappable target is at least 44px tall', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: FacilityAttributionFooter()),
          ),
        ),
      );
      await tester.tap(find.text('Licences and credits'));
      await tester.pumpAndSettle();

      for (final Element e in find.byType(InkWell).evaluate()) {
        expect(
          e.size!.height,
          greaterThanOrEqualTo(44.0),
          reason: 'tap target too small',
        );
      }
    });
  });

  group('attribution stays mounted in the locator', () {
    test('locator_screen.dart imports and renders the footer', () {
      final String src = File(
        'lib/features/locator/locator_screen.dart',
      ).readAsStringSync();
      // A source-level pin: the footer is easy to delete by accident while
      // refactoring the screen, and deleting it breaks a licence condition
      // rather than a layout.
      expect(src, contains("import 'facility_attribution.dart';"));
      expect(src, contains('const FacilityAttributionFooter()'));
    });

    test('the footer sits outside the body, so no state can hide it', () {
      final String src = File(
        'lib/features/locator/locator_screen.dart',
      ).readAsStringSync();
      final int bodyIndex = src.indexOf('Expanded(child: _buildBody())');
      final int footerIndex = src.indexOf('const FacilityAttributionFooter()');
      expect(bodyIndex, greaterThan(-1));
      expect(footerIndex, greaterThan(bodyIndex));
    });
  });
}
