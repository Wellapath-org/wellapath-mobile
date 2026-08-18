/// Performance and determinism for the 1.1 consumer, measured in the
/// engineering harness.
///
/// **No user pays any of this.** The candidate is not an asset and the
/// consumer is never initialised by the application, so a normal build parses
/// nothing and plans nothing. That is asserted structurally in
/// `grouping_isolation_test.dart`, not inferred from these numbers — the
/// figures here exist to characterise the harness, not to argue the app is
/// unaffected.
///
/// Thresholds are deliberately loose. A tight bound on shared CI hardware
/// produces flaky failures that get muted, and a muted performance test is
/// worse than none. These catch an order-of-magnitude regression, which is the
/// only kind worth failing a build over.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/question_flow/grouped_path_planner.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_loader.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';
import 'package:wellapath_mobile/core/question_flow/question_grouping_models.dart';

import '../question_flow/question_flow_test_support.dart';
import 'grouping_test_support.dart';
import 'question_grouping_contract.dart';

int _medianMicros(List<int> samples) {
  final List<int> sorted = List<int>.of(samples)..sort();
  return sorted[sorted.length ~/ 2];
}

void main() {
  test('1.1 parse and full validation, median of 10', () {
    final List<int> bytes = File(kGroupingCandidatePath).readAsBytesSync();
    final Set<String> tokens = liveTokenDictionaryTokens();
    final List<int> samples = <int>[];
    for (int i = 0; i < 10; i++) {
      final Stopwatch watch = Stopwatch()..start();
      final FlowLoadResult result = loadQuestionFlowFromBytes(
        bytes,
        knownTokens: tokens,
      );
      watch.stop();
      expect(result.isSuccess, isTrue);
      samples.add(watch.elapsedMicroseconds);
    }
    final int median = _medianMicros(samples);
    // ignore: avoid_print — this is the measurement the test exists to report.
    print('1.1 parse + validate: ${median}us median (${bytes.length} B)');
    expect(median, lessThan(2000000));
  });

  test('grouping, option union and ordering for a five-token path', () {
    final QuestionFlow flow = groupedFlow();
    const List<String> tokens = <String>[
      'difficulty_breathing',
      'poor_feeding',
      'bleeding',
      'headache',
      'fever',
    ];
    final List<int> samples = <int>[];
    for (int i = 0; i < 200; i++) {
      final Stopwatch watch = Stopwatch()..start();
      planTokens(flow, tokens);
      watch.stop();
      samples.add(watch.elapsedMicroseconds);
    }
    final int median = _medianMicros(samples);
    // ignore: avoid_print — measurement output.
    print('grouped plan (5 tokens): ${median}us median');
    expect(median, lessThan(50000));
  });

  test('option union over the widest group', () {
    final QuestionFlow flow = groupedFlow();
    final FlowQuestion additional = flow.questions.firstWhere(
      (FlowQuestion q) =>
          q.isGrouped && q.grouping!.groupKey == 'additional_symptoms',
    );
    final List<String> allSourceTokens = <String>[
      for (final QuestionGroupSource s in additional.grouping!.sources)
        s.sourceToken,
    ];
    final List<int> samples = <int>[];
    late GroupedPathPlan plan;
    for (int i = 0; i < 100; i++) {
      final Stopwatch watch = Stopwatch()..start();
      plan = planTokens(flow, allSourceTokens);
      watch.stop();
      samples.add(watch.elapsedMicroseconds);
    }
    final int median = _medianMicros(samples);
    final PresentedQuestion merged = plan.presented.firstWhere(
      (PresentedQuestion p) => p.groupKey == 'additional_symptoms',
    );
    // ignore: avoid_print — measurement output.
    print(
      'option union (${additional.grouping!.sources.length} sources -> '
      '${merged.optionIds.length} options): ${median}us median',
    );
    expect(median, lessThan(50000));
    // Every source contributed, and nothing was duplicated.
    expect(merged.contributingSourceIds, hasLength(18));
    expect(merged.optionIds.toSet(), hasLength(merged.optionIds.length));
  });

  test('the full 2,325-path oracle comparison runs in reasonable time', () {
    final QuestionFlow flow = groupedFlow();
    final List<OracleCase> cases = oracleCases(oracle(), 'forward');
    final Stopwatch watch = Stopwatch()..start();
    for (final OracleCase c in cases) {
      planTokens(flow, c.inputTokens);
    }
    watch.stop();
    // ignore: avoid_print — measurement output.
    print(
      '${cases.length} plans in ${watch.elapsedMilliseconds}ms '
      '(${(watch.elapsedMicroseconds / cases.length).round()}us each)',
    );
    expect(watch.elapsedMilliseconds, lessThan(60000));
  });

  test('memory: five loaded 1.1 flows held at once', () {
    final Set<String> tokens = liveTokenDictionaryTokens();
    final List<int> bytes = File(kGroupingCandidatePath).readAsBytesSync();
    final int before = ProcessInfo.currentRss;
    final List<QuestionFlow> flows = <QuestionFlow>[
      for (int i = 0; i < 5; i++)
        loadQuestionFlowFromBytes(bytes, knownTokens: tokens).flow!,
    ];
    final int after = ProcessInfo.currentRss;
    expect(flows, hasLength(5));
    // ignore: avoid_print — measurement output.
    print(
      'RSS with 5 flows held: ${(after / 1024 / 1024).toStringAsFixed(1)} MB '
      '(delta ${((after - before) / 1024 / 1024).toStringAsFixed(1)} MB)',
    );
    expect(after, lessThan(2048 * 1024 * 1024));
  });

  test('repeated planning is byte-identical, run after run', () {
    final QuestionFlow flow = groupedFlow();
    const List<String> tokens = <String>['cough', 'fever', 'headache'];
    final GroupedPathPlan reference = planTokens(flow, tokens);
    final String signature = <String>[
      for (final PresentedQuestion p in reference.presented)
        '${p.question.id.value}|${p.questionText}|${p.optionIds.join(",")}|'
            '${p.contributingSourceIds.join(",")}',
    ].join(';');

    for (int i = 0; i < 100; i++) {
      final GroupedPathPlan plan = planTokens(flow, tokens);
      final String again = <String>[
        for (final PresentedQuestion p in plan.presented)
          '${p.question.id.value}|${p.questionText}|${p.optionIds.join(",")}|'
              '${p.contributingSourceIds.join(",")}',
      ].join(';');
      expect(again, signature, reason: 'run $i diverged');
    }
  });

  test('reloading the artifact produces an identical plan', () {
    // Guards against any hidden dependence on load order or map iteration.
    const List<String> tokens = <String>['bleeding', 'fever', 'body_pain'];
    final List<String> first = planTokens(groupedFlow(), tokens).presentedIds;
    for (int i = 0; i < 5; i++) {
      expect(planTokens(groupedFlow(), tokens).presentedIds, first);
    }
  });
}
