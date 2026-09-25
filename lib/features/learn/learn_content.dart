/// Bundled content for Wella Today and the Learn tab.
///
/// **Product education only, and entirely offline.** Every line below
/// describes how the app behaves — what it does with your answers, what it
/// will and will not tell you, how to use the locator, how to prepare before
/// starting. None of it is clinical guidance: no condition names, no symptom
/// advice, no "what to do if you feel X". Clinically approved health content
/// replaces or extends this only after a human clinical review; the
/// vocabulary guard in `test/learn/learn_content_test.dart` is a tripwire for
/// accidents, not a substitute for that review.
///
/// **Nothing about the reader is recorded.** The daily card is chosen by the
/// device date, "Show me another" walks the deck in memory, and the myth
/// cards forget every answer when the screen closes. There is no reading
/// history, no score, no streak, no profile, and no network call.
library;

/// A one-minute product-education card.
class LearnCard {
  const LearnCard({
    required this.id,
    required this.topic,
    required this.title,
    required this.body,
  });

  final String id;

  /// Short topic heading, so Learn reads as a set of subjects rather than an
  /// undifferentiated article list.
  final String topic;
  final String title;
  final String body;
}

/// A "Myth or fact?" prompt. [isFact] is the answer; [explanation] is shown
/// immediately after either choice.
class MythCard {
  const MythCard({
    required this.id,
    required this.statement,
    required this.isFact,
    required this.explanation,
  });

  final String id;
  final String statement;
  final bool isFact;
  final String explanation;
}

abstract final class LearnContent {
  /// The deck. Order is stable; [forDate] indexes into it.
  ///
  /// Wording approved by the founder 2026-09-25. Changing a word here is a
  /// content change, not a refactor: it needs the same read-through.
  static const List<LearnCard> cards = [
    LearnCard(
      id: 'how_it_works',
      topic: 'How WellaPath works',
      title: 'Three simple steps, on your phone',
      body:
          'Tell WellaPath what is bothering you, answer a few questions, and '
          'receive guidance about what to do next. The assessment runs on '
          'your device.',
    ),
    LearnCard(
      id: 'when_to_check',
      topic: 'When to use symptom checking',
      title: 'When you are unsure what to do next',
      body:
          'Use symptom checking when you are unsure whether to wait, visit a '
          'clinic or seek urgent help. If you need help immediately, use '
          'emergency services instead.',
    ),
    LearnCard(
      id: 'on_device',
      topic: 'Your information',
      title: 'Your answers stay on your device',
      body:
          'WellaPath processes the assessment on your device. Your answers '
          'are not sent to WellaPath or stored on our servers.',
    ),
    LearnCard(
      id: 'can_and_cannot',
      topic: 'What WellaPath can and cannot do',
      title: 'Guidance, not a diagnosis',
      body:
          'WellaPath helps you decide what to do next. It does not diagnose '
          'an illness and does not replace a qualified healthcare '
          'professional.',
    ),
    LearnCard(
      id: 'prepare',
      topic: 'Before you start',
      title: 'Take a quiet moment',
      body:
          'The questions take about two minutes. It may help to think about '
          'when the problem started and whether anything has changed.',
    ),
    LearnCard(
      id: 'find_clinic',
      topic: 'How to use the clinic locator',
      title: 'Finding care',
      body:
          'The clinic locator lists health facilities by distance. You can '
          'allow location access or search using an area name.',
    ),
    LearnCard(
      id: 'offline',
      topic: 'Using WellaPath offline',
      title: 'Core guidance works offline',
      body:
          'After the initial setup, symptom checking and Learn can work '
          'without an internet connection. The clinic map still requires a '
          'connection.',
    ),
    LearnCard(
      id: 'urgent_interrupt',
      topic: 'Urgent answers',
      title: 'When urgent help may be needed',
      body:
          'If your answers suggest that you may need urgent help, WellaPath '
          'stops the questions and shows emergency guidance immediately.',
    ),
  ];

  /// "Myth or fact?" — all about the product, never about a condition.
  static const List<MythCard> myths = [
    MythCard(
      id: 'myth_diagnosis',
      statement: 'WellaPath can tell you what illness you have.',
      isFact: false,
      explanation:
          'It gives guidance on what to do next, not a diagnosis. Naming an '
          'illness is a job for a clinician.',
    ),
    MythCard(
      id: 'myth_offline',
      statement: 'You need the internet to check your symptoms.',
      isFact: false,
      explanation:
          'After the first setup the questions and guidance run offline. '
          'Only the clinic map needs a connection.',
    ),
    MythCard(
      id: 'myth_answers_sent',
      statement: 'Your symptom answers are sent to WellaPath.',
      isFact: false,
      explanation:
          'They are worked out on your device and are not sent to us or '
          'stored on a server.',
    ),
    MythCard(
      id: 'myth_emergency',
      statement:
          'If something is seriously wrong, you should still finish the '
          'questions first.',
      isFact: false,
      explanation:
          'No. If you think it is an emergency, call emergency services '
          'straight away — do not wait to finish anything.',
    ),
    MythCard(
      id: 'fact_account',
      statement: 'You can use WellaPath without making an account.',
      isFact: true,
      explanation:
          'There is no sign-up and no profile. Nothing identifies you to us.',
    ),
    MythCard(
      id: 'fact_two_minutes',
      statement: 'A symptom check takes about two minutes.',
      isFact: true,
      explanation:
          'A few short questions, then guidance. You can stop at any point.',
    ),
  ];

  /// The card of the day, offset by [step] for "Show me another".
  ///
  /// Deterministic and storage-free: the same date always gives the same
  /// first card, and stepping forward walks the deck in memory only.
  static LearnCard forDate(DateTime date, {int step = 0}) {
    final int dayNumber = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime.utc(2026, 1, 1)).inDays;
    final int index = (dayNumber + step) % cards.length;
    return cards[index < 0 ? index + cards.length : index];
  }
}
