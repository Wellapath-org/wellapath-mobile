/// Requirement → test traceability checks (`docs/traceability/`).
///
/// Used by `scripts/traceability_report.dart` and its tests. File access goes
/// through [fileExists] and [readFile] so tests can run against an in-memory
/// tree.
library;

import 'simple_yaml.dart';

typedef FileExists = bool Function(String path);
typedef ReadFile = String Function(String path);

class TraceTest {
  TraceTest(this.path, this.contains);

  final String path;
  final String? contains;

  String get id => contains == null ? path : '$path :: "$contains"';
}

class TraceRow {
  TraceRow({
    required this.id,
    required this.title,
    required this.status,
    required this.coverage,
    required this.tests,
    required this.external,
    this.pending,
    this.gap,
  });

  final String id;
  final String title;
  final String status;
  final String coverage;
  final List<TraceTest> tests;
  final List<String> external;
  final String? pending;
  final String? gap;
}

class TraceReport {
  TraceReport(this.rows, this.errors);

  final List<TraceRow> rows;
  final List<String> errors;

  bool get ok => errors.isEmpty;

  int get mappedTestCount => rows.fold(0, (sum, row) => sum + row.tests.length);
}

final _requirementId = RegExp(r'^(SR|CR)-\d{3}$');
const _coverageValues = {'full', 'partial'};

/// Validates [mapYaml] against [requirementsYaml] and the file tree.
TraceReport buildTraceReport({
  required String requirementsYaml,
  required String mapYaml,
  required FileExists fileExists,
  required ReadFile readFile,
}) {
  final errors = <String>[];
  final requirements = <String, Map<String, Object?>>{};
  final order = <String>[];

  final reqDoc = _parse(requirementsYaml, 'requirements.yaml', errors);
  final reqList = reqDoc is Map ? reqDoc['requirements'] : null;
  if (reqList is! List || reqList.isEmpty) {
    errors.add('requirements.yaml: "requirements" must be a non-empty list');
  } else {
    for (final item in reqList) {
      if (item is! Map || item['id'] is! String) {
        errors.add('requirements.yaml: every requirement needs an id');
        continue;
      }
      final id = item['id'] as String;
      if (!_requirementId.hasMatch(id)) {
        errors.add('requirements.yaml: "$id" is not an SR-NNN or CR-NNN id');
      }
      if (requirements.containsKey(id)) {
        errors.add('requirements.yaml: duplicate requirement $id');
        continue;
      }
      requirements[id] = item.cast<String, Object?>();
      order.add(id);
    }
  }

  final mapDoc = _parse(mapYaml, 'test_map.yaml', errors);
  final mapList = mapDoc is Map ? mapDoc['mappings'] : null;
  final mapped = <String, Map<String, Object?>>{};
  if (mapList is! List) {
    errors.add('test_map.yaml: "mappings" must be a list');
  } else {
    for (final item in mapList) {
      if (item is! Map || item['requirement'] is! String) {
        errors.add('test_map.yaml: every mapping needs a requirement');
        continue;
      }
      final id = item['requirement'] as String;
      if (!requirements.containsKey(id)) {
        errors.add('test_map.yaml: $id is not in requirements.yaml');
      }
      if (mapped.containsKey(id)) {
        errors.add('test_map.yaml: $id is mapped more than once');
        continue;
      }
      mapped[id] = item.cast<String, Object?>();
    }
  }

  final rows = <TraceRow>[];
  for (final id in order) {
    final requirement = requirements[id]!;
    final mapping = mapped[id];
    if (mapping == null) {
      errors.add(
        '$id: no entry in test_map.yaml (add tests or a pending reason)',
      );
      continue;
    }
    final tests = <TraceTest>[];
    final rawTests = mapping['tests'];
    if (rawTests != null && rawTests is! List) {
      errors.add('$id: "tests" must be a list');
    }
    for (final raw in rawTests is List ? rawTests : const []) {
      if (raw is! Map || raw['path'] is! String) {
        errors.add('$id: every test needs a path');
        continue;
      }
      final path = raw['path'] as String;
      final contains = raw['contains'] is String
          ? raw['contains'] as String
          : null;
      tests.add(TraceTest(path, contains));
      if (!path.startsWith('test/') || !path.endsWith('_test.dart')) {
        errors.add('$id: $path is not a test/**/*_test.dart file');
        continue;
      }
      if (!fileExists(path)) {
        errors.add('$id: mapped test file does not exist: $path');
        continue;
      }
      if (contains != null && !readFile(path).contains(contains)) {
        errors.add('$id: "$contains" not found in $path');
      }
    }
    final pending = mapping['pending'] is String
        ? mapping['pending'] as String
        : null;
    final coverage = mapping['coverage'];
    if (tests.isEmpty && (pending == null || pending.trim().isEmpty)) {
      errors.add('$id: has no tests and no pending reason');
    }
    if (tests.isNotEmpty && pending != null) {
      errors.add('$id: lists tests and a pending reason; use one');
    }
    if (tests.isNotEmpty && !_coverageValues.contains(coverage)) {
      errors.add('$id: coverage must be "full" or "partial"');
    }
    if (coverage == 'partial' && (mapping['gap'] is! String)) {
      errors.add('$id: partial coverage needs a "gap"');
    }
    if (id.startsWith('CR-') && tests.isNotEmpty) {
      errors.add(
        '$id: clinical requirements stay unmapped until the clinical reviewer '
        'defines them',
      );
    }
    final external = mapping['external'] is List
        ? (mapping['external'] as List).map((e) => '$e').toList()
        : <String>[];
    rows.add(
      TraceRow(
        id: id,
        title: '${requirement['title'] ?? ''}',
        status: '${requirement['status'] ?? ''}',
        coverage: tests.isEmpty ? 'none' : '$coverage',
        tests: tests,
        external: external,
        pending: pending,
        gap: mapping['gap'] is String ? mapping['gap'] as String : null,
      ),
    );
  }
  return TraceReport(rows, errors);
}

Object? _parse(String source, String label, List<String> errors) {
  try {
    return parseYamlSubset(source);
  } on YamlSubsetException catch (error) {
    errors.add('$label: $error');
    return null;
  }
}

/// Renders the requirement → test matrix as Markdown.
String renderMatrix(TraceReport report) {
  final buffer = StringBuffer()
    ..writeln('# Requirement → test traceability matrix (mobile)')
    ..writeln()
    ..writeln('| Requirement | Register status | Coverage | Verified by |')
    ..writeln('|---|---|---|---|');
  for (final row in report.rows) {
    final cells = <String>[
      for (final test in row.tests) '`${test.id}`',
      for (final item in row.external) 'external: $item',
      if (row.tests.isEmpty && row.pending != null) row.pending!,
    ];
    final coverage = row.gap == null
        ? row.coverage
        : '${row.coverage} (gap: ${row.gap})';
    buffer.writeln(
      '| ${row.id} | ${_cell(row.status)} | ${_cell(coverage)} | '
      '${cells.map(_cell).join('<br>')} |',
    );
  }
  final full = report.rows.where((r) => r.coverage == 'full').length;
  final partial = report.rows.where((r) => r.coverage == 'partial').length;
  final none = report.rows.where((r) => r.coverage == 'none').length;
  buffer
    ..writeln()
    ..writeln(
      '${report.rows.length} requirements: $full full, $partial partial, '
      '$none without tests; ${report.mappedTestCount} test references.',
    );
  return buffer.toString();
}

String _cell(String text) => text.replaceAll('|', r'\|');
