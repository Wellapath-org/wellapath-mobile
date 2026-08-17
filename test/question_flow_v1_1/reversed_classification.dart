/// Decomposition of live forward-versus-reversed instability, dimension by
/// dimension.
///
/// "The option list differs" is not a finding — it is three possible findings
/// wearing the same words, and they have different reviewers:
///
///   * the same options in a different ORDER is a display decision;
///   * a different SET of options changes what a user can declare;
///   * the same options mapping to different TOKENS changes scoring input.
///
/// Collapsing them would let a scoring-input change be signed off as a wording
/// tweak. Every dimension below is therefore computed separately, and the
/// primary classification names the most severe one that applies.
library;

import 'question_flow_v1_1_clinical_index.dart';

/// One question as the live engine produced it.
class LiveQuestion {
  LiveQuestion({
    required this.role,
    required this.questionText,
    required this.options,
    required this.redFlagToken,
  });

  final String role;
  final String questionText;
  final List<String> options;
  final String? redFlagToken;

  /// The tokens this question's answers can contribute.
  ///
  /// An additional-symptoms option IS its token — the live engine uses the
  /// canonical token id as the option value. A clarifier's Yes branch produces
  /// its red-flag token. Severity and duration produce tokens through the
  /// slider and chips, which the live `FollowupQuestion` does not carry, so
  /// they contribute nothing measurable here and no mapping is invented.
  Map<String, String> get optionToToken {
    if (role == 'additional_symptoms') {
      return <String, String>{for (final String o in options) o: o};
    }
    if (role == 'red_flag_clarifier') {
      return <String, String>{'Yes': redFlagToken!, 'No': ''};
    }
    return const <String, String>{};
  }
}

/// Every dimension a forward/reversed pair can differ in.
///
/// Ordered most severe first. The primary classification is the first one that
/// differs, so a path that changes red-flag reachability is never filed under
/// "option order".
enum DifferenceDimension {
  redFlagReachableTokenSet,
  scoringReachableTokenSet,
  reachableTokenSet,
  optionToTokenSet,
  optionIdSet,
  optionLabelSet,
  questionIdentitySequence,
  questionRoleSequence,
  truncationSet,
  requiredSkipSemantics,
  optionToTokenSequence,
  optionIdSequence,
  optionLabelSequence,
  wording,
}

/// Dimensions whose difference means clinical content, not presentation.
///
/// A difference in any of these can change what a user is able to declare, and
/// therefore what the engine scores. None of them is a display decision.
const Set<DifferenceDimension> kClinicallyMeaningfulDimensions =
    <DifferenceDimension>{
      DifferenceDimension.redFlagReachableTokenSet,
      DifferenceDimension.scoringReachableTokenSet,
      DifferenceDimension.reachableTokenSet,
      DifferenceDimension.optionToTokenSet,
      DifferenceDimension.optionIdSet,
      DifferenceDimension.questionIdentitySequence,
      DifferenceDimension.questionRoleSequence,
      DifferenceDimension.truncationSet,
      DifferenceDimension.requiredSkipSemantics,
    };

/// Dimensions that are presentation only, PROVIDED every clinically
/// meaningful dimension is identical on the same path.
const Set<DifferenceDimension> kPresentationOnlyDimensions =
    <DifferenceDimension>{
      DifferenceDimension.optionToTokenSequence,
      DifferenceDimension.optionIdSequence,
      DifferenceDimension.optionLabelSequence,
      DifferenceDimension.optionLabelSet,
      DifferenceDimension.wording,
    };

/// Who has to sign a difference off.
enum ReviewerRequirement {
  /// Presentation only: which of two existing wordings or orderings is shown.
  productOnly,

  /// Changes what a user can declare, or what it maps to.
  productAndClinical,

  /// Changes whether a danger sign can be declared at all.
  safetyBlockerClinical,
}

String reviewerName(ReviewerRequirement r) {
  switch (r) {
    case ReviewerRequirement.productOnly:
      return 'product';
    case ReviewerRequirement.productAndClinical:
      return 'product_and_clinical';
    case ReviewerRequirement.safetyBlockerClinical:
      return 'safety_blocker_clinical';
  }
}

/// The result of comparing one path forward against reversed.
class PathComparison {
  PathComparison({
    required this.forwardTokens,
    required this.reversedTokens,
    required this.differing,
    required this.forwardReachable,
    required this.reversedReachable,
  });

