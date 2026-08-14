import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/crash/crash_reporter.dart';
import 'core/crash/sentry_crash_sink.dart';
import 'core/storage/storage_service.dart';
import 'core/telemetry/telemetry.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await StorageService.init();

  // Installed before the first frame so an early framework error is still
  // classified. Synchronous and dependency-free — it registers the framework,
  // async and isolate handlers and forwards to a sink that goes nowhere.
  CrashReporter.install();

  runApp(const WellaPathApp());

  // A crash provider is attached *after* runApp, and only when both gates are
  // satisfied. Initialising an SDK between launch and first frame would put a
  // third-party package on the path to an assessment; unawaited for the same
  // reason telemetry is. Until this resolves, the boundary keeps its no-op
  // sink and local error behaviour is unchanged.
  unawaited(CrashMonitoring.init());

  // Telemetry starts *after* runApp, deliberately. Opening the queue box and
  // reading configuration must never sit between launch and first frame:
  // telemetry is best-effort and the splash is on the clinical path to an
  // assessment. Unawaited for the same reason.
  unawaited(Telemetry.init());
}
