/// All 13 condition operators, plus the fail-closed rules the contract states
/// so two implementations cannot silently disagree.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/question_flow/condition_evaluator.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';

FlowCondition tokenPresent(String t) =>
    FlowCondition(operator: ConditionOperator.tokenPresent, token: t);
FlowCondition tokenAbsent(String t) =>
    FlowCondition(operator: ConditionOperator.tokenAbsent, token: t);
const FlowCondition alwaysTrue = FlowCondition(
  operator: ConditionOperator.always,
  value: true,
);
const FlowCondition neverTrue = FlowCondition(
  operator: ConditionOperator.never,
  value: true,
);

void main() {
  const FlowEvaluationState empty = FlowEvaluationState();

  group('always / never', () {
    test('always is true, never is false, regardless of state', () {
      expect(evaluateFlowCondition(alwaysTrue, empty), isTrue);
      expect(evaluateFlowCondition(neverTrue, empty), isFalse);
      const FlowEvaluationState full = FlowEvaluationState(
        tokens: <String>{'fever'},
        sex: 'female',
        ageToken: 'adults',
        pregnancy: true,
      );
      expect(evaluateFlowCondition(alwaysTrue, full), isTrue);
      expect(evaluateFlowCondition(neverTrue, full), isFalse);
    });
  });

  group('all / any / not', () {
    test('an empty all is TRUE and an empty any is FALSE', () {
      // Stated by the contract precisely so implementations cannot diverge.
      expect(
        evaluateFlowCondition(
          const FlowCondition(operator: ConditionOperator.all),
          empty,
        ),
        isTrue,
      );
      expect(
        evaluateFlowCondition(
          const FlowCondition(operator: ConditionOperator.any),
          empty,
        ),
        isFalse,
      );
    });

    test('all requires every child', () {
      const FlowEvaluationState s = FlowEvaluationState(
        tokens: <String>{'fever', 'cough'},
      );
      expect(
        evaluateFlowCondition(
          FlowCondition(
            operator: ConditionOperator.all,
            children: <FlowCondition>[
              tokenPresent('fever'),
              tokenPresent('cough'),
            ],
          ),
          s,
        ),
        isTrue,
      );
      expect(
        evaluateFlowCondition(
          FlowCondition(
            operator: ConditionOperator.all,
            children: <FlowCondition>[
              tokenPresent('fever'),
              tokenPresent('headache'),
            ],
          ),
          s,
        ),
        isFalse,
      );
    });

    test('any requires one child', () {
      const FlowEvaluationState s = FlowEvaluationState(
        tokens: <String>{'fever'},
      );
      expect(
        evaluateFlowCondition(
          FlowCondition(
            operator: ConditionOperator.any,
            children: <FlowCondition>[
              tokenPresent('headache'),
              tokenPresent('fever'),
            ],
          ),
          s,
        ),
        isTrue,
      );
      expect(
        evaluateFlowCondition(
          FlowCondition(
            operator: ConditionOperator.any,
            children: <FlowCondition>[
              tokenPresent('headache'),
              tokenPresent('cough'),
            ],
          ),
          s,
        ),
        isFalse,
      );
    });

    test('not inverts, and needs exactly one child', () {
      expect(
        evaluateFlowCondition(
          const FlowCondition(
            operator: ConditionOperator.not,
            children: <FlowCondition>[alwaysTrue],
          ),
          empty,
        ),
        isFalse,
      );
      expect(
        () => evaluateFlowCondition(
          const FlowCondition(
            operator: ConditionOperator.not,
            children: <FlowCondition>[alwaysTrue, neverTrue],
          ),
          empty,
        ),
        throwsA(isA<ConditionContractFailure>()),
      );
    });
  });

  group('token_present / token_absent', () {
    const FlowEvaluationState s = FlowEvaluationState(
      tokens: <String>{'fever'},
    );

    test('present is exact, never fuzzy', () {
      expect(evaluateFlowCondition(tokenPresent('fever'), s), isTrue);
      expect(evaluateFlowCondition(tokenPresent('fevers'), s), isFalse);
      expect(evaluateFlowCondition(tokenPresent('fev'), s), isFalse);
      expect(evaluateFlowCondition(tokenPresent('FEVER'), s), isFalse);
    });

    test('absent is the complement', () {
      expect(evaluateFlowCondition(tokenAbsent('fever'), s), isFalse);
      expect(evaluateFlowCondition(tokenAbsent('headache'), s), isTrue);
    });
  });

  group('demographic gates — not stated is not "no"', () {
    test('sex', () {
      const FlowCondition female = FlowCondition(
        operator: ConditionOperator.sex,
        value: 'female',
      );
      expect(
        evaluateFlowCondition(female, const FlowEvaluationState(sex: 'female')),
        isTrue,
      );
      expect(
        evaluateFlowCondition(female, const FlowEvaluationState(sex: 'male')),
        isFalse,
      );
      expect(
        evaluateFlowCondition(female, empty),
        isFalse,
        reason:
            'Sex not stated must make the gate false — the question is not '
            'asked, rather than wrongly asked.',
      );
    });

    test('pregnancy', () {
      const FlowCondition pregnant = FlowCondition(
        operator: ConditionOperator.pregnancy,
        value: true,
      );
      expect(
        evaluateFlowCondition(
          pregnant,
          const FlowEvaluationState(pregnancy: true),
        ),
        isTrue,
      );
      expect(
        evaluateFlowCondition(
          pregnant,
          const FlowEvaluationState(pregnancy: false),
        ),
        isFalse,
      );
      expect(evaluateFlowCondition(pregnant, empty), isFalse);
    });

    test('age_range', () {
      const FlowCondition adultish = FlowCondition(
        operator: ConditionOperator.ageRange,
        values: <Object?>['adults', 'over_40'],
      );
      expect(
        evaluateFlowCondition(
          adultish,
          const FlowEvaluationState(ageToken: 'adults'),
        ),
        isTrue,
      );
      expect(
        evaluateFlowCondition(
          adultish,
          const FlowEvaluationState(ageToken: 'children_under_5'),
        ),
        isFalse,
      );
      expect(
        evaluateFlowCondition(adultish, empty),
        isFalse,
        reason: 'Unknown age makes the gated condition ineligible.',
      );
    });
  });

  group('equals / one_of', () {
    test('equals reads a declared field', () {
      const FlowCondition c = FlowCondition(
        operator: ConditionOperator.equals,
        field: 'body_area',
        value: 'Chest',
      );
      expect(
        evaluateFlowCondition(c, const FlowEvaluationState(bodyArea: 'Chest')),
        isTrue,
      );
      expect(
        evaluateFlowCondition(c, const FlowEvaluationState(bodyArea: 'Head')),
        isFalse,
      );
      expect(evaluateFlowCondition(c, empty), isFalse);
    });

    test('one_of matches any listed value', () {
      const FlowCondition c = FlowCondition(
        operator: ConditionOperator.oneOf,
        field: 'assessment_phase',
        values: <Object?>['followup', 'clarifier'],
      );
      expect(
        evaluateFlowCondition(
          c,
          const FlowEvaluationState(assessmentPhase: 'followup'),
        ),
        isTrue,
      );
      expect(
        evaluateFlowCondition(
          c,
          const FlowEvaluationState(assessmentPhase: 'demographic'),
        ),
        isFalse,
      );
    });

    test('an unknown field is a contract failure, never false', () {
      expect(
        () => evaluateFlowCondition(
          const FlowCondition(
            operator: ConditionOperator.equals,
            field: 'not_a_field',
            value: 1,
          ),
          empty,
        ),
        throwsA(isA<ConditionContractFailure>()),
        reason:
            'Silently returning false would hide a malformed condition behind '
            'a plausible-looking "not eligible".',
      );
    });
  });

  group('prior_answer_equals', () {
    const FlowCondition c = FlowCondition(
      operator: ConditionOperator.priorAnswerEquals,
      questionId: 'Q-demo-sex',
      value: 'Q-demo-sex::female',
    );

    test('matches a recorded answer', () {
      expect(
        evaluateFlowCondition(
          c,
          const FlowEvaluationState(
            priorAnswers: <String, String>{'Q-demo-sex': 'Q-demo-sex::female'},
          ),
        ),
        isTrue,
      );
    });

    test('a different answer does not match', () {
      expect(
        evaluateFlowCondition(
          c,
          const FlowEvaluationState(
            priorAnswers: <String, String>{'Q-demo-sex': 'Q-demo-sex::male'},
          ),
        ),
        isFalse,
      );
    });

    test('a MISSING prior answer is never an affirmative match', () {
      expect(
        evaluateFlowCondition(c, empty),
        isFalse,
        reason:
            'An unanswered question is not the same as an answer that happens '
            'to match.',
      );
    });
  });

  group('properties', () {
    final List<FlowCondition> corpus = <FlowCondition>[
      alwaysTrue,
      neverTrue,
      tokenPresent('fever'),
      tokenAbsent('fever'),
      FlowCondition(
        operator: ConditionOperator.all,
        children: <FlowCondition>[tokenPresent('fever'), tokenAbsent('cough')],
      ),
      FlowCondition(
        operator: ConditionOperator.any,
        children: <FlowCondition>[tokenPresent('x'), tokenPresent('fever')],
      ),
    ];

    const FlowEvaluationState state = FlowEvaluationState(
      tokens: <String>{'fever'},
      sex: 'female',
      ageToken: 'adults',
    );

    test('repeated evaluation over the same state is identical', () {
      for (final FlowCondition c in corpus) {
        final bool first = evaluateFlowCondition(c, state);
        for (int i = 0; i < 200; i++) {
          expect(evaluateFlowCondition(c, state), first);
        }
      }
    });

    test('evaluation is finite even on deeply nested conditions', () {
      FlowCondition nested = tokenPresent('fever');
      for (int i = 0; i < 200; i++) {
        nested = FlowCondition(
          operator: ConditionOperator.all,
          children: <FlowCondition>[nested],
        );
      }
      expect(evaluateFlowCondition(nested, state), isTrue);
    });

    test('the evaluator reads no field outside the declared four', () {
      for (final String field in kConditionFields) {
        expect(
          () => const FlowEvaluationState().readField(field),
          returnsNormally,
        );
      }
      expect(
        () => const FlowEvaluationState().readField('tokens'),
        throwsA(isA<ConditionContractFailure>()),
      );
    });
  });
}
