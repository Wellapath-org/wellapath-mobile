/// LOCAL-VERIFICATION-ONLY — gate matrix for the build-213 verification UI.
///
/// The Home doorway card and the status-screen synthetic-error button exist
/// only behind [CrashVerificationGate]. These tests prove the gate fails
/// closed: ordinary builds, production-context builds and every partial
/// define combination render neither control; only the exact approved
/// combination shows them; the synthetic error fires only through the
/// confirmed dialog action; and normal Home behaviour is unchanged in both
/// states.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/crash/crash_verification_gate.dart';
import 'package:wellapath_mobile/features/boot/boot_controller.dart';
import 'package:wellapath_mobile/features/home/home_screen.dart';
import 'package:wellapath_mobile/features/status/system_status_screen.dart';

/// The four defines of the approved combination, by define name.
const Map<String, String> kApprovedDefines = {
  'CRASH_VERIFICATION_TRIGGER_ENABLED': 'true',
  'CRASH_REPORTING_ENABLED': 'true',
  'CRASH_REPORTING_PRODUCTION_APPROVED': 'true',
  'CRASH_REPORTING_CONTEXT': 'internal-testing',
};

void main() {
  group('gate logic — fails closed', () {
    test('no defines at all (the ordinary build) resolves to disabled', () {
      expect(CrashVerificationGate.evaluate(const {}), isFalse);
    });

    test('every proper subset of the approved combination is disabled', () {
      final List<String> keys = kApprovedDefines.keys.toList();
      for (int mask = 0; mask < (1 << keys.length); mask++) {
        final Map<String, String> defines = {
          for (int i = 0; i < keys.length; i++)
            if (mask & (1 << i) != 0) keys[i]: kApprovedDefines[keys[i]]!,
        };
        final bool isFullSet = mask == (1 << keys.length) - 1;
        expect(
          CrashVerificationGate.evaluate(defines),
          isFullSet,
          reason: 'defines present: ${defines.keys.join(', ')}',
        );
      }
    });

    test('a production-context build is disabled even with all flags', () {
      final Map<String, String> defines = Map.of(kApprovedDefines);
      defines['CRASH_REPORTING_CONTEXT'] = 'production';
      expect(CrashVerificationGate.evaluate(defines), isFalse);
    });

    test('malformed or different values are disabled', () {
      const Map<String, List<String>> badValues = {
        'CRASH_VERIFICATION_TRIGGER_ENABLED': ['false', '1', 'yes', 'enabled'],
        'CRASH_REPORTING_ENABLED': ['false', '1', 'yes', ''],
        'CRASH_REPORTING_PRODUCTION_APPROVED': ['false', '1', 'approved', ''],
        'CRASH_REPORTING_CONTEXT': [
          'internal_testing',
          'internal-beta',
          'internal testing',
          'staging',
          '',
        ],
      };
      badValues.forEach((String key, List<String> values) {
        for (final String bad in values) {
          final Map<String, String> defines = Map.of(kApprovedDefines);
          defines[key] = bad;
          expect(
            CrashVerificationGate.evaluate(defines),
            isFalse,
            reason: '$key=$bad must fail closed',
          );
        }
      });
    });

    test('trimming and case are normalised, exactly as CrashConfig does', () {
      expect(
        CrashVerificationGate.evaluate({
          'CRASH_VERIFICATION_TRIGGER_ENABLED': ' TRUE ',
          'CRASH_REPORTING_ENABLED': 'True',
          'CRASH_REPORTING_PRODUCTION_APPROVED': 'true',
          'CRASH_REPORTING_CONTEXT': ' Internal-Testing ',
        }),
        isTrue,
      );
    });

    test('only the exact approved combination enables the gate', () {
      expect(CrashVerificationGate.evaluate(kApprovedDefines), isTrue);
    });

    test('this test binary itself resolves to disabled', () {
      expect(CrashVerificationGate.enabled, isFalse);
    });
  });

  group('home doorway card', () {
    final Finder card = find.text('Internal verification — System status');

    Future<void> pumpHome(WidgetTester tester, {bool? doorway}) async {
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(crashVerificationDoorwayEnabled: doorway)),
      );
      await tester.pump();
    }

    void expectNormalHomeServices() {
      expect(find.text('Check your symptoms'), findsOneWidget);
      expect(find.text('Find a clinic'), findsOneWidget);
      expect(find.text('Call emergency — 112'), findsOneWidget);
    }

    testWidgets('the ordinary/default build renders no card', (tester) async {
      await pumpHome(tester); // null override → the real (disabled) gate.
      expect(card, findsNothing);
      expect(find.text('Local build 213 only'), findsNothing);
      expectNormalHomeServices();
    });

    testWidgets('a gated-off build renders no card', (tester) async {
      await pumpHome(tester, doorway: false);
      expect(card, findsNothing);
      expectNormalHomeServices();
    });

    testWidgets('the approved combination shows the labelled card', (
      tester,
    ) async {
      await pumpHome(tester, doorway: true);
      expect(card, findsOneWidget);
      expect(find.text('Local build 213 only'), findsOneWidget);
      expectNormalHomeServices();
    });

    testWidgets('tapping the card opens the system status screen', (
      tester,
    ) async {
      await pumpHome(tester, doorway: true);
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byType(SystemStatusScreen), findsOneWidget);
    });
  });

  group('synthetic-error button', () {
    final Finder button = find.text('Send synthetic Sentry test error');

    Future<void> pumpStatus(WidgetTester tester, {bool? trigger}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SystemStatusScreen(
            result: const BootResult(status: BootStatus.success),
            crashVerificationTriggerEnabled: trigger,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the ordinary/default build renders no button', (tester) async {
      await pumpStatus(tester); // null override → the real (disabled) gate.
      expect(button, findsNothing);
      // The build-identity row remains, display-only.
      expect(find.textContaining('Build '), findsOneWidget);
    });

    testWidgets('a gated-off build renders no button', (tester) async {
      await pumpStatus(tester, trigger: false);
      expect(button, findsNothing);
    });

    testWidgets('the build row carries no gesture in any state', (
      tester,
    ) async {
      await pumpStatus(tester, trigger: true);
      for (int i = 0; i < 5; i++) {
        await tester.longPress(
          find.textContaining('Build '),
          warnIfMissed: false,
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the approved combination shows the button and dialog', (
      tester,
    ) async {
      await pumpStatus(tester, trigger: true);
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Send synthetic test error?'), findsOneWidget);
      expect(
        find.textContaining('no real personal or health information'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Send test error'), findsOneWidget);
    });

    testWidgets('cancel emits nothing', (tester) async {
      await pumpStatus(tester, trigger: true);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Send synthetic test error?'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('confirmation emits exactly the synthetic StateError', (
      tester,
    ) async {
      await pumpStatus(tester, trigger: true);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send test error'));
      await tester.pump();
      final Object? thrown = tester.takeException();
      expect(thrown, isA<StateError>());
      expect(
        (thrown as StateError).message,
        'synthetic crash verification 213',
      );
    });
  });
}
