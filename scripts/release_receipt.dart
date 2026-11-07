/// Release receipts: one JSON record per built app artifact, binding
/// version → build number → commit → artifact sha256 → /config clinical
/// artifact hashes → test result → clinical status.
///
/// Schema: `docs/release/receipts/release_receipt.schema.json`.
/// CLI: `scripts/make_release_receipt.dart` (usage in
/// `docs/release/receipts/README.md`).
///
/// No network access: the /config response is read from a saved file.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const receiptSchemaId = 'wellapath.release_receipt.v1';
const receiptGenerator = 'scripts/make_release_receipt.dart v1';
const applicationId = 'org.wellapath.app';
const defaultClinicalStatus = 'NOT CLINICALLY CLEARED — SAFETY-01/02/03 open';
const defaultKnownBlockers = <String>[
  'SAFETY-01 (HAZ-001, CCL-001): when several demographic modifiers apply, '
      'the last one wins and earlier escalation is lost. Clinical decision '
      'required',
  'SAFETY-02 (HAZ-002, CCL-002): severity, duration and season inputs are '
      'unused, and 0-12 years maps to under-5. Clinical decision required',
  'SAFETY-03 (HAZ-003, CCL-003): emergency facility ordering uses a '
      'type-derived emergency_capable flag. Clinical decision required',
  'WP-027: no named clinical reviewer exists for any live clinical content',
];

class ReceiptException implements Exception {
  ReceiptException(this.message, {this.usage = false});

  final String message;

  /// True for bad invocation (exit 2) rather than bad input (exit 1).
  final bool usage;

  @override
  String toString() => message;
}

class GitInfo {
  const GitInfo(this.commit, this.treeClean);

  final String commit;
  final bool? treeClean;
}

/// Extracts `{id, version, url, sha256}` for every artifact in a saved
/// `/config` response. A missing or malformed hash is an error (SR-005).
List<Map<String, Object?>> configArtifacts(String configJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(configJson);
  } on FormatException catch (error) {
    throw ReceiptException('config file is not JSON: ${error.message}');
  }
  final artifacts = decoded is Map ? decoded['artifacts'] : null;
  if (artifacts is! Map || artifacts.isEmpty) {
    throw ReceiptException('config file has no "artifacts" object');
  }
  final ids = artifacts.keys.map((k) => '$k').toList()..sort();
  return [for (final id in ids) _configArtifact(id, artifacts[id])];
}

Map<String, Object?> _configArtifact(String id, Object? entry) {
  if (entry is! Map) {
    throw ReceiptException('config artifact "$id" is not an object');
  }
  final version = entry['version'];
  final url = entry['url'];
  final hash = entry['hash'];
  if (version is! String || version.isEmpty) {
    throw ReceiptException('config artifact "$id" has no version');
  }
  if (url is! String || url.isEmpty) {
    throw ReceiptException('config artifact "$id" has no url');
  }
  final digest = hash is String ? hash.replaceFirst('sha256:', '') : '';
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    throw ReceiptException('config artifact "$id" has no valid sha256 hash');
  }
  return {'id': id, 'version': version, 'url': url, 'sha256': digest};
}

/// Parses `version: X.Y.Z+N` from pubspec.yaml.
(String, int) pubspecVersion(String pubspecYaml) {
  final match = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspecYaml);
  if (match == null) {
    throw ReceiptException('pubspec.yaml has no "version: X.Y.Z+N" line');
  }
  return (match[1]!, int.parse(match[2]!));
}

