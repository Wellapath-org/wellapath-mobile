/// GF-006 and GF-008 regressions, re-measured here rather than recalled.
///
/// Both defects were found by comparing candidate 1.0 against real live
/// output, not by reading code. A defect recorded in prose and never
/// re-measured is a defect that can come back, so both are pinned against the
/// live `QuestionEngine` itself.
///
/// **GF-006 — default-duration trigger.** Candidate 1.0's trigger was "all 18
/// mapped tokens absent". That fires on the empty selection, where the live
/// engine asks nothing, and fails to fire for `{chest_indrawing_severe,
/// boils}`, where it does — `chest_indrawing_severe` and `fast_breathing_child`
/// are mapped but carry no duration entry.
///
/// **GF-008 — clarifier order.** Candidate 1.0 gave every clarifier priority 0,
/// so ordering fell to the tie-break key, i.e. alphabetical.
/// `kRedFlagClarifiers` is not alphabetical, so the first and third swapped.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/constants/red_flag_clarifiers.dart';
import 'package:wellapath_mobile/features/assessment/models/followup_question.dart';
import 'package:wellapath_mobile/features/assessment/question_engine.dart';
import 'package:wellapath_mobile/core/question_flow/condition_evaluator.dart';
import 'package:wellapath_mobile/core/question_flow/grouped_path_planner.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_loader.dart';
import 'package:wellapath_mobile/core/question_flow/question_grouping_models.dart';
import 'package:wellapath_mobile/core/question_flow/question_ordering.dart';

import '../question_flow/question_flow_test_support.dart';
import 'grouping_test_support.dart';
import 'question_grouping_contract.dart';

/// The live engine's own default-duration wording, read from the engine rather
/// than restated here — a copy could drift.
String _liveDefaultDurationText() {
  final List<FollowupQuestion> questions = QuestionEngine.generateQuestions(
    <String>['boils'],
  );
  final FollowupQuestion duration = questions.firstWhere(
    (FollowupQuestion q) => q.type == QuestionType.duration,
  );
  return duration.questionText;
}

bool _liveAsksDefaultDuration(List<String> tokens, String defaultText) =>
    QuestionEngine.generateQuestions(tokens).any(
      (FollowupQuestion q) =>
          q.type == QuestionType.duration && q.questionText == defaultText,
    );

FlowQuestion _questionById(QuestionFlow flow, String id) =>
    flow.questions.firstWhere((FlowQuestion q) => q.id.value == id);

bool _triggerHolds(FlowQuestion question, List<String> tokens) =>
    evaluateFlowCondition(
      question.triggerCondition,
      FlowEvaluationState(tokens: tokens.toSet(), assessmentPhase: 'followup'),
    );

