/// WP-024: every locator state that lists no facility offers the 112 action.
///
/// Each test drives the real [LocatorScreen] into one such state through its
/// real inputs (cache, loader, location channel) and asserts that the shared
/// emergency control is on screen and dials 112. The control, its wording and
/// its dial behaviour are the home screen's, reused unchanged; nothing here
/// depends on urgency or triage output, and the states that DO list
/// facilities are checked to be unchanged.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/shared/widgets/emergency_call_row.dart';

import 'locator_harness.dart';

const double _lagosLat = 6.4550, _lagosLon = 3.3841;

final List<Map<String, dynamic>> _lagosHospitalOnly = <Map<String, dynamic>>[
  syntheticFacility(
    id: 'syn-la-1',
    name: 'Synthetic Lagos Hospital',
    state: 'Lagos',
    lat: _lagosLat,
    lon: _lagosLon,
    emergencyCapable: true,
  ),
];

void main() {
  final LocatorHarness harness = LocatorHarness();

  setUp(harness.setUp);
  tearDown(harness.tearDown);

  /// The fallback is present, carries the home screen's exact wording, and
  /// a tap hands `tel:112` to the dialer.
  Future<void> expectEmergencyFallback(WidgetTester tester) async {
    expect(find.byType(EmergencyCallRow), findsOneWidget);
    expect(find.text('Need urgent help?'), findsOneWidget);
    expect(find.text('Call emergency services on 112'), findsOneWidget);

    await tester.tap(find.byType(EmergencyCallRow));
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.launchedUrls, <String>['tel:112']);
  }

  group('facility data unavailable', () {
    testWidgets('download failed: error message plus 112', (tester) async {
      await tester.runAsync(harness.seedConfig);
      harness.markFacilitiesDownloadFailed();
      await harness.pumpLocator(tester);

      expect(
        find.textContaining('We could not load available facilities.'),
        findsOneWidget,
      );
      await expectEmergencyFallback(tester);
    });

    testWidgets('offline with no cached config: error message plus 112', (
      tester,
    ) async {
      // Nothing cached and no /config to download from: the state a device
      // that has never been online is in.
      await harness.pumpLocator(tester);

      expect(
        find.textContaining('We could not load available facilities.'),
        findsOneWidget,
      );
      await expectEmergencyFallback(tester);
    });
  });

  group('no usable location', () {
    setUp(() => harness.seedFacilities(_lagosHospitalOnly));

    testWidgets('location services off: manual search plus 112', (
      tester,
    ) async {
      harness.setLocation(FakeLocation(serviceEnabled: false));
      await harness.pumpLocator(tester);

      expect(
        find.textContaining('We could not access your location.'),
        findsOneWidget,
      );
      await expectEmergencyFallback(tester);
    });

    testWidgets('permission permanently denied: manual search plus 112', (
      tester,
    ) async {
      harness.setLocation(
        FakeLocation(permission: FakePermission.deniedForever),
      );
      await harness.pumpLocator(tester);

      expect(
        find.textContaining('We could not access your location.'),
        findsOneWidget,
      );
      await expectEmergencyFallback(tester);
    });

    testWidgets('rationale declined ("Maybe later"): manual search plus 112', (
      tester,
    ) async {
      harness.setLocation(FakeLocation(permission: FakePermission.denied));
      await harness.pumpLocator(tester);

      await tester.tap(find.text('Maybe later'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('We could not access your location.'),
        findsOneWidget,
      );
      await expectEmergencyFallback(tester);
    });

    testWidgets('location fix error: manual search plus 112', (tester) async {
      harness.setLocation(FakeLocation(throwOnPosition: true));
      await harness.pumpLocator(tester);

      expect(
        find.textContaining('We could not access your location.'),
        findsOneWidget,
      );
      await expectEmergencyFallback(tester);
    });

    testWidgets('outside Nigeria: region message plus 112', (tester) async {
      // London.
      harness.setLocation(FakeLocation(latitude: 51.5, longitude: -0.12));
      await harness.pumpLocator(tester);

      expect(
        find.textContaining('not yet available in your region'),
        findsOneWidget,
      );
      await expectEmergencyFallback(tester);
    });
  });

  group('searches that return nothing', () {
    setUp(() => harness.seedFacilities(_lagosHospitalOnly));

    for (final String urgency in const <String>['self_care', 'emergency']) {
      testWidgets('location search with no results ($urgency): 112', (
        tester,
      ) async {
        // self_care never lists hospitals, so this location search is empty.
        // For emergency it is not — that case asserts the opposite below, and
        // together they show the fallback follows what is on screen, not the
        // urgency.
        harness.setLocation(
          FakeLocation(latitude: _lagosLat, longitude: _lagosLon),
        );
        await harness.pumpLocator(tester, urgency: urgency);

        if (urgency == 'self_care') {
          expect(find.text('No facilities found.'), findsOneWidget);
          await expectEmergencyFallback(tester);
        } else {
          expect(find.byType(FlutterMap), findsOneWidget);
          expect(find.byType(EmergencyCallRow), findsNothing);
        }
      });
    }

    testWidgets('manual search with no results keeps 112; with results the '
        'list is shown unchanged', (tester) async {
      harness.setLocation(
        FakeLocation(permission: FakePermission.deniedForever),
      );
      await harness.pumpLocator(tester);

      Future<void> searchState(String state) async {
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(state).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Search'));
        await tester.pumpAndSettle();
      }

      await searchState('Kano');
      expect(find.text('No facilities found in this area.'), findsOneWidget);
      expect(find.byType(EmergencyCallRow), findsOneWidget);

      await searchState('Lagos');
      expect(find.text('Synthetic Lagos Hospital'), findsOneWidget);
      expect(find.byType(EmergencyCallRow), findsNothing);
    });
  });

  group('states that list facilities are unchanged', () {
    testWidgets('location search with results shows the map and no 112 row', (
      tester,
    ) async {
      await tester.runAsync(() => harness.seedFacilities(_lagosHospitalOnly));
      harness.setLocation(
        FakeLocation(latitude: _lagosLat, longitude: _lagosLon),
      );
      await harness.pumpLocator(tester, urgency: 'urgent');

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('1 of 30 shown'), findsOneWidget);
      expect(find.byType(EmergencyCallRow), findsNothing);
    });
  });

  group('one shared control', () {
    test('home and locator use the same widget and dial action', () {
      final String home = File(
        'lib/features/home/home_screen.dart',
      ).readAsStringSync();
      final String locator = File(
        'lib/features/locator/locator_screen.dart',
      ).readAsStringSync();
      expect(home, contains('EmergencyCallRow('));
      expect(home, contains('callEmergencyNumber()'));
      expect(locator, contains('EmergencyCallRow(onTap: callEmergencyNumber)'));
      // The dial target lives in exactly one place.
      expect(home, isNot(contains("path: '112'")));
      expect(locator, isNot(contains("path: '112'")));
    });

    test('the fallback is not gated on urgency or triage output', () {
      final String locator = File(
        'lib/features/locator/locator_screen.dart',
      ).readAsStringSync();
      final int start = locator.indexOf('bool get _showsNoFacilities');
      final int end = locator.indexOf('\n  }\n', start);
      final String getter = locator.substring(start, end);
      expect(getter, isNot(contains('urgency')));
    });
  });
}
