/// The additive closure, reproduced from the authoritative evidence.
///
/// This reads the trigger graph out of the vendored knowledge-base evidence and
/// recomputes the closure here, rather than reading the closure back. If the two
/// disagree, the disagreement is the finding.
///
/// **Nothing here is a clinical model.** It computes which canonical tokens
/// additive re-branching would put into state. What those tokens then do is
/// measured by the shipped `EngineController` and by nothing in this file.
library;

import 'dart:convert';
import 'dart:io';

import 'im003_contract.dart';

/// The trigger graph: token -> tokens whose questions its answers would unlock.
class TriggerGraph {
  TriggerGraph(this.edges)
    : nodes = <String>{
        ...edges.keys,
        ...edges.values.expand((Set<String> v) => v),
      };

  factory TriggerGraph.fromEvidence(Map<String, dynamic> impact) {
    // Built from the PAIR TABLE, which is the authoritative enumeration, not
    // from a pre-computed adjacency list. The pairs are the edges.
    final Map<String, Set<String>> edges = <String, Set<String>>{};
    final Map<String, dynamic> reconciliation =
        impact['pair_reconciliation'] as Map<String, dynamic>;
    for (final Object? entry in reconciliation['pairs'] as List<dynamic>) {
      final Map<String, dynamic> pair = entry as Map<String, dynamic>;
      final String source = pair['source_token'] as String;
      final String option = pair['answer_option'] as String;
      edges.putIfAbsent(source, () => <String>{}).add(option);
    }
    // Every declared node, including any with no outgoing edge.
    for (final Object? node
        in (impact['trigger_graph'] as Map<String, dynamic>)['nodes']
            as List<dynamic>) {
      edges.putIfAbsent(node as String, () => <String>{});
    }
    return TriggerGraph(edges);
  }

  final Map<String, Set<String>> edges;
  final Set<String> nodes;

  int get edgeCount =>
      edges.values.fold(0, (int sum, Set<String> v) => sum + v.length);

  /// Unordered pairs `a <-> b`.
  Set<String> get twoCycles => <String>{
    for (final String a in edges.keys)
      for (final String b in edges[a]!)
        if ((edges[b] ?? const <String>{}).contains(a))
          (<String>[a, b]..sort()).join('|'),
  };

  Set<String> get selfLoops => <String>{
    for (final String a in edges.keys)
      if (edges[a]!.contains(a)) a,
  };

  /// The additive closure of [seeds], and the step at which each token appears.
  ///
  /// Termination is the algorithm: `seen` only grows, each round adds at least
  /// one token or stops, and the node set is finite. Cycles cannot loop it.
  ClosureResult closure(Iterable<String> seeds) {
    final Set<String> seen = <String>{...seeds};
    final Map<String, int> depth = <String, int>{
      for (final String s in seeds) s: 0,
    };
    Set<String> frontier = <String>{...seeds};
    int step = 0;
    while (frontier.isNotEmpty) {
      step += 1;
      final Set<String> next = <String>{};
      for (final String token in frontier) {
        for (final String target in edges[token] ?? const <String>{}) {
          if (seen.add(target)) {
            depth[target] = step;
            next.add(target);
          }
        }
      }
      frontier = next;
    }
    final int maxDepth = depth.values.isEmpty
        ? 0
        : depth.values.reduce((int a, int b) => a > b ? a : b);
    return ClosureResult(
      seeds: (List<String>.of(seeds)..sort()),
      tokens: seen,
      depth: depth,
      convergenceDepth: maxDepth,
    );
  }

  /// Adding a seed never shrinks the reachable set. Checked, not assumed.
  List<String> monotonicityViolations() {
    final List<String> violations = <String>[];
    final List<String> ordered = nodes.toList()..sort();
    for (final String a in ordered) {
      final Set<String> reachA = closure(<String>[a]).tokens;
      for (final String b in ordered) {
        final Set<String> reachBoth = closure(<String>[a, b]).tokens;
        if (!reachA.every(reachBoth.contains)) {
          violations.add('$a+$b');
        }
      }
    }
    return violations;
  }
}

class ClosureResult {
  const ClosureResult({
    required this.seeds,
    required this.tokens,
    required this.depth,
    required this.convergenceDepth,
  });

  final List<String> seeds;

  /// Seeds plus everything reachable.
  final Set<String> tokens;
  final Map<String, int> depth;
  final int convergenceDepth;

  /// Tokens the closure adds beyond the seeds.
  List<String> get added => (tokens.difference(seeds.toSet()).toList()..sort());

  bool get converged => true; // by construction; asserted in tests
}

/// The vendored authoritative evidence.
class Im003Evidence {
  Im003Evidence(this.impact, this.decisionPackage)
    : graph = TriggerGraph.fromEvidence(impact);

  factory Im003Evidence.load() => Im003Evidence(
    jsonDecode(File(kImpactPath).readAsStringSync()) as Map<String, dynamic>,
    jsonDecode(File(kDecisionPackagePath).readAsStringSync())
        as Map<String, dynamic>,
  );

  final Map<String, dynamic> impact;
  final Map<String, dynamic> decisionPackage;
  final TriggerGraph graph;

  Map<String, dynamic> get _redFlagSection =>
      impact['red_flag_cross_reference'] as Map<String, dynamic>;

  /// The 15 newly reachable tokens, as the evidence declares them.
  List<String> get newlyReachableTokens =>
      (_redFlagSection['newly_reachable_tokens'] as List<dynamic>)
          .cast<String>();

  int get redFlagAffectingCount =>
      _redFlagSection['red_flag_affecting_count'] as int;

  Map<String, dynamic> get _scoringDelta =>
      impact['scoring_input_delta'] as Map<String, dynamic>;

  int get affectedConditionCount => _scoringDelta['conditions_touched'] as int;

  /// condition_id -> declared maximum added weight.
  Map<String, int> get declaredWeightDeltaByCondition => <String, int>{
    for (final Object? entry in _scoringDelta['by_condition'] as List<dynamic>)
      (entry as Map<String, dynamic>)['condition_id'] as String:
          entry['max_added_weight'] as int,
  };

  /// condition_id -> {token: weight}, as declared.
  Map<String, Map<String, int>>
  get declaredTokenWeights => <String, Map<String, int>>{
    for (final Object? entry in _scoringDelta['by_condition'] as List<dynamic>)
      (entry as Map<String, dynamic>)['condition_id'] as String: <String, int>{
        for (final Object? t in entry['tokens'] as List<dynamic>)
          (t as Map<String, dynamic>)['token'] as String: t['weight'] as int,
      },
  };

  /// The scenarios the decision package supplies for D004.
  List<Map<String, dynamic>> get suppliedScenarios => <Map<String, dynamic>>[
    for (final Object? s in decisionPackage['scenarios'] as List<dynamic>)
      s as Map<String, dynamic>,
  ];

  /// The nodes the evidence declares, sorted.
  List<String> get declaredNodes =>
      ((impact['trigger_graph'] as Map<String, dynamic>)['nodes']
              as List<dynamic>)
          .cast<String>();
}
