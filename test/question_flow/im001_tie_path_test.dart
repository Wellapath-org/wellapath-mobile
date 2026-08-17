// ignore_for_file: avoid_print
// print() is intentional: this file's console output IS the IM-001 evidence
// recorded in docs/W3_QUESTION_FLOW_CONSUMER.md, and the engineering lead
// reads it to decide whether deterministic ordering is activation-safe.

/// IM-001 tie-path evidence.
///
/// Compares the **live** `QuestionEngine` against the **candidate**
/// deterministic ordering across every input the bounded analysis covers, and
/// classifies each difference.
///
/// The bound is the knowledge base's own: every subset of the driving trigger
/// tokens up to size 3 — 2,325 combinations. That is a coverage limit, not a
/// soundness claim, and it is reported as such.
///
/// **Nothing here activates anything.** The live engine is called for
/// comparison only; the candidate planner never touches assessment state.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/question_flow/condition_evaluator.dart';
import 'package:wellapath_mobile/core/question_flow/initial_path_planner.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';
import 'package:wellapath_mobile/features/assessment/models/followup_question.dart';
import 'package:wellapath_mobile/features/assessment/question_engine.dart';

import 'question_flow_test_support.dart';

/// How a live question maps onto the candidate's vocabulary of roles.
String roleOf(FollowupQuestion q) => switch (q.type) {
  QuestionType.severity => 'severity',
  QuestionType.duration => 'duration',
  QuestionType.additionalSymptoms => 'additional_symptoms',
  QuestionType.redFlagClarifier => 'red_flag_clarifier',
};

/// The candidate's driving trigger tokens: every token named by a
/// `token_present` in a follow-up question's trigger. Derived from the
/// artifact rather than hardcoded.
List<String> drivingTokens(QuestionFlow flow) {
  final Set<String> tokens = <String>{};

  void walk(FlowCondition c) {
    if (c.operator == ConditionOperator.tokenPresent && c.token != null) {
      tokens.add(c.token!);
    }
    for (final FlowCondition child in c.children) {
      walk(child);
    }
  }

  for (final FlowQuestion q in flow.questions) {
    if (q.isDemographic ||
        q.clinicalRole == 'symptom_picker' ||
        q.clinicalRole == 'body_area') {
      continue;
    }
    walk(q.triggerCondition);
  }
  return tokens.toList()..sort();
}

/// All subsets of [tokens] of size 0..3, in deterministic order.
///
/// C(24,1)+C(24,2)+C(24,3) = 2,324, plus the empty set = **2,325**, which is
/// the knowledge base's published `combinations_explored`. The empty set is
/// included so the bound matches theirs exactly rather than approximately.
List<List<String>> boundedSubsets(List<String> tokens) {
  final List<List<String>> out = <List<String>>[<String>[]];
  for (int i = 0; i < tokens.length; i++) {
    out.add(<String>[tokens[i]]);
    for (int j = i + 1; j < tokens.length; j++) {
      out.add(<String>[tokens[i], tokens[j]]);
      for (int k = j + 1; k < tokens.length; k++) {
        out.add(<String>[tokens[i], tokens[j], tokens[k]]);
      }
    }
  }
  return out;
}

class Difference {
  Difference({
    required this.tokens,
    required this.liveRoles,
    required this.candidateIds,
    required this.liveCount,
    required this.candidateCount,
    required this.classification,
  });

  final List<String> tokens;
  final List<String> liveRoles;
  final List<String> candidateIds;
  final int liveCount;
  final int candidateCount;
  final String classification;

  Map<String, Object?> toJson() => <String, Object?>{
    'input_tokens': tokens,
    'demographics': 'none — follow-up phase only',
    'live_order': liveRoles,
    'candidate_order': candidateIds,
    'live_count': liveCount,
    'candidate_count': candidateCount,
    'classification': classification,
  };
}

