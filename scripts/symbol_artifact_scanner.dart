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
       // Copy-normalised: every root ends with '/' (component-boundary
       // safety) and the caller's list — const or shared — is never mutated.
       approvedRootPrefixes = List.unmodifiable([
         for (final prefix
             in approvedRootPrefixes ?? defaultApprovedRootPrefixes)
           prefix.endsWith('/') ? prefix : '$prefix/',
       ]),
       personalNames = {
         for (final name in personalNames ?? const <String>{})
           name.trim().toLowerCase(),
       }..removeWhere((name) => name.isEmpty) {
    // Windows usernames are case-insensitive; compare lowercased.
    _approvedWindowsUsersLower = {
      for (final user in this.approvedWindowsUsers) user.toLowerCase(),
    };
    // The streaming overlap must exceed the longest thing any rule may need
    // to see in one window: the longest built-in match, the longest approved
    // root (right-context for the exemption) and the longest configured
    // personal name. Derived, not assumed.
    var need = kBuiltinMaxPatternLength;
    for (final prefix in this.approvedRootPrefixes) {
      if (prefix.length > need) need = prefix.length;
    }
    for (final name in this.personalNames) {
      if (name.length > need) need = name.length;
    }
    maxMatchNeed = need + 16; // margin
  }

  late final Set<String> _approvedWindowsUsersLower;

  /// The derived streaming overlap requirement for this rule set.
  late final int maxMatchNeed;

  bool isApprovedWindowsUser(String user) =>
      _approvedWindowsUsersLower.contains(user.toLowerCase());

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
  /// POSIX-style prefixes only; Windows exemptions go through
  /// [approvedWindowsUsers]. Normalised to a trailing '/' at construction.
  static const List<String> defaultApprovedRootPrefixes = [
    '/Users/Shared/',
    '/home/runner/',
  ];

  final Set<String> approvedMacUsers;
  final Set<String> approvedLinuxUsers;
  final Set<String> approvedWindowsUsers;

  /// Normalised (trailing '/'), unmodifiable copy.
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

// A true drive prefix (a SINGLE letter + ':', e.g. 'c:') diverts the path
// to the Windows rule. A scheme like 'file:' does NOT — its letter is
// preceded by more letters — so 'file:/Users/...' stays a macOS-rule match
// (nested lookbehind), keeping approved users/roots effective for it.
final RegExp _macHome = RegExp(
  r'(?<!(?<![A-Za-z])[A-Za-z]:)/Users/+([A-Za-z0-9._\-]{1,64})/',
);
final RegExp _linuxHome = RegExp(r'/home/+([A-Za-z0-9._\-]{1,64})/');
final RegExp _windowsProfile = RegExp(
  // The leading lookbehind requires a real single-letter drive: 'file:' and
  // other URI schemes never match here (they belong to the POSIX rules).
  r'(?<![A-Za-z])[A-Za-z]:[\\/]+[Uu][Ss][Ee][Rr][Ss][\\/]+([A-Za-z0-9._\- ]{1,64})[\\/]',
);

/// Local verification-worktree names from the 212–214 investigation. Their
/// presence in an artifact means it was built inside a personal worktree.
final RegExp _worktreeName = RegExp(
  r'wp-(?:dist-[A-Za-z0-9]+|[A-Za-z0-9]+-verification|sentry\b|crash-[A-Za-z0-9\-]+|pr[a-z0-9\-]*\b)',
);

/// The longest string any BUILT-IN rule can match (the longest home-dir
/// pattern is under 80 characters; worktree tokens are shorter). The real
/// per-scan overlap is [ScanRules.maxMatchNeed], which also accounts for
/// user-supplied approved roots and personal names — derived, never assumed.
const int kBuiltinMaxPatternLength = 160;

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

/// Redacts any text destined for output: personal names, then every
/// non-approved home-directory segment on all three platforms. Used for
/// artifact labels and input-error messages, so a personal path can never
/// leak through the scanner's own reporting — not even the path of the
/// artifact being scanned or of a missing input.
String redactForDisplay(String text, ScanRules rules) {
  var out = text;
  for (final name in rules.personalNames) {
    final pattern = RegExp(RegExp.escape(name), caseSensitive: false);
    out = out.replaceAll(pattern, '[REDACTED-NAME:${name.length}]');
  }
  out = out.replaceAllMapped(_macHome, (m) {
    final user = m.group(1)!;
    if (rules.approvedMacUsers.contains(user)) return m.group(0)!;
    return '/Users/${_redactSegment(user)}/';
  });
  out = out.replaceAllMapped(_linuxHome, (m) {
    final user = m.group(1)!;
    if (rules.approvedLinuxUsers.contains(user)) return m.group(0)!;
    return '/home/${_redactSegment(user)}/';
  });
  out = out.replaceAllMapped(_windowsProfile, (m) {
    final user = m.group(1)!;
    if (rules.isApprovedWindowsUser(user)) return m.group(0)!;
    return 'C:\\Users\\${_redactSegment(user)}\\';
  });
  return out;
}

