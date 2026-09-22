/// LOCAL-VERIFICATION-ONLY: gate matrix, recorder discipline and transport
/// isolation for the build-212 no-network pipeline diagnostic.
///
/// The diagnostic must be invisible and inert everywhere except a build
/// compiled with the four verification defines PLUS
/// `CRASH_PIPELINE_DIAGNOSTIC=true`; its recorder must accept only the
/// closed vocabulary; and its transport must record metadata and go nowhere.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wellapath_mobile/core/crash/crash_pipeline_diagnostic.dart';
import 'package:wellapath_mobile/features/boot/boot_controller.dart';
import 'package:wellapath_mobile/features/status/system_status_screen.dart';

/// The five defines of the approved diagnostic combination.
const Map<String, String> kDiagnosticDefines = {
  'CRASH_VERIFICATION_TRIGGER_ENABLED': 'true',
  'CRASH_REPORTING_ENABLED': 'true',
  'CRASH_REPORTING_PRODUCTION_APPROVED': 'true',
  'CRASH_REPORTING_CONTEXT': 'internal-testing',
  'CRASH_PIPELINE_DIAGNOSTIC': 'true',
};

void main() {
  tearDown(() {
    CrashPipelineDiagnostic.debugEnabledOverride = null;
    CrashPipelineDiagnostic.reset();
  });

  group('diagnostic gate — fails closed', () {
    test('no defines at all resolves to disabled', () {
      expect(CrashPipelineDiagnostic.evaluate(const {}), isFalse);
    });

    test('every proper subset of the five defines is disabled', () {
      final List<String> keys = kDiagnosticDefines.keys.toList();
      for (int mask = 0; mask < (1 << keys.length); mask++) {
        final Map<String, String> defines = {
          for (int i = 0; i < keys.length; i++)
            if (mask & (1 << i) != 0) keys[i]: kDiagnosticDefines[keys[i]]!,
        };
        final bool isFullSet = mask == (1 << keys.length) - 1;
        expect(
          CrashPipelineDiagnostic.evaluate(defines),
          isFullSet,
          reason: 'defines present: ${defines.keys.join(', ')}',
        );
      }
    });

    test('the four-gate verification build does NOT activate it', () {
      final Map<String, String> fourGate = Map.of(kDiagnosticDefines)
        ..remove('CRASH_PIPELINE_DIAGNOSTIC');
      expect(CrashPipelineDiagnostic.evaluate(fourGate), isFalse);
    });

    test('a production-context build is disabled even with all five', () {
      final Map<String, String> defines = Map.of(kDiagnosticDefines);
      defines['CRASH_REPORTING_CONTEXT'] = 'production';
      expect(CrashPipelineDiagnostic.evaluate(defines), isFalse);
    });

    test('malformed diagnostic values are disabled', () {
      for (final String bad in ['false', '1', 'yes', 'diagnostic', '']) {
        final Map<String, String> defines = Map.of(kDiagnosticDefines);
        defines['CRASH_PIPELINE_DIAGNOSTIC'] = bad;
        expect(
          CrashPipelineDiagnostic.evaluate(defines),
          isFalse,
          reason: 'CRASH_PIPELINE_DIAGNOSTIC=$bad must fail closed',
        );
      }
    });

    test('trimming and case are normalised like the other gates', () {
      final Map<String, String> defines = Map.of(kDiagnosticDefines);
      defines['CRASH_PIPELINE_DIAGNOSTIC'] = ' TRUE ';
      expect(CrashPipelineDiagnostic.evaluate(defines), isTrue);
    });

    test('this test binary itself resolves to disabled', () {
      expect(CrashPipelineDiagnostic.enabled, isFalse);
    });
  });

  group('recorder discipline', () {
    test('disabled recorder records nothing', () {
      CrashPipelineDiagnostic.record('flutter_error_handler_entered');
      expect(CrashPipelineDiagnostic.stages.value, isEmpty);
    });

    test('enabled recorder records vocabulary stages in order', () {
      CrashPipelineDiagnostic.debugEnabledOverride = true;
      CrashPipelineDiagnostic.record('flutter_error_handler_entered');
      CrashPipelineDiagnostic.record('crash_reporter_report_called');
      CrashPipelineDiagnostic.recordTransportSend(3);
      expect(CrashPipelineDiagnostic.stages.value, [
        'flutter_error_handler_entered',
        'crash_reporter_report_called',
        'transport_send_called items=3',
      ]);
    });

    test('anything outside the closed vocabulary is dropped', () {
      CrashPipelineDiagnostic.debugEnabledOverride = true;
      for (final String rejected in [
        'free-form text',
        'transport_send_called items=abc',
        'transport_send_called items=3; Exception: fever at 6.5,3.3',
        'before_send_invoked ', // trailing space: not the exact vocabulary
        'DSN=https://x@y/1',
      ]) {
        CrashPipelineDiagnostic.record(rejected);
      }
      expect(CrashPipelineDiagnostic.stages.value, isEmpty);
    });
  });

  group('recording transport', () {
    test(
      'send records only the item count and returns a non-null id',
      () async {
        CrashPipelineDiagnostic.debugEnabledOverride = true;
        final envelope = SentryEnvelope.fromEvent(
          SentryEvent(),
          SdkVersion(name: 'test', version: '0'),
        );
        final SentryId? id = await RecordingTransport().send(envelope);
        expect(id, isNotNull);
        expect(id, isNot(const SentryId.empty()));
        expect(CrashPipelineDiagnostic.stages.value, [
          'transport_send_called items=${envelope.items.length}',
          'transport_send_returned',
        ]);
      },
    );

    test('the transport source contains no network primitive', () {
      // Structural guard: the recording transport must have no HTTP client,
      // socket, native transport or forwarding fallback to fall through to.
      final String source = File(
        'lib/core/crash/crash_pipeline_diagnostic.dart',
      ).readAsStringSync();
      for (final String forbidden in [
        'dart:io',
        'HttpClient',
        'Socket',
        'http.Client',
        'HttpTransport',
        'RateLimiter',
        'dio',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: 'diagnostic source must not reference $forbidden',
        );
      }
    });
  });

  group('diagnostic panel visibility', () {
    Future<void> pumpStatus(
      WidgetTester tester, {
      bool? trigger,
      bool? diagnostic,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SystemStatusScreen(
            result: const BootResult(status: BootStatus.success),
            crashVerificationTriggerEnabled: trigger,
            crashPipelineDiagnosticEnabled: diagnostic,
          ),
        ),
      );
      await tester.pump();
    }

    final Finder panel = find.textContaining('Pipeline diagnostic');

    testWidgets('ordinary/default build renders no panel', (tester) async {
      await pumpStatus(tester);
      expect(panel, findsNothing);
    });

    testWidgets('the four-gate verification build renders no panel', (
      tester,
    ) async {
      // Trigger enabled (the previous verification build), diagnostic absent.
      await pumpStatus(tester, trigger: true);
      expect(panel, findsNothing);
      expect(find.text('Send synthetic Sentry test error'), findsOneWidget);
    });

    testWidgets('a gated-off diagnostic renders no panel', (tester) async {
      await pumpStatus(tester, trigger: true, diagnostic: false);
      expect(panel, findsNothing);
    });

    testWidgets('the five-define build renders the panel and live stages', (
      tester,
    ) async {
      CrashPipelineDiagnostic.debugEnabledOverride = true;
      await pumpStatus(tester, trigger: true, diagnostic: true);
      expect(panel, findsOneWidget);
      expect(find.text('(no stages recorded yet)'), findsOneWidget);

      CrashPipelineDiagnostic.record('flutter_error_handler_entered');
      await tester.pump();
      expect(find.text('flutter_error_handler_entered'), findsOneWidget);
    });
  });
}
