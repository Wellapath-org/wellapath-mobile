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
/// `verify` is a MANDATORY pre-upload step for every iOS distribution export —
/// see `docs/NEUTRAL_BUILD_POLICY.md`. It is separate from, and does not
/// replace, the neutral-path scan of the archive and dSYMs.
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
    ..writeln('  dart run scripts/export_options_tool.dart verify <plist>...');
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

  // Verify what we just produced. A generator that is not checked against the
  // same policy as a hand-written file is a second place for the rule to drift.
  final violations = verifyExportOptions(plist);
  if (violations.isNotEmpty) {
    stderr.writeln(
      'internal error: generated plist violates the policy it implements:',
    );
    for (final violation in violations) {
      stderr.writeln('  - $violation');
    }
    exit(_exitUnusable);
  }

  if (out == null) {
    stdout.write(plist);
  } else {
    File(out).writeAsStringSync(plist);
    stdout.writeln('wrote $out (mode=$modeRaw, destination=$destinationRaw)');
  }
  exit(_exitOk);
}

Never _verify(List<String> paths) {
  if (paths.isEmpty) {
    _usage('verify needs at least one plist path');
  }

  var violationCount = 0;
  var unusable = 0;

  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('UNUSABLE $path: no such file');
      unusable++;
      continue;
    }

    final String contents;
    try {
      contents = file.readAsStringSync();
    } on FileSystemException catch (error) {
      stderr.writeln('UNUSABLE $path: ${error.message}');
      unusable++;
      continue;
    }

    if (contents.trim().isEmpty) {
      stderr.writeln('UNUSABLE $path: file is empty');
      unusable++;
      continue;
    }

    final violations = verifyExportOptions(contents);
    if (violations.isEmpty) {
      stdout.writeln('OK $path');
    } else {
      for (final violation in violations) {
        stdout.writeln('FAIL $path: $violation');
      }
      violationCount += violations.length;
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

  if (violationCount > 0) {
    stdout.writeln(
      'export-options verify: $violationCount violation(s) — '
      'DO NOT EXPORT OR UPLOAD',
    );
    exit(_exitViolation);
  }

  stdout.writeln('export-options verify: ${paths.length} file(s) — CLEAN');
  exit(_exitOk);
}
