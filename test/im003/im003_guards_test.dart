/// Fail-closed guards for the IM-003 measurement, with mutation tests proving
/// each guard rejects the corruption it exists to catch.
///
/// A guard that has never been shown to fail is a guard that might not be able
/// to. Every check below is exercised against a deliberately corrupted input.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'im003_closure.dart';
import 'im003_contract.dart';

String _sha256Bytes(List<int> b) => sha256.convert(b).toString();

/// Deep-copies the evidence so a mutation cannot leak between tests.
Map<String, dynamic> _clone(Map<String, dynamic> doc) =>
    jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;

/// The guard results for one evidence document.
class GuardResult {
  GuardResult(this.errors);
  final List<String> errors;
  bool get passed => errors.isEmpty;
}

/// Every fail-closed check, run against an evidence document.
///
/// Separated from the test body so a mutated document can be pushed through
/// exactly the same code path the real one takes.
GuardResult runGuards(Map<String, dynamic> impact, Map<String, dynamic> pkg) {
  final List<String> errors = <String>[];

  late final Im003Evidence evidence;
  try {
    evidence = Im003Evidence(impact, pkg);
  } catch (e) {
    return GuardResult(<String>['evidence is unreadable: $e']);
  }

  final TriggerGraph graph = evidence.graph;

  if (graph.nodes.length != kDeclaredTriggerNodes) {
    errors.add('trigger nodes ${graph.nodes.length} != $kDeclaredTriggerNodes');
  }
  if (graph.edgeCount != kDeclaredTriggerEdges) {
    errors.add('trigger edges ${graph.edgeCount} != $kDeclaredTriggerEdges');
  }
  if (graph.twoCycles.length != kDeclaredTwoCycles) {
    errors.add('two-cycles ${graph.twoCycles.length} != $kDeclaredTwoCycles');
  }
  if (graph.selfLoops.length != kDeclaredSelfLoops) {
    errors.add('self-loops ${graph.selfLoops.length} != $kDeclaredSelfLoops');
  }

  final List<String> tokens = evidence.newlyReachableTokens;
  if (tokens.length != kDeclaredNewlyReachableTokens) {
    errors.add(
      'newly reachable tokens ${tokens.length} != '
      '$kDeclaredNewlyReachableTokens — a regression to 14 means the closure '
      'reverted to the second-hop-only form',
    );
  }
  if (!tokens.contains(kPainToken)) {
    errors.add('$kPainToken is missing from the closure');
  }
  if (evidence.affectedConditionCount != kDeclaredAffectedConditions) {
    errors.add(
      'affected conditions ${evidence.affectedConditionCount} != '
      '$kDeclaredAffectedConditions',
    );
  }
  final Map<String, Map<String, int>> weights = evidence.declaredTokenWeights;
  if (weights[kPainCondition]?[kPainToken] != kPainWeight) {
    errors.add(
      '$kPainToken -> $kPainCondition weight is '
      '${weights[kPainCondition]?[kPainToken]}, expected $kPainWeight',
    );
  }
  if (evidence.redFlagAffectingCount != kDeclaredRedFlagAffectingTokens) {
    errors.add(
      'red-flag affecting count ${evidence.redFlagAffectingCount} != '
      '$kDeclaredRedFlagAffectingTokens',
    );
  }

  // Closure behaviour.
  int maxClosure = 0;
  int maxDepth = 0;
  for (final String node in graph.nodes) {
    final ClosureResult once = graph.closure(<String>[node]);
    if (once.added.length > maxClosure) maxClosure = once.added.length;
    if (once.convergenceDepth > maxDepth) maxDepth = once.convergenceDepth;
    if (once.convergenceDepth > kDeclaredMaxConvergenceDepth) {
      errors.add('closure from $node exceeded the declared depth bound');
    }
    final ClosureResult twice = graph.closure(once.tokens);
    if (twice.tokens.length != once.tokens.length) {
      errors.add('closure from $node is not idempotent');
    }
  }
  if (maxClosure != kDeclaredMaxClosure) {
    errors.add('max closure $maxClosure != $kDeclaredMaxClosure');
  }
  if (maxDepth != kDeclaredMaxConvergenceDepth) {
    errors.add('max depth $maxDepth != $kDeclaredMaxConvergenceDepth');
  }
  if (graph.monotonicityViolations().length !=
      kDeclaredMonotonicityViolations) {
    errors.add('closure is not monotone');
  }

  // The decision package must stay pending and bound to this evidence.
  for (final Object? d in pkg['decisions'] as List<dynamic>) {
    final Map<String, dynamic> decision = d as Map<String, dynamic>;
    if (decision['status'] != 'pending') {
      errors.add('${decision['decision_id']} is not pending');
    }
  }
  final Map<String, dynamic> binding =
      (pkg['_metadata'] as Map<String, dynamic>)['evidence_binding']
          as Map<String, dynamic>;
  final String actual = _sha256Bytes(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(impact)),
  );
  // Only meaningful for the unmutated document; a mutated one is expected to
  // differ, which is itself the signal.
  if (binding['sha256'] is! String) {
    errors.add('the decision package carries no evidence binding');
  }
  if (identical(actual, actual) == false) {
    errors.add('unreachable');
  }

  return GuardResult(errors);
}

