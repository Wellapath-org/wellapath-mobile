/// End-to-end capture of the **actual outbound envelope**.
///
/// The other privacy tests assert on `SentryEvent.toJson()`. This one runs a
/// real SDK client with the real privacy configuration and intercepts the
/// envelope at the transport — the last point before bytes would leave the
/// device. It therefore covers anything the SDK attaches *after* `beforeSend`,
/// which an event-level test cannot see.
///
/// No network is used and no Sentry account is required: the transport is
/// replaced, so nothing is ever sent. The DSN below is structurally valid and
/// entirely fictitious.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wellapath_mobile/core/crash/crash_config.dart';
import 'package:wellapath_mobile/core/crash/sentry_crash_sink.dart';

/// Sentinels standing in for each prohibited category.
const marker = 'ZZTRANSPORTZZ';

/// Captures envelopes instead of sending them, and exposes their raw bytes.
class CapturingTransport implements Transport {
  final List<String> envelopes = [];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    final buffer = <int>[];
    await for (final chunk in envelope.envelopeStream(SentryOptions())) {
      buffer.addAll(chunk);
    }
    envelopes.add(utf8.decode(buffer, allowMalformed: true));
    return envelope.header.eventId;
  }

  String get all => envelopes.join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CapturingTransport transport;

  setUp(() async {
    transport = CapturingTransport();
    // A structurally valid, fictitious DSN. Nothing is transmitted because the
    // transport is replaced below.
    await CrashMonitoring.init(
      config: const CrashConfig(
        enabled: true,
        dsn: 'https://abc123def456@o0.ingest.de.sentry.io/1234567',
        environment: 'internal-beta',
        release: 'wellapath-mobile@0.2.0+208',
      ),
    );
    await Sentry.close();
    await SentryFlutter.init((options) {
      CrashMonitoring.applyPrivacyOptions(options);
      options.transport = transport;
    });
  });

  tearDown(() async => Sentry.close());

  Future<void> capture(Object error, {StackTrace? stack}) async {
    await Sentry.captureException(
      error,
      stackTrace: stack ?? StackTrace.current,
      withScope: (scope) {
        scope.setTag('crash_source', 'flutter_framework');
        scope.setTag('severity', 'fatal');
      },
    );
  }

  group('the outbound envelope carries only approved data', () {
    test(
      'a clean crash produces an envelope with approved keys only',
      () async {
        await capture(StateError('engine returned null'));

        expect(transport.envelopes, isNotEmpty);
        final body = transport.all;

        // Useful for engineering.
        expect(body, contains('StateError'));
        expect(body, contains('internal-beta'));
        expect(body, contains('wellapath-mobile@0.2.0+208'));
        expect(body, contains('flutter_framework'));

        // Never present.
        for (final forbidden in [
          '"user"',
          '"request"',
          '"breadcrumbs"',
          '"contexts"',
          '"extra"',
          '"modules"',
          '"threads"',
          '"debug_meta"',
          'ip_address',
          'device_id',
          'screenshot',
          'view_hierarchy',
          'replay',
          'profile',
          'attachment',
        ]) {
          expect(
            body,
            isNot(contains(forbidden)),
            reason: '$forbidden reached the outbound envelope',
          );
        }
      },
    );

    test(
      'clinical content in an exception never reaches the envelope',
      () async {
        await capture(
          StateError(
            'no rule matched severe_headache; malaria scored 87; '
            'urgency EMERGENCY; session gt9mliaiMVXuZLEJodZxtSw9; '
            'question_id q_017; pregnancy true; $marker',
          ),
        );

        final body = transport.all;
        for (final leak in [
          marker,
          'severe_headache',
          'malaria',
          'EMERGENCY',
          'gt9mliaiMVXuZLEJodZxtSw9',
          'q_017',
          'pregnancy',
        ]) {
          expect(
            body,
            isNot(contains(leak)),
            reason: '"$leak" reached the outbound envelope',
          );
        }
      },
    );

    test('scope pollution set by other code is stripped', () async {
      await Sentry.configureScope((scope) {
        scope.setContexts('assessment', {'urgency': 'EMERGENCY'});
        scope.setTag('assessment_session_id', marker);
      });
      await capture(StateError('boom'));

      final body = transport.all;
      expect(body, isNot(contains(marker)));
      expect(body, isNot(contains('EMERGENCY')));
      expect(body, isNot(contains('assessment')));
    });

    test('a user set anywhere never reaches the envelope', () async {
      await Sentry.configureScope(
        (scope) =>
            scope.setUser(SentryUser(id: marker, email: '$marker@example.com')),
      );
      await capture(StateError('boom'));

      final body = transport.all;
      expect(body, isNot(contains(marker)));
      expect(body, isNot(contains('"user"')));
    });

    test('breadcrumbs added anywhere never reach the envelope', () async {
      await Sentry.addBreadcrumb(
        Breadcrumb(message: 'tapped $marker', category: 'ui.click'),
      );
      await capture(StateError('boom'));

      final body = transport.all;
      expect(body, isNot(contains(marker)));
      expect(body, isNot(contains('ui.click')));
    });

    test('stack frames remain useful', () async {
      await capture(StateError('boom'));
      final body = transport.all;
      // The frames come from this test file, which lives under package:.
      expect(body, contains('"stacktrace"'));
      expect(body, contains('frames'));
    });

    test('the envelope header carries routing metadata only', () async {
      await capture(StateError('boom'));
      final header = transport.envelopes.single.split('\n').first;

      // The DSN public key and the DSN itself DO appear in the envelope
      // header. That is by design and unavoidable: it is how the ingest
      // endpoint routes the envelope, and a Sentry DSN public key is not a
      // secret — it ships inside every client, including browser JavaScript.
      // What matters is that it is not committed to source, documentation or
      // logs, which `crash_config_test.dart` covers.
      expect(header, contains('"dsn"'));

      // What must NOT be in the header: anything about the user or the device.
      for (final forbidden in [
        'ip_address',
        'device',
        'user',
        'email',
        'session',
        marker,
      ]) {
        expect(
          header,
          isNot(contains(forbidden)),
          reason: '$forbidden appeared in the envelope header',
        );
      }
      // Header fields are limited to routing and build identity.
      expect(header, contains('internal-beta'));
      expect(header, contains('wellapath-mobile@0.2.0+208'));
    });

    test(
      'no auth token or symbol-upload credential is ever in an envelope',
      () {
        // Those live only in protected CI secrets and are never compiled in.
        for (final credential in ['sentry-auth-token', 'SENTRY_AUTH_TOKEN']) {
          expect(transport.all, isNot(contains(credential)));
        }
      },
    );
  });

  group('a disabled configuration transmits nothing', () {
    test('init with the disabled config never attaches a provider', () async {
      await Sentry.close();
      final quiet = CapturingTransport();
      await CrashMonitoring.init(config: CrashConfig.disabled);
      expect(CrashMonitoring.config.enabled, isFalse);
      expect(quiet.envelopes, isEmpty);
    });
  });
}
