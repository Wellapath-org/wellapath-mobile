@Tags(['plutil'])
/// Export-options verification against Apple's REAL `/usr/bin/plutil`.
///
/// Tagged `plutil` and run in a mandatory macOS CI job. These cases are
/// deliberately **not** skipped on Linux and **not** reproduced with a fake: the
/// whole point of the plutil design is that Apple's parser decides, so a test
/// that mocked the verdict would be testing the mock.
///
/// Each case states what `plutil` itself resolves, then what the guard must
/// conclude. Where the two could differ is exactly where the previous two
/// string-scanning versions failed, so every case asserts them together.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/export_options_policy.dart';

const String _teamId = '2SCUC2CBBS';

late Directory _dir;

String _write(String name, String contents) {
  final path = '${_dir.path}/$name';
  File(path).writeAsStringSync(contents);
  return path;
}

String _compliant() => buildExportOptionsPlist(
  mode: DistributionMode.appStore,
  destination: ExportDestination.upload,
  teamId: _teamId,
);

/// What Apple resolves for a ROOT-level key, via `plutil -extract … xml1`.
///
/// Returns `null` when there is no value at that root key path — which is also
/// what a key reachable only inside a nested dictionary or array produces, since
/// a keypath is rooted.
///
/// `xml1` rather than `json` on purpose, for two reasons: it preserves the
/// **type** (so a boolean `true` is distinguishable from the string `"true"` and
/// the integer `1`), and `plutil -extract … json` refuses a bare scalar outright
/// with "Invalid object in plist for JSON format". Normalised to short tokens
/// so the assertions below read as values rather than as markup.
String? _appleRootValue(String path, String key) {
  final result = Process.runSync(kPlutilPath, [
    '-extract',
    key,
    'xml1',
    '-o',
    '-',
    path,
  ]);
  if (result.exitCode != 0) return null;

  final out = result.stdout as String;
  final open = out.indexOf('<plist version="1.0">');
  final close = out.lastIndexOf('</plist>');
  if (open < 0 || close < 0) return null;
  final node = out
      .substring(open + '<plist version="1.0">'.length, close)
      .trim();

  final string = RegExp(
    r'^<string>(.*)</string>$',
    dotAll: true,
  ).firstMatch(node);
  if (string != null) return '"${string.group(1)}"';
  final number = RegExp(
    r'^<(?:integer|real)>(.*)</(?:integer|real)>$',
  ).firstMatch(node);
  if (number != null) return number.group(1);
  if (node == '<true/>') return 'true';
  if (node == '<false/>') return 'false';
  return node;
}

