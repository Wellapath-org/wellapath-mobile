/// The neutral-build-path symbol-artifact scanner
/// (scripts/symbol_artifact_scanner.dart).
///
/// Every identity below is FICTIONAL fixture data (`jdoe`, `msmith`); no
/// real username or path from the build-214 event appears anywhere in this
/// repository. Fixtures are generated at runtime in a temp directory so the
/// repo itself never contains a prohibited byte sequence.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/symbol_artifact_scanner.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scanner_test_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  File write(String name, List<int> bytes) =>
      File('${tmp.path}/$name')..writeAsBytesSync(bytes);

  File writeText(String name, String text) => write(name, utf8.encode(text));

  Future<ScanOutcome> scan(List<String> inputs, {ScanRules? rules}) =>
      scanInputs(inputs, rules ?? ScanRules());

  group('prohibited personal paths fail', () {
    test('a synthetic macOS personal path fails', () async {
      final f = writeText('a.symbols', 'x /Users/jdoe/dev/app/main.dart y');
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 1);
      expect(outcome.findings.single.category, 'personal_home_macos');
    });

    test('a synthetic Linux personal path fails', () async {
      final f = writeText('b.so', 'x /home/msmith/build/libapp.so y');
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 1);
      expect(outcome.findings.single.category, 'personal_home_linux');
    });

    test('a synthetic Windows personal path fails', () async {
      final f = writeText('c.pdb', r'x C:\Users\jdoe\src\app\main.dart y');
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 1);
      expect(outcome.findings.single.category, 'personal_profile_windows');
    });

    test('verification-worktree names fail regardless of root', () async {
      for (final token in [
        'wp-dist-212',
        'wp-213-verification',
        'wp-sentry',
        'wp-crash-remediation',
      ]) {
        final f = writeText('wt.symbols', '/Users/Shared/x/$token/lib.so');
        final outcome = await scan([f.path]);
        expect(outcome.exitCode, 1, reason: '$token must fail');
        expect(
          outcome.findings.any(
            (x) => x.category == 'verification_worktree_name',
          ),
          isTrue,
        );
      }
    });

    test(
      'a configured personal name fails anywhere, case-insensitively',
      () async {
        final f = writeText('d.symbols', 'path=/tmp/JDoe-cache/x');
        final outcome = await scan([
          f.path,
        ], rules: ScanRules(personalNames: {'jdoe'}));
        expect(outcome.exitCode, 1);
        expect(outcome.findings.single.category, 'configured_personal_name');
      },
    );
  });

  group('approved roots and accounts pass', () {
    test('an approved /Users/Shared/ root passes', () async {
      final f = writeText(
        'e.symbols',
        '/Users/Shared/wellapath-build-215/build/symbols/app.symbols',
      );
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 0, reason: '${outcome.findings}');
    });

    test('approved CI/service-account roots pass', () async {
      final f = writeText(
        'f.symbols',
        '/home/runner/work/app/app/build/symbols '
            r'C:\Users\runneradmin\work\x '
            '/Users/runner/work/y',
      );
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 0, reason: '${outcome.findings}');
    });

    test('an explicitly approved extra root passes', () async {
      final f = writeText('g.symbols', '/Users/buildsvc/wellapath/out.so');
      final failing = await scan([f.path]);
      expect(failing.exitCode, 1);
      final approved = await scan(
        [f.path],
        rules: ScanRules(
          approvedRootPrefixes: [
            ...ScanRules.defaultApprovedRootPrefixes,
            '/Users/buildsvc/wellapath/',
          ],
        ),
      );
      expect(approved.exitCode, 0, reason: '${approved.findings}');
    });

    test(
      '/opt/homebrew/ passes and is reported as toolchain metadata',
      () async {
        final f = writeText(
          'h.symbols',
          '/opt/homebrew/share/flutter/bin/cache/pkg/sky_engine/lib/x.dart',
        );
        final outcome = await scan([f.path]);
        expect(outcome.exitCode, 0);
        expect(outcome.findings.single.category, 'toolchain_path');
        expect(outcome.findings.single.fatal, isFalse);
        expect(outcome.findings.single.redactedMatch, '/opt/homebrew/');
      },
    );
  });

  group('streaming and binary safety', () {
    test('a prohibited string crossing the chunk boundary fails', () async {
      // Place '/Users/jdoe/' so it straddles the 64 KiB read boundary.
      final prefix = List<int>.filled(kChunkSize - 6, 0x41); // 'A' * (N-6)
      final needle = utf8.encode('/Users/jdoe/secret');
      final f = write('i.bin', [...prefix, ...needle, 0x42, 0x42]);
      expect(await f.length(), greaterThan(kChunkSize));
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 1);
      expect(outcome.findings.single.category, 'personal_home_macos');
    });

    test('binary data containing a prohibited path fails', () async {
      final bytes = BytesBuilder()
        ..add([0x7f, 0x45, 0x4c, 0x46, 0x00, 0xff, 0xfe]) // ELF-ish header
        ..add(utf8.encode('/home/jdoe/wt/libapp.so'))
        ..add(List<int>.generate(256, (i) => i % 256));
      final f = write('j.so', bytes.toBytes());
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 1);
      expect(outcome.findings.single.category, 'personal_home_linux');
    });

    test('multiple inputs where only a later input fails', () async {
      final clean = writeText('k1.symbols', '/Users/Shared/ok');
      final dirty = writeText('k2.symbols', '/Users/jdoe/bad');
      final outcome = await scan([clean.path, dirty.path]);
      expect(outcome.exitCode, 1);
      expect(outcome.scannedFiles, 2);
      // The label is redaction-processed, so compare by basename: the raw
      // temp path may itself sit under a home directory on some CI hosts.
      expect(outcome.findings.single.artifact, endsWith('k2.symbols'));
    });
  });

  group('fail closed', () {
    test('no inputs fails closed', () async {
      final outcome = await scan([]);
      expect(outcome.exitCode, 2);
    });

    test('a missing input fails closed', () async {
      final outcome = await scan(['${tmp.path}/does-not-exist.symbols']);
      expect(outcome.exitCode, 2);
    });

    test('an empty input file fails closed', () async {
      final f = write('empty.symbols', const []);
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 2);
    });

    test('a directory with no regular files fails closed', () async {
      final d = Directory('${tmp.path}/emptydir')..createSync();
      final outcome = await scan([d.path]);
      expect(outcome.exitCode, 2);
    });

    test('an unreadable input fails closed', () async {
      if (Process.runSync('id', ['-u']).stdout.toString().trim() == '0') {
        markTestSkipped('running as root: chmod 000 does not block reads');
        return;
      }
      final f = writeText('locked.symbols', '/Users/Shared/x');
      final result = Process.runSync('chmod', ['000', f.path]);
      expect(result.exitCode, 0);
      addTearDown(() => Process.runSync('chmod', ['644', f.path]));
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 2);
    }, skip: Platform.isWindows);

    test('an incomplete scan dominates a prohibited finding', () async {
      final dirty = writeText('l1.symbols', '/Users/jdoe/bad');
      final outcome = await scan([dirty.path, '${tmp.path}/missing.symbols']);
      expect(outcome.hasFatalFindings, isTrue);
      expect(outcome.exitCode, 2, reason: 'fail closed dominates');
    });
  });

  group('redaction and non-mutation', () {
    test('the personal path and username never appear in findings', () async {
      final f = writeText(
        'm.symbols',
        '/Users/jdoe/dev/secretproject/main.dart and JDoe elsewhere',
      );
      final outcome = await scan([
        f.path,
      ], rules: ScanRules(personalNames: {'jdoe'}));
      expect(outcome.exitCode, 1);
      final rendered = outcome.findings.map((x) => x.toString()).join('\n');
      expect(rendered.toLowerCase(), isNot(contains('jdoe')));
      expect(rendered, isNot(contains('secretproject')));
      expect(rendered, contains('[REDACTED:4]'));
      expect(rendered, contains('[REDACTED-NAME:4]'));
    });

    test(
      'artifacts are never modified — hashes match before and after',
      () async {
        final bytes = List<int>.generate(200000, (i) => (i * 31) % 256);
        final f = write('n.bin', [...bytes, ...utf8.encode('/Users/jdoe/x/')]);
        final before = sha256.convert(await f.readAsBytes()).toString();
        final beforeStat = f.statSync();
        final outcome = await scan([f.path]);
        expect(outcome.exitCode, 1);
        final after = sha256.convert(await f.readAsBytes()).toString();
        expect(after, before);
        expect(f.statSync().size, beforeStat.size);
      },
    );
  });

  group('review regressions — rule and allowlist safety', () {
    test(
      'a personal name equal to an approved service account still fails',
      () async {
        final f = writeText('r1.symbols', '/home/runner/work/app/x');
        final clean = await scan([f.path]);
        expect(clean.exitCode, 0);
        final outcome = await scan([
          f.path,
        ], rules: ScanRules(personalNames: {'runner'}));
        expect(outcome.exitCode, 1, reason: 'explicit prohibition wins');
        expect(
          outcome.findings.any((x) => x.category == 'configured_personal_name'),
          isTrue,
        );
      },
    );

    test('approved-root matching is component-boundary aware', () async {
      final evil = writeText('r2.symbols', '/Users/bsvc/build-evil/lib.so');
      final good = writeText('r3.symbols', '/Users/bsvc/build/lib.so');
      // Root supplied WITHOUT trailing slash — normalised at construction.
      final rules = ScanRules(
        approvedRootPrefixes: [
          ...ScanRules.defaultApprovedRootPrefixes,
          '/Users/bsvc/build',
        ],
      );
      expect((await scan([good.path], rules: rules)).exitCode, 0);
      expect(
        (await scan([evil.path], rules: rules)).exitCode,
        1,
        reason: '/Users/bsvc/build must not approve /Users/bsvc/build-evil',
      );
    });

    test('windows username case, mixed slashes and drive case', () async {
      final ok = writeText('r4.pdb', r'c:/Users/RUNNERADMIN/work/x');
      expect((await scan([ok.path])).exitCode, 0);
      final bad = writeText('r5.pdb', r'c:/USERS/jdoe/src/x');
      final outcome = await scan([bad.path]);
      expect(outcome.exitCode, 1);
      expect(outcome.findings.single.category, 'personal_profile_windows');
    });

    test(
      'repeated separators and dot segments still match (fail-safe)',
      () async {
        for (final sample in ['/Users//jdoe/x', '/Users/./x', '/home/../x']) {
          final f = writeText('r6.symbols', sample);
          expect(
            (await scan([f.path])).exitCode,
            1,
            reason: '$sample must fail',
          );
        }
      },
    );

    test('a neutral root later in a personal path exempts nothing', () async {
      final f = writeText('r7.symbols', '/Users/jdoe/x/Users/Shared/y');
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 1);
      expect(outcome.findings.single.category, 'personal_home_macos');
    });

    test(
      '--approve-user style allowlisting never suppresses worktree rules',
      () async {
        final f = writeText('r8.symbols', '/home/svcacct/wp-dist-1/lib.so');
        final outcome = await scan(
          [f.path],
          rules: ScanRules(
            approvedLinuxUsers: {
              ...ScanRules.defaultApprovedLinuxUsers,
              'svcacct',
            },
          ),
        );
        expect(outcome.exitCode, 1);
        expect(outcome.findings.single.category, 'verification_worktree_name');
      },
    );
  });

  group('review regressions — streaming', () {
    test(
      'boundary sweep finds the pattern at every chunk-edge offset',
      () async {
        const needleText = '/Users/jdoe/s';
        for (var delta = -needleText.length - 1; delta <= 2; delta++) {
          final pad = kChunkSize + delta;
          if (pad < 0) continue;
          final f = write('sweep$delta.bin', [
            ...List<int>.filled(pad, 0x41),
            ...utf8.encode(needleText),
            0x42,
          ]);
          final outcome = await scan([f.path]);
          expect(
            outcome.exitCode,
            1,
            reason: 'pattern at boundary offset $delta must be detected',
          );
        }
      },
    );

    test('a long personal name straddling the boundary is detected', () async {
      final longName = 'z${'q' * 300}z';
      final f = write('longname.bin', [
        ...List<int>.filled(kChunkSize - 150, 0x41),
        ...utf8.encode(longName),
        0x42,
      ]);
      final outcome = await scan([
        f.path,
      ], rules: ScanRules(personalNames: {longName}));
      expect(outcome.exitCode, 1);
      expect(
        outcome.findings.single.redactedMatch,
        '[REDACTED-NAME:${longName.length}]',
      );
    });

    test('a long approved root straddling the boundary passes', () async {
      final root = '/Users/bsvc/${'d' * 200}/';
      final f = write('longroot.bin', [
        ...List<int>.filled(kChunkSize - 8, 0x41),
        ...utf8.encode('${root}symbols/app.symbols'),
        0x42,
      ]);
      final outcome = await scan(
        [f.path],
        rules: ScanRules(
          approvedRootPrefixes: [
            ...ScanRules.defaultApprovedRootPrefixes,
            root,
          ],
        ),
      );
      expect(outcome.exitCode, 0, reason: '${outcome.findings}');
    });
  });

  group('review regressions — output privacy and traversal', () {
    test('the artifact label itself is redacted', () async {
      final dir = Directory('${tmp.path}/Users/jdoe/build')
        ..createSync(recursive: true);
      final f = File('${dir.path}/app.symbols')
        ..writeAsStringSync('/home/msmith/x');
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 1);
      expect(outcome.findings.single.artifact, isNot(contains('jdoe')));
      expect(outcome.findings.single.artifact, contains('[REDACTED:4]'));
    });

    test('missing-input error messages are redacted', () async {
      final outcome = await scan(['${tmp.path}/Users/jdoe/missing.symbols']);
      expect(outcome.exitCode, 2);
      expect(outcome.inputErrors.single, isNot(contains('jdoe')));
      expect(outcome.inputErrors.single, contains('[REDACTED:4]'));
    });

    test('a symlink inside an input directory fails closed', () async {
      final target = writeText('t.symbols', '/Users/Shared/x');
      Link('${tmp.path}/link.symbols').createSync(target.path);
      final outcome = await scan([tmp.path]);
      expect(outcome.exitCode, 2);
      expect(outcome.inputErrors.any((e) => e.contains('symlink')), isTrue);
    }, skip: Platform.isWindows);

    test(
      'a special file (fifo) fails closed instead of hanging',
      () async {
        final fifoPath = '${tmp.path}/pipe.symbols';
        final made = Process.runSync('mkfifo', [fifoPath]);
        expect(made.exitCode, 0);
        writeText('regular.symbols', '/Users/Shared/x');
        final outcome = await scan([tmp.path]);
        expect(outcome.exitCode, 2);
      },
      skip: Platform.isWindows,
    );

    test(
      'scan-incomplete dominates without losing prohibited evidence',
      () async {
        final dirty = writeText('ev.symbols', '/Users/jdoe/bad');
        final outcome = await scan([dirty.path, '${tmp.path}/nope.symbols']);
        expect(outcome.exitCode, 2, reason: 'incomplete dominates');
        expect(outcome.hasFatalFindings, isTrue, reason: 'evidence retained');
        expect(
          outcome.findings.single.category,
          'personal_home_macos',
          reason: 'the prohibited finding is still reported',
        );
      },
    );
  });

  group('review regressions — second pass', () {
    List<int> utf16le(String text) {
      final out = <int>[];
      for (final code in text.codeUnits) {
        out.add(code & 0xff);
        out.add((code >> 8) & 0xff);
      }
      return out;
    }

    test('a UTF-16LE windows personal path fails', () async {
      final f = write('w1.pdb', [
        0x4d, 0x5a, 0x00, 0x01, // PE-ish prefix, odd alignment too
        ...utf16le(r'C:\Users\jdoe\src\app.pdb'),
        0x00,
      ]);
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 1);
      expect(outcome.findings.single.category, 'personal_profile_windows');
    });

    test('a UTF-16LE macos personal path fails', () async {
      final f = write('w2.bin', utf16le('/Users/jdoe/x/'));
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 1);
      expect(outcome.findings.single.category, 'personal_home_macos');
    });

    test('a UTF-16LE pattern straddling the chunk boundary fails', () async {
      final f = write('w3.bin', [
        ...List<int>.filled(kChunkSize - 10, 0x41),
        ...utf16le(r'C:\Users\jdoe\s'),
        0x42,
      ]);
      final outcome = await scan([f.path]);
      expect(outcome.exitCode, 1);
    });

    test('a file: uri under an approved root passes; personal fails', () async {
      final ok = writeText(
        'u1.txt',
        'source=file:/Users/Shared/wellapath-build-215/a.dart',
      );
      expect((await scan([ok.path])).exitCode, 0);
      final bad = writeText('u2.txt', 'source=file:/Users/jdoe/a.dart');
      final outcome = await scan([bad.path]);
      expect(outcome.exitCode, 1);
      expect(outcome.findings.single.category, 'personal_home_macos');
    });

    test('wp-pr worktree variants are covered as documented', () async {
      for (final token in ['wp-pr85', 'wp-prfix', 'wp-pr-b', 'wp-pra']) {
        final f = writeText('p.symbols', '/tmp/$token/lib.so');
        expect((await scan([f.path])).exitCode, 1, reason: '$token must fail');
      }
    });

    test('a const approved-root list neither crashes nor mutates', () async {
      const roots = ['/Users/bsvc/build'];
      final rules = ScanRules(approvedRootPrefixes: roots);
      expect(rules.approvedRootPrefixes, ['/Users/bsvc/build/']);
      expect(roots, ['/Users/bsvc/build'], reason: 'caller list untouched');
      final f = writeText('c1.symbols', '/Users/bsvc/build/x');
      expect((await scan([f.path], rules: rules)).exitCode, 0);
    });

    test(
      'an unreadable subdirectory fails closed with redacted error',
      () async {
        if (Process.runSync('id', ['-u']).stdout.toString().trim() == '0') {
          markTestSkipped('running as root: chmod 000 does not block listing');
          return;
        }
        final sub = Directory('${tmp.path}/Users/jdoe/deep')
          ..createSync(recursive: true);
        File('${sub.path}/x.symbols').writeAsStringSync('/Users/Shared/x');
        Process.runSync('chmod', ['000', sub.path]);
        addTearDown(() => Process.runSync('chmod', ['755', sub.path]));
        final outcome = await scan([tmp.path]);
        expect(outcome.exitCode, 2, reason: 'must not crash, must fail closed');
        expect(outcome.inputErrors.join(), isNot(contains('jdoe')));
      },
      skip: Platform.isWindows,
    );

    test(
      'distinct same-length usernames stay distinct in the evidence',
      () async {
        final f = writeText('d2.symbols', '/Users/jdoe/a /Users/mary/b');
        final outcome = await scan([f.path]);
        expect(outcome.exitCode, 1);
        expect(
          outcome.findings.where((x) => x.fatal).length,
          2,
          reason: 'two independent leaks are two findings',
        );
      },
    );
  });

  group('coverage is not limited to .symbols', () {
    test('dSYM DWARF, native .so and mapping files are all scanned', () async {
      final dsym = Directory(
        '${tmp.path}/Runner.app.dSYM/Contents/Resources/DWARF',
      )..createSync(recursive: true);
      File(
        '${dsym.path}/Runner',
      ).writeAsBytesSync(utf8.encode('\x00/Users/jdoe/ios/Runner\x00'));
      writeText('mapping.txt', 'a.b.c -> d: /home/jdoe/mapping');
      write('libapp.so', utf8.encode('ELF /Users/jdoe/lib'));

      final outcome = await scan([tmp.path]);
      expect(outcome.exitCode, 1);
      final artifacts = outcome.findings
          .where((x) => x.fatal)
          .map((x) => x.artifact)
          .toSet();
      expect(artifacts.length, 3, reason: 'all three artifact kinds flagged');
    });
  });
}
