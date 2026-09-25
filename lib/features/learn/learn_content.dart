/// Content for the Learn tab.
///
/// **Product education only.** Every card below describes how the app behaves
/// — what it does with your answers, where your data lives, how to use it
/// offline. None of it is clinical guidance, and none of it may become
/// clinical guidance without clinical review: no symptom advice, no condition
/// information, no "what to do if you feel X". That line is enforced by
/// `test/learn/learn_content_test.dart`.
///
/// The daily card rotates by date rather than by stored history, so the Learn
/// tab has something new most days **without recording anything about the
/// person reading it** — no view counts, no timestamps, no identifiers, no
/// storage at all.
library;

/// A one-minute product-education card.
class LearnCard {
  const LearnCard({required this.id, required this.title, required this.body});

  final String id;
  final String title;
  final String body;
}

abstract final class LearnContent {
  /// The full deck. Order is stable; [forDate] indexes into it.
  static const List<LearnCard> cards = [
    LearnCard(
      id: 'on_device',
      title: 'Your answers stay on your phone',
      body:
          'WellaPath works out its guidance on your device. Your symptom '
          'answers are not sent to us and are not stored on a server.',
    ),
    LearnCard(
      id: 'few_questions',
      title: 'Why it asks a few questions',
      body:
          'Each answer narrows things down, so the guidance you get at the '
          'end reflects what you actually told it — not a general leaflet.',
    ),
    LearnCard(
      id: 'not_a_diagnosis',
      title: 'Guidance, not a diagnosis',
      body:
          'WellaPath helps you decide what to do next. It does not name what '
          'is wrong with you, and it does not replace a doctor.',
    ),
    LearnCard(
      id: 'urgent_interrupt',
      title: 'It can stop and tell you to get help now',
      body:
          'If your answers point to something urgent, WellaPath interrupts '
          'the questions and shows emergency guidance straight away.',
    ),
    LearnCard(
      id: 'find_clinic',
      title: 'Finding care near you',
      body:
          'Find a clinic lists nearby facilities by distance. You can allow '
          'location access, or search by area name instead.',
    ),
    LearnCard(
      id: 'offline',
      title: 'It works without a connection',
      body:
          'After the first setup, the questions and guidance run offline. '
          'Only finding a clinic on a map needs the internet.',
    ),
    LearnCard(
      id: 'take_it_with_you',
      title: 'Taking the result with you',
      body:
          'The guidance screen is yours to read out or show to whoever you '
          'see next. Nothing is shared unless you choose to share it.',
    ),
  ];

  /// The card of the day. Deterministic, storage-free: the same date always
  /// gives the same card, and a different day usually gives a different one.
  static LearnCard forDate(DateTime date) {
    final int dayNumber = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime.utc(2026, 1, 1)).inDays;
    return cards[dayNumber.abs() % cards.length];
  }
}
