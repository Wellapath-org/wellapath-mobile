/// Offline search index and resolver over a loaded schema-2.0 vocabulary.
///
/// Implements `docs/VOCABULARY_AMBIGUITY_SPEC.md` and the resolver half of
/// `docs/VOCABULARY_NORMALIZATION_SPEC.md`.
///
/// ## The two rules that matter
///
/// 1. **Matching is whole-string equality.** There is no substring, prefix,
///    edit-distance, stemming or semantic step anywhere in this file. `feve`
///    does not reach `fever`, and `no fever` resolves to nothing.
/// 2. **Ambiguity is reported, never guessed.** When a query reaches more than
///    one clinical token the resolver returns `ambiguous` with a null resolved
///    token. It never picks one.
///
/// Resolution order, highest precedence first:
///
/// | Order | Match                                   | Status            |
/// |-------|-----------------------------------------|-------------------|
/// | 1     | raw query is a token id, byte for byte  | `exact_canonical` |
/// | 2     | raw query is an alias, byte for byte    | `exact_alias`     |
/// | 3     | normalized query hits the search index  | `normalized`      |
/// | —     | 2 or 3 reaching >1 token                | `ambiguous`       |
/// | —     | nothing                                 | `no_match`        |
///
/// The exact-id rule sits above the others so a token whose id collides with
/// another token's label still resolves to itself when typed exactly.
///
/// Candidate ordering comes from the artifact's own
/// `search_index.normalized_forms`, which is consumed rather than rebuilt, so
/// the order this returns is the order the knowledge base generated.
///
/// Nothing here performs I/O. A query cannot leave the device because there is
/// no client in this file to carry it.
library;

import 'package:flutter/foundation.dart';

import 'vocabulary_normalizer.dart';
import 'vocabulary_v2.dart';

/// The outcome of resolving one query.
@immutable
class VocabularyResolution {
  const VocabularyResolution({
    required this.query,
    required this.queryNormalized,
    required this.status,
    required this.resolvedTokenId,
    required this.candidateTokenIds,
    required this.matchSource,
  });

  final String query;
  final String queryNormalized;
  final VocabularyMatchStatus status;

  /// **Null on `ambiguous` and `no_match`.** A caller cannot obtain a token
  /// identity from an unresolved query even by ignoring [status], because
  /// there is no [CanonicalTokenId] here to take.
  final CanonicalTokenId? resolvedTokenId;

  /// Every token the query reached, in artifact order. Populated on
  /// `ambiguous` so a picker can offer a disambiguation choice — offering is
  /// the user's decision, not the resolver's.
  final List<CanonicalTokenId> candidateTokenIds;

  /// `canonical_label`, `token_id`, `alias`, or null when nothing matched.
  final String? matchSource;

  /// Whether this resolution may contribute a scoring token. True only when a
  /// single canonical token was identified.
  bool get scoringEligible => resolvedTokenId != null;

  bool get isAmbiguous => status == VocabularyMatchStatus.ambiguous;

  Map<String, Object?> toJson() => <String, Object?>{
    'query': query,
    'query_normalized': queryNormalized,
    'status': vocabularyMatchStatusName(status),
    'resolved_token_id': resolvedTokenId?.value,
    'candidate_token_ids': candidateTokenIds
        .map((CanonicalTokenId c) => c.value)
        .toList(),
    'match_source': matchSource,
    'scoring_eligible': scoringEligible,
  };
}

/// An offline index over canonical ids, canonical normalized forms and
/// approved aliases.
class VocabularySearchIndex {
  VocabularySearchIndex(this.vocabulary)
    : _exactAliasOwners = _buildExactAliasOwners(vocabulary),
      _normalizedAliasOwners = _buildNormalizedAliasOwners(vocabulary);

  final VocabularyV2 vocabulary;

  /// Alias string, byte for byte, to the tokens declaring it (artifact order).
  final Map<String, List<String>> _exactAliasOwners;

  /// Normalized alias form to the tokens declaring it (artifact order).
  final Map<String, List<String>> _normalizedAliasOwners;

  static Map<String, List<String>> _buildExactAliasOwners(VocabularyV2 v) {
    final Map<String, List<String>> out = <String, List<String>>{};
    for (final VocabularyToken t in v.tokens) {
      for (final String alias in t.search.aliases) {
        (out[alias] ??= <String>[]).add(t.tokenId);
      }
    }
    return out;
  }

  static Map<String, List<String>> _buildNormalizedAliasOwners(VocabularyV2 v) {
    final Map<String, List<String>> out = <String, List<String>>{};
    for (final VocabularyToken t in v.tokens) {
      for (final String alias in t.search.aliases) {
        final String form = normalizeVocabularyQuery(alias);
        final List<String> owners = out[form] ??= <String>[];
        if (!owners.contains(t.tokenId)) owners.add(t.tokenId);
      }
    }
    return out;
  }

