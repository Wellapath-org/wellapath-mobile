/// Symbol-artifact scanner engine — the neutral-build-path gate.
///
/// Every potentially distributable build and every symbol upload must
/// originate from an approved non-personal build root
/// (docs/NEUTRAL_BUILD_POLICY.md). The build-214 audit proved why: server
/// symbolication reproduces build-time absolute paths embedded in DWARF, and
/// one frame exposed the build engineer's macOS username. This scanner
/// inspects the exact artifacts about to be uploaded (or used for
/// symbolication) and fails when any prohibited personal path survives in
/// them.
///
/// Design constraints, all deliberate:
///
///  * **Deterministic and repository-owned** — pure `dart:io`, no
///    dependencies, identical behaviour on macOS and Linux.
///  * **Binary-safe** — bytes are scanned as Latin-1 (byte-preserving), so
///    content is never assumed to be UTF-8 and no byte sequence can break
///    the scan.
///  * **Chunk-boundary-safe** — files stream in 64 KiB chunks with a
///    carried overlap window larger than any matchable pattern, so a
///    prohibited string split across a read boundary is still found.
///  * **Fail closed** — no inputs, missing inputs, unreadable files, empty
///    files or an input set yielding zero regular files all abort with a
///    non-zero exit; a scan that could not complete never reports clean.
///  * **Read-only** — artifacts are opened for reading only and never
///    modified.
///  * **Redacting** — findings name the artifact and rule category with a
///    redacted match; the full personal path or username never appears in
///    output.
///
/// Exit-code contract (see [ScanOutcome.exitCode]):
///   0 — every input scanned successfully, no prohibited path found;
///   1 — scan completed, at least one prohibited path detected;
///   2 — the scan could not be completed or validated (missing/unreadable/
///       empty inputs, no inputs, usage error). 2 dominates 1: an
///       incomplete scan can never certify anything.
library;

import 'dart:io';

/// One reportable observation.
class Finding {
  Finding({
    required this.artifact,
    required this.category,
    required this.redactedMatch,
    required this.fatal,
  });

  /// The artifact's path as given (input-relative, never rewritten).
  final String artifact;

  /// Closed-vocabulary rule category.
  final String category;

  /// A match with every personal segment replaced by `[REDACTED:<len>]`.
  final String redactedMatch;

  /// Whether this finding fails the scan (informational findings do not).
  final bool fatal;

  @override
  String toString() =>
      '${fatal ? 'FAIL' : 'info'} $category $artifact: $redactedMatch';
}

/// Configurable rule set. Approved roots and users are explicit so they are
/// reviewable and testable; nothing is approved implicitly.
class ScanRules {
  ScanRules({
    Set<String>? approvedMacUsers,
    Set<String>? approvedLinuxUsers,
    Set<String>? approvedWindowsUsers,
    List<String>? approvedRootPrefixes,
    Set<String>? personalNames,
  }) : approvedMacUsers = approvedMacUsers ?? defaultApprovedMacUsers,
       approvedLinuxUsers = approvedLinuxUsers ?? defaultApprovedLinuxUsers,
       approvedWindowsUsers =
           approvedWindowsUsers ?? defaultApprovedWindowsUsers,
       approvedRootPrefixes =
           approvedRootPrefixes ?? defaultApprovedRootPrefixes,
       personalNames = {
         for (final name in personalNames ?? const <String>{})
           name.trim().toLowerCase(),
       }..removeWhere((name) => name.isEmpty);

  /// `/Users/<name>/` segments that are non-personal by policy.
  /// `Shared` is the documented neutral build root; `runner` is the GitHub
  /// macOS CI account.
  static const Set<String> defaultApprovedMacUsers = {'Shared', 'runner'};

  /// `/home/<name>/` segments that are non-personal by policy (CI/service
  /// accounts only).
  static const Set<String> defaultApprovedLinuxUsers = {'runner'};

  /// `C:\Users\<name>\` segments that are non-personal by policy.
  static const Set<String> defaultApprovedWindowsUsers = {
    'runner',
    'runneradmin',
    'Public',
    'ContainerAdministrator',
  };

  /// Whole-path prefixes approved as neutral build roots. A path matching
  /// one of these passes even if the per-user rules would otherwise object.
  static const List<String> defaultApprovedRootPrefixes = [
    '/Users/Shared/',
    '/home/runner/',
  ];

  final Set<String> approvedMacUsers;
  final Set<String> approvedLinuxUsers;
  final Set<String> approvedWindowsUsers;
  final List<String> approvedRootPrefixes;

  /// Explicitly configured personal identifiers (for the current developer's
  /// username on a local build). Matched case-insensitively anywhere in the
  /// artifact; never echoed in output.
  final Set<String> personalNames;
}

/// Generic, non-personal toolchain prefixes: reported for the release
/// evidence, never a failure by themselves.
const List<String> kToolchainPrefixes = [
  '/opt/homebrew/',
  '/usr/local/',
  '/usr/lib/',
  '/opt/flutter/',
];

final RegExp _macHome = RegExp(r'/Users/([A-Za-z0-9._\-]{1,64})/');
final RegExp _linuxHome = RegExp(r'/home/([A-Za-z0-9._\-]{1,64})/');
final RegExp _windowsProfile = RegExp(
  r'[A-Za-z]:[\\/][Uu][Ss][Ee][Rr][Ss][\\/]([A-Za-z0-9._\- ]{1,64})[\\/]',
);

/// Local verification-worktree names from the 212–214 investigation. Their
/// presence in an artifact means it was built inside a personal worktree.
final RegExp _worktreeName = RegExp(
  r'wp-(?:dist-[A-Za-z0-9]+|[A-Za-z0-9]+-verification|sentry\b|crash-[A-Za-z0-9\-]+|pr[a-z]\b)',
);

