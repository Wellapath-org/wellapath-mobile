/// Obfuscation-safe removal of the SDK's automatic integrations.
///
/// The build-212 binary shipped with `removeAutomaticErrorIntegrations`
/// matching by `runtimeType.toString()`. `--obfuscate` renames every class,
/// so in the release build NO name matched and every automatic integration
/// stayed installed — while the same code passed in debug, where names are
/// unrenamed. These tests pin the corrected `is`-type behaviour:
///
///  * every unwanted integration type is removed, including under a
///    rename-simulating subclass (an `is` check is subtype-based, so renaming
///    cannot defeat it the way string matching was defeated);
///  * integrations outside the unwanted set survive untouched;
///  * the stale `LoadImageListIntegration` name is corrected — the SDK 9.x
///    class is `LoadNativeDebugImagesIntegration`, and it is removed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
// The unwanted classes are not public exports; the sink imports them the same
// way, pinned to CrashMonitoring.sdkVersion.
// ignore: implementation_imports
import 'package:sentry_flutter/src/app_start/ui_load_attached/native_app_start_integration.dart';
// ignore: implementation_imports
import 'package:sentry_flutter/src/integrations/debug_print_integration.dart';
// ignore: implementation_imports
import 'package:sentry_flutter/src/integrations/flutter_error_integration.dart';
// ignore: implementation_imports
import 'package:sentry_flutter/src/integrations/load_contexts_integration.dart';
// ignore: implementation_imports
import 'package:sentry_flutter/src/integrations/native_load_debug_images_integration.dart';
// ignore: implementation_imports
import 'package:sentry_flutter/src/integrations/native_sdk_integration.dart';
// ignore: implementation_imports
import 'package:sentry_flutter/src/integrations/screenshot_integration.dart';
// ignore: implementation_imports
import 'package:sentry_flutter/src/integrations/widgets_binding_integration.dart';
// ignore: implementation_imports
import 'package:sentry_flutter/src/integrations/widgets_flutter_binding_integration.dart';
// ignore: implementation_imports
import 'package:sentry_flutter/src/native/sentry_native_binding.dart';
import 'package:wellapath_mobile/core/crash/sentry_crash_sink.dart';

/// Construction-only stand-in: none of its members are ever invoked, the
/// integrations only need a binding instance to be constructed. Implementing
/// the SDK-internal binding interface is unavoidable here — the native
/// integrations under test accept nothing else.
// ignore: invalid_use_of_internal_member
class _FakeNativeBinding implements SentryNativeBinding {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('never invoked in these tests');
}

/// Stand-in for [NativeAppStartIntegration], whose real constructor needs
/// three handler objects. `implements` keeps the subtype relation the `is`
/// check relies on.
class _FakeNativeAppStartIntegration implements NativeAppStartIntegration {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('never invoked in these tests');
}

/// Simulates what obfuscation does to a class: same type hierarchy, different
/// name. String matching missed this; an `is` check must not.
class _RenamedFlutterErrorIntegration extends FlutterErrorIntegration {}

/// An integration outside the unwanted set — must survive removal.
class _KeptCustomIntegration implements Integration<SentryOptions> {
  @override
  void call(Hub hub, SentryOptions options) {}

  @override
  void close() {}
}

void main() {
  final native = _FakeNativeBinding();

  List<Integration> unwantedInstances() => [
    FlutterErrorIntegration(),
    OnErrorIntegration(),
    RunZonedGuardedIntegration(() async {}, null),
    IsolateErrorIntegration(),
    NativeSdkIntegration(native),
    LoadContextsIntegration(native),
    LoadNativeDebugImagesIntegration(native),
    _FakeNativeAppStartIntegration(),
    ScreenshotIntegration(),
    WidgetsBindingIntegration(),
    DebugPrintIntegration(),
  ];

  group('unwanted integrations are removed by type', () {
    test('every unwanted type is removed individually', () {
      for (final unwanted in unwantedInstances()) {
        final options = SentryFlutterOptions();
        for (final existing in List<Integration>.of(options.integrations)) {
          options.removeIntegration(existing);
        }
        options.addIntegration(unwanted);

        // ignore: invalid_use_of_visible_for_testing_member
        CrashMonitoring.removeAutomaticErrorIntegrations(options);

        expect(
          options.integrations,
          isEmpty,
          reason: '${unwanted.runtimeType} must be removed',
        );
      }
    });

    test('all unwanted types are removed together, kept ones survive', () {
      final options = SentryFlutterOptions();
      for (final existing in List<Integration>.of(options.integrations)) {
        options.removeIntegration(existing);
      }
      final kept = <Integration>[
        WidgetsFlutterBindingIntegration(),
        LoadReleaseIntegration(),
        _KeptCustomIntegration(),
      ];
      for (final integration in [...unwantedInstances(), ...kept]) {
        options.addIntegration(integration);
      }

      // ignore: invalid_use_of_visible_for_testing_member
      CrashMonitoring.removeAutomaticErrorIntegrations(options);

      expect(options.integrations, hasLength(kept.length));
      expect(options.integrations, containsAll(kept));
    });

    test('a rename-simulating subclass is still removed', () {
      // The 212 failure mode: same behaviour, different runtimeType string.
      final renamed = _RenamedFlutterErrorIntegration();
      expect(renamed.runtimeType.toString(), isNot('FlutterErrorIntegration'));

      final options = SentryFlutterOptions();
      for (final existing in List<Integration>.of(options.integrations)) {
        options.removeIntegration(existing);
      }
      options.addIntegration(renamed);

      // ignore: invalid_use_of_visible_for_testing_member
      CrashMonitoring.removeAutomaticErrorIntegrations(options);

      expect(options.integrations, isEmpty);
    });

    test(
      'the membership test itself is type-based for every unwanted type',
      () {
        for (final unwanted in unwantedInstances()) {
          expect(
            // ignore: invalid_use_of_visible_for_testing_member
            CrashMonitoring.isUnwantedIntegration(unwanted),
            isTrue,
            reason: '${unwanted.runtimeType} must be classified unwanted',
          );
        }
        // ignore: invalid_use_of_visible_for_testing_member
        expect(
          CrashMonitoring.isUnwantedIntegration(LoadReleaseIntegration()),
          isFalse,
        );
        // ignore: invalid_use_of_visible_for_testing_member
        expect(
          CrashMonitoring.isUnwantedIntegration(_KeptCustomIntegration()),
          isFalse,
        );
      },
    );
  });

  group('applyPrivacyOptions leaves no unwanted integration behind', () {
    test('after the privacy pass, the default set contains none', () {
      final options = SentryFlutterOptions();
      // The unit-test default set is what SentryOptions itself installs;
      // add the Flutter-side ones init would add, so the assertion covers
      // the full production surface.
      for (final integration in unwantedInstances()) {
        options.addIntegration(integration);
      }

      // ignore: invalid_use_of_visible_for_testing_member
      CrashMonitoring.applyPrivacyOptions(options);

      for (final integration in options.integrations) {
        expect(
          // ignore: invalid_use_of_visible_for_testing_member
          CrashMonitoring.isUnwantedIntegration(integration),
          isFalse,
          reason: '${integration.runtimeType} survived the privacy pass',
        );
      }
    });
  });
}
