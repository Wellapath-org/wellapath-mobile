import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Loads the pinned production artifacts used by the E8.1 case bank run.
///
/// The three files under `test/fixtures/artifacts/` are byte-identical copies
/// of what `/config` served from R2 on 2026-07-26, and each is verified here
/// against the sha256 hash published in that same `/config` response — the
/// same integrity check `StagedArtifactLoader._matchesHash` performs at
/// runtime. Pinning them (rather than downloading during the test) keeps the
/// validation run reproducible and offline-safe: a sign-off number has to be
/// re-derivable from the commit, not from whatever R2 happens to serve later.
///
/// If `/config` moves to a newer artifact version, these fixtures and the
/// hashes below must be refreshed together, and the case bank re-run — that is
/// the point of the check, not an inconvenience.
class PinnedArtifacts {
  const PinnedArtifacts({
    required this.rules,
    required this.tokenDictionary,
    required this.conditions,
    required this.configMetadata,
  });

  final List<Map<String, dynamic>> rules;
  final Map<String, dynamic> tokenDictionary;
  final List<Map<String, dynamic>> conditions;
  final Map<String, dynamic> configMetadata;

  Set<String> get conditionIds => conditions
      .map((Map<String, dynamic> c) => c['condition_id'] as String?)
      .whereType<String>()
      .toSet();

  Set<String> get emergencyConditionIds => conditions
      .where((Map<String, dynamic> c) => c['urgency_default'] == 'emergency')
      .map((Map<String, dynamic> c) => c['condition_id'] as String?)
      .whereType<String>()
      .toSet();
}

const String kKbVersion = '2.4';
const String kRulesVersion = '2.2';
const String kTokenDictVersion = '1.1';

const String _kbHash =
    '6c00d8257f8417e86bd5e237630bf8a4623ad72e2e46b1b071dd447c067cec2b';
const String _rulesHash =
    '1d27e854cba95b179577a88f92445400f494a7fe8e6a53a60fcaa98b3870d1c4';
const String _tokenDictHash =
    '0cc47ad9537c0bd4c6ef3aec8f1931eb9b4c62103a8809d16544f94a90b5c019';

const String _fixtureDir = 'test/fixtures/artifacts';

Map<String, dynamic> _readVerified(String fileName, String expectedHash) {
  final File file = File('$_fixtureDir/$fileName');
  if (!file.existsSync()) {
    throw StateError('Missing pinned artifact fixture: ${file.path}');
  }

  final String raw = file.readAsStringSync();
  final String actualHash = sha256.convert(utf8.encode(raw)).toString();
  if (actualHash != expectedHash) {
    throw StateError(
      'Integrity check failed for $fileName — expected $expectedHash, '
      'got $actualHash. The fixture does not match the artifact /config '
      'published; refresh the fixture and hash together, then re-run.',
    );
  }

  return Map<String, dynamic>.from(jsonDecode(raw) as Map);
}

List<Map<String, dynamic>> _listUnder(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map<dynamic, dynamic>>()
      .map(Map<String, dynamic>.from)
      .toList();
}

PinnedArtifacts loadPinnedArtifacts() {
  final Map<String, dynamic> kb = _readVerified(
    'kb.ng.v$kKbVersion.json',
    _kbHash,
  );
  final Map<String, dynamic> rules = _readVerified(
    'rules.ng.v$kRulesVersion.json',
    _rulesHash,
  );
  final Map<String, dynamic> tokenDict = _readVerified(
    'token_dictionary.ng.v$kTokenDictVersion.json',
    _tokenDictHash,
  );

  return PinnedArtifacts(
    conditions: _listUnder(kb, 'conditions'),
    rules: _listUnder(rules, 'rules'),
    tokenDictionary: tokenDict,
    // Shaped exactly like the `/config` payload OutputFormatter reads, so
    // artifactsUsed in the engine output reflects the real versions.
    configMetadata: <String, dynamic>{
      'artifacts': <String, dynamic>{
        'knowledge_base': <String, dynamic>{'version': kKbVersion},
        'rules': <String, dynamic>{'version': kRulesVersion},
        'token_dictionary': <String, dynamic>{'version': kTokenDictVersion},
      },
    },
  );
}
