/// Crash-boundary behaviour with a provider attached.
///
/// The boundary must keep every guarantee it had when the sink went nowhere:
/// the previous error handler still runs, fatal stays fatal, a provider
/// failure never reaches the caller, and the same failure is never reported
/// twice.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/crash/crash_reporter.dart';
import 'package:wellapath_mobile/core/crash/crash_validation.dart';
import 'package:wellapath_mobile/core/crash/sentry_crash_sink.dart';

/// Records what the boundary hands to a provider, without sending anything.
class CapturingSink extends CrashSink {
  final List<SanitisedCrashReport> reports = [];
  final List<Object?> errors = [];
  final List<StackTrace?> stacks = [];

  @override
  void report(SanitisedCrashReport report) => reports.add(report);

  @override
  void reportDetailed(
    SanitisedCrashReport sanitised,
    Object? error,
    StackTrace? stackTrace,
  ) {
    reports.add(sanitised);
    errors.add(error);
    stacks.add(stackTrace);
  }
}

class ExplodingSink extends CrashSink {
  @override
  void report(SanitisedCrashReport report) => throw StateError('sink down');

  @override
  void reportDetailed(
    SanitisedCrashReport sanitised,
    Object? error,
    StackTrace? stackTrace,
  ) => throw StateError('provider down');
}

void main() {
  setUp(CrashReporter.resetForTest);
  tearDown(CrashReporter.resetForTest);

  group('the provider receives what it needs, and nothing else', () {
    test(
      'the sanitised report and the raw error and stack are handed over',
      () {
        final sink = CapturingSink();
        CrashReporter.install(sink: sink);
        final error = StateError('boom');
        final stack = StackTrace.current;

        CrashReporter.reportHandled(
          error,
          origin: 'handled',
          stackTrace: stack,
        );

        expect(sink.reports, hasLength(1));
        expect(sink.errors.single, same(error));
        expect(sink.stacks.single, same(stack));
        expect(sink.reports.single.isFatal, isFalse);
        expect(sink.reports.single.origin, 'handled');
      },
    );

    test('the sanitised message never carries clinical content', () {
      final sink = CapturingSink();
      CrashReporter.install(sink: sink);
      CrashReporter.reportHandled(
        StateError('no rule matched severe_headache for malaria'),
        origin: 'handled',
      );
      final message = sink.reports.single.message;
      expect(message, isNot(contains('severe_headache')));
      expect(message, isNot(contains('malaria')));
    });

    test('fatal classification is preserved end to end', () {
      final sink = CapturingSink();
      CrashReporter.install(sink: sink);
      CrashReporter.reportFatalForValidation(
        StateError('x'),
        origin: 'platform_dispatch',
      );
      expect(sink.reports.single.isFatal, isTrue);
      expect(sink.reports.single.origin, 'platform_dispatch');
    });
  });

  group('de-duplication', () {
    test('the same failure reported twice in quick succession counts once', () {
      final sink = CapturingSink();
      CrashReporter.install(sink: sink);
      final error = StateError('identical');
      CrashReporter.reportHandled(error, origin: 'handled');
      CrashReporter.reportHandled(error, origin: 'handled');
      CrashReporter.reportHandled(error, origin: 'handled');
      expect(sink.reports, hasLength(1));
    });

    test('different origins are distinct events, not duplicates', () {
      final sink = CapturingSink();
      CrashReporter.install(sink: sink);
      final error = StateError('same message');
      CrashReporter.reportHandled(error, origin: 'handled');
      CrashReporter.reportFatalForValidation(error, origin: 'isolate');
      expect(sink.reports, hasLength(2));
    });

    test('different errors are never collapsed', () {
      final sink = CapturingSink();
      CrashReporter.install(sink: sink);
      CrashReporter.reportHandled(StateError('one'), origin: 'handled');
      CrashReporter.reportHandled(ArgumentError('two'), origin: 'handled');
      expect(sink.reports, hasLength(2));
    });
  });

  group('the boundary never becomes the failure', () {
    test('a provider that throws does not propagate', () {
      CrashReporter.install(sink: ExplodingSink());
      expect(
        () => CrashReporter.reportHandled(StateError('x'), origin: 'handled'),
        returnsNormally,
      );
    });

    test('the previous FlutterError handler still runs', () {
      final handled = <Object>[];
      final original = FlutterError.onError;
      FlutterError.onError = (details) => handled.add(details.exception);

      final sink = CapturingSink();
      CrashReporter.install(sink: sink);

      final error = StateError('engine failed');
      FlutterError.onError!(FlutterErrorDetails(exception: error));

      expect(
        handled,
        contains(error),
        reason: 'a clinical failure must still fail as loudly as before',
      );
      expect(sink.reports, hasLength(1));
      FlutterError.onError = original;
    });

    test('setSink swaps the destination without re-chaining handlers', () {
      final first = CapturingSink();
      CrashReporter.install(sink: first);
      final second = CapturingSink();
      CrashReporter.setSink(second);

      CrashReporter.reportHandled(StateError('x'), origin: 'handled');

      expect(first.reports, isEmpty);
      expect(second.reports, hasLength(1));
    });
  });

  group('the Sentry sink', () {
    test('forwards through the injected capture seam with safe tags', () async {
      final captured = <Map<String, String>>[];
      final sink = SentryCrashSink(
        captureOverride: (error, stack, tags) async => captured.add(tags),
      );
      CrashReporter.install(sink: sink);

      CrashReporter.reportFatalForValidation(
        StateError('x'),
        origin: 'isolate',
      );
      await Future<void>.delayed(Duration.zero);

      expect(captured.single, {'crash_source': 'isolate', 'severity': 'fatal'});
      expect(sink.forwarded, 1);
    });

    test('a report with no raw error is not forwarded to the provider', () {
      final sink = SentryCrashSink(
        captureOverride: (error, stack, tags) async =>
            fail('must not forward without an error'),
      );
      sink.report(
        const SanitisedCrashReport(
          classification: 'StateError',
          origin: 'handled',
          message: 'x',
          isFatal: false,
        ),
      );
      expect(sink.forwarded, 0);
      expect(sink.suppressed, 1);
    });
  });

  group('the validation trigger is not reachable in ordinary builds', () {
    test('unavailable when crash monitoring is disabled', () {
      // No define is set in a test run, and monitoring is disabled.
      expect(CrashMonitoring.config.enabled, isFalse);
      expect(CrashValidation.isAvailable, isFalse);
      expect(CrashValidation.triggerFatal(), isFalse);
      expect(CrashValidation.triggerAsync(), isFalse);
      expect(CrashValidation.triggerNonFatal(), isFalse);
    });

    test('its markers carry no clinical content', () {
      for (final marker in CrashValidation.markers) {
        expect(marker, startsWith('WP_VALIDATION_'));
        expect(marker, matches(RegExp(r'^[A-Z0-9_]+$')));
      }
    });
  });

  group('monitoring diagnostics are safe to print', () {
    test('no DSN, and the disabled capabilities are stated', () {
      final diagnostics = CrashMonitoring.diagnostics();
      expect(diagnostics['enabled'], isFalse);
      expect(diagnostics['sdk_version'], '9.27.0');
      expect(diagnostics['native_crash_handling'], isFalse);
      expect(diagnostics['session_tracking'], isFalse);
      expect(diagnostics.toString(), isNot(contains('https://')));
    });

    test('CrashConfig.disabled is the default before init', () {
      expect(CrashMonitoring.config.enabled, isFalse);
      expect(CrashMonitoring.config.dsn, isEmpty);
    });
  });
}
