/// Guarded `xcodebuild -exportArchive` — verify the export options, or refuse.
///
/// **Why a wrapper and not just a verifier.** A standalone check is only as good
/// as someone's memory of running it. Build 216's `ExportOptions.plist` was
/// hand-authored and nothing stood between it and `xcodebuild`. This wrapper is
/// that something: it takes the export-options pathname, verifies **that exact
/// pathname** with Apple's parser, and invokes `xcodebuild` only on exit 0 —
/// passing through **the same pathname it verified**, never a regenerated or
/// substituted one.
///
/// The substitution point matters as much as the verdict. A wrapper that
/// verified one file and exported with another would satisfy every test about
/// the verifier while shipping an unverified plist, so
/// [runGuardedExport] returns the arguments it actually used and the tests
/// assert the verified path appears in them.
library;

import 'dart:io';

import 'export_options_policy.dart';

/// Invokes the export command and returns its exit code. Injectable so tests can
/// assert the real command is **never** reached when verification fails.
typedef ExportInvoker = int Function(List<String> arguments);

/// What [runGuardedExport] did.
class GuardedExportResult {
  const GuardedExportResult({
    required this.exitCode,
    required this.exportInvoked,
    required this.verdict,
    this.exportArguments,
  });

  /// Exit code to return from the process.
  final int exitCode;

  /// Whether the export command was invoked at all. Must be `false` whenever
  /// [verdict] is not a pass.
  final bool exportInvoked;

  /// The verification verdict for the export-options file.
  final ExportOptionsVerdict verdict;

  /// Arguments handed to the export command, or `null` if it was never invoked.
  final List<String>? exportArguments;
}

/// Verifies [exportOptionsPath], then exports only if that passed.
///
/// Returns without invoking [exportInvoker] on any non-zero verdict.
GuardedExportResult runGuardedExport({
  required String archivePath,
  required String exportOptionsPath,
  required String exportPath,
  required ExportInvoker exportInvoker,
  PlutilRunner plutil = const SystemPlutilRunner(),
  List<String> extraArguments = const [],
}) {
  final verdict = verifyExportOptionsFile(
    path: exportOptionsPath,
    plutil: plutil,
  );

  if (!verdict.isPass) {
    // Hard stop. Nothing is exported and nothing is uploaded.
    return GuardedExportResult(
      exitCode: verdict.exitCode,
      exportInvoked: false,
      verdict: verdict,
    );
  }

  // The verified pathname is passed straight through. Deliberately the same
  // variable — there is no regeneration step between verification and export.
  final arguments = <String>[
    '-exportArchive',
    '-archivePath',
    archivePath,
    '-exportPath',
    exportPath,
    '-exportOptionsPlist',
    exportOptionsPath,
    ...extraArguments,
  ];

  final exportExit = exportInvoker(arguments);
  return GuardedExportResult(
    exitCode: exportExit,
    exportInvoked: true,
    verdict: verdict,
    exportArguments: arguments,
  );
}

/// Runs the real `xcodebuild`, streaming its output.
int runXcodebuild(List<String> arguments) {
  final result = Process.runSync('xcodebuild', arguments);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  return result.exitCode;
}

String? _option(List<String> args, String name) {
  final prefix = '--$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

void main(List<String> args) {
  final archivePath = _option(args, 'archive-path');
  final exportOptionsPath = _option(args, 'export-options');
  final exportPath = _option(args, 'export-path');

  if (archivePath == null || exportOptionsPath == null || exportPath == null) {
    stderr.writeln(
      'usage: dart run scripts/guarded_export.dart '
      '--archive-path=PATH --export-options=PATH --export-path=PATH',
    );
    exit(2);
  }

  final result = runGuardedExport(
    archivePath: archivePath,
    exportOptionsPath: exportOptionsPath,
    exportPath: exportPath,
    exportInvoker: runXcodebuild,
  );

  if (!result.exportInvoked) {
    stderr.writeln(
      'REFUSED: export options at $exportOptionsPath did not pass '
      'verification. xcodebuild was NOT invoked.',
    );
    for (final message in result.verdict.messages) {
      stderr.writeln('  - $message');
    }
    exit(result.exitCode);
  }

  exit(result.exitCode);
}
