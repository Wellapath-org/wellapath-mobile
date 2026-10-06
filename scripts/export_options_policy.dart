/// iOS distribution export-options policy — generate, and verify via `plutil`.
///
/// **Why this exists.** Build 216 was exported and uploaded with
/// `uploadSymbols` set to `false`, so no dSYMs reached App Store Connect and
/// automatic Apple-side symbolication is unavailable for that build. The cause
/// was structural: the `ExportOptions.plist` was hand-authored in an untracked
/// build directory, so no source-controlled rule existed for it to violate.
///
/// **Why this is not a string scanner.** The first two versions of this library
/// scanned the plist as text. Independent review defeated both:
///
///  1. it read the *first* occurrence of a key while Apple resolves the *last*,
///     and it matched keys inside XML comments;
///  2. after that was fixed, it still had no notion of nesting, so an
///     `uploadSymbols` buried in the legitimate `provisioningProfiles`
///     sub-dictionary was reported CLEAN while Apple saw no root-level key at
///     all — the exact "omitted" state this policy calls the 216 regression.
///
/// Both escapes came from the same root cause: a text scanner has no model of
/// plist structure, so each patch closed one shape and left the class open.
/// **Apple's own parser now decides the verdict.** `/usr/bin/plutil` resolves
/// the file — duplicate keys, comments, nesting and types included — and this
/// library reads its answer. A parser cannot disagree with itself.
///
/// The cost is deliberate: verification now requires macOS. That is where iOS
/// archives are exported, and a guard that is portable but wrong is worth less
/// than one that is correct where it runs. If `plutil` is missing the verdict is
/// **exit 2 — nothing certified**. There is no regex fallback, because a
/// fallback is just the defeated scanner wearing a different name.
library;

import 'dart:convert';
import 'dart:io';

/// Whether the exported build is for the internal tester cohort or for
/// external/public distribution. Deliberately has no default value.
enum DistributionMode {
  /// TestFlight internal testers only. Emits
  /// `testFlightInternalTestingOnly`, which bars external testing and Beta App
  /// Review for the build by construction rather than by policy.
  internalTesting,

  /// External/public App Store distribution. Emits no internal-only marker.
  appStore,
}

/// Whether `xcodebuild -exportArchive` writes the container locally or sends it
/// to App Store Connect.
enum ExportDestination {
  /// Write the container to `-exportPath`. Uploads nothing.
  export,

  /// Upload to App Store Connect.
  upload,
}

/// The only permitted value of `uploadSymbols` for a distribution export.
const bool kRequiredUploadSymbols = true;

/// Absolute path to Apple's property-list tool. Absolute on purpose: a `PATH`
/// lookup could resolve to something else.
const String kPlutilPath = '/usr/bin/plutil';

/// Root keys a distribution export must declare explicitly.
const List<String> kRequiredRootKeys = [
  'uploadSymbols',
  'method',
  'destination',
  'teamID',
];

/// Keys this policy reasons about. Used for asserting properties of our own
/// generated output; the verdict never depends on counting them in text.
const List<String> kPolicyKeys = [
  'uploadSymbols',
  'method',
  'destination',
  'teamID',
  'signingStyle',
  'stripSwiftSymbols',
  'testFlightInternalTestingOnly',
];

/// Keys whose presence indicates leaked credential material.
const List<String> kForbiddenCredentialKeys = [
  'storePassword',
  'keyPassword',
  'keyAlias',
  'storeFile',
  'password',
  'privateKey',
  'apiKey',
  'apiIssuer',
];

/// How a verification ended. Maps 1:1 onto the CLI exit contract.
enum VerificationOutcome {
  /// Policy satisfied. Exit 0.
  pass,

  /// A policy violation was found. Exit 1.
  violation,

  /// Nothing could be certified — missing `plutil`, unreadable or unparseable
  /// input, or a parser failure. Exit 2, which dominates.
  unusable,
}

/// The verdict for one export-options file.
class ExportOptionsVerdict {
  const ExportOptionsVerdict(this.outcome, this.messages);

  final VerificationOutcome outcome;
  final List<String> messages;

  /// Exit code for the CLI. `2` dominates `1` dominates `0`.
  int get exitCode => switch (outcome) {
    VerificationOutcome.pass => 0,
    VerificationOutcome.violation => 1,
    VerificationOutcome.unusable => 2,
  };

  bool get isPass => outcome == VerificationOutcome.pass;
}

/// One `plutil` invocation's result.
class PlutilResult {
  const PlutilResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Indirection over `plutil` so tests can simulate it being absent or failing
/// unexpectedly. Production always uses [SystemPlutilRunner].
abstract interface class PlutilRunner {
  /// Whether [kPlutilPath] exists and is executable.
  bool get isAvailable;

