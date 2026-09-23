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

/// A structurally valid DSN shape. Not a credential: a placeholder public
/// key on a non-routable host, never used to send anything.
const String _validDsnShape =
    'https://0123456789abcdef0123456789abcdef@verification.invalid/1';

/// The one passing combination — every define the gate consults, including
/// the ones it delegates to CrashConfig.
const Map<String, String> _allOn = {
  'CRASH_VERIFICATION_TRIGGER_ENABLED': 'true',
  'CRASH_REPORTING_ENABLED': 'true',
  'CRASH_REPORTING_PRODUCTION_APPROVED': 'true',
  'CRASH_REPORTING_CONTEXT': 'internal-testing',
  'SENTRY_DSN': _validDsnShape,
  'APP_VERSION': '0.3.0',
  'APP_BUILD': '214',
};

/// The bundled `.env` is production since build 211, so every gate
/// evaluation states that assumption explicitly rather than depending on
/// whether dotenv happens to be loaded in the test binary.
bool _gate(Map<String, String> defines) =>
    CrashVerificationGate.evaluate(defines, bundledIsProduction: true);

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
      expect(_gate(_allOn), isTrue);
    });

    test('tolerates surrounding whitespace and letter case', () {
      expect(
        _gate({
          'CRASH_VERIFICATION_TRIGGER_ENABLED': ' TRUE ',
          'CRASH_REPORTING_ENABLED': 'True',
          'CRASH_REPORTING_PRODUCTION_APPROVED': 'true ',
          'CRASH_REPORTING_CONTEXT': ' Internal-Testing',
          'SENTRY_DSN': ' $_validDsnShape ',
          'APP_VERSION': ' 0.3.0 ',
          'APP_BUILD': ' 214 ',
        }),
        isTrue,
      );
    });

    test('an empty map fails (the ordinary build)', () {
      expect(_gate(const {}), isFalse);
    });

    for (final key in _allOn.keys) {
      test('missing $key fails', () {
        expect(_gate(_with(key, null)), isFalse);
      });

      test('empty $key fails', () {
        expect(_gate(_with(key, '')), isFalse);
      });

      test('malformed $key fails', () {
        expect(_gate(_with(key, '1')), isFalse);
        expect(_gate(_with(key, 'yes')), isFalse);
        expect(_gate(_with(key, 'truthy')), isFalse);
      });
    }

    test('boolean keys reject "false" outright', () {
      for (final key in [
        'CRASH_VERIFICATION_TRIGGER_ENABLED',
        'CRASH_REPORTING_ENABLED',
        'CRASH_REPORTING_PRODUCTION_APPROVED',
      ]) {
        expect(_gate(_with(key, 'false')), isFalse);
      }
    });

    test('a production context NEVER exposes the trigger', () {
      expect(_gate(_with('CRASH_REPORTING_CONTEXT', 'production')), isFalse);
    });

    test('an unknown context fails rather than defaulting open', () {
      expect(_gate(_with('CRASH_REPORTING_CONTEXT', 'internal-beta')), isFalse);
      expect(
        _gate(_with('CRASH_REPORTING_CONTEXT', 'internal_testing')),
        isFalse,
      );
    });

    group('the trigger cannot open on a build that would waste the one '
        'permitted event', () {
      test('a missing or malformed SENTRY_DSN closes the gate', () {
        // Regression: the gate once checked four defines and NOT the DSN,
        // so a build with a mistyped or unexpanded DSN rendered the trigger
        // while CrashMonitoring left the no-op sink installed. The operator
        // would spend 214's one event on a transmission that never happened.
        for (final bad in <String?>[
          null,
          '',
          'not-a-dsn',
          'https://verification.invalid/1', // no public key
          'https://key@verification.invalid', // no project id
        ]) {
          expect(
            _gate(_with('SENTRY_DSN', bad)),
            isFalse,
            reason: 'DSN "$bad" must not open the trigger',
          );
        }
      });

      test('a missing APP_VERSION/APP_BUILD closes the gate', () {
        // Regression: without these the reporter stamps
        // wellapath-mobile@0.0.0+0 and the single event fails audit
        // criterion 5 on release identity.
        expect(_gate(_with('APP_VERSION', null)), isFalse);
        expect(_gate(_with('APP_BUILD', null)), isFalse);
      });

      test('a neighbouring build number closes the gate', () {
        // 214's trigger is bound to 214's identity: a 213 or 215 binary
        // must not be able to open it.
        expect(_gate(_with('APP_BUILD', '213')), isFalse);
        expect(_gate(_with('APP_BUILD', '215')), isFalse);
        expect(_gate(_with('APP_VERSION', '0.4.0')), isFalse);
      });

      test('the founder-approval key is still required', () {
        expect(
          _gate(_with('CRASH_REPORTING_PRODUCTION_APPROVED', null)),
          isFalse,
        );
      });

      test('an APP_ENV of production closes the gate even when approved', () {
        // CrashConfig derives the label from the context define, but an
        // explicit production APP_ENV must not resolve to internal-testing.
        final defines = Map<String, String>.of(_allOn)
          ..['APP_ENV'] = 'production'
          ..['CRASH_REPORTING_CONTEXT'] = 'production';
        expect(_gate(defines), isFalse);
      });

      test('the passing combination resolves the audited identity', () {
        // What the gate proves when it opens: the very release and
        // environment docs/CRASH_VERIFICATION_214.md criterion 5 expects.
        expect(
          CrashVerificationGate.kExpectedRelease,
          'wellapath-mobile@0.3.0+214',
        );
        expect(CrashVerificationGate.kExpectedEnvironment, 'internal-testing');
        expect(_gate(_allOn), isTrue);
      });
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

    testWidgets('opens the status screen without threading the gate or '
        'claiming a measured boot status', (tester) async {
      await pumpHome(tester, override: true);
      await tester.tap(find.text('Internal verification — System status'));
      await tester.pumpAndSettle();

      expect(find.byType(SystemStatusScreen), findsOneWidget);

      // The doorway passes no override: the status screen reads the same
      // compile-time gate (closed in this binary), so the trigger stays
      // absent rather than being opened across a library boundary.
      final SystemStatusScreen screen = tester.widget(
        find.byType(SystemStatusScreen),
      );
      expect(screen.verificationOverride, isNull);
      expect(find.text('Send synthetic Sentry test error'), findsNothing);

      // No boot ran for this entry, so no green "Online" chip is presented.
      expect(screen.statusMeasured, isFalse);
      expect(find.text('Status not measured for this entry'), findsOneWidget);
      expect(find.text('Online'), findsNothing);
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

    testWidgets('a measured result still shows its real status chip', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SystemStatusScreen(
            result: BootResult(status: BootStatus.offline),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Offline — using cached config'), findsOneWidget);
      expect(find.text('Status not measured for this entry'), findsNothing);
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
