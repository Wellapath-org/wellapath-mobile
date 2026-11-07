/// Data-safety guard: Community never sends assessment data (contract §0.1,
/// §5). The server rejects these keys with 400 `prohibited_key`; the client
/// refuses to send them at all, so an attempt never leaves the device.
///
/// This is the **only** Community file allowed to spell these words: the
/// isolation test exempts it from the clinical-identifier scan, and checks
/// that it holds nothing but this guard.
library;

import '../domain/community_error.dart';

/// §5, verbatim: matched case-insensitively against every key name.
final RegExp kProhibitedKeyPattern = RegExp(
  r'(symptom|triage|assessment|urgency|red_?flag|diagnos|differential|'
  r'condition_id|care_recommendation|engine_version|artifact_version|'
  r'answers?$)',
  caseSensitive: false,
);

/// §5 reference list (must be covered by contract tests on both sides).
const List<String> kProhibitedReferenceKeys = <String>[
  'symptoms',
  'symptom_ids',
  'answers',
  'assessment',
  'assessment_id',
  'assessment_result',
  'assessment_history',
  'triage',
  'triage_result',
  'triage_level',
  'urgency',
  'urgency_level',
  'red_flags',
  'red_flag',
  'diagnosis',
  'differential',
  'condition_ids',
  'care_recommendation',
  'engine_version',
  'artifact_version',
];

bool isProhibitedKey(String key) => kProhibitedKeyPattern.hasMatch(key);

/// Throws [ProhibitedPayloadException] if [body] (at any depth) or [query]
/// carries a prohibited key. The value is never read or echoed.
void assertNoProhibitedKeys({Object? body, Map<String, dynamic>? query}) {
  if (query != null) {
    for (final String key in query.keys) {
      if (isProhibitedKey(key)) throw ProhibitedPayloadException('query.$key');
    }
  }
  _scan(body, 'body');
}

void _scan(Object? node, String path) {
  if (node is Map) {
    for (final MapEntry<dynamic, dynamic> e in node.entries) {
      final String key = '${e.key}';
      final String here = '$path.$key';
      if (isProhibitedKey(key)) throw ProhibitedPayloadException(here);
      _scan(e.value, here);
    }
  } else if (node is Iterable) {
    int i = 0;
    for (final Object? v in node) {
      _scan(v, '$path[${i++}]');
    }
  }
}
