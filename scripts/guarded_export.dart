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
/// the verifier while shipping an unverified plist, so [runGuardedExport]
/// returns the arguments it actually used and the tests assert the verified path
/// appears in them.
///
/// **Scope of the guarantee.** It covers this wrapper only. Calling
/// `xcodebuild -exportArchive` by hand still works and skips the check entirely,
/// exactly as `docs/NEUTRAL_BUILD_POLICY.md` §4 already concedes for the
/// neutral-path scanner. The wrapper removes the chance of *forgetting* the
/// check when you use it; it does not make the check unavoidable.
library;

import 'dart:io';

import 'export_options_policy.dart';

/// Absolute path to Apple's build tool.
///
/// Absolute for the same reason [kPlutilPath] is: a bare `xcodebuild` resolved
/// through `PATH` could be anything earlier on the path, and the one command
/// this wrapper exists to gate is not a good place to accept that. A review of
/// the previous version demonstrated the asymmetry by putting a fake
/// `xcodebuild` first on `PATH` and watching it get invoked.
const String kXcodebuildPath = '/usr/bin/xcodebuild';

/// The flag this wrapper is authoritative for. It may never be supplied or
/// overridden by a caller through `extraArguments`.
const String kExportOptionsFlag = '-exportOptionsPlist';

/// Indirection over `xcodebuild` so tests can inject a recording or unavailable
/// runner. Testability comes from this seam, deliberately — **not** from putting
/// a fake executable earlier on `PATH`, which is the behaviour
/// [kXcodebuildPath] exists to rule out.
abstract interface class XcodebuildRunner {
  /// Whether [kXcodebuildPath] exists and is executable.
  bool get isAvailable;

  /// Runs `xcodebuild` with [arguments] and returns its exit code.
  int run(List<String> arguments);
}

/// Runs the real `/usr/bin/xcodebuild`, streaming its output.
class SystemXcodebuildRunner implements XcodebuildRunner {
  const SystemXcodebuildRunner();

  @override
  bool get isAvailable {
    final file = File(kXcodebuildPath);
    if (!file.existsSync()) return false;
    final mode = file.statSync().mode;
    const anyExecuteBit = 0x49; // 0o111
    return mode & anyExecuteBit != 0;
  }

  @override
  int run(List<String> arguments) {
    try {
      final result = Process.runSync(kXcodebuildPath, arguments);
      stdout.write(result.stdout);
      stderr.write(result.stderr);
      return result.exitCode;
    } on ProcessException catch (error) {
      stderr.writeln('could not execute $kXcodebuildPath: ${error.message}');
      return 2;
    }
  }
}

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

  /// The verification verdict, or — for a refusal that is not about the plist's
  /// contents, such as a rejected `extraArguments` or an unusable
  /// `xcodebuild` — an [VerificationOutcome.unusable] verdict carrying the
  /// reason. Either way a non-pass means nothing was exported.
  final ExportOptionsVerdict verdict;

  /// Arguments handed to the export command, or `null` if it was never invoked.
  final List<String>? exportArguments;
}

/// Whether [argument] supplies or overrides [kExportOptionsFlag] in any form.
///
/// Matches the bare flag, an inline `-exportOptionsPlist=/path` form, and a
/// double-dashed spelling, case-insensitively. Deliberately broad: the cost of a
/// false positive is one rejected unrelated argument, and the cost of a false
/// negative is an export that used a plist nobody verified.
bool overridesExportOptions(String argument) {
  final normalised = argument.toLowerCase().replaceAll(RegExp(r'^-+'), '');
  return normalised == kExportOptionsFlag.substring(1).toLowerCase() ||
      normalised.startsWith(
        '${kExportOptionsFlag.substring(1).toLowerCase()}=',
      );
}

/// Verifies [exportOptionsPath], then exports only if that passed.
///
/// Returns without invoking [xcodebuild] on any non-zero verdict, on a rejected
/// [extraArguments], or when `xcodebuild` itself is unusable.
GuardedExportResult runGuardedExport({
  required String archivePath,
  required String exportOptionsPath,
  required String exportPath,
  required XcodebuildRunner xcodebuild,
  PlutilRunner plutil = const SystemPlutilRunner(),
  List<String> extraArguments = const [],
}) {
  // Checked FIRST, before anything else and certainly before any invocation:
  // this wrapper is authoritative for which plist is exported, and a caller
  // smuggling a second -exportOptionsPlist would make the verified path
  // irrelevant — xcodebuild would take the later one.
  for (final argument in extraArguments) {
    if (overridesExportOptions(argument)) {
      return GuardedExportResult(
        exitCode: 2,
        exportInvoked: false,
        verdict: ExportOptionsVerdict(VerificationOutcome.unusable, [
          'extraArguments may not supply or override $kExportOptionsFlag '
              '(got "$argument"). This wrapper is authoritative for the plist '
              'path it verified; a second one would make that verification '
              'meaningless because xcodebuild takes the later value. Nothing '
              'was exported.',
        ]),
      );
    }
  }

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

  // Fail closed on a missing or non-executable build tool, before export.
  if (!xcodebuild.isAvailable) {
    return GuardedExportResult(
      exitCode: 2,
      exportInvoked: false,
      verdict: ExportOptionsVerdict(VerificationOutcome.unusable, [
        '$kXcodebuildPath is missing or not executable. NOTHING WAS EXPORTED. '
            'The path is fixed rather than resolved through PATH so that the '
            'one command this wrapper gates cannot be substituted.',
      ]),
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
    kExportOptionsFlag,
    exportOptionsPath,
    ...extraArguments,
  ];

  final exportExit = xcodebuild.run(arguments);
  return GuardedExportResult(
    exitCode: exportExit,
    exportInvoked: true,
    verdict: verdict,
    exportArguments: arguments,
  );
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
    xcodebuild: const SystemXcodebuildRunner(),
  );

  if (!result.exportInvoked) {
    stderr.writeln(
      'REFUSED: nothing was exported. $kXcodebuildPath was NOT invoked.',
    );
    for (final message in result.verdict.messages) {
      stderr.writeln('  - $message');
    }
    exit(result.exitCode);
  }

  exit(result.exitCode);
}
