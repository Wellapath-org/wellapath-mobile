// ignore_for_file: avoid_print
// print() is intentional: this output is the performance evidence recorded in
// docs/W3_QUESTION_FLOW_CONSUMER.md.

/// Performance, memory and determinism for the Question Flow consumer.
///
/// **These are engineering/test-harness measurements only.** The candidate is
/// never parsed in a normal build — it is not an asset and nothing in the
/// application initialises the consumer — so none of this cost is paid by a
/// user. That claim is asserted structurally in
/// `question_flow_contract_test.dart`, not inferred from these numbers.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/question_flow/condition_evaluator.dart';
import 'package:wellapath_mobile/core/question_flow/initial_path_planner.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_loader.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';
import 'package:wellapath_mobile/core/question_flow/question_ordering.dart';

import 'question_flow_contract.dart';
import 'question_flow_test_support.dart';

double _median(List<int> samples) {
  final List<int> s = List<int>.of(samples)..sort();
  final int mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid].toDouble() : (s[mid - 1] + s[mid]) / 2;
}

void main() {
  test('question flow performance and memory baseline', () {
    final List<int> bytes = File(kFlowCandidatePath).readAsBytesSync();
    final Set<String> tokens = liveTokenDictionaryTokens();

    // ── parse + validate ───────────────────────────────────────────────
    final Stopwatch first = Stopwatch()..start();
    final FlowLoadResult result = loadQuestionFlowFromBytes(
      bytes,
      knownTokens: tokens,
    );
    first.stop();
    expect(result.isSuccess, isTrue, reason: '${result.failure}');
    final QuestionFlow flow = result.flow!;

    final List<int> loadSamples = <int>[];
    for (int i = 0; i < 10; i++) {
      final Stopwatch w = Stopwatch()..start();
      loadQuestionFlowFromBytes(bytes, knownTokens: tokens);
      w.stop();
      loadSamples.add(w.elapsedMicroseconds);
    }

    // ── ordering ───────────────────────────────────────────────────────
    final List<int> orderSamples = <int>[];
    for (int i = 0; i < 100; i++) {
      final Stopwatch w = Stopwatch()..start();
      orderFlowQuestions(flow.questions);
      w.stop();
      orderSamples.add(w.elapsedMicroseconds);
    }

    // ── condition evaluation ───────────────────────────────────────────
    const FlowEvaluationState state = FlowEvaluationState(
      tokens: <String>{'headache', 'fever', 'cough'},
      sex: 'female',
      ageToken: 'adults',
      assessmentPhase: 'followup',
    );
    final List<int> evalSamples = <int>[];
    for (int i = 0; i < 2000; i++) {
      final FlowQuestion q = flow.questions[i % flow.questions.length];
      final Stopwatch w = Stopwatch()..start();
      evaluateFlowCondition(q.triggerCondition, state);
      w.stop();
      evalSamples.add(w.elapsedMicroseconds);
    }

    // ── planning ───────────────────────────────────────────────────────
    for (int i = 0; i < 50; i++) {
      planInitialPath(flow, state); // warm
    }
    final List<int> planSamples = <int>[];
    for (int i = 0; i < 500; i++) {
      final Stopwatch w = Stopwatch()..start();
      planInitialPath(flow, state);
      w.stop();
      planSamples.add(w.elapsedMicroseconds);
    }

    // ── memory ─────────────────────────────────────────────────────────
    final int rssBefore = ProcessInfo.currentRss;
    final List<QuestionFlow> held = <QuestionFlow>[
      for (int i = 0; i < 5; i++)
        loadQuestionFlowFromBytes(bytes, knownTokens: tokens).flow!,
    ];
    final int rssAfter = ProcessInfo.currentRss;
    expect(held, hasLength(5));

    final List<int> planSorted = List<int>.of(planSamples)..sort();

    print('');
    print('=== QUESTION FLOW 1.0 PERFORMANCE (engineering harness only) ===');
    print('  artifact bytes            : ${bytes.length}');
    print(
      '  questions / options       : ${flow.questions.length} / '
      '${flow.questions.fold<int>(0, (int s, FlowQuestion q) => s + q.answerOptions.length)}',
    );
    print('  parse + validate (first)  : ${first.elapsedMicroseconds} us');
    print(
      '  parse + validate (median) : ${_median(loadSamples).toStringAsFixed(0)} us',
    );
    print(
      '  deterministic ordering    : ${_median(orderSamples).toStringAsFixed(1)} us',
    );
    print(
      '  condition evaluation      : ${_median(evalSamples).toStringAsFixed(1)} us',
    );
    print(
      '  initial path planning     : ${_median(planSamples).toStringAsFixed(1)} us',
    );
    print(
      '  planning p95              : ${planSorted[(planSorted.length * 0.95).floor()]} us',
    );
    print(
      '  RSS delta, 5 flows held   : '
      '${((rssAfter - rssBefore) / 1024 / 1024).toStringAsFixed(1)} MB',
    );
    print('');
    print(
      '  NOT PAID BY USERS: the candidate is not an asset and the consumer',
    );
    print(
      '  is never initialised by the application, so a normal build parses',
    );
    print('  nothing and plans nothing. Runtime isolation is asserted');
    print('  structurally, not inferred from these numbers.');
    print('');

    // Order-of-magnitude ceilings, far above measured values.
    expect(_median(loadSamples), lessThan(2000000));
    expect(_median(orderSamples), lessThan(100000));
    expect(_median(planSamples), lessThan(100000));
  });

  test('repeated planning is byte-identical', () {
    final QuestionFlow flow = loadCandidateFlow().flow!;
    const FlowEvaluationState state = FlowEvaluationState(
      tokens: <String>{'headache', 'fever'},
    );
    final String first = jsonEncode(planInitialPath(flow, state).presentedIds);
    for (int i = 0; i < 200; i++) {
      expect(jsonEncode(planInitialPath(flow, state).presentedIds), first);
    }
  });

  test('two independently loaded flows agree on every plan', () {
    final QuestionFlow a = loadCandidateFlow().flow!;
    final QuestionFlow b = loadCandidateFlow().flow!;
    for (final String token in <String>[
      'headache',
      'fever',
      'cough',
      'bleeding',
    ]) {
      final FlowEvaluationState s = FlowEvaluationState(
        tokens: <String>{token},
      );
      expect(
        planInitialPath(b, s).presentedIds,
        planInitialPath(a, s).presentedIds,
      );
    }
  });
}
