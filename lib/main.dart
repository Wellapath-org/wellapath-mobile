import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/crash/crash_reporter.dart';
import 'core/storage/storage_service.dart';
import 'core/telemetry/telemetry.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await StorageService.init();

  // Installed before the first frame so an early framework error is still
  // classified. Synchronous and dependency-free — it registers two handlers
  // and forwards to a sink that goes nowhere until a provider is approved.
  CrashReporter.install();

  runApp(const WellaPathApp());

  // Telemetry starts *after* runApp, deliberately. Opening the queue box and
  // reading configuration must never sit between launch and first frame:
  // telemetry is best-effort and the splash is on the clinical path to an
  // assessment. Unawaited for the same reason.
  unawaited(Telemetry.init());
}
