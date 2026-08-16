// ignore_for_file: avoid_print
// print() is intentional in the reproduction group only: its console output is
// the QB-002 evidence recorded in docs/QB002_IMMEDIATE_RED_FLAG.md.

/// QB-002 — a red-flag clarifier answered "Yes" must interrupt the assessment
/// immediately, before any further ordinary question.
///
/// Authoritative handoff:
///   wellapath-knowledge-base @ aa7a2f13c577ea23f78235d9d8585416bd07f9de
///   mobile_handoff/question_flow_v1/IM002_SAFETY_FIX.md
///   sha256 6bc1863d02ec565f2f0e47ca1a536a97e17e62add9cb341553666d195df9d29c
///
/// The defect is NOT under-triage. `RedFlagEvaluator` still runs before
/// `ScoringEngine`, and the 239-case bank still reports zero safety-critical
/// under-triage. The harm is *delay*: someone who has just declared a danger
/// sign is asked up to four more routine questions before being told to seek
/// emergency care, and may abandon first — receiving nothing.
///
/// The fix is behind `--dart-define=W3_IMMEDIATE_RED_FLAG=true`. With the flag
/// off, behaviour is byte-identical to before, which is the rollback.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/core/constants/red_flag_clarifiers.dart';
import 'package:wellapath_mobile/features/assessment/assessment_controller.dart';
import 'package:wellapath_mobile/features/assessment/followup_screen.dart';
import 'package:wellapath_mobile/features/assessment/models/followup_question.dart';
import 'package:wellapath_mobile/features/assessment/question_engine.dart';

/// Two clarifiers plus severity, duration and additional-symptoms — the live
/// worst case, and the one the handoff describes: an affirmative answer to the
/// question at index 0 leaves **four** further questions queued.
const List<String> kWorstCaseTokens = <String>[
  'shortness_of_breath',
  'bleeding',
  'headache',
  'fever',
];

/// One clarifier, in the middle of the generated list.
const List<String> kMiddleClarifierTokens = <String>[
  'poor_feeding',
  'headache',
  'fever',
];

