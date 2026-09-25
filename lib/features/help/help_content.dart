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
/// review — the shared guard in `test/support/content_guard.dart`, applied by
/// `test/help/help_offline_test.dart`, catches the obvious accidents.
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
  /// Wording approved by the founder 2026-09-25, verbatim.
  ///
  /// Three accuracy constraints came with that approval and are honoured
  /// here: no claim that "each answer narrows things down" (unverified
  /// against the clinical engine), no promise that an area search returns
  /// "the same facilities" (unproven by any test), and no instruction to
  /// reduce the system text size — the app adapts to the reader's
  /// accessibility settings, not the other way round.
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
        'WellaPath may stop a symptom check partway through and tell you to '
            'seek urgent help. This is a prompt to act, not a diagnosis.',
        'Support and feedback are not monitored for emergencies and may not '
            'receive an immediate response. Never use them to request '
            'emergency help.',
      ],
    ),
    HelpArticle(
      id: 'symptom_checking',
      title: 'How symptom checking works',
      summary: 'What the questions do and what you receive at the end.',
      paragraphs: [
        'Choose what is bothering you and answer a few short questions. '
            'WellaPath uses your answers to provide guidance about what to do '
            'next.',
        'The assessment runs on your phone and usually takes about two '
            'minutes. You can stop at any time. Your answers are not saved '
            'after you leave the symptom check.',
        'The result is guidance about whether to care for yourself, visit a '
            'healthcare professional or seek urgent help. It is not a '
            'diagnosis and does not replace a qualified healthcare '
            'professional.',
      ],
    ),
    HelpArticle(
      id: 'find_clinic',
      title: 'How to find a clinic',
      summary: 'Using the clinic locator with or without location access.',
      paragraphs: [
        'Find a clinic lists health facilities by distance. You can open it '
            'from the Home screen without completing a symptom check.',
        'If you allow location access, your location is used on your device '
            'to sort the facilities. WellaPath does not receive or store your '
            'location.',
        'If you prefer not to allow location access, you can search using an '
            'area name.',
        'Displaying the clinic map requires map information from the map '
            'provider.',
      ],
    ),
    HelpArticle(
      id: 'why_internet',
      title: 'Why some features need the internet',
      summary: 'What works offline and what requires a connection.',
      paragraphs: [
        'After the app completes its first setup, symptom checking, its '
            'guidance, Learn and this Help section can work without an '
            'internet connection.',
        'The clinic map requires a connection because its map information is '
            'loaded while you use it.',
        'The first launch requires a brief connection so WellaPath can '
            'complete its setup. Afterward, the core guidance can continue '
            'working offline.',
      ],
    ),
    HelpArticle(
      id: 'can_and_cannot',
      title: 'What WellaPath can and cannot do',
      summary: 'WellaPath\'s limits, in plain language.',
      paragraphs: [
        'WellaPath can help you decide what to do next, list health '
            'facilities by distance and tell you when your answers suggest '
            'that urgent help may be needed.',
        'It cannot examine you, diagnose an illness, prescribe treatment or '
            'replace a consultation with a qualified healthcare professional.',
        'It only uses the answers you provide during the current symptom '
            'check. It does not have access to your medical records.',
        'If you believe that something is seriously wrong, seek appropriate '
            'help even if the app has not told you to do so.',
      ],
    ),
    HelpArticle(
      id: 'not_working',
      title: 'If the app is not working',
      summary: 'Simple steps to try when something goes wrong.',
      paragraphs: [
        'Close WellaPath fully and open it again. This may resolve a '
            'temporary problem.',
        'If the clinic map is blank, check your internet connection.',
        'If text is cut off or a screen is difficult to use, keep your '
            'preferred system text size and report the problem through an '
            'available feedback or support channel.',
        'If the app will not start, make sure you have an internet '
            'connection before reinstalling it. Reinstalling may repeat the '
            'first-time setup, but there is no WellaPath account or server '
            'profile to lose.',
      ],
    ),
    HelpArticle(
      id: 'privacy_safety',
      title: 'Privacy and safety',
      summary: 'What is processed, what is sent and what is not.',
      paragraphs: [
        'Your symptom answers and guidance are processed on your device. '
            'They are not sent to WellaPath or stored on WellaPath\'s '
            'servers.',
        'The current MVP does not require an account, sign-up or personal '
            'profile. WellaPath does not use your symptom answers to identify '
            'you.',
        'If you allow location access, your location is used on your device '
            'to sort facilities by distance. WellaPath does not receive or '
            'store it. Viewing the clinic map requires requests to the map '
            'provider.',
        'Do not include your name, phone number, symptoms, diagnosis or '
            'other personal health information in feedback or support '
            'messages.',
      ],
    ),
  ];
}
