/// Generate or verify an iOS distribution export-options plist.
///
/// Usage:
///
/// ```
/// # Generate. uploadSymbols is always true; it is not an option.
/// dart run scripts/export_options_tool.dart generate \
///     --mode=internal-testing|app-store \
///     --destination=export|upload \
///     --team-id=TEAMID \
///     [--out=PATH]
///
/// # Verify a plist that already exists, however it was produced.
/// dart run scripts/export_options_tool.dart verify PLIST...
/// ```
///
/// Exit contract, matching `scripts/scan_symbol_artifacts.dart`:
///
///   0 = all inputs verified, policy satisfied
///   1 = a policy violation was found
///   2 = the invocation or an input was unusable, so nothing was verified
///
/// **Fail closed.** Exit 2 dominates: an incomplete check certifies nothing.
/// There is no bypass flag and no warning-only mode, deliberately.
///
/// Verification delegates to Apple's `/usr/bin/plutil`, so it requires macOS. A
/// missing `plutil` is exit 2, never a pass — see `export_options_policy.dart`
/// for why there is no string-scanner fallback.
///
/// `verify` is a MANDATORY pre-export and pre-upload step — see
/// `docs/NEUTRAL_BUILD_POLICY.md` §5.4. It is separate from, and does not
/// replace, the neutral-path scan of the archive and dSYMs. For the real export
/// path prefer `scripts/guarded_export.dart`, which refuses to invoke
/// `xcodebuild` unless this verification passes.
library;

import 'dart:io';

import 'export_options_policy.dart';

const int _exitOk = 0;
const int _exitViolation = 1;
const int _exitUnusable = 2;

void main(List<String> args) {
  if (args.isEmpty) {
    _usage('no subcommand given');
  }

  switch (args.first) {
    case 'generate':
      _generate(args.skip(1).toList());
    case 'verify':
      _verify(args.skip(1).toList());
    default:
      _usage('unknown subcommand "${args.first}"');
  }
}

Never _usage(String problem) {
  stderr
    ..writeln('error: $problem')
    ..writeln()
    ..writeln('usage:')
    ..writeln(
      '  dart run scripts/export_options_tool.dart generate '
      '--mode=internal-testing|app-store --destination=export|upload '
      '--team-id=TEAMID [--out=PATH]',
    )
    ..writeln('  dart run scripts/export_options_tool.dart verify PLIST...');
  exit(_exitUnusable);
}

String? _option(List<String> args, String name) {
  final prefix = '--$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

Never _generate(List<String> args) {
  final modeRaw = _option(args, 'mode');
  final destinationRaw = _option(args, 'destination');
  final teamId = _option(args, 'team-id');
  final out = _option(args, 'out');

  // No defaults. An internal-only marker must never be inherited silently, and
  // neither must its absence on an external candidate.
  final mode = switch (modeRaw) {
    'internal-testing' => DistributionMode.internalTesting,
    'app-store' => DistributionMode.appStore,
    null => _usage('--mode is required (internal-testing|app-store)'),
    _ => _usage('--mode must be internal-testing or app-store, got "$modeRaw"'),
  };

  final destination = switch (destinationRaw) {
    'export' => ExportDestination.export,
    'upload' => ExportDestination.upload,
    null => _usage('--destination is required (export|upload)'),
    _ => _usage(
      '--destination must be export or upload, got "$destinationRaw"',
    ),
  };

  if (teamId == null || teamId.trim().isEmpty) {
    _usage('--team-id is required');
  }

  final plist = buildExportOptionsPlist(
    mode: mode,
    destination: destination,
    teamId: teamId,
  );

  if (out == null) {
    stdout.write(plist);
    exit(_exitOk);
  }

  File(out).writeAsStringSync(plist);

  // Verify what we just wrote, through the same parser a release engineer would
  // use. A generator that is not checked against the policy it implements is a
  // second place for the rule to drift.
  //
  // This verification is never skipped. If `plutil` is unavailable the generator
  // FAILS CLOSED with exit 2 (see below) rather than reporting success for a
  // file nothing checked — an earlier version exited 0 with a passing note,
  // which is the shape of claim this policy exists to prevent.
  final verdict = verifyExportOptionsFile(path: out);
  if (verdict.outcome == VerificationOutcome.violation) {
    stderr.writeln(
      'internal error: generated plist violates the policy it implements:',
    );
    for (final message in verdict.messages) {
      stderr.writeln('  - $message');
    }
    exit(_exitUnusable);
  }

  // Fail closed rather than reporting success for a file nothing verified.
  // Writing a plist and exiting 0 while admitting in passing that it was never
  // checked is the shape of claim this policy exists to prevent.
  if (verdict.outcome == VerificationOutcome.unusable) {
    stderr
      ..writeln('wrote $out, but it could NOT be verified:')
      ..writeln('  - ${verdict.messages.join('\n  - ')}')
      ..writeln(
        'NOTHING IS CERTIFIED about that file. Generate it on a machine with '
        '$kPlutilPath, or verify it there before exporting.',
      );
    exit(_exitUnusable);
  }

  stdout.writeln('wrote $out (mode=$modeRaw, destination=$destinationRaw)');
  exit(_exitOk);
}

Never _verify(List<String> paths) {
  if (paths.isEmpty) {
    _usage('verify needs at least one plist path');
  }

  var violations = 0;
  var unusable = 0;

  for (final path in paths) {
    final verdict = verifyExportOptionsFile(path: path);

    switch (verdict.outcome) {
      case VerificationOutcome.pass:
        stdout.writeln('OK $path');
      case VerificationOutcome.violation:
        for (final message in verdict.messages) {
          stdout.writeln('FAIL $path: $message');
        }
        violations += verdict.messages.length;
      case VerificationOutcome.unusable:
        for (final message in verdict.messages) {
          stderr.writeln('UNUSABLE $path: $message');
        }
        unusable++;
    }
  }

  // Fail closed: an incomplete check certifies nothing, so unusable inputs
  // dominate violations.
  if (unusable > 0) {
    stderr.writeln(
      'export-options verify: $unusable unusable input(s) — '
      'NOTHING IS CERTIFIED',
    );
    exit(_exitUnusable);
  }

  if (violations > 0) {
    stdout.writeln(
      'export-options verify: $violations violation(s) — '
      'DO NOT EXPORT OR UPLOAD',
    );
    exit(_exitViolation);
  }

  stdout.writeln('export-options verify: ${paths.length} file(s) — CLEAN');
  exit(_exitOk);
}
