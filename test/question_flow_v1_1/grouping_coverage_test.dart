/// Supplemental coverage at token-subset sizes 4 and 5, plus the 16
/// authoritative grouped path fixtures.
///
/// ## Mobile can do better than the knowledge base here, and does
///
/// The knowledge base's size 4-5 evidence is MODEL-DERIVED: it could not run
/// Dart, so it used a Python transcription of `question_engine.dart`, validated
/// against all 4,625 captured cases first. Its own report labels it as weaker
/// evidence.
///
/// This test calls the **real `QuestionEngine.generateQuestions`**. That makes
/// the Mobile result captured Dart output rather than a model, for the same
/// 53,130 paths. Both figures are reported: the knowledge base's limitation is
/// restated rather than quietly dropped, because the artifact it shipped is
/// still backed by the weaker evidence.
///
/// Sizes greater than 5 remain uncovered at either end.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/question_flow/grouped_path_planner.dart';
import 'package:wellapath_mobile/core/question_flow/question_flow_models.dart';
import 'package:wellapath_mobile/features/assessment/models/followup_question.dart';
import 'package:wellapath_mobile/features/assessment/question_engine.dart';

import 'grouping_test_support.dart';
import 'question_grouping_contract.dart';

String _role(QuestionType type) {
  switch (type) {
    case QuestionType.severity:
      return 'severity';
    case QuestionType.duration:
      return 'duration';
    case QuestionType.redFlagClarifier:
      return 'red_flag_clarifier';
    case QuestionType.additionalSymptoms:
      return 'additional_symptoms';
  }
}

/// Every subset of exactly [size] from [tokens], in a fixed order.
void _combinations(
  List<String> tokens,
  int size,
  void Function(List<String>) visit,
) {
  final List<String> current = <String>[];
  void recurse(int start) {
    if (current.length == size) {
      visit(List<String>.of(current));
      return;
    }
    for (int i = start; i < tokens.length; i++) {
      current.add(tokens[i]);
      recurse(i + 1);
      current.removeLast();
    }
  }

  recurse(0);
}

class SizeCounters {
  int paths = 0;
  int questionSet = 0;
  int optionSet = 0;
  int redFlagEffects = 0;
  int truncation = 0;
  int redFlagDropped = 0;
  int overLimit = 0;
  int liveOrderSensitive = 0;
  int candidateUnstable = 0;
  final List<String> samples = <String>[];
}

SizeCounters _runSize(QuestionFlow flow, List<String> driving, int size) {
  final SizeCounters counters = SizeCounters();

  _combinations(driving, size, (List<String> tokens) {
    counters.paths += 1;

    final List<FollowupQuestion> live = QuestionEngine.generateQuestions(
      tokens,
    );
    final List<FollowupQuestion> liveReversed =
        QuestionEngine.generateQuestions(tokens.reversed.toList());
    final GroupedPathPlan plan = planTokens(flow, tokens);
    final GroupedPathPlan planReversed = planTokens(flow, tokens.reversed);

    final List<String> liveShape = <String>[
      for (final FollowupQuestion q in live)
        '${_role(q.type)}|${q.questionText}|${q.options.join(",")}',
    ];
    final List<String> liveReversedShape = <String>[
      for (final FollowupQuestion q in liveReversed)
        '${_role(q.type)}|${q.questionText}|${q.options.join(",")}',
    ];
    if (!_eq(liveShape, liveReversedShape)) counters.liveOrderSensitive += 1;

    if (!_eq(plan.presentedIds, planReversed.presentedIds)) {
      counters.candidateUnstable += 1;
    }

    // Question set: which questions, independent of wording.
    final List<String> liveIdentity = <String>[
      for (final FollowupQuestion q in live)
        '${_role(q.type)}|${q.redFlagToken ?? ''}',
    ]..sort();
    final List<String> plannedIdentity = <String>[
      for (final PresentedQuestion p in plan.presented)
        '${p.clinicalRole}|${p.redFlagToken ?? ''}',
    ]..sort();
    if (!_eq(liveIdentity, plannedIdentity)) {
      counters.questionSet += 1;
      if (counters.samples.length < 10) {
        counters.samples.add(
          '$tokens: set live=$liveIdentity candidate=$plannedIdentity',
        );
      }
    }

    // Red-flag effects.
    final List<String> liveFlags = <String>[
      for (final FollowupQuestion q in live)
        if (q.type == QuestionType.redFlagClarifier) q.redFlagToken!,
    ]..sort();
    final List<String> plannedFlags = <String>[
      for (final PresentedQuestion p in plan.presented)
        if (p.clinicalRole == 'red_flag_clarifier') p.redFlagToken!,
    ]..sort();
    if (!_eq(liveFlags, plannedFlags)) counters.redFlagEffects += 1;

    if (plan.droppedRedFlagIds.isNotEmpty) counters.redFlagDropped += 1;
    if (live.length != plan.presented.length) counters.truncation += 1;
    if (plan.presented.length > plan.limit) counters.overLimit += 1;

    // Option sets, where the live model carries them and the shape agrees.
    if (live.length == plan.presented.length) {
      for (int i = 0; i < live.length; i++) {
        final FollowupQuestion liveQuestion = live[i];
        if (!kRolesWithComparableOptions.contains(_role(liveQuestion.type))) {
          continue;
        }
        final List<String> a = List<String>.of(liveQuestion.options)..sort();
        final List<String> b = List<String>.of(plan.presented[i].optionLabels)
          ..sort();
        if (!_eq(a, b)) counters.optionSet += 1;
      }
    }
  });

  return counters;
}

