/// The boundary between the search layer and clinical assessment state.
///
/// The search layer may use aliases, body areas, complaint groups, severity
/// and duration metadata to *locate* a token. Only the resolved canonical
/// token id may cross into assessment state, and this file is the only place
/// that crossing happens.
///
/// ## Why this is structural rather than a convention
///
/// [commit] takes a [CanonicalTokenId], whose constructor is private to
/// `vocabulary_v2.dart`. There is no expression in the app that produces one
/// from a string without going through a vocabulary that contains it. So the
/// following are not "prevented by a check" — they are unrepresentable at the
/// call site:
///
/// - raw query text
/// - normalized query text
/// - alias text
/// - body-area, complaint-group, severity or duration labels
/// - arbitrary metadata
/// - unknown token ids
///
/// An unresolved or ambiguous resolution carries no [CanonicalTokenId] at all
/// (`resolvedTokenId` is null), so there is nothing to hand over. Ambiguity
/// therefore cannot enter scoring even by a caller that ignores the status.
///
/// ## What this does not change
///
/// The live v1.1 picker keeps calling `AssessmentController.addSymptomToken`
/// directly with tokens from the approved Mobile display map. That path is
/// untouched, so existing behaviour with the v2 flag off is bit-for-bit what
/// it was. This boundary governs the v2 consumer.
library;

import 'package:flutter/foundation.dart';

import '../../features/assessment/assessment_controller.dart';
import 'vocabulary_search.dart';
import 'vocabulary_v2.dart';

/// Why a selection was refused.
enum SelectionRejection {
  /// The query matched nothing.
  unresolved,

  /// The query reached more than one clinical token. The user must choose;
  /// the app must not.
  ambiguous,

  /// The token is not in the active approved vocabulary.
  notInActiveVocabulary,

  /// The vocabulary marks the token as not eligible for scoring.
  notScoringEligible,
}

/// The outcome of attempting to commit a selection.
@immutable
class SelectionOutcome {
  const SelectionOutcome._(this.accepted, this.tokenId, this.rejection);

  factory SelectionOutcome.accepted(CanonicalTokenId id) =>
      SelectionOutcome._(true, id, null);

  factory SelectionOutcome.rejected(SelectionRejection reason) =>
      SelectionOutcome._(false, null, reason);

  final bool accepted;
  final CanonicalTokenId? tokenId;
  final SelectionRejection? rejection;
}

/// Commits resolved selections into assessment state.
///
/// [activeVocabularyTokenIds] is the **approved** vocabulary — token
/// dictionary 1.1 in every current build. A candidate token that does not also
/// exist in the approved set is refused, so loading a candidate with new ids
/// could never widen what scoring accepts.
class CanonicalTokenBoundary {
  const CanonicalTokenBoundary({
    required this.activeVocabularyTokenIds,
    required this.searchIndex,
  });

  final Set<String> activeVocabularyTokenIds;
  final VocabularySearchIndex searchIndex;

  /// Commits [id] to [controller], or refuses it.
  ///
  /// Note the parameter type: a caller cannot reach this method with a string.
  SelectionOutcome commit(
    CanonicalTokenId id,
    AssessmentController controller,
  ) {
    if (!activeVocabularyTokenIds.contains(id.value)) {
      return SelectionOutcome.rejected(
        SelectionRejection.notInActiveVocabulary,
      );
    }

    final VocabularyToken? token = searchIndex.vocabulary.token(id.value);
    if (token != null && !token.scoringEligible) {
      return SelectionOutcome.rejected(SelectionRejection.notScoringEligible);
    }

    controller.addSymptomToken(id.value);
    return SelectionOutcome.accepted(id);
  }

  /// Resolves [query] and commits it only if it resolved to exactly one token.
  ///
  /// This is the whole search-to-state path in one function, so there is no
  /// second route a future caller could take: an ambiguous or unresolved query
  /// returns a rejection and touches [controller] not at all.
  SelectionOutcome resolveAndCommit(
    String query,
    AssessmentController controller,
  ) {
    final VocabularyResolution resolution = searchIndex.resolve(query);

    if (resolution.isAmbiguous) {
      return SelectionOutcome.rejected(SelectionRejection.ambiguous);
    }

    final CanonicalTokenId? resolved = resolution.resolvedTokenId;
    if (resolved == null) {
      return SelectionOutcome.rejected(SelectionRejection.unresolved);
    }

    return commit(resolved, controller);
  }
}