  /// Runs `plutil` with [args].
  PlutilResult run(List<String> args);
}

/// Runs the real `/usr/bin/plutil`.
class SystemPlutilRunner implements PlutilRunner {
  const SystemPlutilRunner();

  @override
  bool get isAvailable {
    final file = File(kPlutilPath);
    if (!file.existsSync()) return false;
    // Existence is not enough; it must be runnable.
    final mode = file.statSync().mode;
    const anyExecuteBit = 0x49; // 0o111
    return mode & anyExecuteBit != 0;
  }

  @override
  PlutilResult run(List<String> args) {
    try {
      final result = Process.runSync(kPlutilPath, args);
      return PlutilResult(
        exitCode: result.exitCode,
        stdout: result.stdout is String ? result.stdout as String : '',
        stderr: result.stderr is String ? result.stderr as String : '',
      );
    } on ProcessException catch (error) {
      // Could not execute at all. Caller turns this into exit 2.
      return PlutilResult(exitCode: -1, stderr: error.message);
    }
  }
}

/// Generates an export-options plist for [mode] and [destination].
///
/// `uploadSymbols` is always `true` — see [kRequiredUploadSymbols]. There is no
/// parameter to disable it.
String buildExportOptionsPlist({
  required DistributionMode mode,
  required ExportDestination destination,
  required String teamId,
}) {
  if (teamId.trim().isEmpty) {
    throw ArgumentError.value(teamId, 'teamId', 'must not be empty');
  }

  final lines = <String>[
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
    '<dict>',
    '\t<key>method</key>',
    '\t<string>app-store-connect</string>',
    '\t<key>destination</key>',
    '\t<string>${destination == ExportDestination.upload ? 'upload' : 'export'}'
        '</string>',
    '\t<key>teamID</key>',
    '\t<string>$teamId</string>',
    '\t<key>signingStyle</key>',
    '\t<string>automatic</string>',
    '\t<key>uploadSymbols</key>',
    '\t<${kRequiredUploadSymbols ? 'true' : 'false'}/>',
    '\t<key>stripSwiftSymbols</key>',
    '\t<true/>',
  ];

  if (mode == DistributionMode.internalTesting) {
    lines
      ..add('\t<key>testFlightInternalTestingOnly</key>')
      ..add('\t<true/>');
  }

  lines
    ..add('</dict>')
    ..add('</plist>')
    ..add('');

  return lines.join('\n');
}

/// Removes XML comments from [xml]. Used only for asserting properties of our
/// own generated output, never to decide a value.
String stripXmlComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// Live (non-commented) `<key>$key</key>` occurrences in [plistXml].
///
/// Supplementary only. [verifyExportOptionsFile] takes every value from
/// `plutil`; this exists so tests can assert the generator never emits a key
/// twice, where there is no nesting to confuse it.
int countKeyOccurrences(String plistXml, String key) => RegExp(
  '<key>${RegExp.escape(key)}</key>',
).allMatches(stripXmlComments(plistXml)).length;

/// Verifies the export-options file at [path] using Apple's parser.
///
/// Sequence, failing closed at every step:
///
///  1. `plutil` must exist and be executable, else
///     [VerificationOutcome.unusable].
///  2. The file must exist and be non-empty.
///  3. `plutil -lint` must pass — a malformed plist is never certified.
///  4. `plutil -convert json` must succeed and yield a JSON **object**, so the
///     root is a dictionary.
///  5. `uploadSymbols` must be present at the **root**, be a **boolean**, and be
///     **true**. A key reachable only inside a nested dictionary or array is
///     absent from the root object, so it reads as omitted — which is a
///     violation, exactly as Apple would see it.
///
/// Apple's parsed root-level result determines the value verdict. The credential
/// scan is an additional, independent policy check; it can add violations but
/// never overrides what `plutil` resolved.
ExportOptionsVerdict verifyExportOptionsFile({
  required String path,
  PlutilRunner plutil = const SystemPlutilRunner(),
}) {
  if (!plutil.isAvailable) {
    return ExportOptionsVerdict(VerificationOutcome.unusable, [
      '$kPlutilPath is missing or not executable, so Apple\'s parser could not '
          'decide this file. NOTHING IS CERTIFIED. There is deliberately no '
          'string-scanner fallback: two earlier scanner versions were defeated '
          'by comments, duplicate keys and nesting. Run this on macOS.',
    ]);
  }

  final file = File(path);
  if (!file.existsSync()) {
    return ExportOptionsVerdict(VerificationOutcome.unusable, [
      'no such file: $path',
    ]);
  }

  final String raw;
  try {
    raw = file.readAsStringSync();
  } on FileSystemException catch (error) {
    return ExportOptionsVerdict(VerificationOutcome.unusable, [
      'cannot read $path: ${error.message}',
    ]);
  }
  if (raw.trim().isEmpty) {
    return ExportOptionsVerdict(VerificationOutcome.unusable, [
      '$path is empty',
    ]);
  }

  final lint = plutil.run(['-lint', path]);
  if (lint.exitCode != 0) {
    return ExportOptionsVerdict(VerificationOutcome.unusable, [
      '$path is not a valid property list, so it cannot be certified. '
          'plutil -lint said: '
          '${_oneLine(lint.stderr.isEmpty ? lint.stdout : lint.stderr)}',
    ]);
  }

  final converted = plutil.run(['-convert', 'json', '-o', '-', path]);
  if (converted.exitCode != 0) {
    return ExportOptionsVerdict(VerificationOutcome.unusable, [
      'plutil could not convert $path for inspection: '
          '${_oneLine(converted.stderr.isEmpty ? converted.stdout : converted.stderr)}',
    ]);
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(converted.stdout);
  } on FormatException catch (error) {
    return ExportOptionsVerdict(VerificationOutcome.unusable, [
      'plutil returned output this tool could not read as JSON '
          '(${error.message}). NOTHING IS CERTIFIED.',
    ]);
  }

  if (decoded is! Map<String, Object?>) {
    return ExportOptionsVerdict(VerificationOutcome.unusable, [
      'the root of $path is not a dictionary, so it is not a usable '
          'ExportOptions file.',
    ]);
  }

  final violations = <String>[];
  final root = decoded;

  // --- the value verdict, from Apple's parse of the ROOT object ---
  if (!root.containsKey('uploadSymbols')) {
    violations.add(
      'uploadSymbols is OMITTED at the root. A distribution export must set '
      'it true so dSYMs reach App Store Connect. Note that a key nested '
      'inside a sub-dictionary such as provisioningProfiles, or inside an '
      'array, is NOT a root key — Apple does not see it, and neither does '
      'this check. Omitting it is the build-216 regression.',
    );
  } else {
    final value = root['uploadSymbols'];
    if (value is! bool) {
      violations.add(
        'uploadSymbols must be a boolean, but Apple parsed it as '
        '${_describeType(value)}. A string "true" or an integer 1 is not a '
        'boolean and does not enable symbol upload.',
      );
    } else if (value != kRequiredUploadSymbols) {
      violations.add(
        'uploadSymbols is DISABLED (false). Build 216 shipped with it false '
        'and no dSYMs reached App Store Connect.',
      );
    }
  }

  // --- additional, independent policy checks ---
  for (final key in kRequiredRootKeys) {
    if (key == 'uploadSymbols') continue; // reported above with more detail
    if (!root.containsKey(key)) {
      violations.add(
        '$key is missing at the root. It must be explicit, never inherited '
        'from an xcodebuild default.',
      );
    }
  }

  for (final key in kForbiddenCredentialKeys) {
    // Checked against the raw text as well as the parse: a credential sitting
    // in a comment is still a leaked credential.
    if (root.containsKey(key) || raw.contains('<key>$key</key>')) {
      violations.add(
        'forbidden key "$key" is present. An export-options file must never '
        'carry credential material.',
      );
    }
  }

  // NO duplicate-key lint here, deliberately.
  //
  // An earlier version counted `<key>…</key>` occurrences in the raw text and
  // rejected any repeat. With `plutil` deciding the value that check became both
  // unnecessary and wrong:
  //
  //  * Unnecessary — `plutil` resolves a duplicated key to the last occurrence,
  //    which is exactly what `xcodebuild` will do. A duplicate cannot make the
  //    verdict disagree with what ships, so rejecting it protects nothing.
  //  * Wrong — being text-based it could not tell nesting levels apart, so a
  //    legitimate file with root `uploadSymbols` true and an unrelated
  //    same-named key inside `provisioningProfiles` was flagged as a duplicate.
  //    That is a false positive, and the policy requires that no supplementary
  //    check disagree with Apple's parse.
  //
  // Making it accurate would mean re-introducing the structure scanner this
  // library exists to replace.

  return violations.isEmpty
      ? const ExportOptionsVerdict(VerificationOutcome.pass, [])
      : ExportOptionsVerdict(VerificationOutcome.violation, violations);
}

String _describeType(Object? value) => switch (value) {
  null => 'null',
  String() => 'a string ("$value")',
  int() => 'an integer ($value)',
  double() => 'a real ($value)',
  List() => 'an array',
  Map() => 'a dictionary',
  _ => value.runtimeType.toString(),
};

String _oneLine(String text) =>
    text.trim().replaceAll(RegExp(r'\s+'), ' ').trim();
