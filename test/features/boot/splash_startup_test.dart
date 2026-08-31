/// Splash startup — loading state, single initialization, single navigation,
/// and cancellation when the screen goes away.
///
/// The splash was a static logo. During a backend cold start it sat there
/// silently for up to ~54 s before showing the offline screen, with no
/// indication that anything was happening or being retried. It also started a
/// boot sequence with no way to stop it, so a manual "Try again" — which
/// pushes a fresh splash — could leave the previous screen's retry loop still
/// running against a widget that no longer exists.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wellapath_mobile/features/boot/boot_controller.dart';
import 'package:wellapath_mobile/features/splash/splash_screen.dart';

/// A BootController that never touches the network or storage.
///
/// It records how many times `boot` was entered, reports attempt progress the
/// way the real one does, and can be told to hang so disposal can be tested
/// mid-flight.
class _FakeBootController implements BootController {
  _FakeBootController({
    required this.result,
    this.attemptsToReport = 1,
    this.hang = false,
  });

  final BootResult result;
  final int attemptsToReport;
  final bool hang;

  int bootCalls = 0;
  int cancelChecks = 0;
  bool sawCancellation = false;

  @override
  Future<BootResult> boot({
    void Function(int attempt, int maxAttempts)? onAttempt,
    bool Function()? isCancelled,
  }) async {
    bootCalls++;

    for (var attempt = 1; attempt <= attemptsToReport; attempt++) {
      cancelChecks++;
      if (isCancelled?.call() ?? false) {
        sawCancellation = true;
        return const BootResult(status: BootStatus.failed);
      }
      onAttempt?.call(attempt, 4);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    if (hang) {
      // Long enough to still be running when the test disposes the screen,
      // short enough that no timer outlives the test.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    return result;
  }
}

Widget _app(Widget home) => MaterialApp(home: home);

void main() {
  const fastSplash = Duration(milliseconds: 10);

  // The "Try again" test pushes a REAL SplashScreen, which builds a real
  // BootController and reads the config cache. Hive is initialised here the
  // same way boot_controller_test does it, so that path runs for real instead
  // of dying on an unopened box.
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('splash_startup_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('config_cache');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('loading state', () {
    testWidgets('the logo is shown immediately', (tester) async {
      final controller = _FakeBootController(
        result: const BootResult(status: BootStatus.failed),
      );

      await tester.pumpWidget(
        _app(
          SplashScreen(bootController: controller, minimumSplash: fastSplash),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);

      // Let the pending boot settle so the test does not leak timers.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('a progress indicator and status line exist', (tester) async {
      final controller = _FakeBootController(
        result: const BootResult(status: BootStatus.failed),
        attemptsToReport: 3,
      );

      await tester.pumpWidget(
        _app(
          SplashScreen(bootController: controller, minimumSplash: fastSplash),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));

      // Present from the start (faded), so revealing it cannot shift layout.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('onnecting'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('the status names the attempt once retrying starts', (
      tester,
    ) async {
      final controller = _FakeBootController(
        result: const BootResult(status: BootStatus.failed),
        attemptsToReport: 3,
        hang: true,
      );

      await tester.pumpWidget(
        _app(
          SplashScreen(bootController: controller, minimumSplash: fastSplash),
        ),
      );
      // Each announced attempt sits behind its own async gap, so the tree
      // needs a pump per attempt rather than one long one.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 12));
      }

      expect(
        find.textContaining('attempt'),
        findsOneWidget,
        reason: 'a retrying startup must say so rather than look frozen',
      );

      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('single initialization', () {
    testWidgets('boot runs exactly once for one splash', (tester) async {
      final controller = _FakeBootController(
        result: const BootResult(status: BootStatus.failed),
      );

      await tester.pumpWidget(
        _app(
          SplashScreen(bootController: controller, minimumSplash: fastSplash),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(controller.bootCalls, equals(1));
    });

    testWidgets('rebuilding the widget does not start a second boot', (
      tester,
    ) async {
      final controller = _FakeBootController(
        result: const BootResult(status: BootStatus.failed),
      );

      final splash = SplashScreen(
        bootController: controller,
        minimumSplash: fastSplash,
      );

      await tester.pumpWidget(_app(splash));
      await tester.pump(const Duration(milliseconds: 5));
      // Same State object, rebuilt — initState must not run again, and the
      // _bootStarted guard covers any path that would call it again.
      await tester.pumpWidget(_app(splash));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(controller.bootCalls, equals(1));
    });
  });

  group('navigation happens once', () {
    testWidgets('a failed boot lands on the offline screen exactly once', (
      tester,
    ) async {
      final controller = _FakeBootController(
        result: const BootResult(status: BootStatus.failed),
      );

      await tester.pumpWidget(
        _app(
          SplashScreen(bootController: controller, minimumSplash: fastSplash),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.textContaining('brief internet connection'), findsOneWidget);
      expect(
        find.text('Try again'),
        findsOneWidget,
        reason: 'the manual retry path must survive the automatic policy',
      );
      expect(find.byType(SplashScreen), findsNothing);
    });

    testWidgets('the manual Try again path is still wired', (tester) async {
      final controller = _FakeBootController(
        result: const BootResult(status: BootStatus.failed),
      );

      await tester.pumpWidget(
        _app(
          SplashScreen(bootController: controller, minimumSplash: fastSplash),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));

      await tester.tap(find.text('Try again'));
      await tester.pump();

      // Regression guard. This tap used to throw "This widget has been
      // unmounted": the callback closed over the splash State's context, and
      // pushReplacement had already disposed it. The recovery button on the
      // recovery screen was dead, and only on the screen whose entire purpose
      // is recovery.
      expect(
        tester.takeException(),
        isNull,
        reason: 'Try again must not throw on the offline screen',
      );

      // A fresh splash replaces the offline screen.
      await tester.pump();
      expect(find.byType(SplashScreen), findsOneWidget);

      // That splash builds a REAL BootController. Its /config attempt has no
      // network here, so it falls through to the (empty) cache and reports a
      // failed boot — the correct offline behaviour. Tear the tree down so the
      // retry loop is cancelled rather than left running past the test.
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });
  });

  group('cancellation on dispose', () {
    testWidgets('disposing the splash cancels the boot in flight', (
      tester,
    ) async {
      final controller = _FakeBootController(
        result: const BootResult(status: BootStatus.success),
        attemptsToReport: 6,
      );

      await tester.pumpWidget(
        _app(
          SplashScreen(bootController: controller, minimumSplash: fastSplash),
        ),
      );
      await tester.pump(const Duration(milliseconds: 12));

      // The screen goes away mid-retry.
      await tester.pumpWidget(_app(const SizedBox()));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 12));
      }

      expect(
        controller.sawCancellation,
        isTrue,
        reason:
            'the retry loop must observe cancellation rather than keep '
            'issuing requests for a screen that no longer exists',
      );

      await tester.pumpAndSettle();
    });

    testWidgets('no navigation is attempted after disposal', (tester) async {
      final controller = _FakeBootController(
        result: const BootResult(status: BootStatus.failed),
        hang: true,
      );

      await tester.pumpWidget(
        _app(
          SplashScreen(bootController: controller, minimumSplash: fastSplash),
        ),
      );
      await tester.pump(const Duration(milliseconds: 12));
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Navigating on a disposed State throws; reaching here without an
      // exception is the assertion. Nothing from the splash may be on screen.
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.textContaining('brief internet connection'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
