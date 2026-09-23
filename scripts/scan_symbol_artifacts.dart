/// Mandatory pre-upload symbol-artifact scan (docs/NEUTRAL_BUILD_POLICY.md).
///
/// Usage:
///   dart run scripts/scan_symbol_artifacts.dart [options] <input>...
///
/// Inputs are the EXACT files/directories about to be uploaded or used for
/// symbolication: `build/symbols/` (Dart split-debug `.symbols`), Android
/// native/unstripped libraries and mapping artifacts, iOS `.dSYM` bundles,
/// and anything else handed to `sentry_dart_plugin` or `sentry-cli`.
///
/// Options:
///   --personal-name=NAME   The developer's personal username/identifier to
///                          fail on anywhere in an artifact. Repeatable.
///                          Also read from the WELLAPATH_PERSONAL_NAMES
///                          environment variable (comma-separated), so the
///                          name need not appear in shell history.
///   --approve-root=PREFIX  An explicitly approved neutral root prefix
///                          (e.g. /Users/Shared/wellapath-build-215/).
///                          Repeatable; adds to the built-in defaults.
///   --approve-user=NAME    A non-personal service-account name to allow
///                          under /Users, /home and C:\Users. Repeatable.
///
/// Exit codes: 0 clean · 1 prohibited path detected · 2 scan incomplete or
/// invalid (fail closed; dominates 1). Output is redaction-safe and is kept
/// as release evidence. There is deliberately NO bypass or warning-only
/// flag.
library;

import 'dart:io';

import 'symbol_artifact_scanner.dart';

Future<void> main(List<String> args) async {
  final inputs = <String>[];
  final personalNames = <String>{};
  final approvedRoots = List<String>.of(ScanRules.defaultApprovedRootPrefixes);
  final approvedMac = Set<String>.of(ScanRules.defaultApprovedMacUsers);
  final approvedLinux = Set<String>.of(ScanRules.defaultApprovedLinuxUsers);
  final approvedWindows = Set<String>.of(ScanRules.defaultApprovedWindowsUsers);

  for (final arg in args) {
    if (arg.startsWith('--personal-name=')) {
      personalNames.add(arg.substring('--personal-name='.length));
    } else if (arg.startsWith('--approve-root=')) {
      approvedRoots.add(arg.substring('--approve-root='.length));
    } else if (arg.startsWith('--approve-user=')) {
      final name = arg.substring('--approve-user='.length);
      approvedMac.add(name);
      approvedLinux.add(name);
      approvedWindows.add(name);
    } else if (arg.startsWith('--')) {
      stderr.writeln('unknown option: $arg');
      exitCode = 2;
      return;
    } else {
      inputs.add(arg);
    }
  }
  final envNames = Platform.environment['WELLAPATH_PERSONAL_NAMES'];
  if (envNames != null) {
    personalNames.addAll(envNames.split(',').map((n) => n.trim()));
  }

  final outcome = await scanInputs(
    inputs,
    ScanRules(
      personalNames: personalNames,
      approvedRootPrefixes: approvedRoots,
      approvedMacUsers: approvedMac,
      approvedLinuxUsers: approvedLinux,
      approvedWindowsUsers: approvedWindows,
    ),
  );

  for (final error in outcome.inputErrors) {
    stderr.writeln('INPUT ERROR: $error');
  }
  for (final finding in outcome.findings) {
    (finding.fatal ? stderr : stdout).writeln(finding);
  }
  stdout.writeln(
    'scan: ${outcome.scannedFiles} file(s) scanned, '
    '${outcome.findings.where((f) => f.fatal).length} prohibited finding(s), '
    '${outcome.inputErrors.length} input error(s) — '
    '${outcome.exitCode == 0
        ? 'CLEAN'
        : outcome.exitCode == 1
        ? 'PROHIBITED PATHS PRESENT'
        : 'SCAN INCOMPLETE (fail closed)'}',
  );
  exitCode = outcome.exitCode;
}