bool _eq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  late QuestionFlow flow;
  late List<String> driving;

  setUpAll(() {
    flow = groupedFlow();
    driving =
        ((oracle()['_metadata'] as Map<String, dynamic>)['driving_tokens']
                as List<dynamic>)
            .cast<String>();
  });

  group(
    'supplemental coverage, sizes 4 and 5 (captured Dart, not a model)',
    () {
      late SizeCounters size4;
      late SizeCounters size5;

      setUpAll(() {
        size4 = _runSize(flow, driving, 4);
        size5 = _runSize(flow, driving, 5);
      });

      test('53,130 paths, matching the knowledge base bound', () {
        expect(size4.paths, 10626);
        expect(size5.paths, 42504);
        expect(size4.paths + size5.paths, kModelDerivedPaths);
      });

      test('zero question-set differences at either size', () {
        expect(size4.questionSet, 0, reason: size4.samples.join('\n'));
        expect(size5.questionSet, 0, reason: size5.samples.join('\n'));
      });

      test('zero option-set differences at either size', () {
        expect(size4.optionSet, 0);
        expect(size5.optionSet, 0);
      });

      test('zero red-flag-effect differences at either size', () {
        expect(size4.redFlagEffects, 0);
        expect(size5.redFlagEffects, 0);
      });

      test('zero truncation differences and no red-flag question dropped', () {
        expect(size4.truncation, 0);
        expect(size5.truncation, 0);
        expect(size4.redFlagDropped, 0);
        expect(size5.redFlagDropped, 0);
      });

      test('the path limit is never exceeded', () {
        expect(size4.overLimit, 0);
        expect(size5.overLimit, 0);
      });

      test('live is order-sensitive at scale; the candidate never is', () {
        expect(size4.liveOrderSensitive, greaterThan(0));
        expect(size5.liveOrderSensitive, greaterThan(0));
        expect(size4.candidateUnstable, 0);
        expect(size5.candidateUnstable, 0);
      });

      test('the knowledge base report is model-derived and says so', () {
        // Mobile's own figures above are captured Dart. The shipped artifact is
        // still backed by the weaker evidence, so the limitation is restated
        // here rather than dropped now that a stronger run exists.
        final Map<String, dynamic> report = readJson(kCoverageReportPath);
        final Map<String, dynamic> meta =
            report['_metadata'] as Map<String, dynamic>;
        final Map<String, dynamic> strength =
            meta['evidence_strength'] as Map<String, dynamic>;
        expect(strength['stage_2'], contains('MODEL-DERIVED'));
        expect(report['all_clean'], isTrue);

        final List<dynamic> limits = report['residual_risk'] as List<dynamic>;
        expect(
          limits.any((Object? l) => (l as String).contains('above size 5')),
          isTrue,
          reason: 'sizes greater than 5 must remain a stated coverage limit',
        );
      });

      test('sizes above 5 are uncovered — stated, not silently omitted', () {
        // Nothing in this file exercises a 6-token selection. Recorded as a
        // limit so a reader does not infer coverage that does not exist.
        const int largestCoveredSubsetSize = 5;
        expect(largestCoveredSubsetSize, 5);
      });
    },
  );

  group('16 authoritative grouped path fixtures', () {
    test('every case matches, and captured cases also match live output', () {
      final Map<String, dynamic> doc = readJson(kGroupingPathFixturesPath);
      final List<dynamic> cases = doc['cases'] as List<dynamic>;
      expect(cases, hasLength(kGroupedPathFixtureCount));

      int capturedChecked = 0;
      final List<String> failures = <String>[];

      for (final Object? c in cases) {
        final Map<String, dynamic> fixture = c as Map<String, dynamic>;
        final String id = fixture['fixture_id'] as String;
        final List<String> tokens =
            (fixture['selected_tokens'] as List<dynamic>).cast<String>();
        final Map<String, dynamic> expected =
            fixture['expected'] as Map<String, dynamic>;

        final GroupedPathPlan plan = planTokens(flow, tokens);

        final List<dynamic> expectedQuestions =
            expected['presented_questions'] as List<dynamic>;
        if (plan.presented.length != expectedQuestions.length) {
          failures.add(
            '$id: ${expectedQuestions.length} questions expected, '
            '${plan.presented.length} planned',
          );
          continue;
        }
        for (int i = 0; i < expectedQuestions.length; i++) {
          final Map<String, dynamic> want =
              expectedQuestions[i] as Map<String, dynamic>;
          final PresentedQuestion got = plan.presented[i];
          if (want['question_id'] != got.question.id.value) {
            failures.add(
              '$id[$i]: id ${want['question_id']} != ${got.question.id.value}',
            );
          }
          if (want['clinical_role'] != got.clinicalRole) {
            failures.add(
              '$id[$i]: role ${want['clinical_role']} != ${got.clinicalRole}',
            );
          }
          if (want['question_text'] != got.questionText) {
            failures.add('$id[$i]: text differs');
          }
          final List<String> wantOptions =
              (want['presented_option_labels'] as List<dynamic>).cast<String>();
          if (!_eq(wantOptions, got.optionLabels)) {
            failures.add(
              '$id[$i]: options $wantOptions != ${got.optionLabels}',
            );
          }
          if (want['representative_source'] != got.representativeSourceId) {
            failures.add('$id[$i]: representative source differs');
          }
        }

        final List<String> wantTruncated =
            (expected['truncated_question_ids'] as List<dynamic>)
                .cast<String>();
        if (!_eq(wantTruncated, plan.truncatedIds)) {
          failures.add('$id: truncated $wantTruncated != ${plan.truncatedIds}');
        }
        expect(expected['red_flag_questions_dropped'], isEmpty);
        expect(plan.droppedRedFlagIds, isEmpty);

        // Where the fixture carries real live output, assert against that too.
        // A consumer that only agrees with the model proves nothing about the
        // app.
        if (fixture['live_evidence'] == 'captured') {
          capturedChecked += 1;
          final List<dynamic> liveQuestions =
              fixture['live_questions'] as List<dynamic>;
          final List<String> liveRoles = <String>[
            for (final Object? q in liveQuestions)
              (q as Map<String, dynamic>)['clinical_role'] as String,
          ];
          final List<String> plannedRoles = <String>[
            for (final PresentedQuestion p in plan.presented) p.clinicalRole,
          ];
          if (!_eq(liveRoles, plannedRoles)) {
            failures.add('$id: live roles $liveRoles != $plannedRoles');
          }
          // And against the engine itself, not just the recorded copy.
          final List<String> engineRoles = <String>[
            for (final FollowupQuestion q in QuestionEngine.generateQuestions(
              tokens,
            ))
              _role(q.type),
          ];
          if (!_eq(engineRoles, plannedRoles)) {
            failures.add('$id: engine roles $engineRoles != $plannedRoles');
          }
        }
      }

      expect(failures, isEmpty, reason: failures.join('\n'));
      expect(capturedChecked, 11);
    });

    test('the 5 model-derived cases are labelled, not passed off as live', () {
      final Map<String, dynamic> doc = readJson(kGroupingPathFixturesPath);
      final List<dynamic> cases = doc['cases'] as List<dynamic>;
      final Iterable<Map<String, dynamic>> notCaptured = cases
          .cast<Map<String, dynamic>>()
          .where((Map<String, dynamic> c) => c['live_evidence'] != 'captured');
      expect(notCaptured, hasLength(5));
      for (final Map<String, dynamic> c in notCaptured) {
        expect(c['live_evidence'], 'not_captured');
        expect(c['live_evidence_note'], isNotEmpty);
        expect(c.containsKey('live_questions'), isFalse);
      }
    });
  });
}