void main() {
  setUpAll(() {
    // If this fails the macOS job is misconfigured; failing loudly is correct.
    expect(
      const SystemPlutilRunner().isAvailable,
      isTrue,
      reason:
          '$kPlutilPath must exist for this suite. These tests must run on '
          'macOS, not be skipped to keep another platform green.',
    );
    _dir = Directory.systemTemp.createTempSync('plutil_policy_');
  });

  tearDownAll(() => _dir.deleteSync(recursive: true));

  test('a compliant generated plist PASSES', () {
    final path = _write('good.plist', _compliant());
    expect(_appleRootValue(path, 'uploadSymbols'), 'true');
    expect(verifyExportOptionsFile(path: path).exitCode, 0);
  });

  test('root uploadSymbols false FAILS (exit 1)', () {
    final path = _write(
      'false.plist',
      _compliant().replaceFirst(
        '<key>uploadSymbols</key>\n\t<true/>',
        '<key>uploadSymbols</key>\n\t<false/>',
      ),
    );
    expect(_appleRootValue(path, 'uploadSymbols'), 'false');
    final verdict = verifyExportOptionsFile(path: path);
    expect(verdict.exitCode, 1);
    expect(verdict.messages.join('\n'), contains('DISABLED'));
  });

  test('root uploadSymbols omitted FAILS (exit 1)', () {
    final path = _write(
      'omitted.plist',
      _compliant().replaceFirst('\t<key>uploadSymbols</key>\n\t<true/>\n', ''),
    );
    expect(_appleRootValue(path, 'uploadSymbols'), isNull);
    expect(verifyExportOptionsFile(path: path).exitCode, 1);
  });

  test('nested inside provisioningProfiles FAILS — the found evasion', () {
    // The shape that defeated the string scanner: a valid plist whose only
    // uploadSymbols sits in the legitimate provisioningProfiles sub-dictionary.
    final path = _write(
      'nested_dict.plist',
      _compliant()
          .replaceFirst('\t<key>uploadSymbols</key>\n\t<true/>\n', '')
          .replaceFirst(
            '</dict>\n</plist>',
            '\t<key>provisioningProfiles</key>\n'
                '\t<dict>\n'
                '\t\t<key>org.wellapath.app</key>\n'
                '\t\t<string>WellaPath Distribution</string>\n'
                '\t\t<key>uploadSymbols</key>\n'
                '\t\t<true/>\n'
                '\t</dict>\n'
                '</dict>\n</plist>',
          ),
    );

    // It is a VALID plist — that is what made the evasion plausible.
    expect(Process.runSync(kPlutilPath, ['-lint', path]).exitCode, 0);
    // But Apple sees no ROOT-level uploadSymbols.
    expect(_appleRootValue(path, 'uploadSymbols'), isNull);

    final verdict = verifyExportOptionsFile(path: path);
    expect(verdict.exitCode, 1);
    expect(verdict.messages.join('\n'), contains('OMITTED at the root'));
  });

  test('nested inside an array FAILS', () {
    final path = _write(
      'nested_array.plist',
      _compliant()
          .replaceFirst('\t<key>uploadSymbols</key>\n\t<true/>\n', '')
          .replaceFirst(
            '</dict>\n</plist>',
            '\t<key>notes</key>\n'
                '\t<array>\n'
                '\t\t<string>uploadSymbols</string>\n'
                '\t\t<true/>\n'
                '\t</array>\n'
                '</dict>\n</plist>',
          ),
    );
    expect(Process.runSync(kPlutilPath, ['-lint', path]).exitCode, 0);
    expect(_appleRootValue(path, 'uploadSymbols'), isNull);
    expect(verifyExportOptionsFile(path: path).exitCode, 1);
  });

  test('nested true with root omitted FAILS', () {
    final path = _write(
      'nested_true_root_absent.plist',
      _compliant()
          .replaceFirst('\t<key>uploadSymbols</key>\n\t<true/>\n', '')
          .replaceFirst(
            '</dict>\n</plist>',
            '\t<key>provisioningProfiles</key>\n\t<dict>\n'
                '\t\t<key>uploadSymbols</key>\n\t\t<true/>\n'
                '\t</dict>\n</dict>\n</plist>',
          ),
    );
    expect(verifyExportOptionsFile(path: path).exitCode, 1);
  });

  test('root false plus nested true FAILS', () {
    final path = _write(
      'root_false_nested_true.plist',
      _compliant()
          .replaceFirst(
            '<key>uploadSymbols</key>\n\t<true/>',
            '<key>uploadSymbols</key>\n\t<false/>',
          )
          .replaceFirst(
            '</dict>\n</plist>',
            '\t<key>provisioningProfiles</key>\n\t<dict>\n'
                '\t\t<key>uploadSymbols</key>\n\t\t<true/>\n'
                '\t</dict>\n</dict>\n</plist>',
          ),
    );
    expect(_appleRootValue(path, 'uploadSymbols'), 'false');
    expect(verifyExportOptionsFile(path: path).exitCode, 1);
  });

  test('nested false plus root true PASSES — only the root matters', () {
    final path = _write(
      'root_true_nested_false.plist',
      _compliant().replaceFirst(
        '</dict>\n</plist>',
        '\t<key>provisioningProfiles</key>\n\t<dict>\n'
            '\t\t<key>uploadSymbols</key>\n\t\t<false/>\n'
            '\t</dict>\n</dict>\n</plist>',
      ),
    );
    expect(_appleRootValue(path, 'uploadSymbols'), 'true');
    expect(verifyExportOptionsFile(path: path).exitCode, 0);
  });

  test('a root string "true" FAILS — wrong type', () {
    final path = _write(
      'string_true.plist',
      _compliant().replaceFirst(
        '<key>uploadSymbols</key>\n\t<true/>',
        '<key>uploadSymbols</key>\n\t<string>true</string>',
      ),
    );
    expect(_appleRootValue(path, 'uploadSymbols'), '"true"');
    final verdict = verifyExportOptionsFile(path: path);
    expect(verdict.exitCode, 1);
    expect(verdict.messages.join('\n'), contains('must be a boolean'));
  });

  test('a root integer 1 FAILS — wrong type', () {
    final path = _write(
      'int_one.plist',
      _compliant().replaceFirst(
        '<key>uploadSymbols</key>\n\t<true/>',
        '<key>uploadSymbols</key>\n\t<integer>1</integer>',
      ),
    );
    expect(_appleRootValue(path, 'uploadSymbols'), '1');
    final verdict = verifyExportOptionsFile(path: path);
    expect(verdict.exitCode, 1);
    expect(verdict.messages.join('\n'), contains('must be a boolean'));
  });

  test('a duplicated key FAILS, and Apple resolves the LAST one', () {
    final path = _write(
      'dup.plist',
      _compliant().replaceFirst(
        '</dict>',
        '\t<key>uploadSymbols</key>\n\t<false/>\n</dict>',
      ),
    );
    // Apple takes the last occurrence; this is why first-occurrence scanning
    // was unsound.
    expect(_appleRootValue(path, 'uploadSymbols'), 'false');
    final verdict = verifyExportOptionsFile(path: path);
    expect(verdict.exitCode, 1);
    expect(verdict.messages.join('\n'), contains('DISABLED'));
  });

  test('a malformed, unparseable plist is UNUSABLE (exit 2)', () {
    // A key after the closing dict: plutil cannot parse it at all, so it must
    // never be certified — not passed, and not reported as a mere violation.
    final path = _write(
      'malformed.plist',
      _compliant().replaceFirst(
        '</dict>\n</plist>',
        '</dict>\n\t<key>uploadSymbols</key>\n\t<true/>\n</plist>',
      ),
    );
    expect(Process.runSync(kPlutilPath, ['-lint', path]).exitCode, isNot(0));
    final verdict = verifyExportOptionsFile(path: path);
    expect(verdict.exitCode, 2);
    expect(verdict.outcome, VerificationOutcome.unusable);
  });

  test('an empty file is UNUSABLE (exit 2)', () {
    final path = _write('empty.plist', '\n');
    expect(verifyExportOptionsFile(path: path).exitCode, 2);
  });

  test('BOTH real build-216 plists FAIL, naming uploadSymbols', () {
    // The files that actually shipped the regression. Read-only.
    const paths = [
      '/Users/Shared/wellapath-build-216/ExportOptions216.plist',
      '/Users/Shared/wellapath-build-216/ExportOptionsUpload216.plist',
    ];
    for (final path in paths) {
      if (!File(path).existsSync()) {
        // The historical artifacts are not in the repo; on a machine without
        // them this case cannot run, and saying so is better than pretending.
        markTestSkipped(
          'build-216 evidence not present on this machine: $path',
        );
        continue;
      }
      expect(_appleRootValue(path, 'uploadSymbols'), 'false');
      final verdict = verifyExportOptionsFile(path: path);
      expect(verdict.exitCode, 1, reason: '$path must fail');
      expect(verdict.messages.join('\n'), contains('uploadSymbols'));
    }
  });
}
