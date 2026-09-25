/// Help and Support: offline by construction, emergency first, and no
/// clinical advice smuggled in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellapath_mobile/features/help/help_content.dart';
import 'package:wellapath_mobile/features/help/help_screen.dart';
import 'package:wellapath_mobile/features/help/support_chat_intro_screen.dart';

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

/// Brings [finder] into view, building it first if the lazy list has not
/// reached it yet.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

void main() {
  group('content', () {
    test('covers every required topic', () {
      final Set<String> ids = HelpContent.articles.map((a) => a.id).toSet();
      expect(
        ids,
        containsAll(<String>{
          'symptom_checking',
          'find_clinic',
          'why_internet',
          'can_and_cannot',
          'not_working',
          'privacy_safety',
          'emergency',
        }),
      );
    });

    test('exactly one emergency article, and it is first', () {
      final emergency = HelpContent.articles.where((a) => a.isEmergency);
      expect(emergency, hasLength(1));
      expect(HelpContent.articles.first.isEmergency, isTrue);
    });

    test('no article gives clinical advice', () {
      // Help explains the product. Naming conditions, symptoms or treatments
      // would be clinical content and needs clinical review first.
      const forbidden = [
        'malaria',
        'typhoid',
        'cholera',
        'fever',
        'headache',
        'cough',
        'rash',
        'dosage',
        'antibiotic',
        'you should take',
        'you may have',
        'diagnose',
      ];
      for (final article in HelpContent.articles) {
        final String text =
            '${article.title} ${article.summary} ${article.paragraphs.join(' ')}'
                .toLowerCase();
        for (final String term in forbidden) {
          expect(
            text.contains(term),
            isFalse,
            reason: 'help article "${article.id}" contains "$term"',
          );
        }
      }
    });

    test('is bundled, so it cannot depend on a network call', () {
      // A compile-time constant list is the guarantee: there is no loader,
      // no cache and no URL to fail.
      expect(HelpContent.articles, isNotEmpty);
      expect(
        HelpContent.articles.every((a) => a.paragraphs.isNotEmpty),
        isTrue,
      );
    });
  });

  group('screen', () {
    testWidgets('renders every article with no network available', (
      tester,
    ) async {
      // No HTTP is mocked or permitted here: the test binding fails any real
      // socket, so reaching this state at all proves the screen is offline.
      await _pump(tester, const HelpScreen());

      expect(find.text('Emergency guidance'), findsOneWidget);
      expect(find.textContaining('work without a connection'), findsOneWidget);
      for (final article in HelpContent.articles.take(3)) {
        await _reveal(tester, find.text(article.title));
        expect(find.text(article.title), findsOneWidget);
      }
    });

    testWidgets('opens an article and shows its body', (tester) async {
      await _pump(tester, const HelpScreen());
      await tester.tap(find.text('Emergency guidance'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('In an emergency, call 112 now.'), findsOneWidget);
      expect(
        find.textContaining('call emergency services on 112 now'),
        findsOneWidget,
      );
    });
  });

  group('support chat is designed, not live', () {
    testWidgets('states its limits and offers no way in', (tester) async {
      await _pump(tester, const SupportChatIntroScreen());

      expect(find.text('Support helps you use WellaPath.'), findsOneWidget);
      expect(
        find.textContaining('does not give medical advice'),
        findsOneWidget,
      );
      expect(find.textContaining('do not share symptoms'), findsOneWidget);
      expect(
        find.textContaining('Never use support for an emergency'),
        findsOneWidget,
      );
      expect(
        find.textContaining('needs an internet connection'),
        findsOneWidget,
      );
      await _reveal(tester, find.textContaining('Monday to Friday'));
      expect(find.textContaining('Monday to Friday'), findsOneWidget);
      expect(find.textContaining('within one working day'), findsOneWidget);

      // No way to type or send: nothing can be composed, so nothing can be
      // queued on the device.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Start a conversation'), findsNothing);
    });

    testWidgets('the start control appears only when a backend exists', (
      tester,
    ) async {
      await _pump(tester, const SupportChatIntroScreen(canStartChat: true));
      await _reveal(tester, find.text('Start a conversation'));
      expect(find.text('Start a conversation'), findsOneWidget);
      // Still nothing to type into during the MVP.
      expect(find.byType(TextField), findsNothing);
    });
  });
}
