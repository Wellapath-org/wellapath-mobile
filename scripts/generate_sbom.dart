/// Emits a CycloneDX 1.6 JSON SBOM for the app from `pubspec.lock`.
///
/// Usage:
///   dart run scripts/generate_sbom.dart [--lock=pubspec.lock]
///       [--pubspec=pubspec.yaml] [--out=build/sbom/sbom-mobile.cdx.json]
///       [--git-commit=SHA] [--timestamp=ISO8601]
///
/// Without `--out` the SBOM is written to stdout. No network access.
/// Exit codes: 0 written · 1 lockfile unreadable or invalid · 2 bad usage.
library;

import 'dart:convert';
import 'dart:io';

import 'pubspec_lock_sbom.dart';

Future<void> main(List<String> args) async {
  var lockPath = 'pubspec.lock';
  var pubspecPath = 'pubspec.yaml';
  String? outPath;
  String? gitCommit;
  DateTime? timestamp;

  for (final arg in args) {
    final eq = arg.indexOf('=');
    final key = eq < 0 ? arg : arg.substring(0, eq);
    final value = eq < 0 ? '' : arg.substring(eq + 1);
    switch (key) {
      case '--lock':
        lockPath = value;
      case '--pubspec':
        pubspecPath = value;
      case '--out':
        outPath = value;
      case '--git-commit':
        gitCommit = value;
      case '--timestamp':
        timestamp = DateTime.tryParse(value);
        if (timestamp == null) {
          stderr.writeln('invalid --timestamp: $value');
          exitCode = 2;
          return;
        }
      default:
        stderr.writeln('unknown argument: $arg');
        exitCode = 2;
        return;
    }
  }

  try {
    final bom = buildCycloneDxFromPubspecLock(
      pubspecLock: File(lockPath).readAsStringSync(),
      pubspecYaml: File(pubspecPath).readAsStringSync(),
      timestamp: timestamp ?? DateTime.now().toUtc(),
      gitCommit: gitCommit,
    );
    final json = '${const JsonEncoder.withIndent('  ').convert(bom)}\n';
    if (outPath == null) {
      stdout.write(json);
    } else {
      final out = File(outPath);
      out.parent.createSync(recursive: true);
      out.writeAsStringSync(json);
      final count = (bom['components'] as List).length;
      stdout.writeln('CycloneDX 1.6 SBOM: $count components -> $outPath');
    }
  } on FileSystemException catch (error) {
    stderr.writeln('cannot read input: ${error.path}: ${error.message}');
    exitCode = 1;
  } on Exception catch (error) {
    stderr.writeln('$error');
    exitCode = 1;
  }
}
