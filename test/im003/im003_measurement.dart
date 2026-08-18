/// Measures IM-003's clinical impact using the SHIPPED engine.
///
/// Every clinical value in the output of this file comes from
/// `EngineController.run` — the same `RedFlagEvaluator`, `ScoringEngine`,
/// `UrgencyDeterminer` and `OutputFormatter` the application uses, over the same
/// pinned KB 2.4, rules 2.2 and token dictionary 1.1.
///
/// **There is deliberately no scoring logic here.** No condition weight is
/// copied, no urgency is inferred, no ranking is recomputed. The knowledge
/// base's Python approximation disagreed with this engine on 22 of 239
/// urgencies, which is exactly why the measurement had to move here; a second
/// approximation in Mobile would repeat the mistake.
library;

import 'package:wellapath_mobile/core/engine/engine_controller.dart';
import 'package:wellapath_mobile/core/engine/models/engine_input.dart';
import 'package:wellapath_mobile/core/engine/models/engine_output.dart';
import 'package:wellapath_mobile/core/engine/red_flag_evaluator.dart';
import 'package:wellapath_mobile/core/engine/scoring_engine.dart';

import '../engine/case_bank/artifact_fixtures.dart';
import 'im003_closure.dart';

/// How a scenario came to exist. Never blurred: a mechanically derived boundary
/// case is weaker evidence than one the knowledge base supplied.
enum ScenarioProvenance {
  /// Supplied by the authoritative decision package for D004.
  authoritativeSupplied,

  /// Derived mechanically from the authoritative trigger graph — every newly
  /// reachable token, every two-cycle, the max-closure and max-depth cases.
  /// No clinical answer sequence is invented.
  graphBoundaryDerived,
}

String provenanceName(ScenarioProvenance p) =>
    p == ScenarioProvenance.authoritativeSupplied
    ? 'authoritative_supplied'
    : 'graph_boundary_derived';

class Im003Scenario {
  const Im003Scenario({
    required this.id,
    required this.description,
    required this.seedTokens,
    required this.provenance,
  });

  final String id;
  final String description;

  /// The baseline selected-token set.
  final List<String> seedTokens;
  final ScenarioProvenance provenance;
}

/// One condition as the shipped engine scored it.
class ScoredSnapshot {
  const ScoredSnapshot({
    required this.conditionId,
    required this.score,
    required this.matchedSymptoms,
  });

  final String conditionId;
  final int score;
  final List<String> matchedSymptoms;
}

/// Everything the shipped engine produced for one token set.
class EngineSnapshot {
  EngineSnapshot({
    required this.tokens,
    required this.urgency,
    required this.urgencySource,
    required this.redFlagTriggered,
    required this.matchedRuleId,
    required this.topCondition,
    required this.rankedConditionIds,
    required this.scoreByCondition,
    required this.matchedSymptomsByCondition,
    required this.topScoreTies,
  });

  final List<String> tokens;
  final String urgency;
  final String urgencySource;
  final bool redFlagTriggered;
  final String? matchedRuleId;
  final String? topCondition;
  final List<String> rankedConditionIds;
  final Map<String, int> scoreByCondition;
  final Map<String, List<String>> matchedSymptomsByCondition;

  /// Condition ids sharing the top score. A tie is a ranking fact the reviewer
  /// needs: a tie broken differently after expansion is a real change even when
  /// the top condition's id happens to be stable.
  final List<String> topScoreTies;

  Map<String, Object?> toJson() => <String, Object?>{
    'tokens': tokens,
    'urgency': urgency,
    'urgency_source': urgencySource,
    'red_flag_triggered': redFlagTriggered,
    'matched_rule_id': matchedRuleId,
    'top_condition': topCondition,
    'ranked_condition_ids': rankedConditionIds,
    'score_by_condition': scoreByCondition,
    'top_score_ties': topScoreTies,
  };
}

/// Drives the shipped engine. Constructed once from the pinned artifacts.
class ShippedEngine {
  ShippedEngine._(this._controller, this.artifacts);

  factory ShippedEngine.load() {
    final PinnedArtifacts artifacts = loadPinnedArtifacts();
    return ShippedEngine._(
      EngineController(
        rules: artifacts.rules,
        tokenDictionary: artifacts.tokenDictionary,
        knowledgeBase: artifacts.conditions,
        configMetadata: artifacts.configMetadata,
      ),
      artifacts,
    );
  }

  final EngineController _controller;
  final PinnedArtifacts artifacts;

  /// The same shipped components the controller composes, used directly to
  /// obtain the FULL scored-condition list.
  ///
  /// `OutputFormatter` truncates `topCauses` to three, which is right for the
  /// app and wrong for a ranking measurement. These are the identical classes
  /// with the identical pinned artifacts — not a reimplementation — and the
  /// controller stays the authority for urgency, source and red-flag result.
  /// `_assertConsistent` below fails if the two ever disagree.
  late final RedFlagEvaluator _evaluator = RedFlagEvaluator(
    rules: artifacts.rules,
    tokenDictionary: artifacts.tokenDictionary,
  );
  late final ScoringEngine _scorer = ScoringEngine(
    knowledgeBase: artifacts.conditions,
  );

