/// Adversarial privacy tests against the **serialized outbound Sentry event**.
///
/// The assertions here are made on `event.toJson()` — the actual bytes the
/// transport would send — not on the Dart object. An object-level check can
/// pass while a field the SDK serializes from somewhere else still reaches the
/// wire, and this is the last boundary before a third party receives data.
///
/// Every marker below is a fixed non-clinical sentinel. No real assessment
/// content is used, and no captured envelope is committed.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wellapath_mobile/core/crash/sentry_event_sanitiser.dart';

/// Distinctive sentinels standing in for each prohibited category.
const marker = 'ZZSENTINELZZ';

void main() {
  /// Serializes exactly as the transport would, so assertions see the bytes.
  String wire(SentryEvent? event) =>
      event == null ? '' : jsonEncode(event.toJson());

  SentryEvent baseEvent({
    List<SentryException>? exceptions,
    Map<String, String>? tags,
  }) => SentryEvent(
    eventId: SentryId.newId(),
    timestamp: DateTime.utc(2026, 8, 14),
    level: SentryLevel.fatal,
    release: 'wellapath-mobile@0.2.0+208',
    environment: 'internal-beta',
    platform: 'dart',
    exceptions:
        exceptions ??
        [
          SentryException(
            type: 'StateError',
            value: 'something failed',
            stackTrace: SentryStackTrace(
              frames: [
                SentryStackFrame(
                  absPath: 'package:wellapath_mobile/core/engine/x.dart',
                  fileName: 'x.dart',
                  function: 'EngineController.run',
                  lineNo: 42,
                  colNo: 7,
                  inApp: true,
                ),
              ],
            ),
          ),
        ],
    tags: tags,
  );

  group('the whole-event allowlist', () {
    test('a clean event survives with only approved fields', () {
      final sanitised = SentryEventSanitiser.sanitise(baseEvent());
      expect(sanitised, isNotNull);
      final json = sanitised!.toJson();
      // Whatever else the SDK may add, only these keys may appear.
      const approved = {
        'event_id',
        'timestamp',
        'platform',
        'level',
        'release',
        'environment',
        'dist',
        'exception',
        'tags',
      };
      expect(
        json.keys.toSet().difference(approved),
        isEmpty,
        reason: 'unexpected top-level key reached the wire: ${json.keys}',
      );
    });

    test('an event with no exception is dropped entirely', () {
      final event = SentryEvent(exceptions: const []);
      expect(SentryEventSanitiser.sanitise(event), isNull);
    });

    test('release and environment are preserved for triage', () {
      final json = SentryEventSanitiser.sanitise(baseEvent())!.toJson();
      expect(json['release'], 'wellapath-mobile@0.2.0+208');
      expect(json['environment'], 'internal-beta');
    });
  });

  group('prohibited top-level structures never survive', () {
    test(
      'user, request, breadcrumbs, contexts, extra, modules are stripped',
      () {
        final event = SentryEvent(
          exceptions: baseEvent().exceptions,
          user: SentryUser(
            id: marker,
            email: '$marker@example.com',
            ipAddress: '10.1.2.3',
            username: marker,
          ),
          request: SentryRequest(
            url: 'https://api.example/assess?symptom=$marker',
            cookies: 'session=$marker',
            headers: {'Authorization': 'Bearer $marker'},
            data: {'answer': marker},
          ),
          breadcrumbs: [
            Breadcrumb(message: 'tapped $marker', category: 'ui.click'),
          ],
          // ignore: deprecated_member_use
          extra: {'assessment_session_id': marker, 'urgency': 'EMERGENCY'},
          modules: {'wellapath': marker},
          contexts: Contexts(
            device: SentryDevice(name: marker, model: marker),
            culture: SentryCulture(locale: 'en_NG', timezone: 'Africa/Lagos'),
          ),
          tags: {'assessment_session_id': marker, 'urgency': 'EMERGENCY'},
          fingerprint: [marker],
          transaction: '/assessment/$marker',
          serverName: marker,
          logger: marker,
        );

        final out = wire(SentryEventSanitiser.sanitise(event));

        expect(out, isNot(contains(marker)));
        for (final key in [
          'user',
          'request',
          'breadcrumbs',
          'contexts',
          'extra',
          'modules',
          'fingerprint',
          'transaction',
          'server_name',
          'logger',
          'threads',
          'debug_meta',
          'sdk',
        ]) {
          expect(
            out,
            isNot(contains('"$key"')),
            reason: '$key reached the serialized envelope',
          );
        }
        expect(out, isNot(contains('EMERGENCY')));
        expect(out, isNot(contains('Africa/Lagos')));
        expect(out, isNot(contains('10.1.2.3')));
      },
    );

    test('only allowlisted tags survive, with allowlisted values', () {
      final event = baseEvent(
        tags: {
          'crash_source': 'flutter_framework',
          'severity': 'fatal',
          'assessment_session_id': marker,
          'urgency_category': 'EMERGENCY',
          'facility_id': 'ng_lag_1261',
        },
      );
      final json = SentryEventSanitiser.sanitise(event)!.toJson();
      expect(json['tags'], {
        'crash_source': 'flutter_framework',
        'severity': 'fatal',
      });
      expect(
        wire(SentryEventSanitiser.sanitise(event)),
        isNot(contains(marker)),
      );
    });

    test('an out-of-vocabulary tag value is dropped, not passed through', () {
      final event = baseEvent(
        tags: {'crash_source': 'assessment_screen', 'severity': 'urgent'},
      );
      final json = SentryEventSanitiser.sanitise(event)!.toJson();
      expect(json.containsKey('tags'), isFalse);
    });
  });

  group('exception values are sanitised', () {
    final cases = <String, String>{
      'symptom token': 'No rule matched severe_headache',
      'red flag rule': 'rf_006 evaluation failed',
      'condition': 'malaria scoring produced NaN',
      'urgency': 'urgency EMERGENCY was not expected',
      'question id': 'question_id q_017 out of range',
      'pregnancy': 'pregnancy must be bool',
      'score': 'invalid score for typhoid',
      'session id': 'session gt9mliaiMVXuZLEJodZxtSw9 not found',
      'email': 'failed to notify user@example.com',
      'phone': 'dial failed for +234 801 234 5678',
      'coordinates': 'no facility near 6.5243793,3.3792057',
      'token': 'rejected Authorization: Bearer abc.def.ghi',
      'quoted answer': "Invalid argument: 'productive cough for two weeks'",
    };

    cases.forEach((label, message) {
      test('$label is redacted in the exception value', () {
        final event = baseEvent(
          exceptions: [SentryException(type: 'StateError', value: message)],
        );
        final out = wire(SentryEventSanitiser.sanitise(event)).toLowerCase();
        for (final leak in [
          'severe_headache',
          'rf_006',
          'malaria',
          'typhoid',
          'emergency',
          'q_017',
          'pregnancy',
          'user@example.com',
          '6.5243793',
          'productive cough',
          'gt9mliaimvxuzlejodzxtsw9',
        ]) {
          expect(out, isNot(contains(leak)), reason: '$label leaked "$leak"');
        }
      });
    });

    test('the exception type is kept when it is a real Dart type', () {
      final event = baseEvent(
        exceptions: [SentryException(type: 'RangeError', value: 'x')],
      );
      final json = SentryEventSanitiser.sanitise(event)!.toJson();
      expect(jsonEncode(json), contains('RangeError'));
    });

    test('a type carrying a value is replaced', () {
      final event = baseEvent(
        exceptions: [
          SentryException(type: 'Error for patient $marker', value: 'x'),
        ],
      );
      expect(
        wire(SentryEventSanitiser.sanitise(event)),
        isNot(contains(marker)),
      );
    });

    test('the raw throwable is never re-attached', () {
      final event = baseEvent(
        exceptions: [
          SentryException(
            type: 'StateError',
            value: 'clean',
            throwable: StateError('secret $marker'),
          ),
        ],
      );
      expect(
        wire(SentryEventSanitiser.sanitise(event)),
        isNot(contains(marker)),
      );
    });
  });

  group('stack frames stay useful but safe', () {
    test('package paths, functions and line numbers are preserved', () {
      final json = SentryEventSanitiser.sanitise(baseEvent())!.toJson();
      final out = jsonEncode(json);
      expect(out, contains('package:wellapath_mobile/core/engine/x.dart'));
      expect(out, contains('EngineController.run'));
      expect(out, contains('42'));
    });

    test('symbolication addresses survive for obfuscated builds', () {
      final event = baseEvent(
        exceptions: [
          SentryException(
            type: 'StateError',
            value: 'x',
            stackTrace: SentryStackTrace(
              frames: [
                SentryStackFrame(
                  instructionAddr: '0x1234',
                  imageAddr: '0x1000',
                  symbolAddr: '0x1200',
                  platform: 'native',
                ),
              ],
            ),
          ),
        ],
      );
      final out = wire(SentryEventSanitiser.sanitise(event));
      expect(out, contains('0x1234'));
      expect(out, contains('0x1000'));
    });

    test('a developer home directory is reduced to a basename', () {
      final event = baseEvent(
        exceptions: [
          SentryException(
            type: 'StateError',
            value: 'x',
            stackTrace: SentryStackTrace(
              frames: [
                SentryStackFrame(
                  absPath: '/Users/$marker/dev/wellapath-mobile/lib/a.dart',
                  fileName: '/Users/$marker/dev/wellapath-mobile/lib/a.dart',
                ),
              ],
            ),
          ),
        ],
      );
      final out = wire(SentryEventSanitiser.sanitise(event));
      expect(out, isNot(contains(marker)));
      expect(out, contains('a.dart'));
    });

    test('a URL frame loses its query string', () {
      final event = baseEvent(
        exceptions: [
          SentryException(
            type: 'StateError',
            value: 'x',
            stackTrace: SentryStackTrace(
              frames: [
                SentryStackFrame(
                  absPath: 'https://host/app.js?token=$marker&symptom=fever',
                ),
              ],
            ),
          ),
        ],
      );
      final out = wire(SentryEventSanitiser.sanitise(event));
      expect(out, isNot(contains(marker)));
      expect(out, isNot(contains('fever')));
    });

    test('source text and local variables never survive', () {
      final event = baseEvent(
        exceptions: [
          SentryException(
            type: 'StateError',
            value: 'x',
            stackTrace: SentryStackTrace(
              frames: [
                SentryStackFrame(
                  fileName: 'a.dart',
                  contextLine: "final symptoms = ['$marker'];",
                  preContext: ['// $marker'],
                  postContext: ['// $marker'],
                  vars: {'answers': marker},
                ),
              ],
            ),
          ),
        ],
      );
      final out = wire(SentryEventSanitiser.sanitise(event));
      expect(out, isNot(contains(marker)));
      expect(out, isNot(contains('context_line')));
      expect(out, isNot(contains('vars')));
    });

    test('a dynamically built frame label is replaced', () {
      final event = baseEvent(
        exceptions: [
          SentryException(
            type: 'StateError',
            value: 'x',
            stackTrace: SentryStackTrace(
              frames: [
                SentryStackFrame(function: 'handleAnswer("$marker")'),
                SentryStackFrame(function: 'score for severe_headache'),
              ],
            ),
          ),
        ],
      );
      final out = wire(SentryEventSanitiser.sanitise(event));
      expect(out, isNot(contains(marker)));
      expect(out, isNot(contains('severe_headache')));
    });

    test('absurdly deep stacks are truncated', () {
      final event = baseEvent(
        exceptions: [
          SentryException(
            type: 'StateError',
            value: 'x',
            stackTrace: SentryStackTrace(
              frames: List.generate(
                500,
                (i) => SentryStackFrame(fileName: 'f$i.dart'),
              ),
            ),
          ),
        ],
      );
      final sanitised = SentryEventSanitiser.sanitise(event)!;
      expect(
        sanitised.exceptions!.single.stackTrace!.frames,
        hasLength(SentryEventSanitiser.maxFrames),
      );
    });
  });

  group('fail closed', () {
    test('nothing is hashed and forwarded in place of a prohibited value', () {
      // A hash of a prohibited value is still derived from it. The sanitiser
      // must drop, not transform.
      final event = baseEvent(
        exceptions: [
          SentryException(type: 'StateError', value: 'answer=$marker'),
        ],
      );
      final out = wire(SentryEventSanitiser.sanitise(event));
      expect(out, isNot(contains(marker)));
      expect(out, isNot(contains(marker.hashCode.toString())));
    });

    test('the sanitiser is total — no input makes it throw', () {
      final awkward = [
        SentryEvent(exceptions: null),
        SentryEvent(exceptions: const []),
        SentryEvent(exceptions: [SentryException(type: null, value: null)]),
        SentryEvent(
          exceptions: [
            SentryException(
              type: '',
              value: '',
              stackTrace: SentryStackTrace(frames: const []),
            ),
          ],
        ),
      ];
      for (final event in awkward) {
        expect(() => SentryEventSanitiser.sanitise(event), returnsNormally);
      }
    });
  });
}
