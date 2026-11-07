import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/simple_yaml.dart';

void main() {
  group('parseYamlSubset', () {
    test('reads nested mappings and scalars', () {
      final doc =
          parseYamlSubset('''
# comment
a: 1
b: "two # not a comment"
c: 'it''s'
d:
  e: true
  f: null
  g: plain text: with colon # trailing comment
h: []
''')
              as Map;
      expect(doc['a'], 1);
      expect(doc['b'], 'two # not a comment');
      expect(doc['c'], "it's");
      expect(doc['d'], {'e': true, 'f': null, 'g': 'plain text: with colon'});
      expect(doc['h'], isEmpty);
    });

    test('reads lists of scalars and of item mappings, indented or not', () {
      final doc =
          parseYamlSubset('''
indented:
  - one
  - "two"
flush:
- id: A
  title: "first"
  tags:
    - x
- id: B
''')
              as Map;
      expect(doc['indented'], ['one', 'two']);
      expect(doc['flush'], [
        {
          'id': 'A',
          'title': 'first',
          'tags': ['x'],
        },
        {'id': 'B'},
      ]);
    });

    test('keeps apostrophes inside plain scalars', () {
      expect(parseYamlSubset("note: don't panic"), {'note': "don't panic"});
    });

    test('rejects duplicate keys, bad indentation and unsupported syntax', () {
      expect(
        () => parseYamlSubset('a: 1\na: 2'),
        throwsA(isA<YamlSubsetException>()),
      );
      expect(
        () => parseYamlSubset('a:\n    b: 1\n  c: 2'),
        throwsA(isA<YamlSubsetException>()),
      );
      expect(
        () => parseYamlSubset('a: [1, 2]'),
        throwsA(isA<YamlSubsetException>()),
      );
      expect(
        () => parseYamlSubset('a: |\n  text'),
        throwsA(isA<YamlSubsetException>()),
      );
      expect(
        () => parseYamlSubset('a: "open'),
        throwsA(isA<YamlSubsetException>()),
      );
    });

    test('reads the real pubspec.lock', () {
      final doc = parseYamlSubset(File('pubspec.lock').readAsStringSync());
      final packages = (doc as Map)['packages'] as Map;
      expect(packages, isNotEmpty);
      final crypto = packages['crypto'] as Map;
      expect(crypto['dependency'], 'direct main');
      expect(crypto['source'], 'hosted');
      expect(
        (crypto['description'] as Map)['sha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect((doc['sdks'] as Map)['dart'], isA<String>());
    });
  });
}
