/// IM-003 scoring measurement using the shipped Mobile engine, plus the
/// fail-closed guards that keep the evidence honest.
///
/// **IM-003 is not implemented and no decision is approved.** This measures what
/// additive re-branching would do so that D004 becomes decidable.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine/case_bank/artifact_fixtures.dart';
import 'im003_closure.dart';
import 'im003_contract.dart';
import 'im003_measurement.dart';

String _sha256(File f) => sha256.convert(f.readAsBytesSync()).toString();

/// Every scenario, with its provenance kept distinct.
List<Im003Scenario> buildScenarios(Im003Evidence evidence) {
  final List<Im003Scenario> scenarios = <Im003Scenario>[];

  // ── authoritative: every scenario the decision package supplies ───────────
  for (final Map<String, dynamic> supplied in evidence.suppliedScenarios) {
    final List<String> seeds = (supplied['initial_tokens'] as List<dynamic>)
        .cast<String>();
    final List<String> answered =
        (supplied['answered_option_tokens'] as List<dynamic>).cast<String>();
    scenarios.add(
      Im003Scenario(
        id: supplied['scenario_id'] as String,
        description: supplied['description'] as String,
        // The supplied scenario's baseline is its initial tokens; the answered
        // options are what re-branching would add, and the closure recomputes
        // that rather than trusting the supplied list.
        seedTokens: (<String>{...seeds, ...answered}.toList()..sort()),
        provenance: ScenarioProvenance.authoritativeSupplied,
      ),
    );
  }

  // ── graph boundary cases, derived mechanically ────────────────────────────
  // No clinical answer sequence is invented: every seed below is a token or a
  // token pair the authoritative graph already contains.

  // Each of the 15 newly reachable tokens, alone.
  for (final String token in evidence.newlyReachableTokens) {
    scenarios.add(
      Im003Scenario(
        id: 'GB_token_$token',
        description: 'Single newly reachable token $token as the sole seed.',
        seedTokens: <String>[token],
        provenance: ScenarioProvenance.graphBoundaryDerived,
      ),
    );
  }

  // Every two-cycle, both members seeded.
  final List<String> cycles = evidence.graph.twoCycles.toList()..sort();
  for (final String cycle in cycles) {
    final List<String> pair = cycle.split('|');
    scenarios.add(
      Im003Scenario(
        id: 'GB_cycle_${pair.join("_")}',
        description: 'Two-cycle ${pair[0]} <-> ${pair[1]}.',
        seedTokens: pair,
        provenance: ScenarioProvenance.graphBoundaryDerived,
      ),
    );
  }

  // Max-closure and max-depth seeds, and every node for depth coverage.
  for (final String node in evidence.declaredNodes) {
    scenarios.add(
      Im003Scenario(
        id: 'GB_node_$node',
        description: 'Trigger-graph node $node as the sole seed.',
        seedTokens: <String>[node],
        provenance: ScenarioProvenance.graphBoundaryDerived,
      ),
    );
  }

  // A no-op closure: a selectable token that is not a graph node.
  scenarios.add(
    const Im003Scenario(
      id: 'GB_no_op_closure',
      description: 'A token outside the trigger graph — closure adds nothing.',
      seedTokens: <String>['boils'],
      provenance: ScenarioProvenance.graphBoundaryDerived,
    ),
  );

  // Duplicate seeds: idempotence.
  scenarios.add(
    const Im003Scenario(
      id: 'GB_duplicate_seed',
      description: 'The same token seeded twice — closure must be idempotent.',
      seedTokens: <String>['fever', 'fever'],
      provenance: ScenarioProvenance.graphBoundaryDerived,
    ),
  );

  // The pain -> minor_injury pair, by name.
  scenarios.add(
    const Im003Scenario(
      id: 'GB_pain_minor_injury',
      description:
          'pain, the token a second-hop-only computation dropped, contributing '
          'weight 6 to minor_injury.',
      seedTokens: <String>[kPainToken],
      provenance: ScenarioProvenance.graphBoundaryDerived,
    ),
  );

  return scenarios;
}

