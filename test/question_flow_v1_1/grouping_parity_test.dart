/// Independent reproduction of the knowledge base's captured-Dart parity
/// evidence, computed here rather than copied.
///
/// The comparison target is the captured output of the real
/// `QuestionEngine.generateQuestions` at Mobile 657739cc. Nothing in this file
/// normalises, rewrites or filters the oracle to obtain a pass: every
/// difference found is reported, and the assertions are for zero.
///
/// Comparison keys are declared, not chosen to flatter the result:
///
///  * QUESTION SET — the multiset of (clinical_role, red_flag_token). This is
///    WHICH question is asked; wording is compared separately, because on
///    order-sensitive paths the live engine has two different answers and no
///    single projection can match both.
///  * OPTIONS — only for the roles whose live `FollowupQuestion` carries them.
///    Severity and duration carry an empty list, so there is nothing to
///    compare and no match is claimed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/question_flow/grouped_path_planner.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';

import 'grouping_test_support.dart';
import 'question_grouping_contract.dart';

/// Everything one path can disagree about.
class ParityCounters {
  int pathsCompared = 0;
  int identical = 0;
  int questionSet = 0;
  int questionOrder = 0;
  int wording = 0;
  int optionSet = 0;
  int optionOrder = 0;
  int tokenEffects = 0;
  int redFlagEffects = 0;
  int truncation = 0;
  int redFlagDropped = 0;
  int pathLimitExceeded = 0;
  final List<String> samples = <String>[];

  void note(String detail) {
    if (samples.length < 20) samples.add(detail);
  }

  @override
  String toString() =>
      'compared=$pathsCompared identical=$identical set=$questionSet '
      'order=$questionOrder wording=$wording optionSet=$optionSet '
      'optionOrder=$optionOrder tokens=$tokenEffects redFlags=$redFlagEffects '
      'truncation=$truncation redFlagDropped=$redFlagDropped '
      'overLimit=$pathLimitExceeded';
}

