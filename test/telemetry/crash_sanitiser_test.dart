/// Crash-boundary sanitisation.
///
/// Exception messages are the classic leak path: they quote values. These
/// tests feed representative sensitive strings through the sanitiser and
/// assert that nothing recognisable survives, and that the boundary does not
/// suppress the error it observed.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/crash/crash_reporter.dart';

void main() {
  tearDown(CrashReporter.resetForTest);

  group('sanitisation of representative sensitive strings', () {
    final cases = <String, String>{
      'symptom in a message': 'No rule matched severe_headache',
      'red flag rule id': 'StateError: rf_006 evaluation failed',
      'condition name': 'Exception: malaria scoring produced NaN',
      'urgency level': 'Bad state: urgency EMERGENCY was not expected',
      'question id': 'RangeError: question_id q_017 out of range',
      'pregnancy status': 'Assertion failed: pregnancy must be bool',
      'score': 'Invalid score contribution for condition typhoid',
      'email': 'Failed to notify user@example.com',
      'phone number': 'Dial failed for +234 801 234 5678',
      'coordinates': 'No facility near 6.5243793,3.3792057',
      'bearer token': 'Rejected Authorization: Bearer abc.def.ghi',
      'quoted value': "Invalid argument: 'productive cough for two weeks'",
    };

    cases.forEach((label, message) {
      test('$label is redacted', () {
        final sanitised = CrashSanitiser.sanitise(Exception(message));
        for (final leak in [
          'severe_headache',
          'rf_006',
          'malaria',
          'typhoid',
          'EMERGENCY',
          'q_017',
          'pregnancy',
          'user@example.com',
          '6.5243793',
          '3.3792057',
          'productive cough',
        ]) {
          expect(
            sanitised.toLowerCase(),
            isNot(contains(leak.toLowerCase())),
            reason: '$label leaked "$leak" through as: $sanitised',
          );
        }
      });
    });

    test('a phone number does not survive in any grouping', () {
      for (final phone in [
        '+2348012345678',
        '08012345678',
        '+234 801 234 5678',
        '0801-234-5678',
      ]) {
        final sanitised = CrashSanitiser.sanitise(Exception('call $phone now'));
        expect(sanitised, isNot(contains('8012345678')));
        expect(sanitised, isNot(contains('801 234 5678')));
      }
    });

    test('a long message is truncated', () {
      final sanitised = CrashSanitiser.sanitise(Exception('x' * 5000));
      expect(
        sanitised.length,
        lessThanOrEqualTo(CrashSanitiser.maxMessageLength + 1),
      );
    });

    test('a null error does not throw', () {
      expect(CrashSanitiser.sanitise(null), '');
      expect(CrashSanitiser.classify(null), 'UnknownError');
    });

    test('classification is a Dart type name, never a value', () {
      expect(
        CrashSanitiser.classify(StateError('malaria in the message')),
        'StateError',
      );
      expect(CrashSanitiser.classify(ArgumentError('rf_006')), 'ArgumentError');
    });
  });

  group('the report has no attachment surface', () {
    test('a report serialises to exactly four non-clinical fields', () {
      const report = SanitisedCrashReport(
        classification: 'StateError',
        origin: 'flutter_framework',
        message: 'something went wrong',
        isFatal: false,
      );
      expect(report.toJson().keys.toSet(), {
        'classification',
        'origin',
        'message',
        'is_fatal',
      });
    });
  });

  group('the boundary does not suppress errors', () {
    test('the previous FlutterError handler still runs', () {
      final previouslyHandled = <Object>[];
      final original = FlutterError.onError;
      FlutterError.onError = (details) =>
          previouslyHandled.add(details.exception);

      final sink = RecordingCrashSink();
      CrashReporter.install(sink: sink);

      final error = StateError('engine failed');
      FlutterError.onError!(FlutterErrorDetails(exception: error));

      expect(
        previouslyHandled,
        contains(error),
        reason: 'a clinical failure must still fail as loudly as before',
      );
      expect(sink.reports, hasLength(1));
      expect(sink.reports.single.classification, 'StateError');

      FlutterError.onError = original;
    });

    test('reportHandled records without changing caller behaviour', () {
      final sink = RecordingCrashSink();
      CrashReporter.install(sink: sink);
      CrashReporter.reportHandled(
        StateError('artifact load failed for malaria'),
        origin: 'artifact_loader',
      );
      expect(sink.reports.single.origin, 'artifact_loader');
      expect(sink.reports.single.message, isNot(contains('malaria')));
    });

    test('a sink that throws does not become the crash', () {
      CrashReporter.install(sink: _ThrowingSink());
      expect(
        () => CrashReporter.reportHandled(StateError('boom'), origin: 'test'),
        returnsNormally,
      );
    });
  });

  group('no provider is configured', () {
    test('the default sink transmits nothing', () {
      CrashReporter.resetForTest();
      expect(CrashReporter.sink, isA<NoOpCrashSink>());
    });
  });
}

class _ThrowingSink implements CrashSink {
  @override
  void report(SanitisedCrashReport report) => throw StateError('sink failed');
}