void main() {
  late QuestionFlow flow;
  late List<String> universe;

  setUpAll(() {
    flow = loadCandidateFlow().flow!;
    universe = drivingTokens(flow);
  });

  test('the driving token universe matches the published analysis', () {
    expect(
      universe,
      hasLength(24),
      reason:
          'The knowledge base graph analysis explored 24 driving tokens; a '
          'different count means the comparison bound has moved.',
    );
    expect(boundedSubsets(universe), hasLength(2325));
  });

  test('IM-001 tie-path comparison across all 2,325 bounded paths', () {
    final List<Difference> differences = <Difference>[];
    int identical = 0;
    int orderOnly = 0;
    int setChanged = 0;
    int truncationChanged = 0;
    int redFlagImplicated = 0;

    for (final List<String> tokens in boundedSubsets(universe)) {
      final List<FollowupQuestion> live = QuestionEngine.generateQuestions(
        tokens,
      );
      final InitialPathPlan plan = planInitialPath(
        flow,
        FlowEvaluationState(
          tokens: tokens.toSet(),
          assessmentPhase: 'followup',
        ),
      );

      final List<String> liveRoles = live.map(roleOf).toList(growable: false);
      final List<String> candidateIds = plan.presentedIds;

      // Roles the candidate presents, for a like-for-like comparison.
      final List<String> candidateRoles = plan.presented
          .map((PlannedQuestion p) => p.question.clinicalRole)
          .toList(growable: false);

      if (liveRoles.join(',') == candidateRoles.join(',')) {
        identical += 1;
        continue;
      }

      // Classify. A pure reordering of the same multiset is the mild case;
      // a different multiset means different clinical content is asked.
      final List<String> liveSorted = List<String>.of(liveRoles)..sort();
      final List<String> candSorted = List<String>.of(candidateRoles)..sort();
      final bool sameMultiset = liveSorted.join(',') == candSorted.join(',');

      String classification;
      if (sameMultiset) {
        classification = 'order_only';
        orderOnly += 1;
      } else {
        setChanged += 1;
        if (plan.truncated.isNotEmpty || live.length == 5) {
          classification = 'path_content_exposure_change_with_truncation';
          truncationChanged += 1;
        } else {
          classification = 'path_content_exposure_change';
        }
      }

      final bool redFlagInvolved =
          liveRoles.contains('red_flag_clarifier') ||
          candidateRoles.contains('red_flag_clarifier');
      if (redFlagInvolved) redFlagImplicated += 1;

      differences.add(
        Difference(
          tokens: tokens,
          liveRoles: liveRoles,
          candidateIds: candidateIds,
          liveCount: live.length,
          candidateCount: plan.presented.length,
          classification: classification,
        ),
      );
    }

    final int total = boundedSubsets(universe).length;

    print('');
    print('=== IM-001 TIE-PATH EVIDENCE ===');
    print(
      '  bound            : every subset of ${universe.length} driving '
      'tokens up to size 3, plus the empty set',
    );
    print('  paths compared   : $total');
    print('  identical        : $identical');
    print('  differing        : ${differences.length}');
    print('    order only     : $orderOnly');
    print('    question set changed: $setChanged');
    print(
      '      of which truncation selects a different set: '
      '$truncationChanged',
    );
    print('    red-flag question involved: $redFlagImplicated');
    print('');

    if (differences.isNotEmpty) {
      print('  --- first 5 differing paths ---');
      for (final Difference d in differences.take(5)) {
        print('  tokens      : ${d.tokens}');
        print('    live      : ${d.liveRoles} (${d.liveCount})');
        print('    candidate : ${d.candidateIds} (${d.candidateCount})');
        print('    class     : ${d.classification}');
      }
      print('');
    }

    // Write the full record for the PR.
    const String outDir = 'build/w3_question_flow';
    Directory(outDir).createSync(recursive: true);
    File('$outDir/im001_tie_path_evidence.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'report_id': 'im001_tie_path_evidence',
        'artifact_sha256':
            'c403648f8d4d80184879f4d467d4ae74e63df5be77c461298754b82737024998',
        'bound': {
          'driving_tokens': universe,
          'max_tokens_per_combination': 3,
          'combinations_explored': total,
          'exhaustive_over_full_state_space': false,
          'uncovered':
              'Token subsets larger than 3. Larger subsets can only add '
              'eligible questions, so the bound is a coverage limit rather '
              'than a soundness gap.',
        },
        'summary': {
          'paths_compared': total,
          'identical': identical,
          'differing': differences.length,
          'order_only': orderOnly,
          'question_set_changed': setChanged,
          'truncation_selects_different_set': truncationChanged,
          'red_flag_question_involved': redFlagImplicated,
        },
        'activation_verdict': setChanged > 0
            ? 'BLOCKED — deterministic ordering changes which questions are '
                  'asked, not merely their order. This is a path/content '
                  'exposure change and requires product and clinical review.'
            : 'Order-only differences. Still requires review before activation.',
        'differences': differences.map((Difference d) => d.toJson()).toList(),
      }),
    );
    print('  full record: $outDir/im001_tie_path_evidence.json');
    print('');

    // The evidence must exist and be complete; it is not asserted to be empty.
    expect(total, 2325);
    expect(identical + differences.length, total);
  });

  test('ordering is stable under reversed and randomized token input', () {
    // The live engine depends on selection order; the candidate must not.
    for (final List<String> tokens in boundedSubsets(universe).take(300)) {
      final List<String> forward = planInitialPath(
        flow,
        FlowEvaluationState(tokens: tokens.toSet()),
      ).presentedIds;

      final List<String> reversed = planInitialPath(
        flow,
        FlowEvaluationState(tokens: tokens.reversed.toSet()),
      ).presentedIds;
      expect(reversed, forward, reason: 'reversed input changed the plan');

      for (int seed = 0; seed < 3; seed++) {
        final List<String> shuffled = List<String>.of(tokens)
          ..shuffle(Random(seed));
        expect(
          planInitialPath(
            flow,
            FlowEvaluationState(tokens: shuffled.toSet()),
          ).presentedIds,
          forward,
          reason: 'shuffled input (seed $seed) changed the plan',
        );
      }
    }
  });

  test('the live engine IS order-dependent — which is what IM-001 fixes', () {
    // Demonstrates the defect IM-001 addresses, using the live engine only.
    final List<String> found = <String>[];
    for (final List<String> tokens in boundedSubsets(universe)) {
      if (tokens.length < 2) continue;
      final String forward = QuestionEngine.generateQuestions(
        tokens,
      ).map((FollowupQuestion q) => q.questionText).join('|');
      final String backward = QuestionEngine.generateQuestions(
        tokens.reversed.toList(),
      ).map((FollowupQuestion q) => q.questionText).join('|');
      if (forward != backward) {
        found.add(tokens.join('+'));
        if (found.length >= 5) break;
      }
    }

    print('');
    print(
      '  live engine order-dependence: ${found.isEmpty ? "none found" : found}',
    );
    print('');

    expect(
      found,
      isNotEmpty,
      reason:
          'If the live engine were already order-independent, IM-001 would be '
          'a no-op. It is not: reversing the selected token order changes '
          'which wording is asked.',
    );
  });
}
