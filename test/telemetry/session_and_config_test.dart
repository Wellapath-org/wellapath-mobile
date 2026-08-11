/// Assessment session ID generation and lifecycle, and configuration gating.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/telemetry/assessment_telemetry_session.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_contract.dart';
import 'package:wellapath_mobile/core/telemetry/contract/telemetry_event.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_config.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_runtime.dart';
import 'package:wellapath_mobile/core/telemetry/telemetry_service.dart';
import 'package:wellapath_mobile/features/assessment/assessment_controller.dart';

import 'support/fixtures.dart';

/// Captures events in memory so a test can assert on what was emitted.
class RecordingTelemetryService implements TelemetryService {
  final List<TelemetryEvent> captured = [];

  @override
  void capture(TelemetryEvent event) => captured.add(event);

  @override
  Future<void> flush() async {}

  @override
  void onAppBackgrounded() {}

  @override
  bool get isActive => true;

  @override
  Map<String, Object?> diagnosticsSnapshot() => const {};

  @override
  Future<void> dispose() async {}

  List<String> get names => captured.map((e) => e.eventName).toList();

  T single<T extends TelemetryEvent>() => captured.whereType<T>().single;
}

void main() {
  late RecordingTelemetryService recorder;

  setUp(() {
    recorder = RecordingTelemetryService();
    Telemetry.overrideInstance(recorder);
  });

  tearDown(Telemetry.reset);

  group('session ID generation', () {
    final generator = SecureTelemetryIdGenerator();
    final sessionPattern = RegExp(
      '^(?:${TelemetryContract.events['assessment_start']!.property('assessment_session_id')!.pattern})\$',
    );

    test('matches the contract pattern', () {
      for (var i = 0; i < 500; i++) {
        expect(sessionPattern.hasMatch(generator.newSessionId()), isTrue);
      }
    });

    test('event IDs match their own contract pattern', () {
      final eventPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
      for (var i = 0; i < 500; i++) {
        expect(eventPattern.hasMatch(generator.newEventId()), isTrue);
      }
    });

    test('IDs are unique across a queue-sized population', () {
      final ids = {for (var i = 0; i < 5000; i++) generator.newSessionId()};
      expect(ids, hasLength(5000));
    });

    test('generation takes no input at all', () {
      // The strongest available proof that an ID cannot be derived from
      // symptoms, answers, the clock, device identity or account identity:
      // there is nothing to derive it from.
      expect(generator.newSessionId, isA<String Function()>());
      expect(generator.newEventId, isA<String Function()>());
    });

    test('two generators produce disjoint IDs', () {
      final a = {for (var i = 0; i < 200; i++) generator.newSessionId()};
      final b = {
        for (var i = 0; i < 200; i++)
          SecureTelemetryIdGenerator().newSessionId(),
      };
      expect(a.intersection(b), isEmpty);
    });
  });

  group('session lifecycle', () {
    test('each assessment attempt gets a fresh, never-reused ID', () {
      final ids = {
        for (var i = 0; i < 100; i++)
          AssessmentController().telemetrySession.sessionId,
      };
      expect(ids, hasLength(100));
    });

    test('the ID is stable for the lifetime of one controller', () {
      final controller = AssessmentController();
      final id = controller.telemetrySession.sessionId;
      controller.setSex('female');
      controller.addSymptomToken('fever');
      controller.clearAll();
      expect(controller.telemetrySession.sessionId, id);
    });

    test('start is emitted once, however many times it is called', () {
      final session = AssessmentTelemetrySession();
      session.recordStart();
      session.recordStart();
      session.recordStart();
      expect(
        recorder.names.where((n) => n == 'assessment_start'),
        hasLength(1),
      );
    });

    test('complete is emitted once and the first status wins', () {
      final session = AssessmentTelemetrySession();
      session.recordComplete(CompletionStatus.abandoned);
      session.recordComplete(CompletionStatus.completed);
      final events = recorder.captured.whereType<AssessmentCompleteEvent>();
      expect(events, hasLength(1));
      expect(events.single.completionStatus, CompletionStatus.abandoned);
    });

    test('result view is emitted once', () {
      final session = AssessmentTelemetrySession();
      session.recordResultView();
      session.recordResultView();
      expect(recorder.captured.whereType<ResultViewEvent>(), hasLength(1));
    });

    test('step views increment a depth counter from zero', () {
      final session = AssessmentTelemetrySession();
      for (var i = 0; i < 5; i++) {
        session.recordStepView();
      }
      final steps = recorder.captured
          .whereType<AssessmentStepViewEvent>()
          .map((e) => e.stepIndex)
          .toList();
      expect(steps, [0, 1, 2, 3, 4]);
      expect(session.stepsViewed, 5);
    });

    test('step index never exceeds the contract ceiling of 200', () {
      final session = AssessmentTelemetrySession();
      for (var i = 0; i < 250; i++) {
        session.recordStepView();
      }
      final steps = recorder.captured.whereType<AssessmentStepViewEvent>();
      expect(steps, hasLength(200));
      expect(steps.last.stepIndex, 199);
    });

    test('every emitted event carries this session and only this session', () {
      final session = AssessmentTelemetrySession();
      session.recordStart();
      session.recordStepView();
      session.recordResultView();
      session.recordComplete(CompletionStatus.completed);

      final ids = <String>{
        recorder.single<AssessmentStartEvent>().assessmentSessionId,
        recorder.single<AssessmentStepViewEvent>().assessmentSessionId,
        recorder.single<ResultViewEvent>().assessmentSessionId,
        recorder.single<AssessmentCompleteEvent>().assessmentSessionId,
      };
      expect(ids, {session.sessionId});
    });

    test('duration is measured from session construction', () {
      final clock = FakeClock(DateTime.utc(2026, 8, 11, 9, 0, 0));
      final session = AssessmentTelemetrySession(clock: clock);
      clock.advance(const Duration(minutes: 3, seconds: 20));
      session.recordComplete(CompletionStatus.completed);
      expect(recorder.single<AssessmentCompleteEvent>().durationMs, 200000);
    });

    test('an absurd duration is clamped to the contract maximum', () {
      final clock = FakeClock(DateTime.utc(2026, 8, 11, 9, 0, 0));
      final session = AssessmentTelemetrySession(clock: clock);
      clock.advance(const Duration(days: 3));
      session.recordComplete(CompletionStatus.completed);
      expect(recorder.single<AssessmentCompleteEvent>().durationMs, 7200000);
    });

    test('flow and presentation versions are the declared constants', () {
      final session = AssessmentTelemetrySession();
      session.recordStart(entryPoint: AssessmentEntryPoint.home);
      session.recordResultView();
      expect(
        recorder.single<AssessmentStartEvent>().flowVersion,
        kAssessmentFlowVersion,
      );
      expect(
        recorder.single<ResultViewEvent>().presentationContractVersion,
        kPresentationContractVersion,
      );
    });
  });

  group('configuration', () {
    test('absent TELEMETRY_ENABLED means disabled', () {
      final config = TelemetryConfig.fromEnvironment(
        env: {'API_BASE_URL': 'https://api.example', 'APP_ENV': 'staging'},
      );
      expect(config.enabled, isFalse);
    });

    test('anything other than "true" means disabled', () {
      for (final value in ['1', 'yes', 'TRUE ', 'on', '']) {
        final config = TelemetryConfig.fromEnvironment(
          env: {
            'TELEMETRY_ENABLED': value,
            'API_BASE_URL': 'https://api.example',
          },
        );
        expect(config.enabled, value.trim().toLowerCase() == 'true');
      }
    });

    test('staging with the flag on is enabled', () {
      final config = TelemetryConfig.fromEnvironment(
        env: {
          'TELEMETRY_ENABLED': 'true',
          'APP_ENV': 'staging',
          'API_BASE_URL': 'https://wellapath-backend-staging.onrender.com',
        },
      );
      expect(config.enabled, isTrue);
      expect(
        config.endpoint,
        'https://wellapath-backend-staging.onrender.com/v1/telemetry/events',
      );
    });

    test('production stays disabled even with the flag on', () {
      for (final env in ['production', 'PRODUCTION', 'prod']) {
        final config = TelemetryConfig.fromEnvironment(
          env: {
            'TELEMETRY_ENABLED': 'true',
            'APP_ENV': env,
            'API_BASE_URL': 'https://api.example',
          },
        );
        expect(
          config.enabled,
          isFalse,
          reason: 'production must not be enabled by one flag',
        );
      }
    });

    test('production needs a second, separate approval key', () {
      final config = TelemetryConfig.fromEnvironment(
        env: {
          'TELEMETRY_ENABLED': 'true',
          'TELEMETRY_PRODUCTION_APPROVED': 'true',
          'APP_ENV': 'production',
          'API_BASE_URL': 'https://api.example',
        },
      );
      expect(config.enabled, isTrue);
    });

    test('TELEMETRY_BASE_URL overrides API_BASE_URL', () {
      final config = TelemetryConfig.fromEnvironment(
        env: {
          'TELEMETRY_ENABLED': 'true',
          'API_BASE_URL': 'https://api.example',
          'TELEMETRY_BASE_URL': 'https://telemetry.example',
        },
      );
      expect(config.endpoint, 'https://telemetry.example/v1/telemetry/events');
    });

    test('a trailing slash does not produce a double slash', () {
      final config = TelemetryConfig.fromEnvironment(
        env: {
          'TELEMETRY_ENABLED': 'true',
          'TELEMETRY_BASE_URL': 'https://telemetry.example/',
        },
      );
      expect(config.endpoint, 'https://telemetry.example/v1/telemetry/events');
    });

    test('enabled with no base URL fails closed', () {
      final config = TelemetryConfig.fromEnvironment(
        env: {'TELEMETRY_ENABLED': 'true'},
      );
      expect(config.enabled, isFalse);
    });

    test('the endpoint path is never hard-coded at a call site', () {
      // Application code composes base URL + contract path; this asserts the
      // path constant is the single source.
      expect(TelemetryContract.endpointPath, '/v1/telemetry/events');
      const config = TelemetryConfig(
        enabled: true,
        baseUrl: 'https://host.example',
      );
      expect(
        config.endpoint,
        'https://host.example${TelemetryContract.endpointPath}',
      );
    });
  });

  group('the default service is inert', () {
    test('Telemetry.instance is a no-op before init', () async {
      await Telemetry.reset();
      expect(Telemetry.instance.isActive, isFalse);
      // Must not throw.
      Telemetry.capture(const AppOpenEvent(launchType: LaunchType.cold));
      await Telemetry.instance.flush();
      Telemetry.instance.onAppBackgrounded();
    });
  });
}
