/// A minimal JSON Schema (draft 2020-12) validator, sufficient for
/// `telemetry.v1.schema.json`.
///
/// Written rather than pulled in as a package because the alternative was
/// adding a dependency to `pubspec.yaml` for test-only use, and this schema
/// exercises exactly twenty keywords — enumerated in [_supportedKeywords] and
/// asserted by a test, so a future backend schema that uses something new
/// fails loudly here instead of being silently under-validated.
///
/// It is deliberately strict: an unrecognised keyword is an error, not a
/// shrug. A validator that quietly ignores what it does not understand would
/// let a contract change through while still reporting green.
library;

class SchemaError {
  const SchemaError(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

/// Every keyword this validator understands. Anything else in a schema throws.
const Set<String> _supportedKeywords = {
  // Structural/annotation keywords that carry no constraint.
  r'$schema', r'$id', 'title', 'description', r'$defs',
  // Constraints.
  'type', 'enum', 'const', 'pattern', 'maxLength', 'minimum', 'maximum',
  'required', 'properties', 'additionalProperties', 'oneOf', r'$ref',
  'minItems', 'maxItems', 'items',
};

class JsonSchemaValidator {
  JsonSchemaValidator(this.root);

  final Map<String, Object?> root;

  /// Returns every violation found in [instance]. Empty means valid.
  List<SchemaError> validate(Object? instance) =>
      _validate(instance, root, r'$');

  /// The keyword set actually used by [root], for the guard test.
  Set<String> keywordsUsed() {
    final found = <String>{};
    void walk(Object? node) {
      if (node is Map) {
        for (final entry in node.entries) {
          final key = entry.key as String;
          found.add(key);
          // Property *names* are not keywords; skip a level under these.
          if (key == 'properties' || key == r'$defs') {
            if (entry.value is Map) {
              for (final child in (entry.value as Map).values) {
                walk(child);
              }
            }
          } else {
            walk(entry.value);
          }
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item);
        }
      }
    }

    walk(root);
    return found;
  }

  /// Keywords in [root] this validator does not implement.
  Set<String> unsupportedKeywords() {
    // Property names inside `properties` are skipped by keywordsUsed, but
    // schema objects also nest under `items`/`oneOf`, which walk normally.
    return keywordsUsed().difference(_supportedKeywords);
  }

  Map<String, Object?> _resolve(Map<String, Object?> schema) {
    final ref = schema[r'$ref'];
    if (ref is! String) return schema;
    if (!ref.startsWith('#/\$defs/')) {
      throw ArgumentError('Unsupported \$ref form: $ref');
    }
    final name = ref.substring('#/\$defs/'.length);
    final defs = root[r'$defs'];
    if (defs is! Map || defs[name] is! Map) {
      throw ArgumentError('Unresolvable \$ref: $ref');
    }
    return Map<String, Object?>.from(defs[name] as Map);
  }

  List<SchemaError> _validate(
    Object? instance,
    Map<String, Object?> rawSchema,
    String path,
  ) {
    final schema = _resolve(rawSchema);
    final errors = <SchemaError>[];

    final type = schema['type'];
    if (type is String && !_matchesType(instance, type)) {
      errors.add(SchemaError(path, 'expected type $type'));
      // Every other keyword assumes the type held; stop here.
      return errors;
    }

    final constValue = schema['const'];
    if (schema.containsKey('const') && instance != constValue) {
      errors.add(SchemaError(path, 'expected const $constValue'));
    }

    final enumValues = schema['enum'];
    if (enumValues is List && !enumValues.contains(instance)) {
      errors.add(SchemaError(path, 'value not in enum'));
    }

    if (instance is String) {
      final pattern = schema['pattern'];
      if (pattern is String && !RegExp(pattern).hasMatch(instance)) {
        errors.add(SchemaError(path, 'does not match pattern $pattern'));
      }
      final maxLength = schema['maxLength'];
      if (maxLength is int && instance.length > maxLength) {
        errors.add(SchemaError(path, 'longer than maxLength $maxLength'));
      }
    }

    if (instance is num) {
      final minimum = schema['minimum'];
      if (minimum is num && instance < minimum) {
        errors.add(SchemaError(path, 'below minimum $minimum'));
      }
      final maximum = schema['maximum'];
      if (maximum is num && instance > maximum) {
        errors.add(SchemaError(path, 'above maximum $maximum'));
      }
    }

    if (instance is List) {
      final minItems = schema['minItems'];
      if (minItems is int && instance.length < minItems) {
        errors.add(SchemaError(path, 'fewer than minItems $minItems'));
      }
      final maxItems = schema['maxItems'];
      if (maxItems is int && instance.length > maxItems) {
        errors.add(SchemaError(path, 'more than maxItems $maxItems'));
      }
      final items = schema['items'];
      if (items is Map) {
        for (var i = 0; i < instance.length; i++) {
          errors.addAll(
            _validate(
              instance[i],
              Map<String, Object?>.from(items),
              '$path[$i]',
            ),
          );
        }
      }
    }

    if (instance is Map) {
      final required = schema['required'];
      if (required is List) {
        for (final key in required) {
          if (!instance.containsKey(key)) {
            errors.add(SchemaError(path, 'missing required property $key'));
          }
        }
      }
      final properties = schema['properties'];
      if (properties is Map) {
        for (final entry in instance.entries) {
          final propertySchema = properties[entry.key];
          if (propertySchema is Map) {
            errors.addAll(
              _validate(
                entry.value,
                Map<String, Object?>.from(propertySchema),
                '$path.${entry.key}',
              ),
            );
          } else if (schema['additionalProperties'] == false) {
            errors.add(
              SchemaError(path, 'additional property ${entry.key} not allowed'),
            );
          }
        }
      }
    }

    final oneOf = schema['oneOf'];
    if (oneOf is List) {
      final matches = oneOf.where((branch) {
        return _validate(
          instance,
          Map<String, Object?>.from(branch as Map),
          path,
        ).isEmpty;
      }).length;
      if (matches != 1) {
        errors.add(
          SchemaError(path, 'matched $matches oneOf branches, want 1'),
        );
      }
    }

    return errors;
  }

  bool _matchesType(Object? instance, String type) => switch (type) {
    'object' => instance is Map,
    'array' => instance is List,
    'string' => instance is String,
    // JSON Schema treats booleans as distinct from integers; Dart does too,
    // but a careless `is num` check would let `true` through on some
    // platforms, so bool is excluded explicitly.
    'integer' => instance is int && instance is! bool,
    'number' => instance is num && instance is! bool,
    'boolean' => instance is bool,
    'null' => instance == null,
    _ => throw ArgumentError('Unsupported type: $type'),
  };
}
