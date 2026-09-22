/// Installation and survival of the pure-Dart debug-images integration.
///
/// The 213 audit found events arriving with NO `debug_meta` and every frame
/// `unknown_image`. Local stage instrumentation demonstrated the cause:
/// `SentryFlutter.init` forces `enableDartSymbolication = false` whenever a
/// native binding exists (mobile), BEFORE `Sentry.init` runs — and
/// `Sentry.init`'s default-values phase, the only place the SDK ever adds
/// `LoadDartDebugImagesIntegration`, reads the flag at that moment. Our
/// options callback restored the flag afterwards, which cannot resurrect an
/// add-decision that was already skipped. Flag true + integration absent =
/// no debug images, ever.
///
/// These tests pin the fix and the pipeline behind it:
///
///  * `applyPrivacyOptions` adds the integration when it is absent (the
///    mobile path) — exactly once;
///  * it does not duplicate one that is already present (web / a future SDK
///    whose default-values phase adds it);
///  * the unwanted-integration removal does not remove it (it is unrelated
///    to `LoadNativeDebugImagesIntegration`, which IS removed);
///  * end to end in-process: the SDK processor derives ONE image from a
///    parsed obfuscated-format stack trace, the sanitiser passes exactly the
///    five approved fields, and the serialized event carries them — with the
///    debug ID derived from the trace's build_id and no other image fields.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
// The SDK classes below are not public exports; the sink imports them the
// same way, pinned to CrashMonitoring.sdkVersion.
// ignore: implementation_imports
import 'package:sentry/src/load_dart_debug_images_integration.dart';
// ignore: implementation_imports
import 'package:sentry/src/platform/platform.dart' as sdk_platform;
// ignore: implementation_imports
import 'package:sentry/src/sentry_stack_trace_factory.dart';
import 'package:wellapath_mobile/core/crash/sentry_crash_sink.dart';
import 'package:wellapath_mobile/core/crash/sentry_event_sanitiser.dart';

/// A deterministic Android identity for the image-derivation test, so the
/// expected `type`/`code_file` constants do not depend on the host OS the
/// suite happens to run on.
class _AndroidPlatform extends sdk_platform.Platform {
  const _AndroidPlatform();

  @override
  sdk_platform.OperatingSystem get operatingSystem =>
      sdk_platform.OperatingSystem.android;
}

/// The obfuscated-release stack trace format (`--obfuscate
/// --split-debug-info`), exactly as the VM emits it: header lines carrying
/// the build id and isolate base address, then absolute-address frames.
/// Values are synthetic.
const String _obfuscatedTrace = '''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 19226, tid: 6103134208, name io.flutter.ui
os: android arch: arm64 comp: no sim: no
build_id: 'bca64abfdfcc84d231bb8f1ccdbfbd8d'
isolate_dso_base: 10fa20000, vm_dso_base: 10fa20000
isolate_instructions: 10fa27070, vm_instructions: 10fa21e20
    #00 abs 000000010fa346d7 _kDartIsolateSnapshotInstructions+0x1e26d7
    #01 abs 000000010fa37527 _kDartIsolateSnapshotInstructions+0x1e5527
    #02 abs 000000010fa38999 _kDartIsolateSnapshotInstructions+0x1e6999
''';

const Set<String> _approvedImageFields = {
  'type',
  'image_addr',
  'debug_id',
  'code_id',
  'code_file',
};

int _countDartDebugImagesIntegrations(SentryOptions options) =>
    options.integrations.whereType<LoadDartDebugImagesIntegration>().length;

