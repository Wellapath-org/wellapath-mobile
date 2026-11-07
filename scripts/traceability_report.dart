/// Verifies `docs/traceability/test_map.yaml` against
/// `docs/traceability/requirements.yaml` and prints the requirement → test
/// matrix (Markdown).
///
/// Usage (from the repository root):
///   dart run scripts/traceability_report.dart [--out=PATH]
///
/// Fails (exit 1) if a mapped test file is missing, a `contains` test name is
/// not in its file, a requirement has neither tests nor a pending reason, a
/// mapping names an unknown requirement, or a clinical (CR-) requirement is
/// mapped to tests before the clinical reviewer defines it. Exit 2: bad usage.
library;

import 'dart:io';

import 'traceability.dart';

Future<void> main(List<String> args) async {
  String? outPath;
  for (final arg in args) {
    if (arg.startsWith('--out=')) {
      outPath = arg.substring('--out='.length);
    } else {
      stderr.writeln('unknown argument: $arg');
      exitCode = 2;
      return;
    }
  }

  const requirementsPath = 'docs/traceability/requirements.yaml';
  const mapPath = 'docs/traceability/test_map.yaml';
  final String requirements;
  final String map;
  try {
    requirements = File(requirementsPath).readAsStringSync();
    map = File(mapPath).readAsStringSync();
  } on FileSystemException catch (error) {
    stderr.writeln('cannot read ${error.path}: ${error.message}');
    exitCode = 1;
    return;
  }

  final report = buildTraceReport(
    requirementsYaml: requirements,
    mapYaml: map,
    fileExists: (path) => File(path).existsSync(),
    readFile: (path) => File(path).readAsStringSync(),
  );

  final matrix = renderMatrix(report);
  stdout.write(matrix);
  if (outPath != null) {
    final out = File(outPath);
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(matrix);
  }

  if (!report.ok) {
    stderr.writeln();
    for (final error in report.errors) {
      stderr.writeln('FAIL $error');
    }
    stderr.writeln('${report.errors.length} traceability error(s)');
    exitCode = 1;
  }
}