Map<String, Object?> buildReleaseReceipt({
  required String version,
  required int buildNumber,
  required String artifactFileName,
  required String artifactSha256,
  required int artifactSize,
  required GitInfo git,
  required String configJson,
  required int testsPassed,
  required int testsSkipped,
  required int testsFailed,
  required DateTime createdAt,
  String? testsCommand,
  String clinicalStatus = defaultClinicalStatus,
  List<String> knownBlockers = defaultKnownBlockers,
  String? approver,
}) {
  final lower = artifactFileName.toLowerCase();
  final kind = lower.endsWith('.aab')
      ? 'aab'
      : lower.endsWith('.ipa')
      ? 'ipa'
      : throw ReceiptException(
          'artifact must be an .aab or .ipa file: $artifactFileName',
          usage: true,
        );
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    throw ReceiptException('version must be X.Y.Z: $version', usage: true);
  }
  if (buildNumber < 1) {
    throw ReceiptException('build number must be positive', usage: true);
  }
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(git.commit)) {
    throw ReceiptException(
      'git commit must be a full 40-hex sha: ${git.commit}',
    );
  }
  if (artifactSize < 1) {
    throw ReceiptException('artifact is empty');
  }
  for (final count in [testsPassed, testsSkipped, testsFailed]) {
    if (count < 0) {
      throw ReceiptException('test counts must be >= 0', usage: true);
    }
  }
  if (clinicalStatus.trim().isEmpty) {
    throw ReceiptException('clinical status must not be empty', usage: true);
  }
  return <String, Object?>{
    'schema': receiptSchemaId,
    'app': {
      'application_id': applicationId,
      'version': version,
      'build_number': buildNumber,
      'platform': kind == 'aab' ? 'android' : 'ios',
    },
    'source': {'git_commit': git.commit, 'git_tree_clean': git.treeClean},
    'artifact': {
      'file_name': artifactFileName,
      'kind': kind,
      'sha256': artifactSha256,
      'size_bytes': artifactSize,
    },
    'clinical_config': {
      'config_file_sha256': sha256.convert(utf8.encode(configJson)).toString(),
      'artifacts': configArtifacts(configJson),
    },
    'tests': {
      'passed': testsPassed,
      'skipped': testsSkipped,
      'failed': testsFailed,
      'all_passed': testsFailed == 0,
      'command': ?testsCommand,
    },
    'clinical_status': clinicalStatus,
    'known_blockers': knownBlockers,
    'approver': approver,
    'created_at': createdAt.toUtc().toIso8601String(),
    'generator': receiptGenerator,
  };
}

/// Streams [file] through sha256 so a large AAB/IPA is never held in memory.
Future<(String, int)> hashFile(File file) async {
  var size = 0;
  final digest = await sha256
      .bind(
        file.openRead().map((chunk) {
          size += chunk.length;
          return chunk;
        }),
      )
      .first;
  return (digest.toString(), size);
}

GitInfo readGitInfo() {
  final head = Process.runSync('git', ['rev-parse', 'HEAD']);
  if (head.exitCode != 0) {
    throw ReceiptException('git rev-parse HEAD failed; pass --git-commit');
  }
  final status = Process.runSync('git', ['status', '--porcelain']);
  return GitInfo(
    '${head.stdout}'.trim(),
    status.exitCode == 0 ? '${status.stdout}'.trim().isEmpty : null,
  );
}

const usageText =
    '''
Usage: dart run scripts/make_release_receipt.dart
  --artifact=PATH          the signed .aab or .ipa (required)
  --build-number=N         must equal the +N in pubspec.yaml (required)
  --config=PATH            saved GET /config response JSON (required)
  --tests-passed=N --tests-skipped=N --tests-failed=N   (required)
  [--tests-command=TEXT]   e.g. "flutter test --exclude-tags plutil"
  [--pubspec=pubspec.yaml] [--version=X.Y.Z (overrides pubspec)]
  [--git-commit=SHA [--git-tree-clean=true|false]]  (default: read git)
  [--clinical-status=TEXT] default: "$defaultClinicalStatus"
  [--blocker=TEXT]...      added to the default known blockers
  [--no-default-blockers]  only with an explicit --clinical-status
  [--approver=NAME]        default: null (not recorded)
  [--date=ISO8601]         default: now (UTC)
  [--out=PATH]             default: docs/release/receipts/receipt_<version>+<build>_<platform>.json
Receipts are append-only; an existing --out file is never overwritten.''';

