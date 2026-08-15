/// Strict, offline loader for a schema-2.0 token dictionary.
///
/// Reads local bytes only. There is no URL, no client and no import of the
/// networking layer in this file — a v2 vocabulary cannot be fetched, and a
/// search can never reach the network, because there is nothing here to reach
/// it with.
///
/// ## Fails closed
///
/// Every validation failure returns a typed [VocabularyLoadFailure]. The loader
/// never returns partially-populated v2 data, and it never mutates or replaces
/// the live v1.1 path — the caller keeps whatever it already had. A malformed
/// candidate degrades to "no candidate", never to "half a candidate".
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'vocabulary_normalizer.dart';
import 'vocabulary_v2.dart';

/// The major schema version this loader was written and reviewed against.
///
/// A different major version is refused rather than best-effort parsed: schema
/// 3.0 could move clinical identity somewhere this code does not look.
const int kSupportedSchemaMajor = 2;

/// Why a load failed.
enum VocabularyLoadError {
  malformedJson,
  notAnObject,
  missingMetadata,
  unsupportedSchemaVersion,
  missingTokens,
  malformedToken,
  duplicateTokenId,
  malformedTokenId,
  duplicateNormalizedForm,
  invalidAlias,
  searchNotMarkedSearchOnly,
  invalidEnumValue,
  invalidAmbiguityStructure,
  missingSearchIndex,
  normalizationVersionMismatch,
  staleSearchIndex,
  unresolvedReference,
  legacyArrayMismatch,
  publicationClaimWithoutReview,
}

/// A typed load failure. Carries enough detail to diagnose without leaking the
/// artifact's contents into logs.
@immutable
class VocabularyLoadFailure implements Exception {
  const VocabularyLoadFailure(this.error, this.message, {this.tokenId});

  final VocabularyLoadError error;
  final String message;

  /// The offending token, where the failure is attributable to one.
  final String? tokenId;

  @override
  String toString() =>
      'VocabularyLoadFailure(${error.name}${tokenId == null ? '' : ', $tokenId'}): '
      '$message';
}

/// The outcome of a load: either a vocabulary or a typed failure, never both.
@immutable
class VocabularyLoadResult {
  const VocabularyLoadResult._(this.vocabulary, this.failure);

  factory VocabularyLoadResult.success(VocabularyV2 vocabulary) =>
      VocabularyLoadResult._(vocabulary, null);

  factory VocabularyLoadResult.failure(VocabularyLoadFailure failure) =>
      VocabularyLoadResult._(null, failure);

  final VocabularyV2? vocabulary;
  final VocabularyLoadFailure? failure;

  bool get isSuccess => vocabulary != null;
}

const Set<String> _validStatuses = <String>{'active', 'deprecated'};
const Set<String> _validLabelReviewStatuses = <String>{
  'approved',
  'unreviewed',
  'not_reviewed',
  'rejected',
};

final RegExp _tokenIdPattern = RegExp(r'^[a-z0-9]+(_[a-z0-9]+)*$');

/// Parses and validates a schema-2.0 vocabulary from raw bytes.
///
/// [bytes] comes from an asset, a test fixture or local storage. Nothing in
/// this function performs I/O.
VocabularyLoadResult loadVocabularyV2FromBytes(List<int> bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object catch (e) {
    return VocabularyLoadResult.failure(
      VocabularyLoadFailure(
        VocabularyLoadError.malformedJson,
        'Vocabulary is not valid JSON: $e',
      ),
    );
  }

  if (decoded is! Map<String, dynamic>) {
    return VocabularyLoadResult.failure(
      const VocabularyLoadFailure(
        VocabularyLoadError.notAnObject,
        'Vocabulary must be a JSON object.',
      ),
    );
  }

  return _validate(decoded);
}

/// Convenience wrapper for a UTF-8 string.
VocabularyLoadResult loadVocabularyV2FromString(String raw) =>
    loadVocabularyV2FromBytes(utf8.encode(raw));

VocabularyLoadResult _fail(
  VocabularyLoadError error,
  String message, {
  String? tokenId,
}) => VocabularyLoadResult.failure(
  VocabularyLoadFailure(error, message, tokenId: tokenId),
);

