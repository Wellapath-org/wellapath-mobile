import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/traceability.dart';

const _requirements = '''
requirements:
  - id: SR-001
    title: "first"
    status: Met
  - id: CR-001
    title: "clinical"
    status: TO BE DEFINED
''';

const _files = {'test/a/one_test.dart': "test('does the thing', () {});"};

TraceReport _report(String map, {String requirements = _requirements}) =>
    buildTraceReport(
      requirementsYaml: requirements,
      mapYaml: map,
      fileExists: _files.containsKey,
      readFile: (path) => _files[path]!,
    );

const _goodMap = '''
mappings:
  - requirement: SR-001
    coverage: full
    tests:
      - path: test/a/one_test.dart
        contains: "does the thing"
  - requirement: CR-001
    pending: "none — pending clinical decision"
''';

void main() {
  group('traceability checks', () {
    test('a complete, accurate map passes', () {
      final report = _report(_goodMap);
      expect(report.errors, isEmpty);
      expect(report.rows.map((r) => r.id), ['SR-001', 'CR-001']);
      expect(report.mappedTestCount, 1);
    });

    test('a missing test file fails', () {
      final report = _report(
        _goodMap.replaceFirst('one_test.dart', 'gone_test.dart'),
      );
      expect(report.errors.single, contains('does not exist'));
    });

    test('a test name that is not in the file fails', () {
      final report = _report(
        _goodMap.replaceFirst('does the thing', 'renamed test'),
      );
      expect(report.errors.single, contains('not found in'));
    });

    test('a requirement with no entry fails', () {
      final report = _report('''
mappings:
  - requirement: SR-001
    coverage: full
    tests:
      - path: test/a/one_test.dart
''');
      expect(report.errors.single, contains('CR-001: no entry'));
    });

    test('an unknown requirement and a duplicate mapping fail', () {
      final report = _report('''
$_goodMap  - requirement: SR-999
    pending: "x"
  - requirement: SR-001
    pending: "again"
''');
      expect(
        report.errors,
        contains(contains('SR-999 is not in requirements.yaml')),
      );
      expect(
        report.errors,
        contains(contains('SR-001 is mapped more than once')),
      );
    });

    test('no tests and no pending reason fails', () {
      final report = _report('''
mappings:
  - requirement: SR-001
    tests: []
  - requirement: CR-001
    pending: "none — pending clinical decision"
''');
      expect(report.errors.single, contains('no tests and no pending reason'));
    });

    test('partial coverage must state its gap', () {
      final report = _report(
        _goodMap.replaceFirst('coverage: full', 'coverage: partial'),
      );
      expect(report.errors.single, contains('needs a "gap"'));
    });

    test('a clinical requirement may not be mapped to tests yet', () {
      final report = _report('''
mappings:
  - requirement: SR-001
    pending: "later"
  - requirement: CR-001
    coverage: full
    tests:
      - path: test/a/one_test.dart
''');
      expect(
        report.errors.single,
        contains('clinical requirements stay unmapped'),
      );
    });

    test('a non-test path is rejected', () {
      final report = _report(
        _goodMap.replaceFirst('test/a/one_test.dart', 'lib/main.dart'),
      );
      expect(
        report.errors.single,
        contains('is not a test/**/*_test.dart file'),
      );
    });

    test('the matrix lists every requirement with its verification', () {
      final matrix = renderMatrix(_report(_goodMap));
      expect(
        matrix,
        contains(
          '| SR-001 | Met | full | `test/a/one_test.dart :: "does the thing"` |',
        ),
      );
      expect(
        matrix,
        contains(
          '| CR-001 | TO BE DEFINED | none | none — pending clinical decision |',
        ),
      );
      expect(
        matrix,
        contains('2 requirements: 1 full, 0 partial, 1 without tests'),
      );
    });
  });

  group('the committed traceability files', () {
    late TraceReport report;

    setUpAll(() {
      report = buildTraceReport(
        requirementsYaml: File(
          'docs/traceability/requirements.yaml',
        ).readAsStringSync(),
        mapYaml: File('docs/traceability/test_map.yaml').readAsStringSync(),
        fileExists: (path) => File(path).existsSync(),
        readFile: (path) => File(path).readAsStringSync(),
      );
    });

    test('pass every check', () {
      expect(report.errors, isEmpty);
    });

    test('map SR-001 to SR-012 to real tests', () {
      for (var n = 1; n <= 12; n++) {
        final id = 'SR-${n.toString().padLeft(3, '0')}';
        final row = report.rows.singleWhere((r) => r.id == id);
        expect(row.tests, isNotEmpty, reason: id);
      }
    });

    test('leave CR-001 to CR-004 pending a clinical decision', () {
      for (var n = 1; n <= 4; n++) {
        final row = report.rows.singleWhere((r) => r.id == 'CR-00$n');
        expect(row.tests, isEmpty);
        expect(row.pending, 'none — pending clinical decision');
      }
    });

    test('include SR-016, verified in the knowledge base', () {
      final row = report.rows.singleWhere((r) => r.id == 'SR-016');
      expect(row.external.single, contains('check_published_artifacts.py'));
    });
  });
}
