/// A small OpenAPI 3.1 reader for the Community contract tests: operation
/// lookup by method + path, a request-body validator, and a fixture
/// generator that builds responses from the spec's own schemas.
///
/// It understands only the JSON-Schema subset the Community spec uses:
/// `$ref`, `oneOf`, `const`, `enum`, `type` (incl. `[x, "null"]`), objects
/// with `required` / `properties` / `additionalProperties`, arrays with
/// `items` / `minItems` / `maxItems`, string length/pattern/format and
/// integer bounds.
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

const String kSpecPath = 'docs/community/community_api_v1.openapi.yaml';

Object? _plain(Object? node) {
  if (node is YamlMap) {
    return <String, Object?>{
      for (final MapEntry<dynamic, dynamic> e in node.entries)
        '${e.key}': _plain(e.value),
    };
  }
  if (node is YamlList) return node.map(_plain).toList();
  return node;
}

class SpecOperation {
  SpecOperation(this.method, this.template, this.raw, this.spec);

  final String method;
  final String template;
  final Map<String, Object?> raw;
  final OpenApiSpec spec;

  late final RegExp _pattern = RegExp(
    '^${template.replaceAllMapped(RegExp(r'\{[^}]+\}'), (Match _) => '[^/]+')}\$',
  );

  bool matches(String method, String path) {
    return method.toUpperCase() == this.method && _pattern.hasMatch(path);
  }

  String get id => '$method $template';

  List<Map<String, Object?>> get parameters {
    return <Map<String, Object?>>[
      for (final Object? p
          in (raw['parameters'] as List<Object?>?) ?? <Object?>[])
        spec.resolve(p! as Map<String, Object?>),
    ];
  }

  Map<String, Object?>? get requestSchema {
    final Map<String, Object?>? body =
        raw['requestBody'] as Map<String, Object?>?;
    if (body == null) return null;
    final Map<String, Object?> content =
        body['content']! as Map<String, Object?>;
    final Map<String, Object?> json =
        content['application/json']! as Map<String, Object?>;
    return json['schema'] as Map<String, Object?>?;
  }

  bool get requestBodyRequired =>
      (raw['requestBody'] as Map<String, Object?>?)?['required'] == true;

  /// The first 2xx response: (status, schema or null for no content).
  (int, Map<String, Object?>?) get success {
    final Map<String, Object?> responses =
        raw['responses']! as Map<String, Object?>;
    for (final String code in responses.keys) {
      final int status = int.parse(code);
      if (status < 200 || status >= 300) continue;
      final Map<String, Object?> r = spec.resolve(
        responses[code]! as Map<String, Object?>,
      );
      final Map<String, Object?>? content =
          r['content'] as Map<String, Object?>?;
      if (content == null) return (status, null);
      final Map<String, Object?> json =
          content['application/json']! as Map<String, Object?>;
      return (status, json['schema'] as Map<String, Object?>?);
    }
    throw StateError('no 2xx response for $id');
  }
}

class OpenApiSpec {
  OpenApiSpec(this.root) {
    final Map<String, Object?> paths = root['paths']! as Map<String, Object?>;
    for (final MapEntry<String, Object?> p in paths.entries) {
      final Map<String, Object?> item = p.value! as Map<String, Object?>;
      for (final MapEntry<String, Object?> m in item.entries) {
        operations.add(
          SpecOperation(
            m.key.toUpperCase(),
            p.key,
            m.value! as Map<String, Object?>,
            this,
          ),
        );
      }
    }
  }

  factory OpenApiSpec.load([String path = kSpecPath]) {
    return OpenApiSpec(
      _plain(loadYaml(File(path).readAsStringSync()))! as Map<String, Object?>,
    );
  }

  final Map<String, Object?> root;
  final List<SpecOperation> operations = <SpecOperation>[];

  SpecOperation? find(String method, String path) {
    final List<SpecOperation> hits = operations
        .where((SpecOperation o) => o.matches(method, path))
        .toList();
    if (hits.isEmpty) return null;
    // Prefer the literal path over a templated one (e.g. read-all vs {id}).
    hits.sort(
      (SpecOperation a, SpecOperation b) =>
          '{'.allMatches(a.template).length - '{'.allMatches(b.template).length,
    );
    return hits.first;
  }

  Map<String, Object?> schema(String name) {
    return resolve(<String, Object?>{r'$ref': '#/components/schemas/$name'});
  }

