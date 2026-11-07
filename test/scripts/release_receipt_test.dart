import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/release_receipt.dart';

const _commit = '0123456789abcdef0123456789abcdef01234567';

const _config = '''
{"version":"1.0","country":"ng","artifacts":{
 "token_dictionary":{"version":"1.1","url":"https://r2.example/token_dictionary.ng.v1.1.json","hash":"sha256:0cc47ad9537c0bd4c6ef3aec8f1931eb9b4c62103a8809d16544f94a90b5c019"},
 "knowledge_base":{"version":"2.4","url":"https://r2.example/kb.ng.v2.4.json","hash":"sha256:6c00d8257f8417e86bd5e237630bf8a4623ad72e2e46b1b071dd447c067cec2b"},
 "rules":{"version":"2.2","url":"https://r2.example/rules.ng.v2.2.json","hash":"sha256:1d27e854cba95b179577a88f92445400f494a7fe8e6a53a60fcaa98b3870d1c4"},
 "facilities":{"version":"1.2","url":"https://r2.example/facilities.ng.v1.2.json","hash":"sha256:94f162e492fa91f7d9d3cf2ca33fcf0598a031a2510aa900aa717a581bdb7788"}}}
''';

/// Minimal JSON Schema (2020-12 subset) check: type, const, enum, required,
/// properties, additionalProperties: false, items, minItems, minLength,
/// minimum, pattern. Enough to prove receipts and the committed schema agree.
List<String> _validate(Object? value, Map<String, Object?> schema, String at) {
  final errors = <String>[];
  if (schema.containsKey('const') && value != schema['const']) {
    errors.add('$at: expected const ${schema['const']}');
  }
  if (schema['enum'] is List && !(schema['enum'] as List).contains(value)) {
    errors.add('$at: $value not in enum');
  }
  final type = schema['type'];
  if (type != null) {
    final types = type is List ? type.cast<String>() : [type as String];
    bool matches(String t) => switch (t) {
      'object' => value is Map,
      'array' => value is List,
      'string' => value is String,
      'integer' => value is int,
      'boolean' => value is bool,
      'null' => value == null,
      _ => false,
    };
    if (!types.any(matches)) errors.add('$at: expected $types, got $value');
  }
  if (value is String) {
    if (schema['minLength'] is int &&
        value.length < (schema['minLength'] as int)) {
      errors.add('$at: too short');
    }
    if (schema['pattern'] is String &&
        !RegExp(schema['pattern'] as String).hasMatch(value)) {
      errors.add('$at: "$value" does not match ${schema['pattern']}');
    }
  }
  if (value is int &&
      schema['minimum'] is int &&
      value < (schema['minimum'] as int)) {
    errors.add('$at: below minimum');
  }
  if (value is Map) {
    final props = (schema['properties'] as Map?)?.cast<String, Object?>() ?? {};
    for (final key in (schema['required'] as List?) ?? const []) {
      if (!value.containsKey(key)) errors.add('$at: missing $key');
    }
    for (final entry in value.entries) {
      final sub = props[entry.key];
      if (sub == null) {
        if (schema['additionalProperties'] == false) {
          errors.add('$at: unexpected ${entry.key}');
        }
        continue;
      }
      errors.addAll(
        _validate(entry.value, (sub as Map).cast(), '$at.${entry.key}'),
      );
    }
  }
  if (value is List) {
    if (schema['minItems'] is int &&
        value.length < (schema['minItems'] as int)) {
      errors.add('$at: too few items');
    }
    if (schema['items'] is Map) {
      for (var i = 0; i < value.length; i++) {
        errors.addAll(
          _validate(value[i], (schema['items'] as Map).cast(), '$at[$i]'),
        );
      }
    }
  }
  return errors;
}