  /// Runs the real pipeline. An engine exception propagates — it is never
  /// converted into a warning or a default, because a measurement that
  /// swallowed an engine failure would report a difference of zero.
  EngineSnapshot run(List<String> tokens) {
    final List<String> sorted = List<String>.of(tokens)..sort();

    final EngineInput input = EngineInput(
      symptomTokens: sorted,
      candidateConditionIds: artifacts.conditionIds.toList()..sort(),
    );
    final EngineOutput output = _controller.run(input);

    // Full ranking from the shipped scorer. Skipped entirely when a red flag
    // fired, exactly as the controller does — scoring must not run then.
    final Map<String, int> scores = <String, int>{};
    final Map<String, List<String>> matched = <String, List<String>>{};
    final List<String> ranked = <String>[];
    final RedFlagResult redFlag = _evaluator.evaluate(input);
    if (redFlag.proceedToScoring) {
      final ScoringResult scoring = _scorer.score(input, redFlag);
      for (final ScoredCondition condition in scoring.scoredConditions) {
        ranked.add(condition.conditionId);
        scores[condition.conditionId] = condition.score;
        matched[condition.conditionId] = List<String>.of(
          condition.matchedSymptoms,
        )..sort();
      }
    }

    _assertConsistent(output, ranked, scores);

    final int? best = scores.values.isEmpty
        ? null
        : scores.values.reduce((int a, int b) => a > b ? a : b);
    final List<String> ties = best == null
        ? const <String>[]
        : (scores.entries
              .where((MapEntry<String, int> e) => e.value == best)
              .map((MapEntry<String, int> e) => e.key)
              .toList()
            ..sort());

    return EngineSnapshot(
      tokens: sorted,
      urgency: output.urgency,
      urgencySource: output.urgencySource,
      redFlagTriggered: output.redFlagTriggered,
      matchedRuleId: output.matchedRuleId,
      topCondition: ranked.isEmpty ? null : ranked.first,
      rankedConditionIds: ranked,
      scoreByCondition: scores,
      matchedSymptomsByCondition: matched,
      topScoreTies: ties,
    );
  }
}

/// The controller's formatted top-3 must agree with the full scorer.
///
/// If they ever diverge, the measurement is reading two different engines and
/// every number in this report is suspect — so it throws rather than reporting.
void _assertConsistent(
  EngineOutput output,
  List<String> ranked,
  Map<String, int> scores,
) {
  if (output.redFlagTriggered) {
    if (ranked.isNotEmpty) {
      throw StateError(
        'red flag fired but the scorer produced ${ranked.length} conditions; '
        'scoring must not run when a red flag is active',
      );
    }
    return;
  }
  for (int i = 0; i < output.topCauses.length; i++) {
    final Map<String, dynamic> cause = output.topCauses[i];
    final String id = cause['condition_id'] as String;
    if (i >= ranked.length || ranked[i] != id) {
      throw StateError(
        'controller top cause $i is $id but the shipped scorer ranks '
        '${i < ranked.length ? ranked[i] : "nothing"} there',
      );
    }
    if (scores[id] != cause['score']) {
      throw StateError(
        'controller score for $id is ${cause['score']}, scorer says '
        '${scores[id]}',
      );
    }
  }
}

/// Urgency severity order, for direction of travel.
///
/// Needed because "urgency changed" is not one finding. An escalation and a
/// DE-ESCALATION carry opposite clinical risk, and a report that counted only
/// "25 urgency changes" would hide the one that matters.
const Map<String, int> kUrgencyRank = <String, int>{
  'self_care': 0,
  'non_urgent': 1,
  'urgent': 2,
  'emergency': 3,
};

/// The outcome class of one baseline-versus-expanded comparison.
///
/// Ordered most significant first; the primary class is the first that applies,
/// so a red-flag change is never filed as a score change.
enum OutcomeClass {
  redFlagChange,
  urgencyChange,
  urgencySourceChange,
  topConditionChange,
  rankingChange,
  scoreOnlyChange,
  noEffect,
}

String outcomeName(OutcomeClass c) {
  switch (c) {
    case OutcomeClass.redFlagChange:
      return 'red_flag_change';
    case OutcomeClass.urgencyChange:
      return 'urgency_change';
    case OutcomeClass.urgencySourceChange:
      return 'urgency_source_change';
    case OutcomeClass.topConditionChange:
      return 'top_condition_change';
    case OutcomeClass.rankingChange:
      return 'ranking_change_without_top_condition_change';
    case OutcomeClass.scoreOnlyChange:
      return 'score_only_change';
    case OutcomeClass.noEffect:
      return 'no_effect';
  }
}