void main() {
  late QuestionFlow flow11;
  late QuestionFlow flow10;
  late String defaultDurationText;

  setUpAll(() {
    flow11 = groupedFlow();
    final FlowLoadResultLike result = FlowLoadResultLike(loadCandidateFlow());
    flow10 = result.flow;
    defaultDurationText = _liveDefaultDurationText();
  });

  group('GF-006 — default-duration trigger', () {
    // The six authoritative cases.
    const Map<String, List<String>> cases = <String, List<String>>{
      'empty_selection': <String>[],
      'duration_less_mapped_alone': <String>['chest_indrawing_severe'],
      'duration_less_mapped_plus_unmapped': <String>[
        'boils',
        'chest_indrawing_severe',
      ],
      'second_duration_less_mapped_plus_unmapped': <String>[
        'boils',
        'fast_breathing_child',
      ],
      'unmapped_alone': <String>['boils'],
      'unmapped_plus_duration_bearing': <String>['boils', 'fever'],
    };

    /// The three cases candidate 1.0 got wrong, per the knowledge base.
    const Set<String> v10Mismatches = <String>{
      'empty_selection',
      'duration_less_mapped_plus_unmapped',
      'second_duration_less_mapped_plus_unmapped',
    };

    test('candidate 1.1 matches live behaviour on all six cases', () {
      final FlowQuestion fallback11 = _questionById(
        flow11,
        'Q-followup-default-duration',
      );
      final List<String> failures = <String>[];
      cases.forEach((String name, List<String> tokens) {
        final bool live = _liveAsksDefaultDuration(tokens, defaultDurationText);
        final bool candidate = _triggerHolds(fallback11, tokens);
        if (live != candidate) {
          failures.add('$name $tokens: live=$live candidate1.1=$candidate');
        }
      });
      expect(failures, isEmpty, reason: failures.join('\n'));
    });

    test('candidate 1.0 differs on exactly the three documented cases', () {
      final FlowQuestion fallback10 = _questionById(
        flow10,
        'Q-followup-default-duration',
      );
      final Set<String> observed = <String>{};
      cases.forEach((String name, List<String> tokens) {
        final bool live = _liveAsksDefaultDuration(tokens, defaultDurationText);
        if (_triggerHolds(fallback10, tokens) != live) observed.add(name);
      });
      expect(observed, v10Mismatches);
    });

    test('the empty selection asks nothing at all', () {
      expect(QuestionEngine.generateQuestions(const <String>[]), isEmpty);
      expect(planTokens(flow11, const <String>[]).presented, isEmpty);
    });

    test('chest_indrawing_severe and boils follow actual live behaviour', () {
      // Alone, the mapped-but-duration-less token gets no duration question:
      // it IS mapped, so needsDefaultDuration never gets set.
      expect(
        _liveAsksDefaultDuration(const <String>[
          'chest_indrawing_severe',
        ], defaultDurationText),
        isFalse,
      );
      // Add an unmapped token and the fallback appears.
      expect(
        _liveAsksDefaultDuration(const <String>[
          'boils',
          'chest_indrawing_severe',
        ], defaultDurationText),
        isTrue,
      );
      // The candidate agrees with both.
      final GroupedPathPlan alone = planTokens(flow11, <String>[
        'chest_indrawing_severe',
      ]);
      expect(
        alone.presented.where(
          (PresentedQuestion p) => p.clinicalRole == 'duration',
        ),
        isEmpty,
      );
      final GroupedPathPlan withUnmapped = planTokens(flow11, <String>[
        'boils',
        'chest_indrawing_severe',
      ]);
      expect(
        withUnmapped.presented
            .where((PresentedQuestion p) => p.clinicalRole == 'duration')
            .map((PresentedQuestion p) => p.questionText),
        <String>[defaultDurationText],
      );
    });

    test(
      'no duration mapping is invented for the two tokens that lack one',
      () {
        // Neither token may appear as a source of the duration group. Inventing
        // one would give it a duration question the live engine never asks.
        final FlowQuestion durationGroup = flow11.questions.firstWhere(
          (FlowQuestion q) => q.isGrouped && q.grouping!.groupKey == 'duration',
        );
        final Set<String> sourceTokens = <String>{
          for (final QuestionGroupSource s in durationGroup.grouping!.sources)
            s.sourceToken,
        };
        expect(sourceTokens.contains('chest_indrawing_severe'), isFalse);
        expect(sourceTokens.contains('fast_breathing_child'), isFalse);
      },
    );
  });

  group('GF-008 — clarifier declaration order', () {
    test('declaration order is not alphabetical', () {
      final List<String> declaration = <String>[
        for (final RedFlagClarifier c in kRedFlagClarifiers) c.redFlagToken,
      ];
      final List<String> alphabetical = List<String>.of(declaration)..sort();
      expect(declaration, isNot(alphabetical));
      expect(declaration, <String>[
        'breathlessness_at_rest',
        'inability_to_drink',
        'abnormal_bleeding',
      ]);
    });

    test(
      'across all captured paths with 2+ clarifiers: 248 paths, 1.0 wrong on '
      '168, 1.1 wrong on 0',
      () {
        final Map<String, dynamic> doc = oracle();
        int paths = 0;
        int v10Differs = 0;
        int v11Differs = 0;

        final List<FlowQuestion> clarifiers10 = flow10.questions
            .where((FlowQuestion q) => q.clinicalRole == 'red_flag_clarifier')
            .toList();

        for (final OracleCase c in oracleCases(doc, 'forward')) {
          final List<String> live = <String>[
            for (final OracleQuestion q in c.questions)
              if (q.role == 'red_flag_clarifier') q.redFlagToken!,
          ];
          if (live.length < 2) continue;
          paths += 1;

          // Candidate 1.0: every clarifier at priority 0, so the order key
          // falls through to the tie-break key — alphabetical.
          final List<String> v10 = <String>[
            for (final FlowQuestion q in orderFlowQuestions(
              clarifiers10.where(
                (FlowQuestion q) => _triggerHolds(q, c.inputTokens),
              ),
            ))
              q.tieBreakKey,
          ];
          if (!_sameOrder(v10, live)) v10Differs += 1;

          final List<String> v11 = <String>[
            for (final PresentedQuestion p in planTokens(
              flow11,
              c.inputTokens,
            ).presented)
              if (p.clinicalRole == 'red_flag_clarifier') p.redFlagToken!,
          ];
          if (!_sameOrder(v11, live)) v11Differs += 1;
        }

        expect(paths, kGf008PathsWithTwoOrMoreClarifiers);
        expect(v10Differs, kGf008PathsV10DifferedFromLive);
        expect(v11Differs, kGf008PathsV11DifferedFromLive);
      },
    );

    test('equal-priority clarifiers are not reordered alphabetically', () {
      // The path the knowledge base cites: live emits breathlessness first,
      // alphabetical would put abnormal_bleeding first.
      const List<String> tokens = <String>['bleeding', 'difficulty_breathing'];
      final List<String> live = <String>[
        for (final FollowupQuestion q in QuestionEngine.generateQuestions(
          tokens,
        ))
          if (q.type == QuestionType.redFlagClarifier) q.redFlagToken!,
      ];
      expect(live, <String>['breathlessness_at_rest', 'abnormal_bleeding']);

      final List<String> planned = <String>[
        for (final PresentedQuestion p in planTokens(flow11, tokens).presented)
          if (p.clinicalRole == 'red_flag_clarifier') p.redFlagToken!,
      ];
      expect(planned, live);
      expect(planned, isNot(List<String>.of(live)..sort()));
    });

    test('clarifier priorities encode declaration order, not precedence', () {
      // The priorities exist to reproduce emission order. They are not a
      // clinical ranking between danger signs, and nothing here invents one:
      // every clarifier remains individually undroppable and individually
      // evaluated.
      final List<String> declaration = <String>[
        for (final RedFlagClarifier c in kRedFlagClarifiers) c.redFlagToken,
      ];
      final List<FlowQuestion> clarifiers =
          flow11.questions
              .where((FlowQuestion q) => q.clinicalRole == 'red_flag_clarifier')
              .toList()
            ..sort(compareFlowQuestions);
      expect(
        clarifiers.map((FlowQuestion q) => q.tieBreakKey).toList(),
        declaration,
      );
      for (final FlowQuestion q in clarifiers) {
        expect(q.redFlagEvaluation.canAffectRedFlag, isTrue);
        expect(q.redFlagEvaluation.evaluateAfterAnswer, isTrue);
        expect(q.redFlagEvaluation.blocksNextQuestion, isTrue);
      }
    });
  });
}

bool _sameOrder(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Small adapter so a failed 1.0 load surfaces its reason instead of a null.
class FlowLoadResultLike {
  FlowLoadResultLike(FlowLoadResult result)
    : flow = result.isSuccess
          ? result.flow!
          : throw StateError('candidate 1.0 failed to load: ${result.failure}');

  final QuestionFlow flow;
}
