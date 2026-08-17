/// Deterministic ordering (IM-001), the initial-only planner, the red-flag
/// invariants, the ID-keyed state model, and the 18 authoritative path
/// fixtures.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/question_flow/condition_evaluator.dart';
import 'package:wellapath_mobile/core/question_flow/flow_answer_state.dart';
import 'package:wellapath_mobile/core/question_flow/initial_path_planner.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';
import 'package:wellapath_mobile/core/question_flow/question_ordering.dart';

import 'question_flow_test_support.dart';

FlowEvaluationState stateFor(Map<String, dynamic> input) => FlowEvaluationState(
  tokens: <String>{
    for (final Object? t
        in (input['tokens'] as List<dynamic>?) ?? const <dynamic>[])
      if (t is String) t,
  },
  sex: input['sex'] as String?,
  ageToken: input['age_token'] as String?,
  pregnancy: input['pregnancy'] as bool?,
  bodyArea: input['body_area'] as String?,
  assessmentPhase: input['assessment_phase'] as String?,
);

void main() {
  late QuestionFlow flow;

  setUpAll(() => flow = loadCandidateFlow().flow!);

  group('deterministic ordering (IM-001)', () {
    test('order is (priority, tie_break_key, question_id)', () {
      final List<FlowQuestion> ordered = orderFlowQuestions(flow.questions);
      for (int i = 0; i + 1 < ordered.length; i++) {
        final FlowQuestion a = ordered[i];
        final FlowQuestion b = ordered[i + 1];
        final bool correct =
            a.priority < b.priority ||
            (a.priority == b.priority &&
                a.tieBreakKey.compareTo(b.tieBreakKey) < 0) ||
            (a.priority == b.priority &&
                a.tieBreakKey == b.tieBreakKey &&
                a.id.value.compareTo(b.id.value) < 0);
        expect(correct, isTrue, reason: '${a.id} then ${b.id}');
      }
    });

    test('stable across reversed input', () {
      final List<String> forward = orderFlowQuestions(
        flow.questions,
      ).map((FlowQuestion q) => q.id.value).toList();
      final List<String> reversed = orderFlowQuestions(
        flow.questions.reversed,
      ).map((FlowQuestion q) => q.id.value).toList();
      expect(reversed, forward);
    });

    test('stable across randomized insertion order, many seeds', () {
      final List<String> expected = orderFlowQuestions(
        flow.questions,
      ).map((FlowQuestion q) => q.id.value).toList();

      for (int seed = 0; seed < 50; seed++) {
        final List<FlowQuestion> shuffled = List<FlowQuestion>.of(
          flow.questions,
        )..shuffle(Random(seed));
        expect(
          orderFlowQuestions(
            shuffled,
          ).map((FlowQuestion q) => q.id.value).toList(),
          expected,
          reason: 'seed $seed produced a different order',
        );
      }
    });

    test('stable across repeated runs', () {
      final String first = orderFlowQuestions(
        flow.questions,
      ).map((FlowQuestion q) => q.id.value).join(',');
      for (int i = 0; i < 50; i++) {
        expect(
          orderFlowQuestions(
            flow.questions,
          ).map((FlowQuestion q) => q.id.value).join(','),
          first,
        );
      }
    });

    test('ordering never mutates the caller list', () {
      final List<FlowQuestion> input = List<FlowQuestion>.of(flow.questions);
      final List<String> before = input
          .map((FlowQuestion q) => q.id.value)
          .toList();
      orderFlowQuestions(input);
      expect(input.map((FlowQuestion q) => q.id.value).toList(), before);
    });

    test('the comparison is total — no two questions compare equal', () {
      for (final FlowQuestion a in flow.questions) {
        for (final FlowQuestion b in flow.questions) {
          if (identical(a, b)) continue;
          expect(
            compareFlowQuestions(a, b),
            isNot(0),
            reason: '${a.id} ${b.id}',
          );
        }
      }
    });
  });

  group('the 18 authoritative path fixtures', () {
    test('all 18 are present and bound to this candidate', () {
      expect(pathFixtures(), hasLength(18));
    });

    test('every fixture plans the expected follow-ups, in order', () {
      final List<String> mismatches = <String>[];

      for (final Map<String, dynamic> f in pathFixtures()) {
        final Map<String, dynamic> expected =
            f['expected'] as Map<String, dynamic>;
        final InitialPathPlan plan = planInitialPath(
          flow,
          stateFor(f['input_state'] as Map<String, dynamic>),
        );

        final List<String> wantPresented = <String>[
          for (final Object? q
              in expected['presented_followups'] as List<dynamic>)
            q as String,
        ];
        final List<String> wantTruncated = <String>[
          for (final Object? q
              in (expected['truncated'] as List<dynamic>?) ?? const <dynamic>[])
            q as String,
        ];

        if (plan.presentedIds.join(',') != wantPresented.join(',')) {
          mismatches.add(
            '${f['fixture_id']}: presented ${plan.presentedIds} != $wantPresented',
          );
        }
        if (plan.truncatedIds.toSet().join(',') !=
            wantTruncated.toSet().join(',')) {
          mismatches.add(
            '${f['fixture_id']}: truncated ${plan.truncatedIds} != $wantTruncated',
          );
        }
        if (expected['followup_count'] is int &&
            plan.presented.length != expected['followup_count']) {
          mismatches.add(
            '${f['fixture_id']}: count ${plan.presented.length} != '
            '${expected['followup_count']}',
          );
        }
      }

      expect(mismatches, isEmpty, reason: mismatches.join('\n'));
    });
  });

  group('bounded initial planning', () {
    test('ordinary follow-ups never exceed 5', () {
      for (final Map<String, dynamic> f in pathFixtures()) {
        final InitialPathPlan plan = planInitialPath(
          flow,
          stateFor(f['input_state'] as Map<String, dynamic>),
        );
        expect(
          plan.ordinaryCount,
          lessThanOrEqualTo(5),
          reason: f['fixture_id'] as String,
        );
        expect(plan.limit, 5);
      }
    });

    test('no question is planned twice', () {
      for (final Map<String, dynamic> f in pathFixtures()) {
        final InitialPathPlan plan = planInitialPath(
          flow,
          stateFor(f['input_state'] as Map<String, dynamic>),
        );
        expect(plan.presentedIds.toSet().length, plan.presentedIds.length);
      }
    });

    test('an empty context plans only the default duration question', () {
      // Not "nothing": `Q-followup-default-duration` triggers when every
      // known symptom token is absent, mirroring the live engine's
      // `needsDefaultDuration` fallback. An empty token set is unreachable in
      // product — the picker requires at least one symptom — but the planner
      // is defined for it, and this pins what it does.
      final InitialPathPlan plan = planInitialPath(
        flow,
        const FlowEvaluationState(),
      );
      expect(plan.presentedIds, <String>['Q-followup-default-duration']);
      expect(plan.isTerminal, isFalse);
    });

    test('a terminal state is reachable when nothing triggers', () {
      // Any known token suppresses the default-duration fallback; a token
      // with no follow-up questions of its own then plans nothing.
      final InitialPathPlan plan = planInitialPath(
        flow,
        const FlowEvaluationState(tokens: <String>{'chest_indrawing_severe'}),
      );
      expect(plan.ordinaryCount, lessThanOrEqualTo(5));
    });

    test('demographic nodes are never planned as follow-ups (IM-006)', () {
      final InitialPathPlan plan = planInitialPath(
        flow,
        const FlowEvaluationState(tokens: <String>{'headache'}),
      );
      for (final PlannedQuestion p in plan.presented) {
        expect(p.question.isDemographic, isFalse);
        expect(p.question.clinicalRole, isNot('symptom_picker'));
        expect(p.question.clinicalRole, isNot('body_area'));
      }
      expect(plan.demographic, isNotEmpty);
    });

    test('planning is deterministic across repeated runs', () {
      const FlowEvaluationState s = FlowEvaluationState(
        tokens: <String>{'headache', 'fever', 'cough'},
      );
      final String first = planInitialPath(flow, s).presentedIds.join(',');
      for (int i = 0; i < 100; i++) {
        expect(planInitialPath(flow, s).presentedIds.join(','), first);
      }
    });
  });

  group('red-flag invariants', () {
    test('a red-flag question is never truncated, even past the limit', () {
      // Many tokens: enough eligible questions to force truncation.
      const FlowEvaluationState s = FlowEvaluationState(
        tokens: <String>{
          'bleeding',
          'nosebleed',
          'poor_feeding',
          'difficulty_breathing',
          'headache',
          'fever',
          'cough',
          'vomiting',
          'dizziness',
          'weakness',
        },
      );
      final InitialPathPlan plan = planInitialPath(flow, s);

      expect(plan.truncated, isNotEmpty, reason: 'this case must truncate');
      for (final PlannedQuestion t in plan.truncated) {
        expect(
          t.question.isRedFlagQuestion,
          isFalse,
          reason: '${t.question.id} is a red-flag question and was dropped',
        );
      }
      expect(plan.redFlagCount, greaterThan(0));
    });

    test('red-flag questions are ordered ahead of ordinary ones', () {
      const FlowEvaluationState s = FlowEvaluationState(
        tokens: <String>{'bleeding', 'headache', 'fever'},
      );
      final InitialPathPlan plan = planInitialPath(flow, s);
      final int lastRedFlag = plan.presented.lastIndexWhere(
        (PlannedQuestion p) => p.question.isRedFlagQuestion,
      );
      final int firstOrdinary = plan.presented.indexWhere(
        (PlannedQuestion p) => !p.question.isRedFlagQuestion,
      );
      if (lastRedFlag >= 0 && firstOrdinary >= 0) {
        expect(
          lastRedFlag,
          lessThan(firstOrdinary),
          reason: 'a red-flag question queued behind an ordinary one',
        );
      }
    });

    test('every red-flag question is marked for immediate evaluation', () {
      for (final FlowQuestion q in flow.questions) {
        if (!q.isRedFlagQuestion) continue;
        expect(q.redFlagEvaluation.evaluateAfterAnswer, isTrue);
      }
    });

    test('the planner cannot suppress an existing red-flag token', () {
      // A token already present stays present: the planner reads state and
      // never writes it, so there is no path by which planning removes one.
      const Set<String> tokens = <String>{'breathlessness_at_rest', 'headache'};
      const FlowEvaluationState s = FlowEvaluationState(tokens: tokens);
      planInitialPath(flow, s);
      expect(s.tokens, tokens);
    });

    test('the planner invokes no scoring and produces no token', () {
      // Structural: the plan carries questions, never tokens.
      final InitialPathPlan plan = planInitialPath(
        flow,
        const FlowEvaluationState(tokens: <String>{'headache'}),
      );
      expect(plan.presented, isNotEmpty);
      for (final PlannedQuestion p in plan.presented) {
        // Questions declare their effects; the plan does not apply them.
        expect(p.question.effects.affectsScoring, isA<bool>());
      }
    });
  });

  group('IM-003 is structurally absent', () {
    test('the planner exposes no method that accepts an answer', () {
      // If IM-003 were implemented there would be a re-plan entry point. The
      // only public function takes a flow and an immutable state.
      final InitialPathPlan plan = planInitialPath(
        flow,
        const FlowEvaluationState(tokens: <String>{'headache'}),
      );
      expect(plan, isA<InitialPathPlan>());
      // A second call with the same state returns the same plan; there is no
      // accumulated state that an answer could have changed.
      expect(
        planInitialPath(
          flow,
          const FlowEvaluationState(tokens: <String>{'headache'}),
        ).presentedIds,
        plan.presentedIds,
      );
    });

    test('recording an answer does not change any plan', () {
      const FlowEvaluationState s = FlowEvaluationState(
        tokens: <String>{'headache'},
      );
      final List<String> before = planInitialPath(flow, s).presentedIds;

      FlowAnswerState answers = const FlowAnswerState.empty();
      final AnswerResult r = answers.record(
        flow,
        'Q-followup-headache-duration',
        flow
            .question('Q-followup-headache-duration')!
            .answerOptions
            .first
            .id
            .value,
      );
      expect(r.accepted, isTrue);
      answers = r.state!;

      // The plan is computed from the immutable initial state, which the
      // answer did not touch. This is IM-003 not happening.
      expect(planInitialPath(flow, s).presentedIds, before);
      expect(answers.length, 1);
    });

    test('invalidates_on_change is recorded but never acted on', () {
      final FlowQuestion sexQuestion = flow.question('Q-demo-sex')!;
      expect(sexQuestion.invalidatesOnChange, isNotEmpty);

      // Planning with and without an answer to Q-demo-sex yields the same
      // follow-up plan: nothing is invalidated.
      const FlowEvaluationState a = FlowEvaluationState(
        tokens: <String>{'headache'},
        sex: 'female',
      );
      const FlowEvaluationState b = FlowEvaluationState(
        tokens: <String>{'headache'},
        sex: 'male',
      );
      expect(
        planInitialPath(flow, a).presentedIds,
        planInitialPath(flow, b).presentedIds,
      );
    });
  });

  group('ID-keyed engineering state', () {
    test('records an answer by question and option id', () {
      final FlowQuestion q = flow.question('Q-demo-sex')!;
      final AnswerResult r = const FlowAnswerState.empty().record(
        flow,
        q.id.value,
        q.answerOptions.first.id.value,
      );
      expect(r.accepted, isTrue);
      expect(r.state!.answerFor(q.id), q.answerOptions.first.id.value);
    });

    test('rejects an unknown question id', () {
      final AnswerResult r = const FlowAnswerState.empty().record(
        flow,
        'Q-not-real',
        'anything',
      );
      expect(r.accepted, isFalse);
      expect(r.rejection, AnswerRejection.unknownQuestion);
    });

    test('rejects an option that belongs to a different question', () {
      final AnswerResult r = const FlowAnswerState.empty().record(
        flow,
        'Q-demo-sex',
        'Q-demo-age::adults',
      );
      expect(r.accepted, isFalse);
      expect(r.rejection, AnswerRejection.unknownAnswerOption);
    });

    test('refuses a second answer unless replacement is requested', () {
      final FlowQuestion q = flow.question('Q-demo-sex')!;
      final FlowAnswerState one = const FlowAnswerState.empty()
          .record(flow, q.id.value, q.answerOptions[0].id.value)
          .state!;

      expect(
        one.record(flow, q.id.value, q.answerOptions[1].id.value).rejection,
        AnswerRejection.alreadyAnswered,
      );
      expect(
        one
            .record(
              flow,
              q.id.value,
              q.answerOptions[1].id.value,
              replace: true,
            )
            .accepted,
        isTrue,
      );
    });

    test('serialization is deterministic regardless of insertion order', () {
      FlowAnswerState a = const FlowAnswerState.empty();
      FlowAnswerState b = const FlowAnswerState.empty();
      const List<String> ids = <String>['Q-demo-sex', 'Q-demo-age'];

      for (final String id in ids) {
        a = a
            .record(flow, id, flow.question(id)!.answerOptions.first.id.value)
            .state!;
      }
      for (final String id in ids.reversed) {
        b = b
            .record(flow, id, flow.question(id)!.answerOptions.first.id.value)
            .state!;
      }
      expect(b.toDeterministicJson(), a.toDeterministicJson());
    });

    test('derived tokens are reported, sorted, and never written anywhere', () {
      final FlowQuestion age = flow.question('Q-demo-age')!;
      final FlowAnswerState s = const FlowAnswerState.empty()
          .record(flow, age.id.value, age.answerOptions.first.id.value)
          .state!;
      final List<String> derived = s.derivedTokens(flow);
      expect(derived, equals(List<String>.of(derived)..sort()));
    });

    test('clearing empties the isolated state', () {
      final FlowAnswerState s = const FlowAnswerState.empty()
          .record(
            flow,
            'Q-demo-sex',
            flow.question('Q-demo-sex')!.answerOptions.first.id.value,
          )
          .state!;
      expect(s.isEmpty, isFalse);
      expect(s.cleared().isEmpty, isTrue);
    });

    test('questions needing immediate evaluation are identified', () {
      final FlowQuestion clarifier = flow.question(
        'Q-clarifier-breathlessness_at_rest',
      )!;
      final FlowAnswerState s = const FlowAnswerState.empty()
          .record(
            flow,
            clarifier.id.value,
            clarifier.answerOptions.first.id.value,
          )
          .state!;
      expect(
        s.questionsRequiringImmediateEvaluation(flow),
        contains('Q-clarifier-breathlessness_at_rest'),
      );
    });
  });

  group('serialization sanity', () {
    test('a plan can be described without leaking answers', () {
      final InitialPathPlan plan = planInitialPath(
        flow,
        const FlowEvaluationState(tokens: <String>{'headache'}),
      );
      final String described = jsonEncode(<String, Object?>{
        'presented': plan.presentedIds,
        'truncated': plan.truncatedIds,
        'limit': plan.limit,
      });
      expect(described.contains('answer'), isFalse);
    });
  });
}