  /// Follows `$ref` chains to the target object.
  Map<String, Object?> resolve(Map<String, Object?> node) {
    Map<String, Object?> n = node;
    while (n.containsKey(r'$ref')) {
      final String ref = n[r'$ref']! as String;
      Object? target = root;
      for (final String part in ref.substring(2).split('/')) {
        target = (target! as Map<String, Object?>)[part];
      }
      n = target! as Map<String, Object?>;
    }
    return n;
  }

  String? refName(Map<String, Object?> node) {
    final Object? ref = node[r'$ref'];
    return ref is String ? ref.split('/').last : null;
  }

  // ---- validation ------------------------------------------------------------

  /// Returns the list of violations of [value] against [schema].
  List<String> validate(
    Map<String, Object?> schema,
    Object? value, [
    String at = r'$',
  ]) {
    final List<String> errors = <String>[];
    _validate(schema, value, at, errors);
    return errors;
  }

  void _validate(
    Map<String, Object?> s0,
    Object? v,
    String at,
    List<String> errors,
  ) {
    final Map<String, Object?> s = resolve(s0);
    if (s.containsKey('oneOf')) {
      final int ok = (s['oneOf']! as List<Object?>)
          .where(
            (Object? b) => validate(b! as Map<String, Object?>, v, at).isEmpty,
          )
          .length;
      if (ok != 1) errors.add('$at: matches $ok oneOf branches');
      return;
    }
    if (s.containsKey('const') && v != s['const']) {
      errors.add('$at: expected const ${s['const']}');
      return;
    }
    if (s.containsKey('enum') && !(s['enum']! as List<Object?>).contains(v)) {
      errors.add('$at: "$v" not in enum');
      return;
    }
    final Object? type = s['type'];
    final List<String> types = type == null
        ? <String>[]
        : type is List
        ? type.cast<String>()
        : <String>[type as String];
    if (v == null) {
      if (types.isNotEmpty && !types.contains('null')) errors.add('$at: null');
      return;
    }
    final String actual = v is Map
        ? 'object'
        : v is List
        ? 'array'
        : v is String
        ? 'string'
        : v is int
        ? 'integer'
        : v is bool
        ? 'boolean'
        : 'number';
    if (types.isNotEmpty &&
        !types.contains(actual) &&
        !(actual == 'integer' && types.contains('number'))) {
      errors.add('$at: $actual is not ${types.join('|')}');
      return;
    }
    if (types.contains('object') || s.containsKey('properties')) {
      if (v is! Map) {
        errors.add('$at: not an object');
        return;
      }
      final Map<String, Object?> props =
          (s['properties'] as Map<String, Object?>?) ?? <String, Object?>{};
      for (final Object? r
          in (s['required'] as List<Object?>?) ?? <Object?>[]) {
        if (!v.containsKey(r)) errors.add('$at.$r: required');
      }
      for (final MapEntry<dynamic, dynamic> e in v.entries) {
        final Map<String, Object?>? p = props[e.key] as Map<String, Object?>?;
        if (p == null) {
          if (s['additionalProperties'] == false) {
            errors.add('$at.${e.key}: unknown_field');
          }
          continue;
        }
        _validate(p, e.value, '$at.${e.key}', errors);
      }
      return;
    }
    if (types.contains('array')) {
      if (v is! List) {
        errors.add('$at: not an array');
        return;
      }
      for (int i = 0; i < v.length; i++) {
        _validate(s['items']! as Map<String, Object?>, v[i], '$at[$i]', errors);
      }
      return;
    }
    if (types.contains('string')) {
      if (v is! String) {
        errors.add('$at: not a string');
        return;
      }
      final int? minL = s['minLength'] as int?;
      final int? maxL = s['maxLength'] as int?;
      if (minL != null && v.length < minL) errors.add('$at: min_length');
      if (maxL != null && v.length > maxL) errors.add('$at: max_length');
      final String? pattern = s['pattern'] as String?;
      if (pattern != null && !RegExp(pattern).hasMatch(v)) {
        errors.add('$at: pattern');
      }
      if (s['format'] == 'uuid' &&
          !RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(v)) {
        errors.add('$at: format uuid');
      }
      if (s['format'] == 'date-time' && DateTime.tryParse(v) == null) {
        errors.add('$at: format date-time');
      }
      return;
    }
    if (types.contains('integer')) {
      if (v is! int) {
        errors.add('$at: not an integer');
        return;
      }
      final num? min = s['minimum'] as num?;
      final num? max = s['maximum'] as num?;
      if ((min != null && v < min) || (max != null && v > max)) {
        errors.add('$at: out of range');
      }
      return;
    }
    if (types.contains('boolean') && v is! bool) errors.add('$at: not a bool');
  }

