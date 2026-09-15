/// Isolation guards: the Facilities 2.0 consumer must be unreachable from
/// the product, introduce no network client or telemetry of its own, and
/// leave the shipped v1.1 locator byte-identical in behaviour.
///
/// Same guard style as the Question Flow 1.1 and Vocabulary 2.0 consumers:
/// exclusion is proven by import topology, not asserted.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final consumerDir = Directory('lib/core/facilities_v2');

  List<File> dartFilesUnder(String path) => Directory(path)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('no file outside lib/core/facilities_v2 imports the consumer', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      if (file.path.startsWith(consumerDir.path)) continue;
      final source = file.readAsStringSync();
      if (source.contains('facilities_v2')) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'the v2 consumer must stay unreachable from the product until '
          'the gate, manifest approval and Product/Clinical sign-off exist',
    );
  });

  test('the consumer imports no HTTP client, plugin or telemetry', () {
    for (final file in dartFilesUnder(consumerDir.path)) {
      final source = file.readAsStringSync();
      for (final banned in const [
        'package:dio',
        'package:http',
        'package:geolocator',
        'package:sentry',
        'core/telemetry',
        'package:hive',
      ]) {
        expect(
          source.contains(banned),
          isFalse,
          reason:
              '${file.path} must not import $banned — the consumer is '
              'pure/local, with networking and storage injected as seams',
        );
      }
    }
  });

  test('the shipped v1.1 locator does not reference the v2 consumer', () {
    for (final file in dartFilesUnder('lib/features/locator')) {
      expect(
        file.readAsStringSync().contains('facilities_v2'),
        isFalse,
        reason: '${file.path} must be untouched by v2 preparation',
      );
    }
  });

  test('no candidate artifact is bundled', () {
    // The real candidate must not be copied into the repo, under any name.
    final everywhere = [
      ...dartFilesUnder('lib'),
      ...Directory('assets').listSync(recursive: true).whereType<File>(),
      ...Directory(
        'test/fixtures/facilities_v2',
      ).listSync(recursive: true).whereType<File>(),
    ];
    for (final file in everywhere) {
      expect(
        file.path.contains('facilities.ng.v2'),
        isFalse,
        reason: 'candidate artifact file found: ${file.path}',
      );
    }
    // pubspec bundles no facilities data of any kind.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('facilities'), isFalse);
  });

  test('the synthetic fixture declares itself synthetic', () {
    final fixture = File(
      'test/fixtures/facilities_v2/synthetic_facilities_v2_fixture.json',
    ).readAsStringSync();
    expect(fixture, contains('SYNTHETIC TEST-ONLY DATA'));
    expect(fixture, contains('candidate_unapproved'));
    // Every record is visibly marked.
    expect(
      RegExp('"name": "ZZTest').allMatches(fixture).length,
      greaterThanOrEqualTo(10),
    );
  });

  test('no facilities-v2 configuration key ships in the tracked .env', () {
    expect(File('.env').readAsStringSync().contains('FACILITIES_V2'), isFalse);
  });
}
