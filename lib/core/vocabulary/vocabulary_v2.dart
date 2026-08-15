/// Immutable in-memory model for a schema-2.0 token dictionary, plus the
/// canonical-token type boundary.
///
/// The type that matters here is [CanonicalTokenId]. It cannot be constructed
/// from arbitrary text — only [VocabularyV2.canonicalTokenId] and the resolver
/// can mint one, and both refuse anything that is not a token in the loaded
/// vocabulary. That is what makes "an alias can never become a scoring token"
/// a property of the type system rather than a code-review promise.
library;

import 'package:flutter/foundation.dart';

/// A token id that is known to exist in a loaded vocabulary.
///
/// The constructor is private, so there is no expression anywhere in the app
/// that turns a raw query, an alias, a body-area label or any other string
/// into one of these without going through a vocabulary that contains it.
@immutable
class CanonicalTokenId {
  const CanonicalTokenId._(this.value);

  /// The `lowercase_snake_case` token id, e.g. `chest_pain`.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is CanonicalTokenId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// How a query reached the token it resolved to.
enum VocabularyMatchStatus {
  /// The raw query is a token id, byte for byte.
  exactCanonical,

  /// The raw query is an approved alias, byte for byte, and unique.
  exactAlias,

  /// The query matched only after normalization.
  normalized,

  /// The query maps to more than one clinical token. **Never auto-resolved.**
  ambiguous,

  /// Nothing matched.
  noMatch,
}

String vocabularyMatchStatusName(VocabularyMatchStatus s) => switch (s) {
  VocabularyMatchStatus.exactCanonical => 'exact_canonical',
  VocabularyMatchStatus.exactAlias => 'exact_alias',
  VocabularyMatchStatus.normalized => 'normalized',
  VocabularyMatchStatus.ambiguous => 'ambiguous',
  VocabularyMatchStatus.noMatch => 'no_match',
};

/// Display metadata. Read-only, and gated on [displaySafe].
@immutable
class TokenDisplay {
  const TokenDisplay({
    required this.canonicalLabel,
    required this.labelSource,
    required this.labelReviewStatus,
    required this.displaySafe,
    required this.locale,
  });

  final String canonicalLabel;
  final String labelSource;
  final String labelReviewStatus;

  /// False on every token in the current candidate. While false the label is
  /// **not** approved clinical UI content and must not be shown to a user.
  final bool displaySafe;

  final String locale;
}

/// Search-side metadata. Never a scoring input.
@immutable
class TokenSearch {
  const TokenSearch({
    required this.normalizedForm,
    required this.aliases,
    required this.searchOnly,
  });

  final String normalizedForm;
  final List<String> aliases;

  /// The artifact's own assertion that this block is search-only. The loader
  /// requires it to be true — a vocabulary claiming its aliases are anything
  /// other than search metadata is rejected rather than trusted.
  final bool searchOnly;
}

/// Body area, complaint group, severity and duration associations.
///
/// These are **search and filter metadata only**. Nothing in this class is
/// ever converted into a scoring token; see `vocabulary_search.dart`, which
/// returns [CanonicalTokenId]s and nothing else.
@immutable
class TokenAssociations {
  const TokenAssociations({
    required this.bodyAreas,
    required this.complaintGroups,
    required this.severityDescriptors,
    required this.durationDescriptors,
  });

  final List<String> bodyAreas;
  final List<String> complaintGroups;
  final List<String> severityDescriptors;
  final List<String> durationDescriptors;
}

/// One vocabulary entry.
@immutable
class VocabularyToken {
  const VocabularyToken({
    required this.tokenId,
    required this.category,
    required this.status,
    required this.replacedBy,
    required this.scoringEligible,
    required this.display,
    required this.search,
    required this.associations,
  });

  final String tokenId;
  final String category;

  /// `active` or `deprecated`.
  final String status;
  final String? replacedBy;

  /// The artifact's own flag. Note this is *not* what makes a token usable for
  /// scoring in Mobile — the live v1.1 dictionary is still the scoring
  /// authority. It is carried so a future activation can honour it.
  final bool scoringEligible;

  final TokenDisplay display;
  final TokenSearch search;
  final TokenAssociations associations;
}

/// Metadata block, including the publication state this consumer refuses to
/// ignore.
@immutable
class VocabularyMetadata {
  const VocabularyMetadata({
    required this.artifactId,
    required this.version,
    required this.schemaVersion,
    required this.releaseStatus,
    required this.mayPublish,
    required this.clinicalReviewStatus,
    required this.totalTokens,
    required this.country,
  });

  final String artifactId;
  final String version;
  final String schemaVersion;

  /// `candidate_unapproved` for the current candidate.
  final String releaseStatus;

  /// Null in the current candidate — absence is *not* permission. The
  /// contract guard treats anything other than an explicit `false` or absent
  /// as a change requiring review.
  final bool? mayPublish;

  final String clinicalReviewStatus;
  final int totalTokens;
  final String country;

  bool get isCandidateUnapproved => releaseStatus == 'candidate_unapproved';
  bool get isClinicallyReviewed => clinicalReviewStatus == 'approved';

  /// True only if the artifact positively claims it may be published.
  bool get claimsPublishable => mayPublish == true;
}

/// A fully validated, immutable schema-2.0 vocabulary.
@immutable
class VocabularyV2 {
  VocabularyV2({
    required this.metadata,
    required this.tokens,
    required this.bodyAreas,
    required this.complaintGroups,
    required this.legacyArrays,
    required this.normalizedForms,
    required this.normalizationVersion,
    required this.resolverVersion,
  }) : _byId = <String, VocabularyToken>{
         for (final VocabularyToken t in tokens) t.tokenId: t,
       };

  final VocabularyMetadata metadata;
  final List<VocabularyToken> tokens;
  final List<String> bodyAreas;
  final List<String> complaintGroups;

  /// The frozen legacy clinical arrays, e.g. `symptom_tokens`, in artifact
  /// order. These are what reconstruct token dictionary 1.1.
  final Map<String, List<String>> legacyArrays;

  /// `search_index.normalized_forms` as shipped: normalized string → the
  /// token ids it reaches, **in artifact order**. Consumed rather than rebuilt,
  /// so candidate ordering is authoritative and cannot drift here.
  final Map<String, List<String>> normalizedForms;

  final String normalizationVersion;
  final String resolverVersion;

  final Map<String, VocabularyToken> _byId;

  Set<String> get tokenIds => _byId.keys.toSet();

  VocabularyToken? token(String tokenId) => _byId[tokenId];

  /// The only public way to mint a [CanonicalTokenId].
  ///
  /// Returns null for anything that is not a token in this vocabulary — a raw
  /// query, a normalized query, an alias, a body-area label, a severity label
  /// or an unknown id all return null rather than a usable identity.
  CanonicalTokenId? canonicalTokenId(String candidate) {
    if (!_byId.containsKey(candidate)) return null;
    return CanonicalTokenId._(candidate);
  }
}