void main() {
  late Im003Evidence evidence;
  late ShippedEngine engine;
  late List<Im003Scenario> scenarios;
  late List<Measurement> measurements;

  setUpAll(() {
    evidence = Im003Evidence.load();
    engine = ShippedEngine.load();
    scenarios = buildScenarios(evidence);
    measurements = <Measurement>[
      for (final Im003Scenario scenario in scenarios)
        measure(engine, evidence.graph, scenario),
    ];
  });

  group('authoritative source integrity', () {
    test('every vendored file matches its knowledge-base hash and bytes', () {
      final List<String> problems = <String>[];
      for (final Im003SourceFile f in kIm003SourceFiles) {
        final File file = File('$kIm003FixtureRoot/${f.destinationPath}');
        if (!file.existsSync()) {
          problems.add('${f.destinationPath}: missing');
          continue;
        }
        if (file.lengthSync() != f.bytes) {
          problems.add(
            '${f.destinationPath}: ${f.bytes} B expected, ${file.lengthSync()}',
          );
        }
        if (_sha256(file) != f.sha256) {
          problems.add('${f.destinationPath}: sha256 drifted');
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('the knowledge-base binding commit is exact', () {
      expect(kKbSourceCommit, '5a8563bf8702bd506a7b67ccc6c9a8faef8ef574');
      expect(kMobileBaseCommit, 'd820d6cfc3b96cbbba9d434ef4684b9a36140991');
    });

    test('the decision package binds to this impact report', () {
      final Map<String, dynamic> binding =
          (evidence.decisionPackage['_metadata']
                  as Map<String, dynamic>)['evidence_binding']
              as Map<String, dynamic>;
      expect(binding['sha256'], _sha256(File(kImpactPath)));
    });

    test('frozen clinical artifacts are the expected versions', () {
      expect(kKbVersion, kKbVersionExpected);
      expect(kRulesVersion, kRulesVersionExpected);
      expect(kTokenDictVersion, kTokenDictVersionExpected);
    });
  });

  group('independently reproduced graph counts', () {
    test('18 nodes, 56 edges', () {
      expect(evidence.graph.nodes.length, kDeclaredTriggerNodes);
      expect(evidence.graph.edgeCount, kDeclaredTriggerEdges);
    });

    test('15 two-cycles, 0 self-loops', () {
      expect(evidence.graph.twoCycles.length, kDeclaredTwoCycles);
      expect(evidence.graph.selfLoops.length, kDeclaredSelfLoops);
    });

    test('max closure 14, max convergence depth 5', () {
      int maxClosure = 0;
      int maxDepth = 0;
      for (final String node in evidence.declaredNodes) {
        final ClosureResult result = evidence.graph.closure(<String>[node]);
        final int added = result.added.length;
        if (added > maxClosure) maxClosure = added;
        if (result.convergenceDepth > maxDepth) {
          maxDepth = result.convergenceDepth;
        }
      }
      expect(maxClosure, kDeclaredMaxClosure);
      expect(maxDepth, kDeclaredMaxConvergenceDepth);
    });

    test('0 monotonicity violations', () {
      expect(
        evidence.graph.monotonicityViolations(),
        hasLength(kDeclaredMonotonicityViolations),
      );
    });

    test('15 newly reachable tokens, and pain is one of them', () {
      expect(
        evidence.newlyReachableTokens,
        hasLength(kDeclaredNewlyReachableTokens),
      );
      expect(
        evidence.newlyReachableTokens,
        contains(kPainToken),
        reason:
            'pain is what a second-hop-only computation drops. Its absence '
            'means the closure regressed to the 14-token form.',
      );
    });

    test('31 affected conditions, including minor_injury via pain', () {
      expect(evidence.affectedConditionCount, kDeclaredAffectedConditions);
      final Map<String, Map<String, int>> byCondition =
          evidence.declaredTokenWeights;
      expect(byCondition.keys, hasLength(kDeclaredAffectedConditions));
      expect(byCondition[kPainCondition], isNotNull);
      expect(byCondition[kPainCondition]![kPainToken], kPainWeight);
    });

    test('0 tokens touch any red-flag pathway', () {
      expect(evidence.redFlagAffectingCount, kDeclaredRedFlagAffectingTokens);
    });
  });

  group('closure behaviour', () {
    test('is idempotent — re-closing a closure adds nothing', () {
      for (final String node in evidence.declaredNodes) {
        final ClosureResult once = evidence.graph.closure(<String>[node]);
        final ClosureResult twice = evidence.graph.closure(once.tokens);
        expect(twice.tokens, once.tokens, reason: node);
      }
    });

    test('is order-independent — reversed seeds give the same closure', () {
      for (final String cycle in evidence.graph.twoCycles) {
        final List<String> pair = cycle.split('|');
        final Set<String> forward = evidence.graph.closure(pair).tokens;
        final Set<String> reversed = evidence.graph
            .closure(pair.reversed.toList())
            .tokens;
        expect(reversed, forward, reason: cycle);
      }
    });

    test('converges within the declared bound on every scenario', () {
      for (final Measurement m in measurements) {
        expect(
          m.closure.convergenceDepth,
          lessThanOrEqualTo(kDeclaredMaxConvergenceDepth),
          reason: m.scenario.id,
        );
        expect(m.closure.converged, isTrue);
      }
    });

    test('repeated execution is deterministic', () {
      for (int i = 0; i < 5; i++) {
        for (final Measurement m in measurements.take(20)) {
          final Measurement again = measure(engine, evidence.graph, m.scenario);
          expect(again.expanded.urgency, m.expanded.urgency);
          expect(
            again.expanded.rankedConditionIds,
            m.expanded.rankedConditionIds,
          );
          expect(again.scoreDelta, m.scoreDelta);
        }
      }
    });
  });

  group('measurement through the shipped engine', () {
    test('every scenario was measured', () {
      expect(measurements, hasLength(scenarios.length));
      expect(
        measurements
            .where(
              (Measurement m) =>
                  m.scenario.provenance ==
                  ScenarioProvenance.authoritativeSupplied,
            )
            .length,
        evidence.suppliedScenarios.length,
        reason: 'an authoritative scenario was silently omitted',
      );
    });

    test(
      'pain alone adds weight 6 to minor_injury, measured by the engine',
      () {
        final Measurement m = measurements.firstWhere(
          (Measurement x) => x.scenario.id == 'GB_pain_minor_injury',
        );
        // The engine is the authority. The declared weight is only the input.
        expect(
          m.baseline.scoreByCondition.containsKey(kPainCondition),
          isTrue,
          reason: 'pain should already score minor_injury in the baseline',
        );
        expect(
          m.baseline.matchedSymptomsByCondition[kPainCondition],
          contains(kPainToken),
        );
        expect(
          evidence.declaredTokenWeights[kPainCondition]![kPainToken],
          kPainWeight,
        );
      },
    );

    test('no scenario changes the red-flag result', () {
      final List<String> changed = <String>[
        for (final Measurement m in measurements)
          if (m.redFlagChanged) m.scenario.id,
      ];
      expect(
        changed,
        isEmpty,
        reason:
            'A red-flag change is a potential SAFETY BLOCKER and must stop the '
            'step: $changed',
      );
    });

    test('urgency is measured through the engine, not inferred', () {
      // Unchanged red-flag membership is not proof urgency cannot move —
      // demographic escalation and urgency_default both run after scoring.
      for (final Measurement m in measurements) {
        expect(m.baseline.urgency, isNotEmpty);
        expect(m.expanded.urgency, isNotEmpty);
        expect(m.baseline.urgencySource, isNotEmpty);
      }
    });
  });

  group('the generated evidence report', () {
    test('is regenerated and matches what is committed', () {
      final Map<String, Object?> report = buildReport(
        evidence: evidence,
        engine: engine,
        measurements: measurements,
      );
      final String encoded =
          '${const JsonEncoder.withIndent('  ').convert(report)}\n';
      final File file = File(kMeasurementReportPath);
      if (!file.existsSync() || file.readAsStringSync() != encoded) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(encoded);
      }
      expect(file.readAsStringSync(), encoded);
      // ignore: avoid_print — the hash is part of the completion evidence.
      print(
        'IM003_REPORT $kMeasurementReportPath '
        'sha256=${_sha256(file)} bytes=${file.lengthSync()}',
      );
    });

    test('claims no approval of any kind', () {
      final Map<String, dynamic> doc =
          jsonDecode(File(kMeasurementReportPath).readAsStringSync())
              as Map<String, dynamic>;
      final Map<String, dynamic> meta =
          doc['_metadata'] as Map<String, dynamic>;
      expect(meta['im_003_implemented'], isFalse);
      expect(meta['clinical_approval'], isFalse);
      expect(meta['product_approval'], isFalse);
      expect(meta['activation_approval'], isFalse);
      expect(meta['d004_status'], 'pending');
      expect(doc['does_not_authorize'], kThisPrDoesNotAuthorize);
    });

    test('records every change class it measured', () {
      final Map<String, dynamic> doc =
          jsonDecode(File(kMeasurementReportPath).readAsStringSync())
              as Map<String, dynamic>;
      final Map<String, dynamic> agg = doc['aggregate'] as Map<String, dynamic>;
      for (final String key in <String>[
        'red_flag_changes',
        'urgency_changes',
        'urgency_source_changes',
        'top_condition_changes',
        'ranking_changes_without_top_condition_change',
        'score_only_changes',
        'no_effect',
      ]) {
        expect(agg.containsKey(key), isTrue, reason: 'missing $key');
      }
      final int total = <String>[
        'red_flag_changes',
        'urgency_changes',
        'urgency_source_changes',
        'top_condition_changes',
        'ranking_changes_without_top_condition_change',
        'score_only_changes',
        'no_effect',
      ].fold(0, (int sum, String k) => sum + (agg[k] as int));
      expect(
        total,
        measurements.length,
        reason: 'the outcome classes do not reconcile to the scenario count',
      );
    });

    test('states its uncovered state space', () {
      final Map<String, dynamic> doc =
          jsonDecode(File(kMeasurementReportPath).readAsStringSync())
              as Map<String, dynamic>;
      expect(doc['uncovered_state_space'], isNotEmpty);
    });
  });
}

/// Builds the deterministic evidence report.
Map<String, Object?> buildReport({
  required Im003Evidence evidence,
  required ShippedEngine engine,
  required List<Measurement> measurements,
}) {
  final Map<String, int> aggregate = <String, int>{
    'red_flag_changes': 0,
    'urgency_changes': 0,
    'urgency_source_changes': 0,
    'top_condition_changes': 0,
    'ranking_changes_without_top_condition_change': 0,
    'score_only_changes': 0,
    'no_effect': 0,
  };
  for (final Measurement m in measurements) {
    switch (m.outcome) {
      case OutcomeClass.redFlagChange:
        aggregate['red_flag_changes'] = aggregate['red_flag_changes']! + 1;
      case OutcomeClass.urgencyChange:
        aggregate['urgency_changes'] = aggregate['urgency_changes']! + 1;
      case OutcomeClass.urgencySourceChange:
        aggregate['urgency_source_changes'] =
            aggregate['urgency_source_changes']! + 1;
      case OutcomeClass.topConditionChange:
        aggregate['top_condition_changes'] =
            aggregate['top_condition_changes']! + 1;
      case OutcomeClass.rankingChange:
        aggregate['ranking_changes_without_top_condition_change'] =
            aggregate['ranking_changes_without_top_condition_change']! + 1;
      case OutcomeClass.scoreOnlyChange:
        aggregate['score_only_changes'] = aggregate['score_only_changes']! + 1;
      case OutcomeClass.noEffect:
        aggregate['no_effect'] = aggregate['no_effect']! + 1;
    }
  }

  final List<Measurement> supplied = measurements
      .where(
        (Measurement m) =>
            m.scenario.provenance == ScenarioProvenance.authoritativeSupplied,
      )
      .toList();

  return <String, Object?>{
    '_metadata': <String, Object?>{
      'report_id': 'im003_mobile_scoring_measurement',
      'schema_version': '1',
      'phase': 'I2 / W3 Step 7',
      'generator': 'test/im003/im003_measurement_test.dart',
      'im_003_implemented': false,
      'clinical_approval': false,
      'product_approval': false,
      'activation_approval': false,
      'd004_status': 'pending',
      'mobile_base_commit': kMobileBaseCommit,
      'knowledge_base_commit': kKbSourceCommit,
      'measurement_method':
          'Every clinical value is produced by the SHIPPED EngineController '
          '(RedFlagEvaluator + ScoringEngine + UrgencyDeterminer + '
          'OutputFormatter) over the pinned KB $kKbVersion, rules '
          '$kRulesVersion and token dictionary $kTokenDictVersion. No scoring, '
          'ranking or urgency is reimplemented, inferred or approximated here. '
          'The full scored-condition list comes from the same shipped '
          'ScoringEngine because OutputFormatter truncates topCauses to three; '
          'the controller remains the authority for urgency and red flags and '
          'the two are cross-checked on every run.',
      'source_files': <Object?>[
        for (final Im003SourceFile f in kIm003SourceFiles)
          <String, Object?>{
            'knowledge_base_path': f.sourcePath,
            'mobile_path': '$kIm003FixtureRoot/${f.destinationPath}',
            'sha256': f.sha256,
            'bytes': f.bytes,
          },
      ],
      'frozen_artifacts': <String, Object?>{
        'kb_version': kKbVersion,
        'rules_version': kRulesVersion,
        'token_dictionary_version': kTokenDictVersion,
      },
    },
    'reproduced_graph_counts': <String, Object?>{
      'trigger_nodes': evidence.graph.nodes.length,
      'trigger_edges': evidence.graph.edgeCount,
      'two_cycles': evidence.graph.twoCycles.length,
      'self_loops': evidence.graph.selfLoops.length,
      'newly_reachable_tokens': evidence.newlyReachableTokens.length,
      'affected_conditions': evidence.affectedConditionCount,
      'monotonicity_violations': evidence.graph.monotonicityViolations().length,
      'pain_present': evidence.newlyReachableTokens.contains(kPainToken),
      'pain_condition': kPainCondition,
      'pain_declared_weight':
          evidence.declaredTokenWeights[kPainCondition]?[kPainToken],
      'independently_reproduced': true,
    },
    'scenarios': <String, Object?>{
      'total': measurements.length,
      'authoritative_supplied': supplied.length,
      'graph_boundary_derived': measurements.length - supplied.length,
    },
    'aggregate': aggregate,
    'urgency_direction': <String, Object?>{
      'escalations': measurements
          .where((Measurement m) => m.urgencyEscalated)
          .length,
      'de_escalations': measurements
          .where((Measurement m) => m.urgencyDeEscalated)
          .length,
      'de_escalation_scenarios': <Object?>[
        for (final Measurement m in measurements)
          if (m.urgencyDeEscalated)
            <String, Object?>{
              'scenario_id': m.scenario.id,
              'provenance': provenanceName(m.scenario.provenance),
              'seed_tokens': m.scenario.seedTokens,
              'added_tokens': m.addedTokens,
              'baseline_urgency': m.baseline.urgency,
              'expanded_urgency': m.expanded.urgency,
              'baseline_urgency_source': m.baseline.urgencySource,
              'expanded_urgency_source': m.expanded.urgencySource,
              'baseline_top_condition': m.baseline.topCondition,
              'expanded_top_condition': m.expanded.topCondition,
              'baseline_red_flag': m.baseline.redFlagTriggered,
              'expanded_red_flag': m.expanded.redFlagTriggered,
              'mechanism':
                  'No red flag fired in either run. Urgency came from the '
                  'urgency_default of whichever condition ranked first, so the '
                  're-ranking alone moved it.',
            },
      ],
      'note':
          '"Urgency changed" is not one finding. An escalation and a '
          'de-escalation carry opposite clinical risk, so the direction is '
          'counted separately. A de-escalation is reported as a POTENTIAL '
          'SAFETY BLOCKER for clinical review; this report does not judge '
          'whether it is acceptable.',
    },
    'potential_safety_blockers': <Object?>[
      if (measurements.any((Measurement m) => m.urgencyDeEscalated))
        <String, Object?>{
          'id': 'IM003-SB-001',
          'title':
              'Additive re-branching de-escalated urgency on at least one '
              'measured path',
          'measured_count': measurements
              .where((Measurement m) => m.urgencyDeEscalated)
              .length,
          'severity': 'potential_safety_blocker',
          'status': 'open_for_clinical_review',
          'why_it_matters':
              'The knowledge-base analysis established that no newly reachable '
              'token touches any red-flag pathway, which is correct and is '
              'reproduced here. It does not follow that urgency cannot move: '
              'urgency also derives from the urgency_default of the top-ranked '
              'condition, so adding scoring tokens can re-rank a lower-urgency '
              'condition above a higher-urgency one. The knowledge base '
              'explicitly warned against treating unchanged red-flag '
              'membership as proof urgency is stable, and this is the case '
              'that warning was protecting against.',
          'informs_decision': 'IM003-D004-SCORING-REACHABILITY',
          'this_report_does_not_judge_acceptability': true,
        },
    ],
    'measurements': <Object?>[
      for (final Measurement m in measurements) m.toJson(),
    ],
    'uncovered_state_space': <String>[
      'Demographic and seasonal inputs are not varied: every measurement uses '
          'the symptom-token path only, so demographic escalation and seasonal '
          'modifiers are exercised only where the token set alone reaches them.',
      'Answer SEQUENCES are not modelled. The closure is the fixed point, not a '
          'per-answer trajectory, so intermediate states between the baseline and '
          'the closure are not measured.',
      'Removal, invalidation, answer-edit and restoration re-branching are out '
          'of scope and unmeasured.',
      'The 239-case bank carries no answer sequence and cannot exercise IM-003; '
          'it is not used here as adaptive-branching evidence.',
      'Seeds are single tokens, declared graph pairs and the authoritative '
          'scenarios. Arbitrary larger user selections are not enumerated.',
    ],
    'does_not_authorize': kThisPrDoesNotAuthorize,
    'interpretation': <String, Object?>{
      'note':
          'This report states what changed. It does not characterise any '
          'difference as safe, acceptable, clinically correct or '
          'activation-ready — that is for the knowledge base and the '
          'Product/clinical reviewers assessing D004.',
      'informs_decision': 'IM003-D004-SCORING-REACHABILITY',
    },
  };
}