/// Runs the CLI. Returns the exit code: 0 written, 1 bad input, 2 usage.
Future<int> makeReleaseReceipt(
  List<String> args, {
  required StringSink out,
  required StringSink err,
  GitInfo Function() git = readGitInfo,
  DateTime Function() clock = _now,
}) async {
  final options = <String, String>{};
  final blockers = <String>[];
  var noDefaultBlockers = false;
  for (final arg in args) {
    if (arg == '--no-default-blockers') {
      noDefaultBlockers = true;
      continue;
    }
    if (arg == '--help' || arg == '-h') {
      out.writeln(usageText);
      return 0;
    }
    final eq = arg.indexOf('=');
    if (!arg.startsWith('--') || eq < 0) {
      err.writeln('unknown argument: $arg\n$usageText');
      return 2;
    }
    final key = arg.substring(2, eq);
    final value = arg.substring(eq + 1);
    if (key == 'blocker') {
      blockers.add(value);
    } else if (_knownOptions.contains(key)) {
      options[key] = value;
    } else {
      err.writeln('unknown option: --$key\n$usageText');
      return 2;
    }
  }

  try {
    for (final key in const [
      'artifact',
      'build-number',
      'config',
      'tests-passed',
      'tests-skipped',
      'tests-failed',
    ]) {
      if ((options[key] ?? '').isEmpty) {
        throw ReceiptException('missing --$key', usage: true);
      }
    }
    if (noDefaultBlockers && !options.containsKey('clinical-status')) {
      throw ReceiptException(
        '--no-default-blockers requires an explicit --clinical-status',
        usage: true,
      );
    }
    final buildNumber = _int(options, 'build-number');
    String version;
    if (options.containsKey('version')) {
      version = options['version']!;
    } else {
      final pubspecPath = options['pubspec'] ?? 'pubspec.yaml';
      final (pubVersion, pubBuild) = pubspecVersion(_read(pubspecPath));
      if (pubBuild != buildNumber) {
        throw ReceiptException(
          '--build-number=$buildNumber does not match $pubspecPath '
          '(+$pubBuild). Build from the commit whose pubspec carries this '
          'build number, or pass --version explicitly.',
        );
      }
      version = pubVersion;
    }

    final GitInfo gitInfo;
    if (options.containsKey('git-commit')) {
      final clean = options['git-tree-clean'];
      if (clean != null && clean != 'true' && clean != 'false') {
        throw ReceiptException(
          '--git-tree-clean must be true or false',
          usage: true,
        );
      }
      gitInfo = GitInfo(
        options['git-commit']!,
        clean == null ? null : clean == 'true',
      );
    } else {
      gitInfo = git();
    }

    final artifactFile = File(options['artifact']!);
    if (!artifactFile.existsSync()) {
      throw ReceiptException('artifact not found: ${artifactFile.path}');
    }
    final (digest, size) = await hashFile(artifactFile);

    DateTime createdAt = clock();
    if (options.containsKey('date')) {
      createdAt =
          DateTime.tryParse(options['date']!) ??
          (throw ReceiptException('invalid --date', usage: true));
    }

    final receipt = buildReleaseReceipt(
      version: version,
      buildNumber: buildNumber,
      artifactFileName: artifactFile.uri.pathSegments.last,
      artifactSha256: digest,
      artifactSize: size,
      git: gitInfo,
      configJson: _read(options['config']!),
      testsPassed: _int(options, 'tests-passed'),
      testsSkipped: _int(options, 'tests-skipped'),
      testsFailed: _int(options, 'tests-failed'),
      testsCommand: options['tests-command'],
      clinicalStatus: options['clinical-status'] ?? defaultClinicalStatus,
      knownBlockers: [
        if (!noDefaultBlockers) ...defaultKnownBlockers,
        ...blockers,
      ],
      approver: options['approver'],
      createdAt: createdAt,
    );

    final app = receipt['app'] as Map;
    final outPath =
        options['out'] ??
        'docs/release/receipts/receipt_${app['version']}+'
            '${app['build_number']}_${app['platform']}.json';
    final outFile = File(outPath);
    if (outFile.existsSync()) {
      throw ReceiptException(
        'refusing to overwrite $outPath: receipts are append-only',
      );
    }
    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(receipt)}\n',
    );
    out.writeln('release receipt written: $outPath');
    out.writeln('  artifact sha256 $digest ($size bytes)');
    if ((receipt['tests'] as Map)['all_passed'] != true) {
      err.writeln('WARNING: the receipt records failing tests.');
    }
    return 0;
  } on ReceiptException catch (error) {
    err.writeln('error: $error');
    return error.usage ? 2 : 1;
  }
}

const _knownOptions = {
  'artifact',
  'build-number',
  'config',
  'tests-passed',
  'tests-skipped',
  'tests-failed',
  'tests-command',
  'pubspec',
  'version',
  'git-commit',
  'git-tree-clean',
  'clinical-status',
  'approver',
  'date',
  'out',
};

DateTime _now() => DateTime.now().toUtc();

int _int(Map<String, String> options, String key) {
  final value = int.tryParse(options[key] ?? '');
  if (value == null) {
    throw ReceiptException('--$key must be an integer', usage: true);
  }
  return value;
}

String _read(String path) {
  try {
    return File(path).readAsStringSync();
  } on FileSystemException catch (error) {
    throw ReceiptException('cannot read $path: ${error.message}');
  }
}