  // ---- fixtures --------------------------------------------------------------

  /// Builds a value from [schema]. [rich] fills every optional field and
  /// picks non-null branches; otherwise only required fields, nulls where
  /// allowed and the last `oneOf` branch.
  Object? generate(Map<String, Object?> schema, {required bool rich}) {
    final String? name = refName(schema);
    final Map<String, Object?> s = resolve(schema);
    Object? out;
    if (s.containsKey('oneOf')) {
      final List<Map<String, Object?>> branches = (s['oneOf']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final Map<String, Object?> pick = rich
          ? branches.firstWhere(
              (Map<String, Object?> b) => resolve(b)['type'] != 'null',
            )
          : branches.last;
      out = generate(pick, rich: rich);
    } else if (s.containsKey('const')) {
      out = s['const'];
    } else if (s.containsKey('enum')) {
      out = (s['enum']! as List<Object?>).first;
    } else {
      out = _byType(s, rich: rich);
    }
    final Fixup? fix = name == null ? null : fixups[name];
    return fix == null ? out : fix(out);
  }

  Object? _byType(Map<String, Object?> s, {required bool rich}) {
    final Object? type = s['type'];
    final List<String> types = type == null
        ? <String>['object']
        : type is List
        ? type.cast<String>()
        : <String>[type as String];
    if (!rich && types.contains('null')) return null;
    if (types.contains('object')) {
      final Map<String, Object?> props =
          (s['properties'] as Map<String, Object?>?) ?? <String, Object?>{};
      final Set<Object?> required =
          ((s['required'] as List<Object?>?) ?? <Object?>[]).toSet();
      return <String, Object?>{
        for (final MapEntry<String, Object?> p in props.entries)
          if (rich || required.contains(p.key))
            p.key: generate(p.value! as Map<String, Object?>, rich: rich),
      };
    }
    if (types.contains('array')) {
      final int min = (s['minItems'] as int?) ?? 0;
      final int n = rich ? (min > 0 ? min : 1) : min;
      return <Object?>[
        for (int i = 0; i < n; i++)
          generate(s['items']! as Map<String, Object?>, rich: rich),
      ];
    }
    if (types.contains('string')) {
      switch (s['format']) {
        case 'date-time':
          return '2026-11-07T10:15:00.000Z';
        case 'uuid':
          return '0192f1d2-0000-4000-8000-000000000001';
        case 'email':
          return 'a@b.ng';
      }
      final String? pattern = s['pattern'] as String?;
      if (pattern == r'^[0-9]{6}$') return '123456';
      if (pattern != null && pattern.startsWith('^wprt_')) {
        return 'wprt_${'x' * 43}';
      }
      String v = 'SunnyMum';
      final int? minL = s['minLength'] as int?;
      final int? maxL = s['maxLength'] as int?;
      if (minL != null && v.length < minL) v = v.padRight(minL, 'x');
      if (maxL != null && v.length > maxL) v = v.substring(0, maxL);
      return v;
    }
    if (types.contains('integer')) {
      final int? min = (s['minimum'] as num?)?.toInt();
      final int? max = (s['maximum'] as num?)?.toInt();
      if (rich) return max ?? (min ?? 0) + 3;
      return min ?? 1;
    }
    if (types.contains('boolean')) return rich;
    return null;
  }
}

typedef Fixup = Object? Function(Object? value);

/// Rules the markdown states but the YAML cannot express without
/// `if/then`. Applied to generated fixtures so they are valid under BOTH
/// documents (listed as a proposed YAML change in the deliverable).
final Map<String, Fixup> fixups = <String, Fixup>{
  // §7.1: verified_at is non-null iff status == "verified".
  'ProfessionalVerification': (Object? v) {
    final Map<String, Object?> m = Map<String, Object?>.of(
      v! as Map<String, Object?>,
    );
    if (m['status'] != 'verified') m['verified_at'] = null;
    return m;
  },
  // §11: notice is null unless type == "moderation_notice".
  'Notification': (Object? v) {
    final Map<String, Object?> m = Map<String, Object?>.of(
      v! as Map<String, Object?>,
    );
    if (m['type'] != 'moderation_notice') m['notice'] = null;
    return m;
  },
};
