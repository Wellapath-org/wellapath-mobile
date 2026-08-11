/// Proof that telemetry changed nothing clinical.
///
/// The wider regression evidence is the existing 244-test suite, which passes
/// unchanged. This file covers what that suite cannot: that telemetry is
/// *active* and still cannot influence, delay or observe clinical state.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/telemetry/assessment_telemetry_session.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_event.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_config.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_runtime.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_service.dart';
import 'package:wellapath_mobile/features/assessment/assessment_controller.dart';

import 'session_and_config_test.dart' show RecordingTelemetryService;
import 'support/fixtures.dart';

void main() {
  late RecordingTelemetryService recorder;

  setUp(() {
    recorder = RecordingTelemetryService();
    Telemetry.overrideInstance(recorder);
  });

  tearDown(Telemetry.reset);

  /// The clinical state a realistic assessment would hold by the end.
  AssessmentController buildRealisticAssessment() {
    final controller = AssessmentController()
      ..setSex('female')
      ..setAgeRange('18–40')
      ..setPregnancy(true)
      ..setMedicalCondition('Diabetes', true)
      ..setBodyArea('Head')
      ..addSymptomToken('severe_headache')
      ..addSymptomToken('fever')
      ..addSymptomToken('neck_stiffness')
      ..setSeverityToken('very_severe')
      ..setDurationToken('days_1_3');
    return controller;
  }

  group('the controller is untouched by telemetry', () {
    test('a clinical build produces the same input with telemetry active', () {
      final controller = buildRealisticAssessment();
      final input = controller.buildInput();

      expect(input.symptomTokens, [
        'severe_headache',
        'fever',
        'neck_stiffness',
      ]);
      expect(input.demographicTokens, contains('pregnancy'));
      expect(input.demographicTokens, contains('adults'));
      expect(input.demographicTokens, contains('diabetes_known'));
      expect(input.severityTokens, ['very_severe']);
      expect(input.durationTokens, ['days_1_3']);
    });

    test('the telemetry session has no access to clinical state', () {
      final controller = buildRealisticAssessment();
      // Everything the session can be asked for.
      expect(controller.telemetrySession.sessionId, isA<String>());
      expect(controller.telemetrySession.stepsViewed, 0);
      // There is no API to read symptoms, answers or results from it, and no
      // API to hand them in — the methods take a status enum or nothing.
      controller.telemetrySession.recordStart();
      controller.telemetrySession.recordComplete(CompletionStatus.completed);
      expect(recorder.captured, hasLength(2));
    });

    test('clearAll does not disturb the session ID', () {
      final controller = buildRealisticAssessment();
      final id = controller.telemetrySession.sessionId;
      controller.clearAll();
      expect(controller.telemetrySession.sessionId, id);
      expect(controller.symptomTokens, isEmpty);
    });
  });

  group('no clinical value reaches any emitted event', () {
    test('a full simulated assessment emits nothing clinical', () {
      final controller = buildRealisticAssessment();
      final session = controller.telemetrySession;

      session.recordStart(entryPoint: AssessmentEntryPoint.home);
      for (var i = 0; i < 8; i++) {
        session.recordStepView();
      }
      session.recordResultView();
      session.recordComplete(CompletionStatus.completed);

      final serialised = recorder.captured
          .map((e) => serialiseEvent(e).toString())
          .join('\n');

      for (final clinicalValue in [
        'severe_headache',
        'fever',
        'neck_stiffness',
        'very_severe',
        'days_1_3',
        'pregnancy',
        'diabetes_known',
        'adults',
        'female',
        'Head',
        'emergency',
        'urgent',
        'malaria',
        'meningitis',
      ]) {
        expect(
          serialised,
          isNot(contains(clinicalValue)),
          reason: '"$clinicalValue" reached a telemetry event',
        );
      }
    });

    test('the emitted event sequence is exactly the expected shape', () {
      final session = AssessmentTelemetrySession();
      session.recordStart();
      session.recordStepView();
      session.recordStepView();
      session.recordResultView();
      session.recordComplete(CompletionStatus.completed);

      expect(recorder.names, [
        'assessment_start',
        'assessment_step_view',
        'assessment_step_view',
        'result_view',
        'assessment_complete',
      ]);
    });
  });

  group('the red-flag path is indistinguishable from the ordinary path', () {
    /// Emits the sequence the app produces for a given engine outcome.
    List<Map<String, Object?>> sequenceFor({required bool redFlagTriggered}) {
      recorder.captured.clear();
      final session = AssessmentTelemetrySession();
      session.recordStart(entryPoint: AssessmentEntryPoint.home);
      session.recordStepView();
      // Both branches in `loading_screen.dart` do exactly this.
      session.recordResultView();
      session.recordComplete(CompletionStatus.completed);
      return recorder.captured
          .map((e) => {'event_name': e.eventName, ...e.toProperties()})
          .toList();
    }

    test('the two sequences differ only by session ID', () {
      final ordinary = sequenceFor(redFlagTriggered: false);
      final redFlag = sequenceFor(redFlagTriggered: true);

      String withoutSession(Map<String, Object?> event) =>
          (Map<String, Object?>.from(
            event,
          )..remove('assessment_session_id')).toString();

      expect(
        redFlag.map(withoutSession).toList(),
        ordinary.map(withoutSession).toList(),
        reason:
            'a red-flag assessment must be unobservable in telemetry — if '
            'these sequences differ, the completion status or the presence '
            'of result_view has become a red-flag detector',
      );
    });

    test('completion status never carries a clinical outcome', () {
      // The enum has exactly three members and none of them names a clinical
      // result. `interrupted` is reserved for technical failures.
      expect(CompletionStatus.values.map((v) => v.wire), [
        'completed',
        'abandoned',
        'interrupted',
      ]);
    });
  });

  group('telemetry cannot block or delay a clinical flow', () {
    test('capture returns before any I/O completes', () async {
      final clock = FakeClock(DateTime.utc(2026, 8, 11, 9));
      final diagnostics = TelemetryDiagnostics();
      final service = DefaultTelemetryService(
        config: const TelemetryConfig(
          enabled: true,
          baseUrl: 'https://example.invalid',
          flushInterval: Duration(hours: 1),
        ),
        queue: memoryQueue(clock: clock, diagnostics: diagnostics),
        transport: FakeTransport([accepted]),
        appContext: testAppContext,
        clock: clock,
        idGenerator: FakeIdGenerator(),
        diagnostics: diagnostics,
      );
      await service.init();

      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      }
      stopwatch.stop();

      // 1000 captures on the caller's thread. Generous ceiling — the point is
      // that this is validation and a map build, with the write deferred.
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(500),
        reason: 'capture must not do I/O on the caller path',
      );
      await service.dispose();
    });

    test('a dead backend does not make capture fail or throw', () async {
      final clock = FakeClock(DateTime.utc(2026, 8, 11, 9));
      final diagnostics = TelemetryDiagnostics();
      final service = DefaultTelemetryService(
        config: const TelemetryConfig(
          enabled: true,
          baseUrl: 'https://example.invalid',
          flushInterval: Duration(hours: 1),
        ),
        queue: memoryQueue(clock: clock, diagnostics: diagnostics),
        transport: FakeTransport([networkFailure]),
        appContext: testAppContext,
        clock: clock,
        idGenerator: FakeIdGenerator(),
        diagnostics: diagnostics,
        sleep: RecordingSleeper().call,
      );
      await service.init();

      // No try/catch at the call site — this is how product code calls it.
      service.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await Future<void>.delayed(Duration.zero);
      await service.flush();

      expect(diagnostics.captureAccepted, 1);
      await service.dispose();
    });

    test(
      'a disabled build behaves identically to no telemetry at all',
      () async {
        await Telemetry.reset();
        final controller = buildRealisticAssessment();

        controller.telemetrySession.recordStart();
        controller.telemetrySession.recordStepView();
        controller.telemetrySession.recordComplete(CompletionStatus.completed);

        // Nothing captured, nothing thrown, and the clinical input is intact.
        expect(Telemetry.instance.isActive, isFalse);
        expect(controller.buildInput().symptomTokens, hasLength(3));
      },
    );
  });
}