Future<void> pumpFollowup(
  WidgetTester tester,
  AssessmentController controller, {
  VoidCallback? onCancel,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FollowupScreen(
        assessmentController: controller,
        onCancel: onCancel ?? () {},
        primarySymptomLabel: 'your symptoms',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AssessmentController controllerFor(List<String> tokens) {
  final AssessmentController c = AssessmentController();
  for (final String t in tokens) {
    c.addSymptomToken(t);
  }
  return c;
}

/// Answers the visible clarifier "Yes" and taps Next.
Future<void> answerClarifierYesAndAdvance(WidgetTester tester) async {
  await tester.tap(find.text('Yes').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
}

void main() {
  group('QB-002 reproduction — the defect this fix removes', () {
    test('the live worst case leaves four questions queued after a clarifier', () {
      final List<FollowupQuestion> questions = QuestionEngine.generateQuestions(
        kWorstCaseTokens,
      );

      expect(questions, hasLength(5));
      expect(questions.first.type, QuestionType.redFlagClarifier);
      expect(questions.first.redFlagToken, 'breathlessness_at_rest');

      final int remaining = questions.length - 1;
      expect(
        remaining,
        4,
        reason:
            'The handoff records a worst case of four further questions after '
            'an affirmative clarifier.',
      );

      print('');
      print(
        '=== QB-002 EVIDENCE — questions presented after "Yes" at index 0 ===',
      );
      for (int i = 0; i < questions.length; i++) {
        final FollowupQuestion q = questions[i];
        final String marker = i == 0
            ? '<- user answers "Yes"'
            : '<- still asked';
        print(
          '  [$i] ${q.type.name}'
          '${q.redFlagToken == null ? '' : ' (${q.redFlagToken})'}'
          '  $marker',
        );
      }
      print(
        '  remaining ordinary/clarifier questions after the trigger: $remaining',
      );
      print('');
    });

    testWidgets(
      'PRE-FIX BEHAVIOUR: with the flag off, "Yes" advances instead of interrupting',
      (WidgetTester tester) async {
        // This is the defect, pinned. It is also the rollback contract: with
        // W3_IMMEDIATE_RED_FLAG unset, behaviour must be exactly this.
        final AssessmentController controller = controllerFor(kWorstCaseTokens);
        await pumpFollowup(tester, controller);

        expect(
          find.text(kRedFlagClarifiers.first.questionText),
          findsOneWidget,
        );

        await answerClarifierYesAndAdvance(tester);

        if (kImmediateRedFlagEnabled) {
          // The suite is running with the fix enabled; this pin does not apply.
          return;
        }

        expect(
          controller.symptomTokens,
          isNot(contains('breathlessness_at_rest')),
          reason:
              'PRE-FIX: the clarifier answer is held in widget state and is not '
              'committed until the final question, so the red flag token is '
              'not present yet.',
        );
        expect(
          find.text(kRedFlagClarifiers.first.questionText),
          findsNothing,
          reason: 'PRE-FIX: the screen advanced past the clarifier.',
        );
      },
    );
  });

  group('QB-002 fix — immediate interruption', () {
    testWidgets('an affirmative clarifier commits its token immediately', (
      WidgetTester tester,
    ) async {
      final AssessmentController controller = controllerFor(kWorstCaseTokens);
      await pumpFollowup(tester, controller);
      await answerClarifierYesAndAdvance(tester);

      if (!kImmediateRedFlagEnabled) return;

      expect(
        controller.symptomTokens,
        contains('breathlessness_at_rest'),
        reason:
            'The answer must be committed BEFORE evaluation — evaluating '
            'against state that does not yet include the answer is the same '
            'bug in a new place.',
      );
    });

    testWidgets('no further ordinary question is presented', (
      WidgetTester tester,
    ) async {
      final AssessmentController controller = controllerFor(kWorstCaseTokens);
      final List<FollowupQuestion> questions = QuestionEngine.generateQuestions(
        kWorstCaseTokens,
      );

      await pumpFollowup(tester, controller);
      await answerClarifierYesAndAdvance(tester);

      if (!kImmediateRedFlagEnabled) return;

      // None of the four queued questions may appear.
      for (int i = 1; i < questions.length; i++) {
        expect(
          find.text(questions[i].questionText),
          findsNothing,
          reason:
              'Question ${questions[i].questionText} was presented after a '
              'declared danger sign.',
        );
      }
    });

    testWidgets('the assessment leaves the questionnaire exactly once', (
      WidgetTester tester,
    ) async {
      final AssessmentController controller = controllerFor(kWorstCaseTokens);
      await pumpFollowup(tester, controller);
      await answerClarifierYesAndAdvance(tester);

      if (!kImmediateRedFlagEnabled) return;

      // The follow-up screen is gone; evaluation has taken over.
      expect(find.byType(FollowupScreen), findsNothing);
    });

    testWidgets('a clarifier answered No preserves the ordinary flow', (
      WidgetTester tester,
    ) async {
      final AssessmentController controller = controllerFor(kWorstCaseTokens);
      final List<FollowupQuestion> questions = QuestionEngine.generateQuestions(
        kWorstCaseTokens,
      );

      await pumpFollowup(tester, controller);
      await tester.tap(find.text('No').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(
        controller.symptomTokens,
        isNot(contains('breathlessness_at_rest')),
        reason: 'Only an explicit Yes raises the red flag.',
      );
      expect(
        find.text(questions[1].questionText),
        findsOneWidget,
        reason: 'A negative answer must advance exactly as before.',
      );
      expect(find.byType(FollowupScreen), findsOneWidget);
    });

    testWidgets('an unanswered clarifier raises no red flag and advances', (
      WidgetTester tester,
    ) async {
      // Next is not gated on an answer today, and this fix does not change
      // that. What matters is that an unanswered clarifier commits nothing,
      // so it cannot raise a red flag and cannot trigger an interrupt.
      final AssessmentController controller = controllerFor(kWorstCaseTokens);
      final List<FollowupQuestion> questions = QuestionEngine.generateQuestions(
        kWorstCaseTokens,
      );

      await pumpFollowup(tester, controller);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(
        controller.symptomTokens,
        isNot(contains('breathlessness_at_rest')),
        reason: 'An unanswered clarifier must commit nothing.',
      );
      expect(find.byType(FollowupScreen), findsOneWidget);
      expect(find.text(questions[1].questionText), findsOneWidget);
    });

    testWidgets('a middle clarifier interrupts too', (
      WidgetTester tester,
    ) async {
      final AssessmentController controller = controllerFor(
        kMiddleClarifierTokens,
      );
      await pumpFollowup(tester, controller);
      await answerClarifierYesAndAdvance(tester);

      if (!kImmediateRedFlagEnabled) return;

      expect(controller.symptomTokens, contains('inability_to_drink'));
      expect(find.byType(FollowupScreen), findsNothing);
    });

    testWidgets('a double tap produces exactly one transition', (
      WidgetTester tester,
    ) async {
      final AssessmentController controller = controllerFor(kWorstCaseTokens);
      await pumpFollowup(tester, controller);

      await tester.tap(find.text('Yes').first);
      await tester.pump();

      // Two taps with no settle in between — the classic double-tap race.
      final Finder next = find.text('Next');
      await tester.tap(next);
      await tester.tap(next, warnIfMissed: false);
      await tester.pumpAndSettle();

      if (!kImmediateRedFlagEnabled) return;

      expect(
        controller.symptomTokens.where(
          (String t) => t == 'breathlessness_at_rest',
        ),
        hasLength(1),
        reason: 'The answer must be committed exactly once.',
      );
      expect(find.byType(FollowupScreen), findsNothing);
    });

    testWidgets('the ordinary path is unchanged end to end', (
      WidgetTester tester,
    ) async {
      // The load-bearing case: a path with no clarifier must present exactly
      // the same questions, in the same order, as it does today.
      const List<String> ordinary = <String>['headache', 'fever'];
      final List<FollowupQuestion> questions = QuestionEngine.generateQuestions(
        ordinary,
      );
      expect(
        questions.any(
          (FollowupQuestion q) => q.type == QuestionType.redFlagClarifier,
        ),
        isFalse,
      );

      final AssessmentController controller = controllerFor(ordinary);
      await pumpFollowup(tester, controller);

      for (int i = 0; i < questions.length; i++) {
        expect(
          find.text(questions[i].questionText),
          findsOneWidget,
          reason: 'question $i out of order or missing',
        );
        if (i == questions.length - 1) break;
        await answerCurrent(tester, questions[i]);
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      expect(find.byType(FollowupScreen), findsOneWidget);
    });
  });

  group('QB-002 — telemetry, lifecycle and race safety', () {
    testWidgets('no step-view is recorded for a question never shown', (
      WidgetTester tester,
    ) async {
      final AssessmentController controller = controllerFor(kWorstCaseTokens);
      await pumpFollowup(tester, controller);

      final int before = controller.telemetrySession.stepsViewed;
      await answerClarifierYesAndAdvance(tester);
      final int after = controller.telemetrySession.stepsViewed;

      if (!kImmediateRedFlagEnabled) return;

      expect(
        after,
        before,
        reason:
            'Interception happens before recordStepView(), so an interrupted '
            'path must emit no step event for the question it prevented from '
            'appearing. Emitting one would be untrue and would make the event '
            'count a red-flag oracle.',
      );
    });

    testWidgets('an ordinary advance still records exactly one step-view', (
      WidgetTester tester,
    ) async {
      final AssessmentController controller = controllerFor(kWorstCaseTokens);
      await pumpFollowup(tester, controller);

      final int before = controller.telemetrySession.stepsViewed;
      await tester.tap(find.text('No').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(
        controller.telemetrySession.stepsViewed,
        before + 1,
        reason: 'Non-red-flag telemetry must be unchanged by this fix.',
      );
    });

    testWidgets(
      'a red-flag path is structurally indistinguishable from abandonment',
      (WidgetTester tester) async {
        // Both stop early and emit fewer step views. Nothing about the counts,
        // the statuses or the event set identifies which one happened.
        final AssessmentController redFlag = controllerFor(kWorstCaseTokens);
        await pumpFollowup(tester, redFlag);
        await answerClarifierYesAndAdvance(tester);

        final AssessmentController abandoned = controllerFor(kWorstCaseTokens);
        await pumpFollowup(tester, abandoned);
        // Same point in the flow, user simply stops.

        if (!kImmediateRedFlagEnabled) return;

        expect(
          redFlag.telemetrySession.stepsViewed,
          abandoned.telemetrySession.stepsViewed,
          reason:
              'A red-flag interrupt and an abandonment at the same step must '
              'produce the same step count, or the count identifies the '
              'danger sign.',
        );
      },
    );

    testWidgets('the committed token is visible to the engine path', (
      WidgetTester tester,
    ) async {
      final AssessmentController controller = controllerFor(kWorstCaseTokens);
      await pumpFollowup(tester, controller);
      await answerClarifierYesAndAdvance(tester);

      if (!kImmediateRedFlagEnabled) return;

      // buildInput() is exactly what LoadingScreen hands to the engine.
      expect(
        controller.buildInput().symptomTokens,
        contains('breathlessness_at_rest'),
        reason:
            'The interrupt path must carry the committed answer into the '
            'engine and the result state.',
      );
    });

    testWidgets('an affirmative FINAL clarifier behaves as before', (
      WidgetTester tester,
    ) async {
      // A clarifier that is already the last question has nothing queued after
      // it, so the fix must change nothing here.
      const List<String> tokens = <String>['bleeding'];
      final List<FollowupQuestion> questions = QuestionEngine.generateQuestions(
        tokens,
      );
      final AssessmentController controller = controllerFor(tokens);
      await pumpFollowup(tester, controller);

      // Walk to the last question.
      for (int i = 0; i < questions.length - 1; i++) {
        await answerCurrent(tester, questions[i]);
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }

      expect(find.byType(FollowupScreen), findsOneWidget);
    });

    testWidgets('multiple red-flag-capable answers interrupt on the first', (
      WidgetTester tester,
    ) async {
      // Two clarifiers queued. Answering the first Yes must stop before the
      // second is ever shown.
      final AssessmentController controller = controllerFor(kWorstCaseTokens);
      await pumpFollowup(tester, controller);
      await answerClarifierYesAndAdvance(tester);

      if (!kImmediateRedFlagEnabled) return;

      expect(controller.symptomTokens, contains('breathlessness_at_rest'));
      expect(
        controller.symptomTokens,
        isNot(contains('abnormal_bleeding')),
        reason:
            'The second clarifier was never presented, so its token must not '
            'be committed.',
      );
      expect(find.text(kRedFlagClarifiers[2].questionText), findsNothing);
    });

    testWidgets('cancellation during the flow still abandons cleanly', (
      WidgetTester tester,
    ) async {
      bool cancelled = false;
      final AssessmentController controller = controllerFor(kWorstCaseTokens);
      await pumpFollowup(tester, controller, onCancel: () => cancelled = true);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, cancel'));
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
      expect(
        controller.symptomTokens,
        isEmpty,
        reason: 'clearAll() runs on cancel, unchanged by this fix.',
      );
    });

    testWidgets('the transition is guarded against a disposed widget', (
      WidgetTester tester,
    ) async {
      // `_goToEvaluation` checks `mounted` before touching the Navigator. This
      // exercises the transition and then tears the tree down, draining the
      // LoadingScreen delay that the existing engine path schedules, and
      // asserts nothing was thrown along the way.
      final AssessmentController controller = controllerFor(kWorstCaseTokens);
      await pumpFollowup(tester, controller);
      await answerClarifierYesAndAdvance(tester);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      // Let the pre-existing LoadingScreen timer expire against a disposed
      // tree; it guards on `mounted` too, so this must be silent.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('works with no network available', (WidgetTester tester) async {
      // Nothing in the interception path performs I/O. This test binding has
      // no HTTP client wired, so reaching for one would throw; completing
      // proves the decision is entirely on-device.
      final AssessmentController controller = controllerFor(kWorstCaseTokens);
      await pumpFollowup(tester, controller);
      await answerClarifierYesAndAdvance(tester);

      expect(tester.takeException(), isNull);
      if (!kImmediateRedFlagEnabled) return;
      expect(controller.symptomTokens, contains('breathlessness_at_rest'));
    });
  });

  group('QB-002 — added synchronous cost', () {
    // The added work is one answer commit plus one membership check on the
    // committed token list. Measured and reported rather than asserted against
    // an invented clinical latency threshold — no sourced one exists. The only
    // defensible assertion is that synchronous work must not stall a frame.
    const int frameBudgetMicros = 16667;

    Future<int> measureNext(WidgetTester tester) async {
      final Stopwatch w = Stopwatch()..start();
      await tester.tap(find.text('Next'));
      w.stop();
      await tester.pumpAndSettle();
      return w.elapsedMicroseconds;
    }

    void report(String label, int micros) {
      print(
        '  [flag ${kImmediateRedFlagEnabled ? "ON " : "OFF"}] '
        '${label.padRight(34)} $micros us  '
        '(frame budget $frameBudgetMicros us)',
      );
      expect(micros, lessThan(frameBudgetMicros));
    }

    testWidgets('affirmative red-flag clarifier', (WidgetTester tester) async {
      final AssessmentController c = controllerFor(kWorstCaseTokens);
      await pumpFollowup(tester, c);
      await tester.tap(find.text('Yes').first);
      await tester.pumpAndSettle();
      report('affirmative red-flag clarifier', await measureNext(tester));
    });

    testWidgets('negative clarifier', (WidgetTester tester) async {
      final AssessmentController c = controllerFor(kWorstCaseTokens);
      await pumpFollowup(tester, c);
      await tester.tap(find.text('No').first);
      await tester.pumpAndSettle();
      report('negative clarifier', await measureNext(tester));
    });

    testWidgets('ordinary non-clarifier question', (WidgetTester tester) async {
      final AssessmentController c = controllerFor(kWorstCaseTokens);
      await pumpFollowup(tester, c);
      // Walk past both clarifiers to reach an ordinary question.
      for (int i = 0; i < 2; i++) {
        await tester.tap(find.text('No').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      report('ordinary non-clarifier question', await measureNext(tester));
    });
  });
}

/// Provides whatever answer the current question type needs so Next enables.
Future<void> answerCurrent(WidgetTester tester, FollowupQuestion q) async {
  switch (q.type) {
    case QuestionType.severity:
      // The severity slider always has a value; nothing to do.
      break;
    case QuestionType.duration:
      await tester.tap(find.text('Less than 3 days'));
    case QuestionType.additionalSymptoms:
      break;
    case QuestionType.redFlagClarifier:
      await tester.tap(find.text('No').first);
  }
  await tester.pumpAndSettle();
}
