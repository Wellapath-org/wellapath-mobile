/// A controllable stand-in for `/usr/bin/plutil`.
///
/// Exists so the fail-closed paths — plutil absent, lint rejecting the file,
/// conversion failing, conversion returning something unreadable — can be
/// exercised on any platform, including Linux CI where Apple's parser does not
/// exist. The cases that must go through the REAL parser live in
/// `export_options_plutil_test.dart`, tagged `plutil`, and run on macOS.
///
/// This fake is never used to decide a production verdict; it only lets tests
/// prove the wrapper refuses to certify when the parser cannot answer.
library;

import 'dart:convert';

import '../../scripts/export_options_policy.dart';

class FakePlutilRunner implements PlutilRunner {
  FakePlutilRunner({
    this.available = true,
    this.lintExitCode = 0,
    this.convertExitCode = 0,
    this.convertStdout,
    this.stderrText = '',
    Map<String, Object?>? rootObject,
  }) : _rootObject = rootObject;

  /// Whether the fake reports `plutil` as present and executable.
  final bool available;

  /// Exit code returned for `-lint`.
  final int lintExitCode;

  /// Exit code returned for `-convert json`.
  final int convertExitCode;

  /// Raw stdout for `-convert json`. Takes precedence over [_rootObject], so a
  /// test can return deliberately unreadable output.
  final String? convertStdout;

  final String stderrText;

  final Map<String, Object?>? _rootObject;

  /// Every argument list this fake was asked to run, in order.
  final List<List<String>> invocations = [];

  @override
  bool get isAvailable => available;

  @override
  PlutilResult run(List<String> args) {
    invocations.add(List.unmodifiable(args));

    if (args.isNotEmpty && args.first == '-lint') {
      return PlutilResult(
        exitCode: lintExitCode,
        stdout: lintExitCode == 0 ? 'OK' : '',
        stderr: lintExitCode == 0 ? '' : stderrText,
      );
    }

    if (args.isNotEmpty && args.first == '-convert') {
      if (convertExitCode != 0) {
        return PlutilResult(exitCode: convertExitCode, stderr: stderrText);
      }
      final out =
          convertStdout ?? jsonEncode(_rootObject ?? <String, Object?>{});
      return PlutilResult(exitCode: 0, stdout: out);
    }

    return PlutilResult(exitCode: -1, stderr: 'unexpected args: $args');
  }
}

/// A root object that satisfies every policy requirement.
Map<String, Object?> compliantRoot() => <String, Object?>{
  'method': 'app-store-connect',
  'destination': 'upload',
  'teamID': '2SCUC2CBBS',
  'signingStyle': 'automatic',
  'uploadSymbols': true,
  'stripSwiftSymbols': true,
};