  /// The number of distinct normalized keys reachable by a query.
  int get indexedFormCount => <String>{
    ...vocabulary.normalizedForms.keys,
    ..._normalizedAliasOwners.keys,
  }.length;

  /// Mints ids through the vocabulary's own validating accessor.
  ///
  /// Deliberately not a privileged shortcut: the resolver has no way to
  /// construct a [CanonicalTokenId] that the vocabulary would reject, so there
  /// is no construction path anywhere in the app that skips membership.
  List<CanonicalTokenId> _mint(List<String> ids) =>
      List<CanonicalTokenId>.unmodifiable(
        ids.map(vocabulary.canonicalTokenId).whereType<CanonicalTokenId>(),
      );

  /// Resolves [query] against this vocabulary.
  ///
  /// Deterministic: the same query against the same vocabulary always returns
  /// the same result, in the same order.
  VocabularyResolution resolve(String query) {
    final String normalized = normalizeVocabularyQuery(query);

    VocabularyResolution build(
      VocabularyMatchStatus status,
      List<String> ids,
      String? source,
    ) {
      final List<CanonicalTokenId> candidates = _mint(ids);
      final bool single =
          candidates.length == 1 && status != VocabularyMatchStatus.ambiguous;
      return VocabularyResolution(
        query: query,
        queryNormalized: normalized,
        status: status,
        resolvedTokenId: single ? candidates.first : null,
        candidateTokenIds: candidates,
        matchSource: source,
      );
    }

    // 1 — the raw query is a token id, byte for byte. Checked first so an id
    // that collides with another token's label still resolves to itself.
    if (vocabulary.token(query) != null) {
      return build(VocabularyMatchStatus.exactCanonical, <String>[
        query,
      ], 'token_id');
    }

    // 2 — the raw query is an approved alias, byte for byte.
    final List<String>? exactAliasOwners = _exactAliasOwners[query];
    if (exactAliasOwners != null && exactAliasOwners.isNotEmpty) {
      final List<String> deduped = _dedupe(exactAliasOwners);
      return build(
        deduped.length == 1
            ? VocabularyMatchStatus.exactAlias
            : VocabularyMatchStatus.ambiguous,
        deduped,
        'alias',
      );
    }

    // An empty normalized query can only be a no-match; it must not be looked
    // up, in case an index ever contains an empty key.
    if (normalized.isEmpty) {
      return build(VocabularyMatchStatus.noMatch, const <String>[], null);
    }

    // 3 — normalized lookup, over canonical forms and normalized aliases.
    // Canonical owners come first so artifact order is preserved, then any
    // alias owners not already present.
    final List<String> canonicalOwners =
        vocabulary.normalizedForms[normalized] ?? const <String>[];
    final List<String> aliasOwners =
        _normalizedAliasOwners[normalized] ?? const <String>[];

    final List<String> merged = _dedupe(<String>[
      ...canonicalOwners,
      ...aliasOwners,
    ]);

    if (merged.isEmpty) {
      return build(VocabularyMatchStatus.noMatch, const <String>[], null);
    }

    final String source = canonicalOwners.isNotEmpty
        ? 'canonical_label'
        : 'alias';

    return build(
      merged.length == 1
          ? VocabularyMatchStatus.normalized
          : VocabularyMatchStatus.ambiguous,
      merged,
      source,
    );
  }

  /// Tokens associated with [bodyAreaId]. Filter metadata only — the return
  /// type is still canonical ids, so filtering cannot introduce a label into
  /// clinical state.
  List<CanonicalTokenId> tokensInBodyArea(String bodyAreaId) => _mint(
    vocabulary.tokens
        .where(
          (VocabularyToken t) => t.associations.bodyAreas.contains(bodyAreaId),
        )
        .map((VocabularyToken t) => t.tokenId)
        .toList(),
  );

  /// Tokens associated with [complaintGroupId]. Filter metadata only.
  List<CanonicalTokenId> tokensInComplaintGroup(String complaintGroupId) =>
      _mint(
        vocabulary.tokens
            .where(
              (VocabularyToken t) =>
                  t.associations.complaintGroups.contains(complaintGroupId),
            )
            .map((VocabularyToken t) => t.tokenId)
            .toList(),
      );

  /// A label safe to show for [id], or null when the vocabulary has not
  /// approved one.
  ///
  /// Every token in the current candidate has `display_safe: false`, so this
  /// returns null for all of them — deliberately. Callers fall back to the
  /// existing approved Mobile display map rather than surfacing an unreviewed
  /// candidate label as clinical UI content.
  String? displaySafeLabel(CanonicalTokenId id) {
    final VocabularyToken? t = vocabulary.token(id.value);
    if (t == null) return null;
    if (!t.display.displaySafe) return null;
    return t.display.canonicalLabel;
  }

  static List<String> _dedupe(List<String> ids) {
    final Set<String> seen = <String>{};
    final List<String> out = <String>[];
    for (final String id in ids) {
      if (seen.add(id)) out.add(id);
    }
    return out;
  }
}