void main() {
  group('installation in applyPrivacyOptions', () {
    test(
      'adds the integration when absent (the mobile path), exactly once',
      () {
        final options = SentryFlutterOptions();
        // The precondition the fix exists for: SentryFlutter's created options
        // carry no dart debug-images integration on mobile, because the
        // default-values phase saw the flag forced false.
        expect(_countDartDebugImagesIntegrations(options), 0);

        // ignore: invalid_use_of_visible_for_testing_member
        CrashMonitoring.applyPrivacyOptions(options);

        expect(options.enableDartSymbolication, isTrue);
        expect(_countDartDebugImagesIntegrations(options), 1);
      },
    );

    test('does not duplicate an integration that is already present', () {
      final options = SentryFlutterOptions()
        ..addIntegration(LoadDartDebugImagesIntegration());

      // ignore: invalid_use_of_visible_for_testing_member
      CrashMonitoring.applyPrivacyOptions(options);

      expect(_countDartDebugImagesIntegrations(options), 1);
    });

    test('the unwanted-integration removal leaves it installed', () {
      final options = SentryFlutterOptions()
        ..addIntegration(LoadDartDebugImagesIntegration());

      // ignore: invalid_use_of_visible_for_testing_member
      CrashMonitoring.removeAutomaticErrorIntegrations(options);

      expect(_countDartDebugImagesIntegrations(options), 1);
    });

    test(
      'debug/JIT precisely: the integration OBJECT is installed, but its '
      'call() adds no event processor (runtime gates close, not the flag)',
      () {
        final options = SentryFlutterOptions();
        // ignore: invalid_use_of_visible_for_testing_member
        CrashMonitoring.applyPrivacyOptions(options);
        options.dsn = 'https://k@h/1';

        final integration = options.integrations
            .whereType<LoadDartDebugImagesIntegration>()
            .single;
        expect(
          options.eventProcessors
              // ignore: invalid_use_of_internal_member
              .whereType<LoadDartDebugImagesIntegrationEventProcessor>(),
          isEmpty,
        );

        // Execute the integration exactly as Sentry.init's integration loop
        // would. In a JIT test run isAppObfuscated()/isSplitDebugInfoBuild()
        // are false, so the gate inside call() must close.
        integration.call(Hub(options), options);

        expect(
          options.eventProcessors
              // ignore: invalid_use_of_internal_member
              .whereType<LoadDartDebugImagesIntegrationEventProcessor>(),
          isEmpty,
          reason:
              'in JIT/debug the processor must not install; the no-op comes '
              'from the runtime checks, not from the flag',
        );
        expect(options.enableDartSymbolication, isTrue);
      },
    );

    test('is idempotent across a second apply', () {
      final options = SentryFlutterOptions();
      // ignore: invalid_use_of_visible_for_testing_member
      CrashMonitoring.applyPrivacyOptions(options);
      // ignore: invalid_use_of_visible_for_testing_member
      CrashMonitoring.applyPrivacyOptions(options);

      expect(_countDartDebugImagesIntegrations(options), 1);
    });
  });

  group('image derivation, sanitisation and serialization', () {
    SentryEvent buildEventWithParsedTrace(SentryOptions options) {
      final parsed = SentryStackTraceFactory(
        options,
      ).parse(StackTrace.fromString(_obfuscatedTrace));
      return SentryEvent(
        exceptions: [
          SentryException(
            type: 'StateError',
            value: 'synthetic verification',
            stackTrace: parsed,
          ),
        ],
      );
    }

    test('the parsed trace carries what the processor needs', () {
      final options = SentryOptions(dsn: 'https://k@h/1')
        ..platform = const _AndroidPlatform();
      final event = buildEventWithParsedTrace(options);
      final stackTrace = event.exceptions!.single.stackTrace!;

      // ignore: invalid_use_of_internal_member
      expect(stackTrace.buildId, 'bca64abfdfcc84d231bb8f1ccdbfbd8d');
      // ignore: invalid_use_of_internal_member
      expect(stackTrace.baseAddr, '0x10fa20000');
      expect(stackTrace.frames.any((f) => f.platform == 'native'), isTrue);
    });

    test(
      'processor derives one image; sanitiser and serialization keep exactly '
      'the five approved fields with the derived debug id',
      () async {
        final options = SentryOptions(dsn: 'https://k@h/1')
          ..platform = const _AndroidPlatform();
        final event = buildEventWithParsedTrace(options);

        final processor = LoadDartDebugImagesIntegrationEventProcessor(options);
        final processed = (await processor.apply(event, Hint()))!;

        final images = processed.debugMeta?.images;
        expect(images, isNotNull);
        expect(images, hasLength(1));

        final sanitised = SentryEventSanitiser.sanitise(processed)!;
        final json = sanitised.toJson();
        final debugMeta = json['debug_meta'] as Map<String, dynamic>;
        final serialized = (debugMeta['images'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(serialized, hasLength(1));

        final image = serialized.single;
        expect(image.keys.toSet(), _approvedImageFields);
        expect(image['type'], 'elf');
        expect(image['code_file'], 'libapp.so');
        expect(image['image_addr'], '0x10fa20000');
        expect(image['code_id'], 'bca64abfdfcc84d231bb8f1ccdbfbd8d');
        // The debug id is the build id in GUID form (the SDK byte-swaps the
        // first three groups on little-endian hosts). Pin shape and content:
        // a UUID whose hex digits are a permutation of the build id's.
        final debugId = image['debug_id'] as String;
        expect(
          debugId,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
            ),
          ),
        );
        final digits = debugId.replaceAll('-', '');
        expect(digits.length, 32);
        final sortedDigits = (digits.split('')..sort()).join();
        final sortedBuildId = ('bca64abfdfcc84d231bb8f1ccdbfbd8d'.split(
          '',
        )..sort()).join();
        expect(sortedDigits, sortedBuildId);
      },
    );

    test(
      'no image is derived when the trace has no obfuscation header',
      () async {
        final options = SentryOptions(dsn: 'https://k@h/1')
          ..platform = const _AndroidPlatform();
        final parsed = SentryStackTraceFactory(
          options,
        ).parse(StackTrace.current);
        final event = SentryEvent(
          exceptions: [
            SentryException(
              type: 'StateError',
              value: 'plain trace',
              stackTrace: parsed,
            ),
          ],
        );

        final processor = LoadDartDebugImagesIntegrationEventProcessor(options);
        final processed = (await processor.apply(event, Hint()))!;

        expect(processed.debugMeta?.images ?? const <DebugImage>[], isEmpty);
      },
    );
  });
}