/// One measured scenario: baseline versus additive closure, both through the
/// shipped engine.
class Measurement {
  Measurement({
    required this.scenario,
    required this.closure,
    required this.baseline,
    required this.expanded,
  });

  final Im003Scenario scenario;
  final ClosureResult closure;
  final EngineSnapshot baseline;
  final EngineSnapshot expanded;

  List<String> get addedTokens => closure.added;

  bool get redFlagChanged =>
      baseline.redFlagTriggered != expanded.redFlagTriggered ||
      baseline.matchedRuleId != expanded.matchedRuleId;
  bool get urgencyChanged => baseline.urgency != expanded.urgency;
  bool get urgencySourceChanged =>
      baseline.urgencySource != expanded.urgencySource;
  bool get topConditionChanged =>
      baseline.topCondition != expanded.topCondition;
  bool get rankingChanged =>
      baseline.rankedConditionIds.join(',') !=
      expanded.rankedConditionIds.join(',');
  bool get tiesChanged =>
      baseline.topScoreTies.join(',') != expanded.topScoreTies.join(',');

  /// condition_id -> (expanded score - baseline score), non-zero only.
  Map<String, int> get scoreDelta {
    final Map<String, int> delta = <String, int>{};
    final Set<String> ids = <String>{
      ...baseline.scoreByCondition.keys,
      ...expanded.scoreByCondition.keys,
    };
    for (final String id in ids.toList()..sort()) {
      final int before = baseline.scoreByCondition[id] ?? 0;
      final int after = expanded.scoreByCondition[id] ?? 0;
      if (before != after) delta[id] = after - before;
    }
    return delta;
  }

  bool get scoreChanged => scoreDelta.isNotEmpty;

  /// -1 de-escalation, 0 unchanged, +1 escalation.
  ///
  /// A de-escalation means the expanded token set produced a LOWER urgency than
  /// the baseline. Red-flag membership being unchanged does not prevent it:
  /// urgency also comes from the `urgency_default` of whichever condition ranks
  /// first, so re-ranking alone can move it in either direction.
  int get urgencyDirection {
    final int? before = kUrgencyRank[baseline.urgency];
    final int? after = kUrgencyRank[expanded.urgency];
    if (before == null || after == null || before == after) return 0;
    return after > before ? 1 : -1;
  }

  bool get urgencyEscalated => urgencyDirection > 0;

  /// The safety-relevant direction. Reported as a potential blocker, never
  /// characterised as acceptable — that judgement belongs to clinical review.
  bool get urgencyDeEscalated => urgencyDirection < 0;

  OutcomeClass get outcome {
    if (redFlagChanged) return OutcomeClass.redFlagChange;
    if (urgencyChanged) return OutcomeClass.urgencyChange;
    if (urgencySourceChanged) return OutcomeClass.urgencySourceChange;
    if (topConditionChanged) return OutcomeClass.topConditionChange;
    if (rankingChanged) return OutcomeClass.rankingChange;
    if (scoreChanged) return OutcomeClass.scoreOnlyChange;
    return OutcomeClass.noEffect;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'scenario_id': scenario.id,
    'description': scenario.description,
    'provenance': provenanceName(scenario.provenance),
    'seed_tokens': scenario.seedTokens,
    'added_tokens': addedTokens,
    'added_token_count': addedTokens.length,
    'closure_depth': closure.convergenceDepth,
    'converged': closure.converged,
    'baseline': baseline.toJson(),
    'expanded': expanded.toJson(),
    'primary_outcome': outcomeName(outcome),
    'red_flag_changed': redFlagChanged,
    'urgency_changed': urgencyChanged,
    'urgency_direction': urgencyDirection,
    'urgency_escalated': urgencyEscalated,
    'urgency_de_escalated': urgencyDeEscalated,
    'urgency_source_changed': urgencySourceChanged,
    'top_condition_changed': topConditionChanged,
    'ranking_changed': rankingChanged,
    'ties_changed': tiesChanged,
    'score_delta_by_condition': scoreDelta,
    'score_delta_condition_count': scoreDelta.length,
    'measured_with':
        'shipped EngineController (RedFlagEvaluator + '
        'ScoringEngine + UrgencyDeterminer + OutputFormatter)',
  };
}

/// Runs one scenario end to end through the shipped engine.
Measurement measure(
  ShippedEngine engine,
  TriggerGraph graph,
  Im003Scenario scenario,
) {
  final ClosureResult closure = graph.closure(scenario.seedTokens);
  return Measurement(
    scenario: scenario,
    closure: closure,
    baseline: engine.run(scenario.seedTokens),
    expanded: engine.run(closure.tokens.toList()),
  );
}
