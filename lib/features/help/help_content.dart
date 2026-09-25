/// Help and Support articles, bundled with the app.
///
/// **Offline by construction.** These are compile-time constants, so Help
/// works with the radio off, on a first launch that never reached the
/// network, and on a plane. Nothing here is fetched, cached or updated
/// remotely.
///
/// **Product support, not medical advice.** The articles explain how to use
/// the app and what it can and cannot do. The emergency article tells people
/// to call emergency services; it does not triage, list symptoms, or advise
/// on a condition. Any change that adds clinical content needs clinical
/// review — the guard in `test/help/help_content_test.dart` catches the
/// obvious accidents.
library;

class HelpArticle {
  const HelpArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.paragraphs,
    this.isEmergency = false,
  });

  final String id;
  final String title;

  /// One line shown in the list, so people can find the right article
  /// without opening several.
  final String summary;
  final List<String> paragraphs;

  /// Renders with the emergency treatment and sorts to the top.
  final bool isEmergency;
}

abstract final class HelpContent {
  static const List<HelpArticle> articles = [
    HelpArticle(
      id: 'emergency',
      title: 'Emergency guidance',
      summary: 'What to do if you think this is an emergency.',
      isEmergency: true,
      paragraphs: [
        'If you think you or someone else is in immediate danger, call '
            'emergency services on 112 now. Do not wait to finish a symptom '
            'check, and do not use this app instead of calling.',
        'WellaPath can stop a symptom check part way through and tell you to '
            'seek urgent help. That is a prompt to act, not a diagnosis.',
        'Support and feedback are never a route for an emergency. Nobody '
            'monitors them, and they do not reach a clinician.',
      ],
    ),
    HelpArticle(
      id: 'symptom_checking',
      title: 'How symptom checking works',
      summary: 'What the questions do and what you get at the end.',
      paragraphs: [
        'You choose what is bothering you, then answer a few short '
            'questions. Each answer narrows things down, so the guidance at '
            'the end reflects what you actually told it.',
        'The whole thing runs on your phone and takes about two minutes. You '
            'can stop at any point; nothing is kept when you do.',
        'What you get is guidance on what to do next — whether to look after '
            'yourself, see someone, or seek urgent care. It is not a '
            'diagnosis and it does not replace a doctor.',
      ],
    ),
    HelpArticle(
      id: 'find_clinic',
      title: 'How to find a clinic',
      summary: 'Using the locator, with or without location access.',
      paragraphs: [
        'Find a clinic lists health facilities sorted by distance, closest '
            'first. You can open it from the home screen at any time — you '
            'do not need to do a symptom check first.',
        'If you allow location access, the list is sorted around where you '
            'are. Your location is used on the device for that sorting and '
            'is not sent to WellaPath.',
        'If you prefer not to share location, you can search by area name '
            'instead. The results are the same facilities.',
      ],
    ),
    HelpArticle(
      id: 'why_internet',
      title: 'Why some things need the internet',
      summary: 'What works offline, and what does not.',
      paragraphs: [
        'Symptom checking, your guidance, Learn and this Help section all '
            'work offline once the app has finished its first setup.',
        'The clinic map needs a connection, because the map images come from '
            'a map provider as you look at them.',
        'The very first launch also needs a brief connection so the app can '
            'fetch its configuration. After that it keeps working without '
            'one.',
      ],
    ),
    HelpArticle(
      id: 'can_and_cannot',
      title: 'What WellaPath can and cannot do',
      summary: 'The limits, in plain words.',
      paragraphs: [
        'It can help you decide what to do next, list health facilities by '
            'distance, and tell you when something looks urgent.',
        'It cannot examine you, name your illness, prescribe anything, or '
            'replace a consultation. It does not know your history, and it '
            'has no access to your medical records.',
        'If your own judgement says something is seriously wrong, act on '
            'that, whatever the app says.',
      ],
    ),
    HelpArticle(
      id: 'not_working',
      title: 'If the app is not working',
      summary: 'Simple steps when something goes wrong.',
      paragraphs: [
        'Close the app fully and open it again. Most temporary problems '
            'clear this way.',
        'If the clinic map is blank, check your connection — the map is the '
            'one part that needs one.',
        'If a screen looks wrong or text is cut off, try reducing the system '
            'text size a little, then report it through feedback when that '
            'becomes available.',
        'If the app will not start at all, reinstalling it is safe: there is '
            'nothing of yours stored inside it to lose.',
      ],
    ),
    HelpArticle(
      id: 'privacy_safety',
      title: 'Privacy and safety',
      summary: 'What is kept, what is sent, and what is not.',
      paragraphs: [
        'Your symptom answers and the guidance you get are worked out on '
            'this device. They are not sent to WellaPath and not stored on a '
            'server.',
        'There is no account, no sign-up and no profile. Nothing in the app '
            'identifies you to us.',
        'Location, if you allow it, is used on the device to sort facilities '
            'by distance. Viewing the clinic map requests map images from the '
            'map provider.',
        'Please do not put your name, phone number, symptoms or any health '
            'information into feedback or support messages.',
      ],
    ),
  ];

  static HelpArticle byId(String id) =>
      articles.firstWhere((article) => article.id == id);
}
