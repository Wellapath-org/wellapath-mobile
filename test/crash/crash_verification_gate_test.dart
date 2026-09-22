/// LOCAL-VERIFICATION-ONLY — NEVER MERGE, NEVER DISTRIBUTE.
///
/// The build-214 verification gate and its two gated controls
/// (docs/CRASH_VERIFICATION_214.md). The matrix tests pin the fail-closed
/// gate over every meaningful define combination; the widget tests pin
/// that a passing gate renders the doorway card and the synthetic-error
/// button, that a failing gate renders neither, that the confirmation
/// dialog carries the no-personal-or-health wording, and that ONLY the
/// confirmed action throws — the exact `StateError` whose stored form the
/// audit expects as `Bad state: synthetic [redacted] verification 214`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/crash/crash_verification_gate.dart';
import 'package:wellapath_mobile/features/boot/boot_controller.dart';
import 'package:wellapath_mobile/features/home/home_screen.dart';
import 'package:wellapath_mobile/features/status/system_status_screen.dart';

/// The one passing combination.
const Map<String, String> _allOn = {
  'CRASH_VERIFICATION_TRIGGER_ENABLED': 'true',
  'CRASH_REPORTING_ENABLED': 'true',
  'CRASH_REPORTING_PRODUCTION_APPROVED': 'true',
  'CRASH_REPORTING_CONTEXT': 'internal-testing',
};

Map<String, String> _with(String key, String? value) {
  final map = Map<String, String>.of(_allOn);
  if (value == null) {
    map.remove(key);
  } else {
    map[key] = value;
  }
  return map;
}

void main() {
  group('gate matrix — fail closed', () {
    test('passes only with all four defines exactly right', () {
      expect(CrashVerificationGate.evaluate(_allOn), isTrue);
    });

    test('tolerates surrounding whitespace and letter case', () {
      expect(
        CrashVerificationGate.evaluate({
          'CRASH_VERIFICATION_TRIGGER_ENABLED': ' TRUE ',
          'CRASH_REPORTING_ENABLED': 'True',
          'CRASH_REPORTING_PRODUCTION_APPROVED': 'true ',
          'CRASH_REPORTING_CONTEXT': ' Internal-Testing',
        }),
        isTrue,
      );
    });

    test('an empty map fails (the ordinary build)', () {
      expect(CrashVerificationGate.evaluate(const {}), isFalse);
    });

    for (final key in _allOn.keys) {
      test('missing $key fails', () {
        expect(CrashVerificationGate.evaluate(_with(key, null)), isFalse);
      });

      test('empty $key fails', () {
        expect(CrashVerificationGate.evaluate(_with(key, '')), isFalse);
      });

      test('malformed $key fails', () {
        expect(CrashVerificationGate.evaluate(_with(key, '1')), isFalse);
        expect(CrashVerificationGate.evaluate(_with(key, 'yes')), isFalse);
        expect(CrashVerificationGate.evaluate(_with(key, 'truthy')), isFalse);
      });
    }

    test('boolean keys reject "false" outright', () {
      for (final key in [
        'CRASH_VERIFICATION_TRIGGER_ENABLED',
        'CRASH_REPORTING_ENABLED',
        'CRASH_REPORTING_PRODUCTION_APPROVED',
      ]) {
        expect(CrashVerificationGate.evaluate(_with(key, 'false')), isFalse);
      }
    });

    test('a production context NEVER exposes the trigger', () {
      expect(
        CrashVerificationGate.evaluate(
          _with('CRASH_REPORTING_CONTEXT', 'production'),
        ),
        isFalse,
      );
    });

    test('an unknown context fails rather than defaulting open', () {
      expect(
        CrashVerificationGate.evaluate(
          _with('CRASH_REPORTING_CONTEXT', 'internal-beta'),
        ),
        isFalse,
      );
      expect(
        CrashVerificationGate.evaluate(
          _with('CRASH_REPORTING_CONTEXT', 'internal_testing'),
        ),
        isFalse,
      );
    });

    test('the compiled-in gate is CLOSED in this test binary', () {
      // The suite builds with none of the four defines, so the resolved
      // gate must read false — the same closed state every ordinary build
      // gets. A true here would mean the gate leaks into normal builds.
      expect(CrashVerificationGate.enabled, isFalse);
    });
  });

  group('home doorway card', () {
    Future<void> pumpHome(WidgetTester tester, {bool? override}) async {
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(verificationDoorwayOverride: override)),
      );
      await tester.pump();
    }

    testWidgets('absent by default (compile-time gate closed)', (tester) async {
      await pumpHome(tester);
      expect(find.textContaining('Internal verification'), findsNothing);
      expect(find.textContaining('Local build 214'), findsNothing);
    });

    testWidgets('absent when the gate fails', (tester) async {
      await pumpHome(tester, override: false);
      expect(find.textContaining('Internal verification'), findsNothing);
    });

    testWidgets('visible and labelled when the gate passes', (tester) async {
      await pumpHome(tester, override: true);
      expect(
        find.text('Internal verification — System status'),
        findsOneWidget,
      );
      expect(find.text('Local build 214 only'), findsOneWidget);
    });

    testWidgets('opens the system status screen', (tester) async {
      await pumpHome(tester, override: true);
      await tester.tap(find.text('Internal verification — System status'));
      await tester.pumpAndSettle();

      expect(find.byType(SystemStatusScreen), findsOneWidget);
      expect(find.text('Send synthetic Sentry test error'), findsOneWidget);
    });
  });

  group('status screen synthetic-error button', () {
    Future<void> pumpStatus(WidgetTester tester, {bool? override}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SystemStatusScreen(
            result: BootResult(status: BootStatus.success),
            verificationOverride: override,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('absent by default and when the gate fails', (tester) async {
      await pumpStatus(tester);
      expect(find.text('Send synthetic Sentry test error'), findsNothing);

      await pumpStatus(tester, override: false);
      expect(find.text('Send synthetic Sentry test error'), findsNothing);
    });

    testWidgets('visible when the gate passes', (tester) async {
      await pumpStatus(tester, override: true);
      expect(find.text('Send synthetic Sentry test error'), findsOneWidget);
    });

    testWidgets('the dialog states one synthetic event and no personal or '
        'health information', (tester) async {
      await pumpStatus(tester, override: true);
      await tester.tap(find.text('Send synthetic Sentry test error'));
      await tester.pumpAndSettle();

      expect(find.text('Send synthetic test error?'), findsOneWidget);
      expect(
        find.textContaining('exactly one synthetic engineering error'),
        findsOneWidget,
      );
      expect(
        find.textContaining('no real personal or health information'),
        findsOneWidget,
      );
    });

    testWidgets('cancel closes the dialog and throws nothing', (tester) async {
      await pumpStatus(tester, override: true);
      await tester.tap(find.text('Send synthetic Sentry test error'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Send synthetic test error?'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('only the confirmed action throws the exact synthetic '
        'StateError', (tester) async {
      await pumpStatus(tester, override: true);
      await tester.tap(find.text('Send synthetic Sentry test error'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send test error'));
      await tester.pump();

      final Object? thrown = tester.takeException();
      expect(thrown, isA<StateError>());
      expect(
        (thrown as StateError).message,
        'synthetic crash verification 214',
      );
      // The stored form the audit expects (StateError.toString() adds the
      // prefix; the sanitiser redacts the rash stem inside 'crash'):
      //   Bad state: synthetic [redacted] verification 214
      expect(thrown.toString(), 'Bad state: synthetic crash verification 214');
    });
  });
}
