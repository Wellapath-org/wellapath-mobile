/// Builds a CycloneDX 1.6 JSON SBOM (software bill of materials / SOUP
/// list) from `pubspec.lock`.
///
/// Used by `scripts/generate_sbom.dart` and CI. Pure function, no I/O, so it
/// is fully testable offline.
///
/// Lockfile limitation, stated in the SBOM itself: `pubspec.lock` marks
/// packages `direct main`, `direct dev` or `transitive`, but it does not say
/// whose transitive dependency a package is. Transitive packages of dev-only
/// tools are therefore listed too, and are not distinguished from runtime
/// ones. Direct dev dependencies get `scope: optional`. Everything else gets
/// `scope: required`, which errs toward listing too much.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'simple_yaml.dart';

class SbomException implements Exception {
  SbomException(this.message);

  final String message;

  @override
  String toString() => 'SbomException: $message';
}

/// Returns the CycloneDX document as a JSON-encodable map.
///
/// [timestamp] is injected so output is reproducible in tests. The serial
/// number is derived from the lockfile bytes, so the same lockfile always
/// yields the same serial number.
Map<String, Object?> buildCycloneDxFromPubspecLock({
  required String pubspecLock,
  required String pubspecYaml,
  required DateTime timestamp,
  String? gitCommit,
}) {
  final parsed = parseYamlSubset(pubspecLock);
  if (parsed is! Map<String, Object?> || parsed['packages'] is! Map) {
    throw SbomException('pubspec.lock has no "packages" mapping');
  }
  final packages = (parsed['packages'] as Map).cast<String, Object?>();
  final sdks = parsed['sdks'] is Map
      ? (parsed['sdks'] as Map).cast<String, Object?>()
      : const <String, Object?>{};

  final appName = _topLevelScalar(pubspecYaml, 'name');
  final appVersion = _topLevelScalar(pubspecYaml, 'version');
  if (appName == null || appVersion == null) {
    throw SbomException('pubspec.yaml must declare top-level name and version');
  }

  final names = packages.keys.toList()..sort();
  final components = <Map<String, Object?>>[];
  for (final name in names) {
    final entry = packages[name];
    if (entry is! Map) {
      throw SbomException('package "$name" is not a mapping');
    }
    components.add(_component(name, entry.cast<String, Object?>()));
  }

  final lockDigest = sha256.convert(utf8.encode(pubspecLock)).toString();
  return <String, Object?>{
    r'$schema': 'http://cyclonedx.org/schema/bom-1.6.schema.json',
    'bomFormat': 'CycloneDX',
    'specVersion': '1.6',
    'serialNumber': 'urn:uuid:${_uuidFromHex(lockDigest)}',
    'version': 1,
    'metadata': <String, Object?>{
      'timestamp': timestamp.toUtc().toIso8601String(),
      'tools': <String, Object?>{
        'components': [
          <String, Object?>{
            'type': 'application',
            'name': 'wellapath-mobile scripts/generate_sbom.dart',
            'version': '1',
          },
        ],
      },
      'component': <String, Object?>{
        'type': 'application',
        'bom-ref': _purl(appName, appVersion),
        'name': appName,
        'version': appVersion,
        'purl': _purl(appName, appVersion),
      },
      'properties': [
        _property('wellapath:source', 'pubspec.lock'),
        _property('wellapath:pubspec_lock_sha256', lockDigest),
        if (gitCommit != null) _property('wellapath:git_commit', gitCommit),
        for (final sdk in (sdks.keys.toList()..sort()))
          _property('pub:sdk_constraint:$sdk', '${sdks[sdk]}'),
        _property(
          'wellapath:limitation',
          'pubspec.lock does not separate runtime from dev-only transitive '
              'packages; transitive packages are all listed with scope '
              'required. Direct dev dependencies have scope optional.',
        ),
        _property(
          'wellapath:not_a_certification',
          'Engineering SOUP evidence only. WellaPath is not NAFDAC approved '
              'or registered.',
        ),
      ],
    },
    'components': components,
  };
}

Map<String, Object?> _component(String name, Map<String, Object?> entry) {
  final dependency = entry['dependency']?.toString() ?? 'unknown';
  final source = entry['source']?.toString() ?? 'unknown';
  final version = entry['version']?.toString() ?? '';
  if (version.isEmpty) {
    throw SbomException('package "$name" has no version');
  }
  final description = entry['description'];
  final properties = <Map<String, Object?>>[
    _property('pub:dependency', dependency),
    _property('pub:source', source),
  ];
  final hashes = <Map<String, Object?>>[];
  final references = <Map<String, Object?>>[];
  String purl;

  switch (source) {
    case 'hosted':
      if (description is! Map) {
        throw SbomException('hosted package "$name" has no description');
      }
      final hostedName = description['name']?.toString() ?? name;
      final url = description['url']?.toString() ?? 'https://pub.dev';
      final digest = description['sha256']?.toString();
      if (digest == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
        throw SbomException('hosted package "$name" has no valid sha256');
      }
      hashes.add(<String, Object?>{'alg': 'SHA-256', 'content': digest});
      purl = url == 'https://pub.dev'
          ? _purl(hostedName, version)
          : '${_purl(hostedName, version)}'
                '?repository_url=${Uri.encodeComponent(url)}';
      references.add(<String, Object?>{
        'type': 'distribution',
        'url': '$url/packages/$hostedName/versions/$version',
      });
    case 'git':
      if (description is! Map) {
        throw SbomException('git package "$name" has no description');
      }
      final url = description['url']?.toString() ?? '';
      final resolved = description['resolved-ref']?.toString() ?? '';
      purl = _purl(name, version);
      properties.add(_property('pub:git_url', url));
      properties.add(_property('pub:git_resolved_ref', resolved));
      if (url.isNotEmpty) {
        references.add(<String, Object?>{'type': 'vcs', 'url': url});
      }
    case 'sdk':
      // Flutter SDK packages report version 0.0.0; the real version is the
      // SDK's, recorded in metadata.properties.
      purl = _purl(name, version);
      properties.add(_property('pub:sdk', '$description'));
    case 'path':
      purl = _purl(name, version);
      if (description is Map) {
        properties.add(_property('pub:path', '${description['path']}'));
      }
    default:
      throw SbomException('package "$name" has unknown source "$source"');
  }

  return <String, Object?>{
    'type': 'library',
    'bom-ref': purl,
    'name': name,
    'version': version,
    'scope': dependency == 'direct dev' ? 'optional' : 'required',
    'purl': purl,
    if (hashes.isNotEmpty) 'hashes': hashes,
    if (references.isNotEmpty) 'externalReferences': references,
    'properties': properties,
  };
}

/// Package URL per the purl spec (`pkg:pub/<name>@<version>`), with the
/// version percent-encoded (a `+build` suffix becomes `%2B`).
String _purl(String name, String version) =>
    'pkg:pub/$name@${Uri.encodeComponent(version)}';

Map<String, Object?> _property(String name, String value) => <String, Object?>{
  'name': name,
  'value': value,
};

String? _topLevelScalar(String yaml, String key) {
  final match = RegExp(
    '^$key:\\s*["\']?([^"\'#\\s]+)',
    multiLine: true,
  ).firstMatch(yaml);
  return match?.group(1);
}

/// Formats the first 128 bits of [hex] as an RFC 4122 version-5-style UUID.
String _uuidFromHex(String hex) {
  final chars = hex.substring(0, 32).split('');
  chars[12] = '5';
  chars[16] = '89ab'[int.parse(chars[16], radix: 16) & 3];
  final s = chars.join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
      '${s.substring(16, 20)}-${s.substring(20, 32)}';
}