  final List<String> forwardTokens;
  final List<String> reversedTokens;

  /// Every dimension that differs. May be empty.
  final Set<DifferenceDimension> differing;

  final Set<String> forwardReachable;
  final Set<String> reversedReachable;

  bool get isIdentical => differing.isEmpty;

  /// The most severe differing dimension, or null when identical.
  DifferenceDimension? get primary {
    for (final DifferenceDimension d in DifferenceDimension.values) {
      if (differing.contains(d)) return d;
    }
    return null;
  }

  bool get hasClinicallyMeaningfulDifference =>
      differing.any(kClinicallyMeaningfulDimensions.contains);

  /// Tokens reachable in one order and not the other. Empty is the safe case.
  Set<String> get reachabilityDelta =>
      forwardReachable.difference(reversedReachable)
        ..addAll(reversedReachable.difference(forwardReachable));

  ReviewerRequirement get reviewer {
    if (differing.contains(DifferenceDimension.redFlagReachableTokenSet)) {
      return ReviewerRequirement.safetyBlockerClinical;
    }
    if (hasClinicallyMeaningfulDifference) {
      return ReviewerRequirement.productAndClinical;
    }
    return ReviewerRequirement.productOnly;
  }
}

bool _seqEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _setEq(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

List<String> _flatOptionIds(List<LiveQuestion> qs) => <String>[
  for (final LiveQuestion q in qs) '${q.role}:${q.options.join(",")}',
];

Set<String> _optionIdSet(List<LiveQuestion> qs) => <String>{
  for (final LiveQuestion q in qs)
    for (final String o in q.options) '${q.role}:$o',
};

List<String> _flatMappingSeq(List<LiveQuestion> qs) => <String>[
  for (final LiveQuestion q in qs)
    '${q.role}:${q.optionToToken.entries.map((MapEntry<String, String> e) => "${e.key}=${e.value}").join(",")}',
];

Set<String> _mappingSet(List<LiveQuestion> qs) => <String>{
  for (final LiveQuestion q in qs)
    for (final MapEntry<String, String> e in q.optionToToken.entries)
      '${q.role}:${e.key}=${e.value}',
};

/// Every canonical token any answer on this path could contribute.
Set<String> reachableTokens(List<LiveQuestion> qs) => <String>{
  for (final LiveQuestion q in qs)
    for (final String token in q.optionToToken.values)
      if (token.isNotEmpty) token,
};

/// Compares one path forward against reversed, dimension by dimension.
PathComparison classifyPath({
  required List<String> forwardTokens,
  required List<String> reversedTokens,
  required List<LiveQuestion> forward,
  required List<LiveQuestion> reversed,
  required ClinicalIndex clinical,
}) {
  final Set<DifferenceDimension> differing = <DifferenceDimension>{};

  final Set<String> forwardReachable = reachableTokens(forward);
  final Set<String> reversedReachable = reachableTokens(reversed);

  if (!_setEq(forwardReachable, reversedReachable)) {
    differing.add(DifferenceDimension.reachableTokenSet);
    if (!_setEq(
      clinical.redFlagAffecting(forwardReachable),
      clinical.redFlagAffecting(reversedReachable),
    )) {
      differing.add(DifferenceDimension.redFlagReachableTokenSet);
    }
    if (!_setEq(
      clinical.scoringAffecting(forwardReachable),
      clinical.scoringAffecting(reversedReachable),
    )) {
      differing.add(DifferenceDimension.scoringReachableTokenSet);
    }
  }

  if (!_setEq(_mappingSet(forward), _mappingSet(reversed))) {
    differing.add(DifferenceDimension.optionToTokenSet);
  }
  if (!_seqEq(_flatMappingSeq(forward), _flatMappingSeq(reversed))) {
    differing.add(DifferenceDimension.optionToTokenSequence);
  }
  if (!_setEq(_optionIdSet(forward), _optionIdSet(reversed))) {
    differing.add(DifferenceDimension.optionIdSet);
  }
  if (!_seqEq(_flatOptionIds(forward), _flatOptionIds(reversed))) {
    differing.add(DifferenceDimension.optionIdSequence);
  }

  // The live model uses the canonical token id as both option id and label for
  // additional symptoms, and Yes/No for clarifiers, so label and id move
  // together. Computed separately anyway: assuming they agree is how a
  // relabelling would go unnoticed.
  if (!_setEq(_optionIdSet(forward), _optionIdSet(reversed))) {
    differing.add(DifferenceDimension.optionLabelSet);
  }
  if (!_seqEq(_flatOptionIds(forward), _flatOptionIds(reversed))) {
    differing.add(DifferenceDimension.optionLabelSequence);
  }

  final List<String> forwardIdentity = <String>[
    for (final LiveQuestion q in forward) '${q.role}|${q.redFlagToken ?? ""}',
  ];
  final List<String> reversedIdentity = <String>[
    for (final LiveQuestion q in reversed) '${q.role}|${q.redFlagToken ?? ""}',
  ];
  if (!_seqEq(forwardIdentity, reversedIdentity)) {
    differing.add(DifferenceDimension.questionIdentitySequence);
  }
  if (!_seqEq(
    <String>[for (final LiveQuestion q in forward) q.role],
    <String>[for (final LiveQuestion q in reversed) q.role],
  )) {
    differing.add(DifferenceDimension.questionRoleSequence);
  }

  // Truncation set: which questions survived the limit of 5. A difference here
  // means one order asks about a symptom the other never raises.
  if (forward.length != reversed.length ||
      !_setEq(forwardIdentity.toSet(), reversedIdentity.toSet())) {
    differing.add(DifferenceDimension.truncationSet);
  }

  // Required/skip semantics: the live engine authors no optional question and
  // no skip sentinel, so this is constant. Asserted rather than assumed —
  // a skip appearing in one order only would change path completion.
  final bool forwardHasSkip = forward.any(
    (LiveQuestion q) => q.options.any(
      (String o) =>
          o.toLowerCase() == 'skip' || o.toLowerCase() == 'prefer not to say',
    ),
  );
  final bool reversedHasSkip = reversed.any(
    (LiveQuestion q) => q.options.any(
      (String o) =>
          o.toLowerCase() == 'skip' || o.toLowerCase() == 'prefer not to say',
    ),
  );
  if (forwardHasSkip != reversedHasSkip) {
    differing.add(DifferenceDimension.requiredSkipSemantics);
  }

  if (!_seqEq(
    <String>[for (final LiveQuestion q in forward) q.questionText],
    <String>[for (final LiveQuestion q in reversed) q.questionText],
  )) {
    differing.add(DifferenceDimension.wording);
  }

  return PathComparison(
    forwardTokens: forwardTokens,
    reversedTokens: reversedTokens,
    differing: differing,
    forwardReachable: forwardReachable,
    reversedReachable: reversedReachable,
  );
}

/// The mutually exclusive primary buckets. These must sum to the total.
String primaryBucket(PathComparison c) {
  if (c.isIdentical) return 'identical';
  final DifferenceDimension primary = c.primary!;
  final bool wording = c.differing.contains(DifferenceDimension.wording);
  final bool presentationOnly = c.differing.every(
    kPresentationOnlyDimensions.contains,
  );

  if (!presentationOnly) {
    switch (primary) {
      case DifferenceDimension.redFlagReachableTokenSet:
        return 'red_flag_reachable_token_difference';
      case DifferenceDimension.scoringReachableTokenSet:
        return 'scoring_reachable_token_difference';
      case DifferenceDimension.reachableTokenSet:
        return 'reachable_token_set_difference';
      case DifferenceDimension.optionToTokenSet:
        return 'token_mapping_difference';
      case DifferenceDimension.optionIdSet:
        return 'option_membership_difference';
      case DifferenceDimension.questionIdentitySequence:
      case DifferenceDimension.questionRoleSequence:
        return 'question_set_or_role_difference';
      case DifferenceDimension.truncationSet:
        return 'truncation_difference';
      case DifferenceDimension.requiredSkipSemantics:
        return 'required_skip_semantics_difference';
      default:
        return 'unclassified_difference';
    }
  }

  final bool optionOrder =
      c.differing.contains(DifferenceDimension.optionIdSequence) ||
      c.differing.contains(DifferenceDimension.optionToTokenSequence) ||
      c.differing.contains(DifferenceDimension.optionLabelSequence);
  final bool labelSet = c.differing.contains(
    DifferenceDimension.optionLabelSet,
  );

  if (labelSet) return 'option_label_only_difference';
  if (wording && optionOrder) return 'wording_and_option_order_difference';
  if (wording) return 'wording_only_difference';
  if (optionOrder) return 'option_order_only_difference';
  return 'unclassified_difference';
}