void main() {
  late Directory temp;
  late File aab;
  late File configFile;
  late File pubspec;
  late Map<String, Object?> schema;

  setUpAll(() {
    schema =
        (jsonDecode(
                  File(
                    'docs/release/receipts/release_receipt.schema.json',
                  ).readAsStringSync(),
                )
                as Map)
            .cast();
  });

  setUp(() {
    temp = Directory.systemTemp.createTempSync('receipt_test_');
    aab = File('${temp.path}/WellaPath-999.aab')
      ..writeAsBytesSync(utf8.encode('fake aab bytes'));
    configFile = File('${temp.path}/config.json')..writeAsStringSync(_config);
    pubspec = File('${temp.path}/pubspec.yaml')
      ..writeAsStringSync('name: x\nversion: 0.3.0+999\n');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  List<String> args({String artifact = '', List<String> extra = const []}) => [
    '--artifact=${artifact.isEmpty ? aab.path : artifact}',
    '--build-number=999',
    '--config=${configFile.path}',
    '--pubspec=${pubspec.path}',
    '--tests-passed=1700',
    '--tests-skipped=3',
    '--tests-failed=0',
    '--git-commit=$_commit',
    '--git-tree-clean=true',
    '--date=2026-11-07T12:00:00Z',
    '--out=${temp.path}/receipt.json',
    ...extra,
  ];

  Future<(int, String, String)> run(List<String> a) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await makeReleaseReceipt(
      a,
      out: out,
      err: err,
      git: () =>
          throw StateError('git must not be called when --git-commit is given'),
    );
    return (code, '$out', '$err');
  }

  Map<String, Object?> readReceipt() =>
      (jsonDecode(File('${temp.path}/receipt.json').readAsStringSync()) as Map)
          .cast();

  group('make_release_receipt', () {
    test('writes a receipt that conforms to the committed schema', () async {
      final (code, out, err) = await run(args());
      expect(code, 0, reason: err);
      expect(out, contains('release receipt written'));
      final receipt = readReceipt();
      expect(_validate(receipt, schema, r'$'), isEmpty);
    });

    test(
      'records version, build, commit, date and artifact hash and size',
      () async {
        await run(args());
        final receipt = readReceipt();
        expect(receipt['app'], {
          'application_id': 'org.wellapath.app',
          'version': '0.3.0',
          'build_number': 999,
          'platform': 'android',
        });
        expect(receipt['source'], {
          'git_commit': _commit,
          'git_tree_clean': true,
        });
        expect(receipt['created_at'], '2026-11-07T12:00:00.000Z');
        final bytes = aab.readAsBytesSync();
        expect(receipt['artifact'], {
          'file_name': 'WellaPath-999.aab',
          'kind': 'aab',
          'sha256': sha256.convert(bytes).toString(),
          'size_bytes': bytes.length,
        });
      },
    );

    test(
      'records every /config artifact version and hash from the saved file',
      () async {
        await run(args());
        final config = readReceipt()['clinical_config'] as Map;
        expect(
          config['config_file_sha256'],
          sha256.convert(utf8.encode(_config)).toString(),
        );
        final artifacts = (config['artifacts'] as List).cast<Map>();
        expect(artifacts.map((a) => '${a['id']} ${a['version']}'), [
          'facilities 1.2',
          'knowledge_base 2.4',
          'rules 2.2',
          'token_dictionary 1.1',
        ]);
        expect(
          artifacts.firstWhere((a) => a['id'] == 'knowledge_base')['sha256'],
          '6c00d8257f8417e86bd5e237630bf8a4623ad72e2e46b1b071dd447c067cec2b',
        );
      },
    );

    test(
      'defaults to NOT CLINICALLY CLEARED with the SAFETY blockers',
      () async {
        await run(args());
        final receipt = readReceipt();
        expect(
          receipt['clinical_status'],
          'NOT CLINICALLY CLEARED — SAFETY-01/02/03 open',
        );
        final blockers = (receipt['known_blockers'] as List).join('\n');
        expect(blockers, contains('SAFETY-01'));
        expect(blockers, contains('SAFETY-02'));
        expect(blockers, contains('SAFETY-03'));
        expect(blockers, contains('WP-027'));
        expect(receipt['approver'], isNull);
      },
    );

    test('records the test summary, including failures', () async {
      final (code, _, err) = await run([
        ...args().where((a) => !a.startsWith('--tests-failed')),
        '--tests-failed=2',
        '--tests-command=flutter test --exclude-tags plutil',
      ]);
      expect(code, 0);
      expect(err, contains('failing tests'));
      expect(readReceipt()['tests'], {
        'passed': 1700,
        'skipped': 3,
        'failed': 2,
        'all_passed': false,
        'command': 'flutter test --exclude-tags plutil',
      });
    });

    test('an extra blocker is added to the defaults', () async {
      await run(args(extra: ['--blocker=RC-BLK-016: CB_211 open']));
      final blockers = readReceipt()['known_blockers'] as List;
      expect(blockers.last, 'RC-BLK-016: CB_211 open');
      expect(blockers.length, defaultKnownBlockers.length + 1);
    });

    test('an IPA is recorded as ios', () async {
      final ipa = File('${temp.path}/WellaPath-999.ipa')
        ..writeAsStringSync('ipa');
      await run(args(artifact: ipa.path));
      expect((readReceipt()['app'] as Map)['platform'], 'ios');
    });

    test('refuses to overwrite an existing receipt', () async {
      expect((await run(args())).$1, 0);
      final (code, _, err) = await run(args());
      expect(code, 1);
      expect(err, contains('append-only'));
    });

    test('refuses a build number that does not match pubspec.yaml', () async {
      final (code, _, err) = await run([
        ...args().where((a) => !a.startsWith('--build-number')),
        '--build-number=998',
      ]);
      expect(code, 1);
      expect(err, contains('does not match'));
    });

    test('refuses a /config entry without a valid hash', () async {
      configFile.writeAsStringSync(
        _config.replaceFirst('sha256:6c00d825', 'sha256:zz'),
      );
      final (code, _, err) = await run(args());
      expect(code, 1);
      expect(err, contains('knowledge_base'));
    });

    test(
      'refuses a non-AAB/IPA artifact, a short commit, and missing options',
      () async {
        final apk = File('${temp.path}/app.apk')..writeAsStringSync('apk');
        expect((await run(args(artifact: apk.path))).$1, 2);
        expect(
          (await run([
            ...args().where((a) => !a.startsWith('--git-commit')),
            '--git-commit=abc123',
          ])).$1,
          1,
        );
        expect((await run(['--artifact=${aab.path}'])).$1, 2);
        expect((await run([...args(), '--bogus=1'])).$1, 2);
      },
    );

    test(
      '--no-default-blockers requires an explicit clinical status',
      () async {
        expect((await run([...args(), '--no-default-blockers'])).$1, 2);
      },
    );

    test('reads git when no --git-commit is given', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await makeReleaseReceipt(
        args().where((a) => !a.startsWith('--git-')).toList(),
        out: out,
        err: err,
        git: () => const GitInfo(_commit, false),
      );
      expect(code, 0, reason: '$err');
      expect(readReceipt()['source'], {
        'git_commit': _commit,
        'git_tree_clean': false,
      });
    });
  });

  test('no build-217 receipt is committed (build 217 is built separately)', () {
    final receipts = Directory('docs/release/receipts')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .where((name) => name.startsWith('receipt_'));
    expect(receipts.where((name) => name.contains('+217')), isEmpty);
  });
}