ParityCounters _compareForward(QuestionFlow flow, List<OracleCase> cases) {
  final ParityCounters counters = ParityCounters();

  for (final OracleCase liveCase in cases) {
    counters.pathsCompared += 1;
    final GroupedPathPlan plan = planTokens(flow, liveCase.inputTokens);
    final List<PresentedQuestion> planned = plan.presented;
    bool clean = true;

    // ── question set, as a multiset of identities ─────────────────────────
    final List<String> liveIdentities = <String>[
      for (final OracleQuestion q in liveCase.questions)
        identityKey(q.role, q.redFlagToken),
    ]..sort();
    final List<String> plannedIdentities = <String>[
      for (final PresentedQuestion p in planned)
        identityKey(p.clinicalRole, p.redFlagToken),
    ]..sort();

    if (!_listEquals(liveIdentities, plannedIdentities)) {
      counters.questionSet += 1;
      clean = false;
      counters.note(
        '${liveCase.inputTokens}: set live=$liveIdentities '
        'candidate=$plannedIdentities',
      );
    } else {
      // ── order ───────────────────────────────────────────────────────────
      final List<String> liveOrder = <String>[
        for (final OracleQuestion q in liveCase.questions)
          identityKey(q.role, q.redFlagToken),
      ];
      final List<String> plannedOrder = <String>[
        for (final PresentedQuestion p in planned)
          identityKey(p.clinicalRole, p.redFlagToken),
      ];
      if (!_listEquals(liveOrder, plannedOrder)) {
        counters.questionOrder += 1;
        clean = false;
        counters.note(
          '${liveCase.inputTokens}: order live=$liveOrder '
          'candidate=$plannedOrder',
        );
      } else {
        // ── wording, options and token effects, positionally ─────────────
        for (int i = 0; i < liveCase.questions.length; i++) {
          final OracleQuestion live = liveCase.questions[i];
          final PresentedQuestion candidate = planned[i];

          if (live.questionText != candidate.questionText) {
            counters.wording += 1;
            clean = false;
            counters.note(
              '${liveCase.inputTokens}: wording live="${live.questionText}" '
              'candidate="${candidate.questionText}"',
            );
          }

          if (kRolesWithComparableOptions.contains(live.role)) {
            final List<String> liveOptions = live.options;
            final List<String> candidateOptions = candidate.optionLabels;
            final List<String> liveSorted = List<String>.of(liveOptions)
              ..sort();
            final List<String> candidateSorted = List<String>.of(
              candidateOptions,
            )..sort();
            if (!_listEquals(liveSorted, candidateSorted)) {
              counters.optionSet += 1;
              clean = false;
              counters.note(
                '${liveCase.inputTokens}: option set ${live.role} '
                'live=$liveOptions candidate=$candidateOptions',
              );
            } else if (!_listEquals(liveOptions, candidateOptions)) {
              counters.optionOrder += 1;
              clean = false;
              counters.note(
                '${liveCase.inputTokens}: option order ${live.role} '
                'live=$liveOptions candidate=$candidateOptions',
              );
            }
          }

          final Set<String>? expectedTokens = liveProducedTokens(live);
          if (expectedTokens != null) {
            final Set<String> actual = candidate.producedTokens.toSet();
            if (!_setEquals(expectedTokens, actual)) {
              counters.tokenEffects += 1;
              clean = false;
              counters.note(
                '${liveCase.inputTokens}: tokens ${live.role} '
                'live=$expectedTokens candidate=$actual',
              );
            }
          }
        }
      }
    }

    // ── red-flag effects ──────────────────────────────────────────────────
    final List<String> liveRedFlags = <String>[
      for (final OracleQuestion q in liveCase.questions)
        if (q.role == 'red_flag_clarifier') q.redFlagToken!,
    ]..sort();
    final List<String> plannedRedFlags = <String>[
      for (final PresentedQuestion p in planned)
        if (p.clinicalRole == 'red_flag_clarifier') p.redFlagToken!,
    ]..sort();
    if (!_listEquals(liveRedFlags, plannedRedFlags)) {
      counters.redFlagEffects += 1;
      clean = false;
      counters.note(
        '${liveCase.inputTokens}: red flags live=$liveRedFlags '
        'candidate=$plannedRedFlags',
      );
    }

    if (plan.droppedRedFlagIds.isNotEmpty) {
      counters.redFlagDropped += 1;
      clean = false;
      counters.note(
        '${liveCase.inputTokens}: dropped red flags ${plan.droppedRedFlagIds}',
      );
    }

    if (liveCase.questions.length != planned.length) {
      counters.truncation += 1;
      clean = false;
      counters.note(
        '${liveCase.inputTokens}: count live=${liveCase.questions.length} '
        'candidate=${planned.length}',
      );
    }

    if (planned.length > plan.limit) {
      counters.pathLimitExceeded += 1;
      clean = false;
    }

    if (clean) counters.identical += 1;
  }

  return counters;
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

void main() {
  late QuestionFlow flow;
  late Map<String, dynamic> oracleDoc;

  setUpAll(() {
    flow = groupedFlow();
    oracleDoc = oracle();
  });

  group('captured-Dart forward parity, all 2,325 paths', () {
    late ParityCounters counters;

    setUpAll(() {
      counters = _compareForward(flow, oracleCases(oracleDoc, 'forward'));
    });

    test('every path was compared', () {
      expect(counters.pathsCompared, kOracleForwardCases);
    });

    test('2,325 of 2,325 identical', () {
      expect(
        counters.identical,
        kExpectedForwardMatches,
        reason: 'differences:\n${counters.samples.join('\n')}',
      );
    });

    test('zero question-set differences', () {
      expect(counters.questionSet, 0, reason: counters.samples.join('\n'));
    });

    test('zero question-order differences', () {
      expect(counters.questionOrder, 0, reason: counters.samples.join('\n'));
    });

    test('zero wording differences', () {
      expect(counters.wording, 0, reason: counters.samples.join('\n'));
    });

    test('zero option-set differences', () {
      expect(counters.optionSet, 0, reason: counters.samples.join('\n'));
    });

    test('zero option-order differences', () {
      expect(counters.optionOrder, 0, reason: counters.samples.join('\n'));
    });

    test('zero token-effect differences', () {
      expect(counters.tokenEffects, 0, reason: counters.samples.join('\n'));
    });

    test('zero red-flag-effect differences', () {
      expect(counters.redFlagEffects, 0, reason: counters.samples.join('\n'));
    });

    test('zero truncation differences', () {
      expect(counters.truncation, 0, reason: counters.samples.join('\n'));
    });

    test('zero red-flag questions dropped', () {
      expect(counters.redFlagDropped, 0, reason: counters.samples.join('\n'));
    });

    test('zero path-limit violations', () {
      expect(counters.pathLimitExceeded, 0);
    });

    test('our figures agree with the knowledge base report', () {
      // The KB computed these independently. Agreeing is evidence; the
      // assertion above is what actually proves this consumer correct.
      final Map<String, dynamic> report = readJson(kParityReportPath);
      final Map<String, dynamic> forward =
          report['forward'] as Map<String, dynamic>;
      expect(forward['paths_compared'], counters.pathsCompared);
      expect(forward['identical'], counters.identical);
      expect(forward['question_set_differences'], counters.questionSet);
      expect(forward['option_set_differences'], counters.optionSet);
      expect(forward['token_effect_differences'], counters.tokenEffects);
      expect(forward['red_flag_effect_differences'], counters.redFlagEffects);
      expect(forward['truncation_count_differences'], counters.truncation);
    });
  });

  group('reversed selection order', () {
    late int liveWordingUnstable;
    late int liveOptionUnstable;
    late int liveAnyUnstable;
    late int liveRoleUnstable;
    late int candidateUnstable;
    late int setChanged;
    late int optionChanged;
    late int tokenChanged;
    late int redFlagChanged;
    late int truncationChanged;

    setUpAll(() {
      final Map<String, OracleCase> forwardByKey = <String, OracleCase>{
        for (final OracleCase c in oracleCases(oracleDoc, 'forward')) c.key: c,
      };
      liveWordingUnstable = 0;
      liveOptionUnstable = 0;
      liveAnyUnstable = 0;
      liveRoleUnstable = 0;
      candidateUnstable = 0;
      setChanged = 0;
      optionChanged = 0;
      tokenChanged = 0;
      redFlagChanged = 0;
      truncationChanged = 0;

      for (final OracleCase reversedCase in oracleCases(
        oracleDoc,
        'reversed',
      )) {
        final OracleCase forwardCase = forwardByKey[reversedCase.key]!;

        // Does the LIVE engine disagree with itself? Measured three ways,
        // because they do not give the same answer and only one of them is
        // the knowledge base's published figure.
        final List<String> forwardWording = <String>[
          for (final OracleQuestion q in forwardCase.questions) q.questionText,
        ];
        final List<String> reversedWording = <String>[
          for (final OracleQuestion q in reversedCase.questions) q.questionText,
        ];
        final List<String> forwardOptions = <String>[
          for (final OracleQuestion q in forwardCase.questions)
            q.options.join(','),
        ];
        final List<String> reversedOptions = <String>[
          for (final OracleQuestion q in reversedCase.questions)
            q.options.join(','),
        ];
        final List<String> forwardRoles = <String>[
          for (final OracleQuestion q in forwardCase.questions) q.role,
        ];
        final List<String> reversedRoles = <String>[
          for (final OracleQuestion q in reversedCase.questions) q.role,
        ];

        final bool wordingDiffers = !_listEquals(
          forwardWording,
          reversedWording,
        );
        final bool optionsDiffer = !_listEquals(
          forwardOptions,
          reversedOptions,
        );
        final bool rolesDiffer = !_listEquals(forwardRoles, reversedRoles);

        if (wordingDiffers) liveWordingUnstable += 1;
        if (optionsDiffer) liveOptionUnstable += 1;
        if (rolesDiffer) liveRoleUnstable += 1;
        if (wordingDiffers || optionsDiffer || rolesDiffer) {
          liveAnyUnstable += 1;
        }

        // Does the CANDIDATE? It takes a set, so it must not.
        final GroupedPathPlan forwardPlan = planTokens(
          flow,
          forwardCase.inputTokens,
        );
        final GroupedPathPlan reversedPlan = planTokens(
          flow,
          reversedCase.inputTokens,
        );

        final List<String> forwardIds = forwardPlan.presentedIds;
        final List<String> reversedIds = reversedPlan.presentedIds;
        final List<String> forwardText = <String>[
          for (final PresentedQuestion p in forwardPlan.presented)
            p.questionText,
        ];
        final List<String> reversedText = <String>[
          for (final PresentedQuestion p in reversedPlan.presented)
            p.questionText,
        ];
        final List<String> forwardPlanOptions = <String>[
          for (final PresentedQuestion p in forwardPlan.presented)
            p.optionIds.join(','),
        ];
        final List<String> reversedPlanOptions = <String>[
          for (final PresentedQuestion p in reversedPlan.presented)
            p.optionIds.join(','),
        ];

        if (!_listEquals(forwardIds, reversedIds) ||
            !_listEquals(forwardText, reversedText) ||
            !_listEquals(forwardPlanOptions, reversedPlanOptions)) {
          candidateUnstable += 1;
        }

        // What specifically changes on a reversed path, reported separately.
        if (!_listEquals(forwardIds, reversedIds)) setChanged += 1;
        if (!_listEquals(forwardPlanOptions, reversedPlanOptions)) {
          optionChanged += 1;
        }

        final List<String> forwardTokens = <String>[
          for (final PresentedQuestion p in forwardPlan.presented)
            p.producedTokens.join(','),
        ];
        final List<String> reversedTokens = <String>[
          for (final PresentedQuestion p in reversedPlan.presented)
            p.producedTokens.join(','),
        ];
        if (!_listEquals(forwardTokens, reversedTokens)) tokenChanged += 1;

        final List<String> forwardFlags = <String>[
          for (final PresentedQuestion p in forwardPlan.presented)
            if (p.redFlagToken != null) p.redFlagToken!,
        ];
        final List<String> reversedFlags = <String>[
          for (final PresentedQuestion p in reversedPlan.presented)
            if (p.redFlagToken != null) p.redFlagToken!,
        ];
        if (!_listEquals(forwardFlags, reversedFlags)) redFlagChanged += 1;

        if (!_listEquals(forwardPlan.truncatedIds, reversedPlan.truncatedIds)) {
          truncationChanged += 1;
        }
      }
    });

    test('the live engine disagrees with itself on 1,680 of 2,300 paths', () {
      // The knowledge base's published figure, and the one the step specifies.
      // It compares the sequence of question WORDINGS.
      expect(liveWordingUnstable, kExpectedLiveReversedInstability);
    });

    test('live option ordering is unstable on MORE paths than wording', () {
      // Not a contradiction of the figure above — a different measurement.
      // The live engine appends additional-symptom options in tap order, so a
      // path can show identical wording with a different option order. This
      // makes the baseline instability BROADER than the headline number, not
      // narrower, and it is disclosed rather than folded into one figure.
      expect(liveOptionUnstable, kLiveReversedOptionInstability);
      expect(liveAnyUnstable, kLiveReversedAnyInstability);
      expect(
        liveAnyUnstable - liveWordingUnstable,
        kLiveReversedOptionOnlyInstability,
        reason: 'paths where wording is identical but option order is not',
      );
      // Which questions get asked never depends on order — only how they are
      // worded and how their options are arranged.
      expect(liveRoleUnstable, 0);
    });

    test('the candidate is unstable on 0 of 2,300 paths', () {
      expect(candidateUnstable, kExpectedCandidateReversedInstability);
    });

    test('no reversed path changes the question set', () {
      expect(setChanged, 0);
    });

    test('no reversed path changes the answer-option set', () {
      expect(optionChanged, 0);
    });

    test('no reversed path changes token effects', () {
      expect(tokenChanged, 0);
    });

    test('no reversed path changes red-flag effects', () {
      expect(redFlagChanged, 0);
    });

    test('no reversed path changes the truncation set', () {
      expect(truncationChanged, 0);
    });

    test('IM-001 is NOT activation-ready: wording review is still pending', () {
      // Stability is necessary and not sufficient. Which of two existing
      // wordings is shown is a product decision, and all 135 are open.
      final Map<String, dynamic> report = readJson(kIm001ReviewReportPath);
      final Map<String, dynamic> signOff =
          report['sign_off'] as Map<String, dynamic>;
      expect(signOff['status'], 'PENDING');
      expect(signOff['blocks_activation'], isTrue);
    });
  });

  group('determinism under repetition and shuffling', () {
    test('the same token set yields a byte-identical plan every time', () {
      const List<String> tokens = <String>[
        'headache',
        'fever',
        'difficulty_breathing',
      ];
      final GroupedPathPlan first = planTokens(flow, tokens);
      for (int i = 0; i < 25; i++) {
        final GroupedPathPlan again = planTokens(flow, tokens);
        expect(again.presentedIds, first.presentedIds);
        expect(
          <String>[
            for (final PresentedQuestion p in again.presented) p.questionText,
          ],
          <String>[
            for (final PresentedQuestion p in first.presented) p.questionText,
          ],
        );
        expect(
          <String>[
            for (final PresentedQuestion p in again.presented)
              p.optionIds.join(','),
          ],
          <String>[
            for (final PresentedQuestion p in first.presented)
              p.optionIds.join(','),
          ],
        );
      }
    });

    test('shuffled input orders all produce the same plan', () {
      final List<String> tokens = <String>[
        'abdominal_cramps',
        'body_pain',
        'cough',
        'fever',
        'bleeding',
      ];
      final GroupedPathPlan reference = planTokens(flow, tokens);
      for (int seed = 0; seed < 30; seed++) {
        final List<String> shuffled = List<String>.of(tokens);
        // A deterministic rotation, so a failure is reproducible rather than
        // dependent on a random seed nobody recorded.
        for (int i = 0; i <= seed % tokens.length; i++) {
          shuffled.add(shuffled.removeAt(0));
        }
        final GroupedPathPlan plan = planTokens(flow, shuffled);
        expect(plan.presentedIds, reference.presentedIds, reason: '$shuffled');
        expect(
          <String>[
            for (final PresentedQuestion p in plan.presented) p.questionText,
          ],
          <String>[
            for (final PresentedQuestion p in reference.presented)
              p.questionText,
          ],
          reason: '$shuffled',
        );
      }
    });

    test('group identities are stable across reversed input', () {
      for (final OracleCase c in oracleCases(oracleDoc, 'forward')) {
        if (c.inputTokens.length < 2) continue;
        final List<String?> forward = <String?>[
          for (final PresentedQuestion p in planTokens(
            flow,
            c.inputTokens,
          ).presented)
            p.groupKey,
        ];
        final List<String?> reversed = <String?>[
          for (final PresentedQuestion p in planTokens(
            flow,
            c.inputTokens.reversed,
          ).presented)
            p.groupKey,
        ];
        expect(reversed, forward, reason: '${c.inputTokens}');
      }
    });
  });
}