/// Top-level keys a schema-2.0 vocabulary may carry. Anything else means the
/// document is not the shape this consumer was reviewed against.
const Set<String> _allowedTopLevelKeys = <String>{
  '_metadata',
  'symptom_tokens',
  'red_flag_tokens',
  'duration_tokens',
  'body_area_tokens',
  'demographic_tokens',
  'severity_tokens',
  'body_areas',
  'complaint_groups',
  'tokens',
  'search_index',
};

bool _isBlank(Object? v) => v == null || (v is String && v.trim().isEmpty);

VocabularyLoadResult _validate(Map<String, dynamic> json) {
  // ── no unknown top-level keys ───────────────────────────────────────────
  final Set<String> unknownKeys = json.keys.toSet().difference(
    _allowedTopLevelKeys,
  );
  if (unknownKeys.isNotEmpty) {
    return _fail(
      VocabularyLoadError.malformedToken,
      'Vocabulary carries unknown top-level key(s): '
      '${(unknownKeys.toList()..sort()).join(', ')}. An unrecognised key may '
      'be clinical data this consumer would silently ignore.',
    );
  }

  // ── metadata ────────────────────────────────────────────────────────────
  final Object? rawMeta = json['_metadata'];
  if (rawMeta is! Map<String, dynamic>) {
    return _fail(
      VocabularyLoadError.missingMetadata,
      'Vocabulary is missing "_metadata".',
    );
  }

  final String schemaVersion = rawMeta['schema_version'] as String? ?? '';
  final int? major = int.tryParse(schemaVersion.split('.').first);
  if (major != kSupportedSchemaMajor) {
    return _fail(
      VocabularyLoadError.unsupportedSchemaVersion,
      'Unsupported schema version "$schemaVersion". This consumer was '
      'reviewed against major version $kSupportedSchemaMajor; a different '
      'major version may place clinical identity somewhere it does not look.',
    );
  }

  final Object? review = rawMeta['clinical_review'];
  final String reviewStatus = review is Map<String, dynamic>
      ? (review['status'] as String? ?? 'not_reviewed')
      : 'not_reviewed';
  final String releaseStatus = rawMeta['release_status'] as String? ?? '';
  final Object? mayPublishRaw = rawMeta['may_publish'];
  final bool? mayPublish = mayPublishRaw is bool ? mayPublishRaw : null;

  // An artifact that claims publishability while unreviewed is refused: the
  // one combination that must never load is "ship me" plus "nobody checked".
  if ((mayPublish == true || releaseStatus == 'published') &&
      reviewStatus != 'approved') {
    return _fail(
      VocabularyLoadError.publicationClaimWithoutReview,
      'Vocabulary claims publication (release_status="$releaseStatus", '
      'may_publish=$mayPublish) without an approved clinical review '
      '(status="$reviewStatus").',
    );
  }

  // A review claim must be backed by a reviewer, a date and evidence. A bare
  // status string asserting "reviewed" is exactly the claim that must not be
  // taken at face value.
  if (review is Map<String, dynamic> &&
      reviewStatus != 'not_reviewed' &&
      reviewStatus.isNotEmpty) {
    final List<String> missing = <String>[
      if (_isBlank(review['reviewer'])) 'reviewer',
      if (_isBlank(review['review_date'])) 'review_date',
      if (_isBlank(review['evidence'])) 'evidence',
    ];
    if (missing.isNotEmpty) {
      return _fail(
        VocabularyLoadError.publicationClaimWithoutReview,
        'Vocabulary claims clinical_review.status="$reviewStatus" but is '
        'missing ${missing.join(', ')}. A review claim must be backed by '
        'evidence, not asserted by a status field.',
      );
    }
  }

  final VocabularyMetadata metadata = VocabularyMetadata(
    artifactId: rawMeta['artifact_id'] as String? ?? '',
    version: rawMeta['version'] as String? ?? '',
    schemaVersion: schemaVersion,
    releaseStatus: releaseStatus,
    mayPublish: mayPublish,
    clinicalReviewStatus: reviewStatus,
    totalTokens: rawMeta['total_tokens'] as int? ?? -1,
    country: rawMeta['country'] as String? ?? '',
  );

  // ── tokens ──────────────────────────────────────────────────────────────
  final Object? rawTokens = json['tokens'];
  if (rawTokens is! List) {
    return _fail(
      VocabularyLoadError.missingTokens,
      'Vocabulary is missing its "tokens" list.',
    );
  }

  final List<VocabularyToken> tokens = <VocabularyToken>[];
  final Set<String> seenIds = <String>{};
  final Map<String, String> canonicalNormalizedOwner = <String, String>{};

  for (final Object? entry in rawTokens) {
    if (entry is! Map<String, dynamic>) {
      return _fail(
        VocabularyLoadError.malformedToken,
        'A token entry is not an object.',
      );
    }

    final Object? rawId = entry['token_id'];
    if (rawId is! String || rawId.isEmpty) {
      return _fail(
        VocabularyLoadError.malformedTokenId,
        'A token entry has a missing or non-string token_id.',
      );
    }
    if (!_tokenIdPattern.hasMatch(rawId)) {
      return _fail(
        VocabularyLoadError.malformedTokenId,
        'Token id "$rawId" is not lowercase_snake_case.',
        tokenId: rawId,
      );
    }
    if (!seenIds.add(rawId)) {
      return _fail(
        VocabularyLoadError.duplicateTokenId,
        'Token id "$rawId" appears more than once. Clinical identity must be '
        'unique.',
        tokenId: rawId,
      );
    }

    final Object? identity = entry['clinical_identity'];
    if (identity is! Map<String, dynamic>) {
      return _fail(
        VocabularyLoadError.malformedToken,
        'Token "$rawId" is missing clinical_identity.',
        tokenId: rawId,
      );
    }

    final String status = identity['status'] as String? ?? '';
    if (!_validStatuses.contains(status)) {
      return _fail(
        VocabularyLoadError.invalidEnumValue,
        'Token "$rawId" has status "$status", expected one of '
        '${_validStatuses.join(', ')}.',
        tokenId: rawId,
      );
    }

    final String? replacedBy = identity['replaced_by'] as String?;
    if (status == 'deprecated' && (replacedBy == null || replacedBy.isEmpty)) {
      return _fail(
        VocabularyLoadError.unresolvedReference,
        'Token "$rawId" is deprecated but names no replacement.',
        tokenId: rawId,
      );
    }

    final Object? display = entry['display'];
    if (display is! Map<String, dynamic>) {
      return _fail(
        VocabularyLoadError.malformedToken,
        'Token "$rawId" is missing display.',
        tokenId: rawId,
      );
    }
    final Object? canonicalLabel = display['canonical_label'];
    if (canonicalLabel is! String || canonicalLabel.isEmpty) {
      return _fail(
        VocabularyLoadError.malformedToken,
        'Token "$rawId" has no canonical_label.',
        tokenId: rawId,
      );
    }
    final String labelReviewStatus =
        display['label_review_status'] as String? ?? '';
    if (!_validLabelReviewStatuses.contains(labelReviewStatus)) {
      return _fail(
        VocabularyLoadError.invalidEnumValue,
        'Token "$rawId" has label_review_status "$labelReviewStatus".',
        tokenId: rawId,
      );
    }
    final bool displaySafe = display['display_safe'] as bool? ?? false;
    if (displaySafe && labelReviewStatus != 'approved') {
      return _fail(
        VocabularyLoadError.invalidEnumValue,
        'Token "$rawId" is display_safe but its label is not approved. A '
        'label cannot be shown to a user on the strength of a flag alone.',
        tokenId: rawId,
      );
    }

    final Object? search = entry['search'];
    if (search is! Map<String, dynamic>) {
      return _fail(
        VocabularyLoadError.malformedToken,
        'Token "$rawId" is missing search.',
        tokenId: rawId,
      );
    }

    final String normalizedForm = search['normalized_form'] as String? ?? '';
    final String expectedForm = normalizeTokenId(rawId);
    if (normalizedForm != expectedForm) {
      return _fail(
        VocabularyLoadError.staleSearchIndex,
        'Token "$rawId" declares normalized_form "$normalizedForm" but the '
        'contract pipeline produces "$expectedForm". The artifact was '
        'generated by a different normalizer.',
        tokenId: rawId,
      );
    }

    // A vocabulary that does not assert its search block is search-only is
    // refused rather than trusted to behave.
    final bool searchOnly = search['search_only'] as bool? ?? false;
    if (!searchOnly) {
      return _fail(
        VocabularyLoadError.searchNotMarkedSearchOnly,
        'Token "$rawId" does not declare search.search_only. Aliases and '
        'search metadata must be explicitly non-clinical.',
        tokenId: rawId,
      );
    }

    final Object? rawAliases = search['aliases'];
    if (rawAliases is! List) {
      return _fail(
        VocabularyLoadError.invalidAlias,
        'Token "$rawId" has a non-list aliases field.',
        tokenId: rawId,
      );
    }
    final List<String> aliases = <String>[];
    final Set<String> seenAliasForms = <String>{};
    for (final Object? a in rawAliases) {
      if (a is! String || a.isEmpty) {
        return _fail(
          VocabularyLoadError.invalidAlias,
          'Token "$rawId" has a non-string or empty alias.',
          tokenId: rawId,
        );
      }
      // Own-canonical is an **exact** comparison, and duplicate-within-entry
      // is a **normalized** one. That asymmetry is the contract, not an
      // oversight: `FROBNITZ!` is a legitimate alias of `frobnitz` even though
      // it normalizes to the canonical form, because a user may well type it
      // that way. What is redundant is repeating the label verbatim.
      if (a == canonicalLabel || a == rawId) {
        return _fail(
          VocabularyLoadError.invalidAlias,
          'Token "$rawId" lists an alias identical to its own canonical form.',
          tokenId: rawId,
        );
      }
      final String aliasForm = normalizeVocabularyQuery(a);
      if (!seenAliasForms.add(aliasForm)) {
        return _fail(
          VocabularyLoadError.invalidAlias,
          'Token "$rawId" lists duplicate aliases after normalization.',
          tokenId: rawId,
        );
      }
      aliases.add(a);
    }

    if (canonicalNormalizedOwner.containsKey(expectedForm)) {
      return _fail(
        VocabularyLoadError.duplicateNormalizedForm,
        'Tokens "${canonicalNormalizedOwner[expectedForm]}" and "$rawId" share '
        'the normalized canonical form "$expectedForm".',
        tokenId: rawId,
      );
    }
    canonicalNormalizedOwner[expectedForm] = rawId;

    // Every entry must say where it came from. A token with no provenance
    // cannot be traced back to a source or a reviewer.
    final Object? reviewBlock = entry['review'];
    if (reviewBlock is! Map<String, dynamic> ||
        _isBlank(reviewBlock['provenance'])) {
      return _fail(
        VocabularyLoadError.malformedToken,
        'Token "$rawId" has no provenance. Every entry must record where it '
        'came from.',
        tokenId: rawId,
      );
    }

    final Object? assoc = entry['associations'];
    final Map<String, dynamic> associations = assoc is Map<String, dynamic>
        ? assoc
        : const <String, dynamic>{};

    tokens.add(
      VocabularyToken(
        tokenId: rawId,
        category: entry['category'] as String? ?? '',
        status: status,
        replacedBy: replacedBy,
        scoringEligible: identity['scoring_eligible'] as bool? ?? false,
        display: TokenDisplay(
          canonicalLabel: canonicalLabel,
          labelSource: display['label_source'] as String? ?? '',
          labelReviewStatus: labelReviewStatus,
          displaySafe: displaySafe,
          locale: display['locale'] as String? ?? '',
        ),
        search: TokenSearch(
          normalizedForm: normalizedForm,
          aliases: List<String>.unmodifiable(aliases),
          searchOnly: searchOnly,
        ),
        associations: TokenAssociations(
          bodyAreas: _stringList(associations['body_areas']),
          complaintGroups: _stringList(associations['complaint_groups']),
          severityDescriptors: _stringList(
            associations['severity_descriptors'],
          ),
          durationDescriptors: _stringList(
            associations['duration_descriptors'],
          ),
        ),
      ),
    );
  }

  // ── an alias must not shadow another token's canonical form ─────────────
  //
  // Needs the full canonical set, so it runs after the token loop. Note this
  // is narrower than "collides with anything": two tokens whose *labels*
  // normalize alike are a legitimate ambiguity the resolver reports. What is
  // forbidden is an alias reaching across and claiming a different token's
  // canonical identity, which would let search-only data override clinical
  // identity.
  for (final VocabularyToken t in tokens) {
    for (final String alias in t.search.aliases) {
      final String form = normalizeVocabularyQuery(alias);
      final String? owner = canonicalNormalizedOwner[form];
      if (owner != null && owner != t.tokenId) {
        return _fail(
          VocabularyLoadError.invalidAlias,
          'Token "${t.tokenId}" lists an alias that shadows the canonical form '
          'of "$owner".',
          tokenId: t.tokenId,
        );
      }
    }
  }

  // ── replacement links resolve, and do not cycle ─────────────────────────
  for (final VocabularyToken t in tokens) {
    final String? target = t.replacedBy;
    if (target == null) continue;
    if (!seenIds.contains(target)) {
      return _fail(
        VocabularyLoadError.unresolvedReference,
        'Token "${t.tokenId}" is replaced by "$target", which does not exist.',
        tokenId: t.tokenId,
      );
    }
  }
  final VocabularyLoadResult? cycle = _detectReplacementCycle(tokens);
  if (cycle != null) return cycle;

  // ── body area / complaint group references resolve ──────────────────────
  final List<String> bodyAreas = _idList(json['body_areas']);
  final List<String> complaintGroups = _idList(json['complaint_groups']);
  final Set<String> bodyAreaSet = bodyAreas.toSet();
  final Set<String> complaintGroupSet = complaintGroups.toSet();

  for (final VocabularyToken t in tokens) {
    for (final String a in t.associations.bodyAreas) {
      if (!bodyAreaSet.contains(a)) {
        return _fail(
          VocabularyLoadError.unresolvedReference,
          'Token "${t.tokenId}" references unknown body area "$a".',
          tokenId: t.tokenId,
        );
      }
    }
    for (final String g in t.associations.complaintGroups) {
      if (!complaintGroupSet.contains(g)) {
        return _fail(
          VocabularyLoadError.unresolvedReference,
          'Token "${t.tokenId}" references unknown complaint group "$g".',
          tokenId: t.tokenId,
        );
      }
    }
  }

  // ── legacy arrays describe the same set, in the same order ──────────────
  final Map<String, List<String>> legacyArrays = <String, List<String>>{};
  for (final String key in json.keys) {
    if (!key.endsWith('_tokens')) continue;
    final List<String> values = _stringList(json[key]);
    legacyArrays[key] = List<String>.unmodifiable(values);
  }

  final List<String> legacyUnion = <String>[
    for (final List<String> v in legacyArrays.values) ...v,
  ];
  if (legacyUnion.toSet().length != seenIds.length ||
      !legacyUnion.toSet().containsAll(seenIds)) {
    return _fail(
      VocabularyLoadError.legacyArrayMismatch,
      'The legacy clinical arrays (${legacyUnion.toSet().length} ids) and the '
      'tokens list (${seenIds.length} ids) describe different sets.',
    );
  }

  // Entry order must reproduce legacy array order, which is what lets v1.1 be
  // reconstructed byte-for-byte.
  //
  // Compared **per array**, on the relative order of that array's members
  // within `tokens[]` — not by concatenating the arrays. The categories are
  // not required to appear as contiguous blocks in entry order, and in the
  // synthetic fixture they do not.
  final List<String> tokenOrder = tokens
      .map((VocabularyToken t) => t.tokenId)
      .toList();
  for (final MapEntry<String, List<String>> e in legacyArrays.entries) {
    final Set<String> members = e.value.toSet();
    final List<String> relative = tokenOrder.where(members.contains).toList();
    if (!listEquals(relative, e.value)) {
      return _fail(
        VocabularyLoadError.legacyArrayMismatch,
        'Token entry order does not reproduce the order of legacy array '
        '"${e.key}". Reconstructing token dictionary 1.1 byte-for-byte '
        'depends on this order.',
      );
    }
  }

  // ── search index ────────────────────────────────────────────────────────
  final Object? rawIndex = json['search_index'];
  if (rawIndex is! Map<String, dynamic>) {
    return _fail(
      VocabularyLoadError.missingSearchIndex,
      'Vocabulary is missing "search_index".',
    );
  }

  final String indexNormVersion =
      rawIndex['normalization_version'] as String? ?? '';
  if (indexNormVersion != kNormalizationVersion) {
    return _fail(
      VocabularyLoadError.normalizationVersionMismatch,
      'Artifact search_index was generated by normalization version '
      '"$indexNormVersion" but this consumer implements '
      '"$kNormalizationVersion". Searching one with the other would silently '
      'change which token a query resolves to.',
    );
  }

  final Object? rawForms = rawIndex['normalized_forms'];
  if (rawForms is! Map<String, dynamic>) {
    return _fail(
      VocabularyLoadError.missingSearchIndex,
      'search_index is missing "normalized_forms".',
    );
  }

  final Map<String, List<String>> normalizedForms = <String, List<String>>{};
  for (final MapEntry<String, dynamic> e in rawForms.entries) {
    final List<String> ids = _stringList(e.value);
    for (final String id in ids) {
      if (!seenIds.contains(id)) {
        return _fail(
          VocabularyLoadError.staleSearchIndex,
          'search_index maps "${e.key}" to unknown token "$id".',
        );
      }
    }
    // The index key must itself be a normalized string, or a query could never
    // reach it.
    if (normalizeVocabularyQuery(e.key) != e.key) {
      return _fail(
        VocabularyLoadError.staleSearchIndex,
        'search_index key "${e.key}" is not in normalized form.',
      );
    }
    normalizedForms[e.key] = List<String>.unmodifiable(ids);
  }

  // Every token's own canonical form must be reachable.
  for (final VocabularyToken t in tokens) {
    final List<String>? owners = normalizedForms[t.search.normalizedForm];
    if (owners == null || !owners.contains(t.tokenId)) {
      return _fail(
        VocabularyLoadError.staleSearchIndex,
        'search_index does not reach token "${t.tokenId}" through its own '
        'normalized form "${t.search.normalizedForm}".',
        tokenId: t.tokenId,
      );
    }
  }

  return VocabularyLoadResult.success(
    VocabularyV2(
      metadata: metadata,
      tokens: List<VocabularyToken>.unmodifiable(tokens),
      bodyAreas: List<String>.unmodifiable(bodyAreas),
      complaintGroups: List<String>.unmodifiable(complaintGroups),
      legacyArrays: Map<String, List<String>>.unmodifiable(legacyArrays),
      normalizedForms: Map<String, List<String>>.unmodifiable(normalizedForms),
      normalizationVersion: indexNormVersion,
      resolverVersion: rawIndex['resolver_version'] as String? ?? '',
    ),
  );
}

VocabularyLoadResult? _detectReplacementCycle(List<VocabularyToken> tokens) {
  final Map<String, String?> next = <String, String?>{
    for (final VocabularyToken t in tokens) t.tokenId: t.replacedBy,
  };

  for (final String start in next.keys) {
    final Set<String> path = <String>{start};
    String? cursor = next[start];
    while (cursor != null) {
      if (!path.add(cursor)) {
        return _fail(
          VocabularyLoadError.unresolvedReference,
          'Replacement chain from "$start" cycles at "$cursor".',
          tokenId: start,
        );
      }
      cursor = next[cursor];
    }
  }
  return null;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList();
}

/// Body areas and complaint groups may ship as bare ids or as objects with an
/// `id`/`body_area_id` field; both shapes are read the same way.
List<String> _idList(Object? value) {
  if (value is! List) return const <String>[];
  final List<String> out = <String>[];
  for (final Object? e in value) {
    if (e is String) {
      out.add(e);
    } else if (e is Map<String, dynamic>) {
      final Object? id =
          e['id'] ?? e['body_area_id'] ?? e['complaint_group_id'];
      if (id is String) out.add(id);
    }
  }
  return out;
}
