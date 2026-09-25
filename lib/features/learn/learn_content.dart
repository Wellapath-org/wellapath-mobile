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
  static const List<LearnCard> cards = [
    LearnCard(
      id: 'how_it_works',
      topic: 'How WellaPath works',
      title: 'Three steps, on your phone',
      body:
          'You say what is bothering you, answer a few questions, and get '
          'guidance on what to do next. The work happens on this device.',
    ),
    LearnCard(
      id: 'when_to_check',
      topic: 'When to use symptom checking',
      title: 'Good for deciding what to do next',
      body:
          'Use it when you are unsure whether to wait, visit a clinic, or '
          'seek urgent care. If you already know you need help now, call '
          'emergency services instead.',
    ),
    LearnCard(
      id: 'on_device',
      topic: 'Your information',
      title: 'Your answers stay on your phone',
      body:
          'WellaPath works out its guidance on your device. Your answers are '
          'not sent to us and are not stored on a server.',
    ),
    LearnCard(
      id: 'can_and_cannot',
      topic: 'What WellaPath can and cannot do',
      title: 'Guidance, not a diagnosis',
      body:
          'It helps you decide what to do next. It does not name what is '
          'wrong with you, and it does not replace a doctor.',
    ),
    LearnCard(
      id: 'prepare',
      topic: 'Before you start',
      title: 'Have a quiet minute',
      body:
          'Answering takes about two minutes. Knowing when things started, '
          'and whether anything has changed, makes your answers easier to '
          'give.',
    ),
    LearnCard(
      id: 'find_clinic',
      topic: 'How to use the clinic locator',
      title: 'Finding care',
      body:
          'Find a clinic lists health facilities sorted by distance. You can '
          'allow location access, or search by area name instead.',
    ),
    LearnCard(
      id: 'offline',
      topic: 'Using it offline',
      title: 'It works without a connection',
      body:
          'After the first setup, the questions, guidance and everything in '
          'Learn work offline. Only the clinic map needs the internet.',
    ),
    LearnCard(
      id: 'urgent_interrupt',
      topic: 'Urgent answers',
      title: 'It can stop and tell you to get help now',
      body:
          'If your answers point to something urgent, WellaPath stops the '
          'questions and shows emergency guidance straight away.',
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
