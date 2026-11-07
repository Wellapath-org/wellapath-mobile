/// Community must never touch the clinical flow, in either direction.
///
/// COMMUNITY_BUILD_STATUS.md §3: no automatic transfer of symptoms, triage
/// results, urgency or assessment history into Community. The simplest
/// enforceable form of that rule is structural — Community code cannot import
/// the engine, the assessment flow, the results screens or their models, and
/// clinical code cannot import Community.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Directories Community code may not reach.
const List<String> _clinical = [
  'lib/core/engine',
  'lib/core/question_flow',
  'lib/core/vocabulary',
  'lib/features/assessment',
  'lib/features/results',
];

const String _community = 'lib/features/community';

/// The only files outside the module allowed to import it (the gated entry).
const Set<String> _allowedCommunityImporters = {
  'lib/features/more/more_screen.dart',
};

final RegExp _directive = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Resolves every import/export/part in [file] to a repo-relative `lib/...`
/// path (package: and relative forms), ignoring dart: and other packages.
List<String> _resolvedImports(File file) {
  final String source = file.readAsStringSync();
  final String dir = File(file.path).parent.path;
  final List<String> out = [];
  for (final RegExpMatch m in _directive.allMatches(source)) {
    final String uri = m.group(1)!;
    out.add(_resolve(uri, dir));
  }
  return out;
}

String _resolve(String uri, String fromDir) {
  if (uri.startsWith('package:wellapath_mobile/')) {
    return 'lib/${uri.substring('package:wellapath_mobile/'.length)}';
  }
  if (uri.startsWith('dart:') || uri.startsWith('package:')) return uri;
  final List<String> parts = fromDir.split('/')..removeWhere((p) => p == '.');
  for (final String seg in uri.split('/')) {
    if (seg == '..') {
      parts.removeLast();
    } else if (seg != '.') {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

bool _under(String path, String dir) => path == dir || path.startsWith('$dir/');

List<File> _dartFiles(String root) {
  final Directory dir = Directory(root);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList();
}

void main() {
  test('the resolver catches both import forms (guard self-test)', () {
    expect(
      _resolve(
        '../../../core/engine/models/engine_output.dart',
        '$_community/ui',
      ),
      'lib/core/engine/models/engine_output.dart',
    );
    expect(
      _resolve(
        'package:wellapath_mobile/features/assessment/models/x.dart',
        '$_community/ui',
      ),
      'lib/features/assessment/models/x.dart',
    );
    expect(_under('lib/features/results/a.dart', 'lib/features/results'), true);
    expect(
      _under('lib/features/resultsx/a.dart', 'lib/features/results'),
      false,
    );
  });

  test('the community module exists and has code to scan', () {
    expect(_dartFiles(_community), isNotEmpty);
  });

  test('community code imports nothing from engine/assessment/results', () {
    final List<String> offenders = [];
    for (final File f in _dartFiles(_community)) {
      for (final String target in _resolvedImports(f)) {
        if (_clinical.any((String c) => _under(target, c))) {
          offenders.add('${f.path} -> $target');
        }
        // Guard against reaching assessment models by any other route.
        if (target.contains('assessment') || target.contains('engine_')) {
          offenders.add('${f.path} -> $target (assessment-like name)');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'Community must stay isolated');
  });

  test('engine/assessment/results code does not import community', () {
    final List<String> offenders = [];
    for (final String root in _clinical) {
      for (final File f in _dartFiles(root)) {
        for (final String target in _resolvedImports(f)) {
          if (_under(target, _community)) {
            offenders.add('${f.path} -> $target');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('only the gated More-tab entry imports community from outside', () {
    final List<String> offenders = [];
    for (final File f in _dartFiles('lib')) {
      final String path = f.path;
      if (_under(path, _community)) continue;
      final bool importsCommunity = _resolvedImports(
        f,
      ).any((String t) => _under(t, _community));
      if (importsCommunity && !_allowedCommunityImporters.contains(path)) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('community source never mentions assessment data concepts', () {
    // Not a ban on words in comments — a ban on code identifiers that would
    // carry clinical data across (e.g. a field named `urgency`).
    final RegExp clinicalIdent = RegExp(
      r'\b(?:EngineOutput|AssessmentController|urgency|redFlag|topCauses|'
      r'symptom\w*)\b',
    );
    final List<String> offenders = [];
    for (final File f in _dartFiles(_community)) {
      final List<String> lines = f.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String t = lines[i].trimLeft();
        if (t.startsWith('//')) continue;
        if (clinicalIdent.hasMatch(lines[i])) {
          offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