/// The longest string any rule can match; the streaming overlap must exceed
/// it so no match can hide across a chunk boundary.
const int kMaxPatternLength = 160;

/// Streaming chunk size.
const int kChunkSize = 64 * 1024;

class ScanOutcome {
  ScanOutcome(this.findings, this.inputErrors, this.scannedFiles);

  final List<Finding> findings;
  final List<String> inputErrors;
  final int scannedFiles;

  bool get hasFatalFindings => findings.any((f) => f.fatal);

  /// 2 (incomplete scan) dominates 1 (prohibited path) dominates 0.
  int get exitCode => inputErrors.isNotEmpty
      ? 2
      : hasFatalFindings
      ? 1
      : 0;
}

String _redactSegment(String segment) => '[REDACTED:${segment.length}]';

/// Scans [inputs] (files and/or directories) against [rules].
Future<ScanOutcome> scanInputs(List<String> inputs, ScanRules rules) async {
  final findings = <Finding>[];
  final inputErrors = <String>[];
  var scannedFiles = 0;

  if (inputs.isEmpty) {
    return ScanOutcome(findings, ['no inputs given'], 0);
  }

  final files = <File>[];
  for (final input in inputs) {
    final type = FileSystemEntity.typeSync(input, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        files.add(File(input));
      case FileSystemEntityType.directory:
        var regularFilesInDir = 0;
        await for (final entity in Directory(
          input,
        ).list(recursive: true, followLinks: false)) {
          if (entity is File) {
            files.add(entity);
            regularFilesInDir++;
          }
        }
        if (regularFilesInDir == 0) {
          inputErrors.add('input directory contains no regular files: $input');
        }
      case FileSystemEntityType.notFound:
        inputErrors.add('input missing: $input');
      default:
        inputErrors.add('input is not a regular file or directory: $input');
    }
  }
  if (files.isEmpty && inputErrors.isEmpty) {
    inputErrors.add('input set resolved to zero regular files');
  }

  for (final file in files) {
    try {
      final length = await file.length();
      if (length == 0) {
        inputErrors.add('input file is empty: ${file.path}');
        continue;
      }
      await _scanFile(file, rules, findings);
      scannedFiles++;
    } on FileSystemException catch (e) {
      inputErrors.add('input unreadable: ${file.path} (${e.osError?.message})');
    }
  }

  return ScanOutcome(findings, inputErrors, scannedFiles);
}

Future<void> _scanFile(
  File file,
  ScanRules rules,
  List<Finding> findings,
) async {
  final seen = <String>{};

  void add(String category, String redactedMatch, {required bool fatal}) {
    final key = '$category|$redactedMatch';
    if (seen.add(key)) {
      findings.add(
        Finding(
          artifact: file.path,
          category: category,
          redactedMatch: redactedMatch,
          fatal: fatal,
        ),
      );
    }
  }

  final raf = await file.open();
  try {
    var carry = '';
    while (true) {
      final bytes = await raf.read(kChunkSize);
      if (bytes.isEmpty) break;
      // Latin-1: byte-preserving, so binary content cannot break the scan
      // and every byte participates in matching.
      final window = carry + String.fromCharCodes(bytes);
      _scanWindow(window, rules, add);
      carry = window.length > kMaxPatternLength
          ? window.substring(window.length - kMaxPatternLength)
          : window;
    }
  } finally {
    await raf.close();
  }
}

/// True when the home-directory match at [matchStart] is the beginning of an
/// explicitly approved neutral root. Every rule pattern and every approved
/// prefix starts at the same anchor (`/Users/` or `/home/`), so a plain
/// prefix comparison at the match position is exact — no lookbehind needed,
/// and the streaming overlap guarantees the full prefix is inside the
/// window whenever the match is.
bool _underApprovedRoot(String window, int matchStart, ScanRules rules) {
  for (final prefix in rules.approvedRootPrefixes) {
    if (window.startsWith(prefix, matchStart)) return true;
  }
  return false;
}

void _scanWindow(
  String window,
  ScanRules rules,
  void Function(String category, String redactedMatch, {required bool fatal})
  add,
) {
  final lower = window.toLowerCase();

  for (final match in _macHome.allMatches(window)) {
    final user = match.group(1)!;
    if (rules.approvedMacUsers.contains(user)) continue;
    if (_underApprovedRoot(window, match.start, rules)) continue;
    add('personal_home_macos', '/Users/${_redactSegment(user)}/', fatal: true);
  }

  for (final match in _linuxHome.allMatches(window)) {
    final user = match.group(1)!;
    if (rules.approvedLinuxUsers.contains(user)) continue;
    if (_underApprovedRoot(window, match.start, rules)) continue;
    add('personal_home_linux', '/home/${_redactSegment(user)}/', fatal: true);
  }

  for (final match in _windowsProfile.allMatches(window)) {
    final user = match.group(1)!;
    if (rules.approvedWindowsUsers.contains(user)) continue;
    add(
      'personal_profile_windows',
      'C:\\Users\\${_redactSegment(user)}\\',
      fatal: true,
    );
  }

  for (final match in _worktreeName.allMatches(window)) {
    // Worktree tokens are project-internal, not personal; safe to show.
    add('verification_worktree_name', match.group(0)!, fatal: true);
  }

  for (final name in rules.personalNames) {
    if (lower.contains(name)) {
      add(
        'configured_personal_name',
        '[REDACTED-NAME:${name.length}]',
        fatal: true,
      );
    }
  }

  for (final prefix in kToolchainPrefixes) {
    if (window.contains(prefix)) {
      add('toolchain_path', prefix, fatal: false);
    }
  }
}