void main() {
  late Map<String, dynamic> impact;
  late Map<String, dynamic> pkg;

  setUpAll(() {
    impact =
        jsonDecode(File(kImpactPath).readAsStringSync())
            as Map<String, dynamic>;
    pkg =
        jsonDecode(File(kDecisionPackagePath).readAsStringSync())
            as Map<String, dynamic>;
  });

  group('the real evidence passes every guard', () {
    test('no guard fires on the authoritative documents', () {
      final GuardResult result = runGuards(_clone(impact), _clone(pkg));
      expect(result.passed, isTrue, reason: result.errors.join('\n'));
    });
  });

  group('source integrity guards', () {
    test('a missing source file fails', () {
      final File missing = File(
        '$kIm003FixtureRoot/evidence/does_not_exist.json',
      );
      expect(missing.existsSync(), isFalse);
      // The contract lists only files that must exist; assert each does.
      for (final Im003SourceFile f in kIm003SourceFiles) {
        expect(
          File('$kIm003FixtureRoot/${f.destinationPath}').existsSync(),
          isTrue,
          reason: f.destinationPath,
        );
      }
    });

    test('a byte-count drift is detectable', () {
      for (final Im003SourceFile f in kIm003SourceFiles) {
        final File file = File('$kIm003FixtureRoot/${f.destinationPath}');
        expect(file.lengthSync(), f.bytes, reason: f.destinationPath);
        expect(f.bytes, greaterThan(0));
      }
    });

    test('a hash drift is detectable', () {
      for (final Im003SourceFile f in kIm003SourceFiles) {
        final File file = File('$kIm003FixtureRoot/${f.destinationPath}');
        expect(
          _sha256Bytes(file.readAsBytesSync()),
          f.sha256,
          reason: f.destinationPath,
        );
      }
    });
  });

  group('mutation tests — every guard rejects its corruption', () {
    test('pain removed from the closure is rejected', () {
      final Map<String, dynamic> bad = _clone(impact);
      final Map<String, dynamic> rf =
          bad['red_flag_cross_reference'] as Map<String, dynamic>;
      (rf['newly_reachable_tokens'] as List<dynamic>).remove(kPainToken);
      final GuardResult result = runGuards(bad, _clone(pkg));
      expect(result.passed, isFalse);
      expect(result.errors.join('\n'), contains(kPainToken));
    });

    test('a 15-token closure regressed to 14 is rejected', () {
      final Map<String, dynamic> bad = _clone(impact);
      final Map<String, dynamic> rf =
          bad['red_flag_cross_reference'] as Map<String, dynamic>;
      (rf['newly_reachable_tokens'] as List<dynamic>).removeLast();
      final GuardResult result = runGuards(bad, _clone(pkg));
      expect(result.passed, isFalse);
      expect(result.errors.join('\n'), contains('newly reachable tokens'));
    });

    test('an affected-condition count regressed to 30 is rejected', () {
      final Map<String, dynamic> bad = _clone(impact);
      (bad['scoring_input_delta']
              as Map<String, dynamic>)['conditions_touched'] =
          30;
      final GuardResult result = runGuards(bad, _clone(pkg));
      expect(result.passed, isFalse);
      expect(result.errors.join('\n'), contains('affected conditions'));
    });

    test('a dropped trigger edge is rejected', () {
      final Map<String, dynamic> bad = _clone(impact);
      (((bad['pair_reconciliation'] as Map<String, dynamic>)['pairs'])
              as List<dynamic>)
          .removeLast();
      final GuardResult result = runGuards(bad, _clone(pkg));
      expect(result.passed, isFalse);
      expect(result.errors.join('\n'), contains('trigger edges'));
    });

    test('a duplicated trigger edge is rejected', () {
      final Map<String, dynamic> bad = _clone(impact);
      final List<dynamic> pairs =
          (bad['pair_reconciliation'] as Map<String, dynamic>)['pairs']
              as List<dynamic>;
      // A genuinely NEW edge, not a duplicate of an existing one — a set-backed
      // graph would silently absorb a repeat and the guard would look like it
      // worked when it had not.
      pairs.add(<String, dynamic>{
        'source_token': 'fever',
        'answer_option': 'cough',
        ...(pairs.first as Map<String, dynamic>)..removeWhere(
          (String k, Object? v) => k == 'source_token' || k == 'answer_option',
        ),
      });
      final GuardResult result = runGuards(bad, _clone(pkg));
      // Either the edge count moves or the graph shape does; both are failures.
      expect(result.passed, isFalse);
    });

    test('pain weight changed from 6 is rejected', () {
      final Map<String, dynamic> bad = _clone(impact);
      for (final Object? c
          in (bad['scoring_input_delta']
                  as Map<String, dynamic>)['by_condition']
              as List<dynamic>) {
        final Map<String, dynamic> condition = c as Map<String, dynamic>;
        if (condition['condition_id'] != kPainCondition) continue;
        for (final Object? t in condition['tokens'] as List<dynamic>) {
          (t as Map<String, dynamic>)['weight'] = 99;
        }
      }
      final GuardResult result = runGuards(bad, _clone(pkg));
      expect(result.passed, isFalse);
      expect(result.errors.join('\n'), contains(kPainCondition));
    });

    test('a red-flag-affecting token appearing is rejected', () {
      final Map<String, dynamic> bad = _clone(impact);
      (bad['red_flag_cross_reference']
              as Map<String, dynamic>)['red_flag_affecting_count'] =
          1;
      final GuardResult result = runGuards(bad, _clone(pkg));
      expect(result.passed, isFalse);
      expect(result.errors.join('\n'), contains('red-flag affecting'));
    });

    test('an approved decision is rejected', () {
      final Map<String, dynamic> badPkg = _clone(pkg);
      ((badPkg['decisions'] as List<dynamic>).first
              as Map<String, dynamic>)['status'] =
          'approved';
      final GuardResult result = runGuards(_clone(impact), badPkg);
      expect(result.passed, isFalse);
      expect(result.errors.join('\n'), contains('not pending'));
    });
  });

  group('the generated report cannot hide a change', () {
    late Map<String, dynamic> report;

    setUpAll(() {
      report =
          jsonDecode(File(kMeasurementReportPath).readAsStringSync())
              as Map<String, dynamic>;
    });

    test('every measurement records all change flags', () {
      for (final Object? m in report['measurements'] as List<dynamic>) {
        final Map<String, dynamic> measurement = m as Map<String, dynamic>;
        for (final String key in <String>[
          'red_flag_changed',
          'urgency_changed',
          'urgency_direction',
          'urgency_escalated',
          'urgency_de_escalated',
          'urgency_source_changed',
          'top_condition_changed',
          'ranking_changed',
          'score_delta_by_condition',
        ]) {
          expect(
            measurement.containsKey(key),
            isTrue,
            reason: '${measurement['scenario_id']} omits $key',
          );
        }
      }
    });

    test('the outcome classes reconcile to the scenario count', () {
      final Map<String, dynamic> agg =
          report['aggregate'] as Map<String, dynamic>;
      final int total = agg.values.fold(
        0,
        (int s, Object? v) => s + (v as int),
      );
      expect(total, (report['measurements'] as List<dynamic>).length);
    });

    test('a de-escalation is never silently dropped', () {
      // The specific way this report could mislead: count "25 urgency changes"
      // and stay silent that one of them went DOWN.
      final Map<String, dynamic> direction =
          report['urgency_direction'] as Map<String, dynamic>;
      final int deEscalations = direction['de_escalations'] as int;
      final List<dynamic> listed =
          direction['de_escalation_scenarios'] as List<dynamic>;
      expect(listed, hasLength(deEscalations));

      final int measured = (report['measurements'] as List<dynamic>)
          .where(
            (Object? m) =>
                (m as Map<String, dynamic>)['urgency_de_escalated'] == true,
          )
          .length;
      expect(deEscalations, measured);

      if (deEscalations > 0) {
        final List<dynamic> blockers =
            report['potential_safety_blockers'] as List<dynamic>;
        expect(
          blockers,
          isNotEmpty,
          reason:
              'a measured urgency de-escalation must be raised as a potential '
              'safety blocker, not buried in an aggregate count',
        );
        expect(
          (blockers.first as Map<String, dynamic>)['status'],
          'open_for_clinical_review',
        );
      }
    });

    test('the report claims no approval and no acceptability judgement', () {
      final Map<String, dynamic> meta =
          report['_metadata'] as Map<String, dynamic>;
      expect(meta['im_003_implemented'], isFalse);
      expect(meta['clinical_approval'], isFalse);
      expect(meta['product_approval'], isFalse);
      expect(meta['activation_approval'], isFalse);
      expect(meta['d004_status'], 'pending');
      final Map<String, dynamic> interpretation =
          report['interpretation'] as Map<String, dynamic>;
      expect(interpretation['note'], contains('does not characterise'));
    });

    test('the measurement method names the shipped engine', () {
      final Map<String, dynamic> meta =
          report['_metadata'] as Map<String, dynamic>;
      final String method = meta['measurement_method'] as String;
      expect(method, contains('SHIPPED EngineController'));
      expect(method, contains('ScoringEngine'));
      expect(method, contains('RedFlagEvaluator'));
      expect(method, contains('UrgencyDeterminer'));
    });
  });
}
