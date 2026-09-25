/// Feedback: two steps, an honest ending, and nothing kept on the device.
///
/// The load-bearing assertions are the negative ones — that an ordinary
/// build cannot reach feedback at all, that the screen never claims to have
/// sent anything when it has not, that nothing is written to preferences,
/// and that the payload carries no clinical, location or identifying data.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wellapath_mobile/core/config/feature_flags.dart';
import 'package:wellapath_mobile/features/feedback/feedback_screen.dart';
import 'package:wellapath_mobile/features/feedback/feedback_submission.dart';
import 'package:wellapath_mobile/features/help/help_screen.dart';

/// Test-only: records what it was given, in memory, and never persists.
class _RecordingSubmitter extends FeedbackSubmitter {
  _RecordingSubmitter({this.result = FeedbackResult.sent});

  final FeedbackResult result;
  final List<FeedbackPayload> received = [];

  @override
  Future<FeedbackResult> submit(FeedbackPayload payload) async {
    received.add(payload);
    return result;
  }
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _tap(WidgetTester tester, String label) async {
  // The page's own ListView, named explicitly: once the comment field is on
  // screen there is more than one Scrollable, and a lazily-built row below
  // the fold does not exist until it is scrolled to.
  final Finder target = find.text(label);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.pump();
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('reachability', () {
    test('feedback is off in an ordinary build', () {
      expect(FeatureFlags.feedbackEnabled, isFalse);
      expect(FeatureFlags.supportChatEnabled, isFalse);
    });

    testWidgets('Help offers no feedback or chat row while flags are off', (
      tester,
    ) async {
      await _pump(tester, const HelpScreen());
      expect(find.text('Give feedback'), findsNothing);
      expect(find.text('Message the support team'), findsNothing);
      // Not present at all, rather than present-but-disabled: a greyed row
      // still invites a tap.
      expect(find.textContaining('Coming soon'), findsNothing);
    });
  });

  group('the flow', () {
    testWidgets('asks how it was, then what about', (tester) async {
      await _pump(tester, const FeedbackScreen());
      expect(find.text('How was your experience?'), findsOneWidget);
      for (final String label in ['Good', 'Okay', 'Needs improvement']) {
        expect(find.text(label), findsOneWidget);
      }
      // The second question appears only after the first is answered.
      expect(find.text('What would you like to tell us about?'), findsNothing);

      await _tap(tester, 'Okay');
      expect(
        find.text('What would you like to tell us about?'),
        findsOneWidget,
      );
      for (final String label in [
        'Ease of use',
        'Understanding the app',
        'Finding a clinic',
        'App performance',
        'Accessibility',
        'Something else',
      ]) {
        expect(find.text(label), findsWidgets, reason: '$label must exist');
      }
    });

    testWidgets('warns against personal and health details', (tester) async {
      await _pump(tester, const FeedbackScreen());
      await _tap(tester, 'Good');
      await _tap(tester, 'Ease of use');

      expect(
        find.text(
          'Please do not include your name, phone number, symptoms, '
          'diagnosis or other personal health information.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the comment field is off until it is switched on', (
      tester,
    ) async {
      await _pump(tester, const FeedbackScreen());
      await _tap(tester, 'Good');
      await _tap(tester, 'Accessibility');

      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
    });
  });

  group('outcomes are honest', () {
    testWidgets('the production default reports that nothing was sent', (
      tester,
    ) async {
      await _pump(tester, const FeedbackScreen());
      await _tap(tester, 'Needs improvement');
      await _tap(tester, 'App performance');
      await _tap(tester, 'Send feedback');

      expect(find.text('Feedback is not open yet'), findsOneWidget);
      expect(
        find.textContaining('nothing was sent'),
        findsOneWidget,
        reason: 'it must never imply a submission happened',
      );
      expect(find.text('Thank you'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys(),
        isEmpty,
        reason: 'nothing may be saved or queued on the device',
      );
    });

    testWidgets('a failure says so, and still stores nothing', (tester) async {
      final submitter = _RecordingSubmitter(result: FeedbackResult.failed);
      await _pump(tester, FeedbackScreen(submitter: submitter));
      await _tap(tester, 'Okay');
      await _tap(tester, 'Something else');
      await _tap(tester, 'Send feedback');

      expect(find.text('That did not send'), findsOneWidget);
      expect(find.textContaining('Nothing was saved'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    testWidgets('a real submitter gets exactly the approved payload', (
      tester,
    ) async {
      final submitter = _RecordingSubmitter();
      await _pump(
        tester,
        FeedbackScreen(
          submitter: submitter,
          appVersion: '0.3.0+215',
          platform: 'android',
        ),
      );
      await _tap(tester, 'Good');
      await _tap(tester, 'Finding a clinic');
      await _tap(tester, 'Send feedback');

      expect(find.text('Thank you'), findsOneWidget);
      expect(submitter.received, hasLength(1));

      final Map<String, Object?> json = submitter.received.single.toJson();
      expect(json.keys.toSet(), {
        'rating',
        'category',
        'app_version',
        'platform',
      });
      expect(json['rating'], 'good');
      expect(json['category'], 'findingClinic');

      // Nothing clinical, locational or identifying may appear.
      final String serialised = json.toString().toLowerCase();
      for (final String forbidden in [
        'symptom',
        'assessment',
        'urgency',
        'result',
        'latitude',
        'longitude',
        'device_id',
        'user_id',
        'session',
        'email',
        'phone',
      ]) {
        expect(
          serialised.contains(forbidden),
          isFalse,
          reason: 'payload must not carry "$forbidden"',
        );
      }
    });

    testWidgets('one tap, one submission', (tester) async {
      final submitter = _RecordingSubmitter();
      await _pump(tester, FeedbackScreen(submitter: submitter));
      await _tap(tester, 'Good');
      await _tap(tester, 'Ease of use');
      await _tap(tester, 'Send feedback');
      expect(submitter.received, hasLength(1));
    });
  });
}