/// Scans [inputs] (files and/or directories) against [rules].
Future<ScanOutcome> scanInputs(List<String> inputs, ScanRules rules) async {
  final findings = <Finding>[];
  final inputErrors = <String>[];
  var scannedFiles = 0;

  if (inputs.isEmpty) {
    return ScanOutcome(findings, ['no inputs given'], 0);
  }

  void addError(String message) =>
      inputErrors.add(redactForDisplay(message, rules));

  // Nothing reachable from a supplied input is silently skipped: symlinks,
  // broken links and special files (FIFOs, sockets, devices — which could
  // also hang a read) fail the scan closed. Directory traversal never
  // follows links, so link cycles cannot recurse.
  final files = <File>[];
  for (final input in inputs) {
    final type = FileSystemEntity.typeSync(input, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        files.add(File(input));
      case FileSystemEntityType.directory:
        var regularFilesInDir = 0;
        try {
          await for (final entity in Directory(
            input,
          ).list(recursive: true, followLinks: false)) {
            if (entity is File) {
              files.add(entity);
              regularFilesInDir++;
            } else if (entity is Link) {
              addError(
                'input contains a symlink (not scanned): ${entity.path}',
              );
            } else if (entity is! Directory) {
              addError('input contains a special file: ${entity.path}');
            }
          }
        } on FileSystemException catch (e) {
          // An unreadable subdirectory must fail CLOSED with a redacted
          // message, never crash with a raw-path stack trace.
          addError('input traversal failed: ${e.path} (${e.osError?.message})');
        }
        if (regularFilesInDir == 0) {
          addError('input directory contains no regular files: $input');
        }
      case FileSystemEntityType.link:
        addError('input is a symlink: $input');
      case FileSystemEntityType.notFound:
        addError('input missing: $input');
      default:
        addError('input is not a regular file or directory: $input');
    }
  }
  if (files.isEmpty && inputErrors.isEmpty) {
    addError('input set resolved to zero regular files');
  }

  for (final file in files) {
    try {
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file) {
        addError('input is not a regular file: ${file.path}');
        continue;
      }
      if (stat.size == 0) {
        addError('input file is empty: ${file.path}');
        continue;
      }
      await _scanFile(file, rules, findings);
      scannedFiles++;
    } on FileSystemException catch (e) {
      addError('input unreadable: ${file.path} (${e.osError?.message})');
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
  // The artifact label itself is redacted: an artifact scanned from inside a
  // personal directory must not leak that directory through its own name.
  final artifactLabel = redactForDisplay(file.path, rules);

  // The dedup key carries the RAW matched text (never displayed), so two
  // distinct personal homes of equal length remain two findings in the
  // release evidence instead of collapsing into one redacted line.
  void add(
    String category,
    String redactedMatch,
    String rawKey, {
    required bool fatal,
  }) {
    if (seen.add('$category|$rawKey')) {
      findings.add(
        Finding(
          artifact: artifactLabel,
          category: category,
          redactedMatch: redactedMatch,
          fatal: fatal,
        ),
      );
    }
  }

  // The byte overlap is 2x the rule set's need so that UTF-16LE (two bytes
  // per character) wide-string patterns straddling a chunk edge are also
  // fully visible in one window.
  final overlap = 2 * rules.maxMatchNeed;
  final raf = await file.open();
  try {
    var carry = '';
    while (true) {
      final bytes = await raf.read(kChunkSize);
      final isFinal = bytes.isEmpty;
      final window = isFinal
          ? carry
          // Latin-1: byte-preserving one-byte-per-code-unit decoding, so
          // binary content cannot break the scan, byte positions are exact
          // and ASCII path patterns are always visible.
          : carry + String.fromCharCodes(bytes);
      if (window.isEmpty) break;
      // Deferral: a match starting inside the trailing overlap region may
      // lack right context (a longer approved root, the rest of a name), so
      // it is NOT judged in this window — the tail is carried over and the
      // match is re-seen with full context in the next window. Only the
      // final window judges to its end.
      final freshLimit = isFinal ? window.length : window.length - overlap;
      _scanWindow(window, freshLimit, rules, add);
      // Wide-string pass: Windows PE/PDB artifacts embed paths as UTF-16LE,
      // which Latin-1 narrow scanning cannot see (every character is
      // interleaved with 0x00). Both byte alignments are projected down to
      // narrow text (a non-ASCII wide char becomes \u0001, which matches
      // nothing) and scanned with the same rules. Positions halve, so the
      // fresh limit halves with them — conservative in the safe direction.
      for (var phase = 0; phase < 2; phase++) {
        final projected = _projectUtf16le(window, phase);
        if (projected.isEmpty) continue;
        final wideLimit = isFinal
            ? projected.length
            : (freshLimit - phase) ~/ 2;
        _scanWindow(projected, wideLimit, rules, add);
      }
      if (isFinal) break;
      carry = window.length > overlap
          ? window.substring(window.length - overlap)
          : window;
    }
  } finally {
    await raf.close();
  }
}

/// Projects a Latin-1 window down to the narrow text a UTF-16LE encoding of
/// it would represent, starting at byte [phase] (0 or 1): each byte pair
/// (low, 0x00) becomes the low byte; any other pair becomes \u0001, which
/// no rule can match.
String _projectUtf16le(String window, int phase) {
  final length = (window.length - phase) ~/ 2;
  if (length <= 0) return '';
  final codes = List<int>.filled(length, 0);
  for (var i = 0; i < length; i++) {
    final low = window.codeUnitAt(phase + 2 * i);
    final high = window.codeUnitAt(phase + 2 * i + 1);
    codes[i] = (high == 0 && low != 0) ? low : 1;
  }
  return String.fromCharCodes(codes);
}

bool _underApprovedRoot(String window, int matchStart, ScanRules rules) {
  for (final prefix in rules.approvedRootPrefixes) {
    if (window.startsWith(prefix, matchStart)) return true;
  }
  return false;
}

void _scanWindow(
  String window,
  int freshLimit,
  ScanRules rules,
  void Function(
    String category,
    String redactedMatch,
    String rawKey, {
    required bool fatal,
  })
  add,
) {
  for (final match in _macHome.allMatches(window)) {
    if (match.start >= freshLimit) continue; // re-judged next window
    final user = match.group(1)!;
    if (rules.approvedMacUsers.contains(user)) continue;
    if (_underApprovedRoot(window, match.start, rules)) continue;
    add(
      'personal_home_macos',
      '/Users/${_redactSegment(user)}/',
      'mac|$user',
      fatal: true,
    );
  }

  for (final match in _linuxHome.allMatches(window)) {
    if (match.start >= freshLimit) continue;
    final user = match.group(1)!;
    if (rules.approvedLinuxUsers.contains(user)) continue;
    if (_underApprovedRoot(window, match.start, rules)) continue;
    add(
      'personal_home_linux',
      '/home/${_redactSegment(user)}/',
      'linux|$user',
      fatal: true,
    );
  }

  for (final match in _windowsProfile.allMatches(window)) {
    if (match.start >= freshLimit) continue;
    final user = match.group(1)!;
    // Windows usernames are case-insensitive.
    if (rules.isApprovedWindowsUser(user)) continue;
    add(
      'personal_profile_windows',
      'C:\\Users\\${_redactSegment(user)}\\',
      'win|${user.toLowerCase()}',
      fatal: true,
    );
  }

  for (final match in _worktreeName.allMatches(window)) {
    if (match.start >= freshLimit) continue;
    // Worktree tokens are project-internal, not personal; safe to show.
    // Note: home-directory allowlists and approved roots deliberately do
    // NOT exempt this rule — a worktree name is prohibited anywhere.
    final token = match.group(0)!;
    add('verification_worktree_name', token, 'wt|$token', fatal: true);
  }

  // Configured personal names ALWAYS fail — deliberately checked without
  // any allowlist or approved-root exemption, so a personal name that
  // happens to equal a service account (e.g. 'runner') still fails. The
  // lowercase copy is only made when names are configured, and one hit per
  // name per window suffices (the dedup key is the name itself).
  if (rules.personalNames.isNotEmpty) {
    final lower = window.toLowerCase();
    for (final name in rules.personalNames) {
      final at = lower.indexOf(name);
      if (at >= 0 && at < freshLimit) {
        add(
          'configured_personal_name',
          '[REDACTED-NAME:${name.length}]',
          'name|$name',
          fatal: true,
        );
      }
    }
  }

  for (final prefix in kToolchainPrefixes) {
    final at = window.indexOf(prefix);
    if (at >= 0 && at < freshLimit) {
      add('toolchain_path', prefix, 'tc|$prefix', fatal: false);
    }
  }
}
