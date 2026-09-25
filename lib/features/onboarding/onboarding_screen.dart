/// "Meet Wella" — a five-screen, story-led introduction.
///
/// Two ways in:
///
///  * **First launch** — the splash pushes this, and finishing (or skipping)
///    writes [OnboardingScreen.onboardingSeenKey] so it never interrupts
///    again.
///  * **Replay** — opened from *How WellaPath works* with `replay: true`. A
///    replay pops back where it came from and deliberately does not touch
///    preferences: watching the introduction again is not a state change.
///
/// **No health data is created here.** The three cards on the "what brings
/// you here" screen choose a *destination* and nothing else: the answer lives
/// in this widget's State for the length of the flow, is never written to
/// disk, never sent anywhere, and never reaches the assessment engine. It is
/// a menu, not an intake form.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/motion/motion.dart';
import '../../shared/theme/brand.dart';
import '../../shared/widgets/wella.dart';
import '../locator/locator_screen.dart';
import '../shell/app_shell.dart';

/// Where the user said they would like to start. Navigation only.
enum OnboardingIntent {
  symptoms,
  clinic,
  learn;

  /// The shell tab this intent opens on.
  ShellTab get tab => switch (this) {
    OnboardingIntent.symptoms => ShellTab.home,
    OnboardingIntent.clinic => ShellTab.home,
    OnboardingIntent.learn => ShellTab.learn,
  };
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.replay = false});

  /// True when opened from *How WellaPath works*.
  final bool replay;

  /// Persisted flag — once true, the splash goes straight to the app.
  static const String onboardingSeenKey = 'onboarding_seen';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pages = PageController();

  /// In-memory only. See the library comment.
  OnboardingIntent? _intent;

  int _page = 0;

  static const int _pageCount = 5;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page >= _pageCount - 1) {
      _finish();
      return;
    }
    if (!motionEnabled(context)) {
      _pages.jumpToPage(_page + 1);
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// Guards against a double tap: `_finish` awaits preferences, so two quick
  /// taps would otherwise run it twice — two `pushReplacement` calls, and for
  /// the clinic intent two stacked locators to back out of.
  bool _finishing = false;

  /// Both *Skip for now* and *Start with WellaPath* land here. Skipping is a
  /// decision, not an interruption — re-showing the introduction on the next
  /// launch would override it.
  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    if (widget.replay) {
      Navigator.of(context).pop();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(OnboardingScreen.onboardingSeenKey, true);
    } catch (_) {
      // A preferences failure must not trap anyone in onboarding; the worst
      // case is seeing the introduction again next launch.
    }
    if (!mounted) return;
    final OnboardingIntent? intent = _intent;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AppShell(initialTab: intent?.tab ?? ShellTab.home),
      ),
    );
    // "Find a clinic" opens the locator straight away. The symptom route
    // deliberately does NOT auto-start an assessment: that flow opens with a
    // disclosure sheet on the home screen, and onboarding must not step
    // around it.
    if (intent == OnboardingIntent.clinic) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const LocatorScreen(urgency: 'non_urgent'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.surface,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              onSkip: _finish,
              skipLabel: widget.replay ? 'Close' : 'Skip for now',
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _WelcomePage(onNext: _next),
                  _IntentPage(
                    selected: _intent,
                    onSelect: (intent) {
                      setState(() => _intent = intent);
                      _next();
                    },
                    onSkipChoice: _next,
                  ),
                  _JourneyPage(onNext: _next),
                  _TrustPage(onNext: _next),
                  _BeginPage(onStart: _finish, replay: widget.replay),
                ],
              ),
            ),
            _PageDots(count: _pageCount, index: _page),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSkip, required this.skipLabel});

  final VoidCallback onSkip;
  final String skipLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // The wordmark is decoration; "Skip for now" is a control. When
          // the system font is turned up far enough that both cannot fit
          // (measured: they overflow a 360dp bar by 49px at 2x), the
          // decoration gives way rather than the control being pushed off
          // screen or the label being ellipsised into nonsense.
          if (MediaQuery.textScalerOf(context).scale(17) < 27)
            const Flexible(
              child: Text(
                'wellapath',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Brand.ink,
                  letterSpacing: -0.2,
                ),
              ),
            )
          else
            const SizedBox.shrink(),
          Flexible(
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: Brand.inkSoft,
                minimumSize: const Size(64, Brand.minTapTarget),
              ),
              child: Text(
                // At a large system font "Skip for now" alone is wider than
                // the bar (measured: 49px over at 2x). The label shortens to
                // a word that still says exactly what the control does,
                // rather than being ellipsised into "Skip for n…".
                MediaQuery.textScalerOf(context).scale(15) >= 24
                    ? (skipLabel == 'Close' ? 'Close' : 'Skip')
                    : skipLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared page scaffold: generous margins, content top-aligned, action pinned
/// to the bottom so the primary button sits in the same place on every page.
class _Page extends StatelessWidget {
  const _Page({required this.children, this.action});

  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Brand.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.radiusControl),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 28,
      height: 1.22,
      fontWeight: FontWeight.w800,
      color: Brand.ink,
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 16, height: 1.55, color: Brand.inkSoft),
  );
}

// ── 1. A warm welcome ───────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _Page(
      action: _PrimaryButton(label: 'Say hello', onPressed: onNext),
      children: const [
        SizedBox(height: 8),
        Center(
          child: EntranceFade(
            duration: Duration(milliseconds: 560),
            offset: 18,
            child: Wella(size: 168, mood: WellaMood.waving),
          ),
        ),
        SizedBox(height: 20),
        EntranceFade(
          delay: Duration(milliseconds: 160),
          child: _Heading('Meet Wella'),
        ),
        SizedBox(height: 12),
        EntranceFade(
          delay: Duration(milliseconds: 280),
          child: _Body(
            'Your friendly guide to understanding your symptoms and finding '
            'the right care.',
          ),
        ),
      ],
    );
  }
}

// ── 2. Show the value ───────────────────────────────────────────────────────

class _IntentPage extends StatelessWidget {
  const _IntentPage({
    required this.selected,
    required this.onSelect,
    required this.onSkipChoice,
  });

  final OnboardingIntent? selected;
  final ValueChanged<OnboardingIntent> onSelect;
  final VoidCallback onSkipChoice;

  @override
  Widget build(BuildContext context) {
    const options = [
      (
        OnboardingIntent.symptoms,
        Icons.favorite_outline_rounded,
        'I want to understand my symptoms',
      ),
      (
        OnboardingIntent.clinic,
        Icons.location_on_outlined,
        'I want to find a nearby clinic',
      ),
      (
        OnboardingIntent.learn,
        Icons.lightbulb_outline_rounded,
        'I want to learn how WellaPath works',
      ),
    ];

    return _Page(
      action: TextButton(
        onPressed: onSkipChoice,
        style: TextButton.styleFrom(
          foregroundColor: Brand.inkSoft,
          minimumSize: const Size.fromHeight(Brand.minTapTarget),
        ),
        child: const Text(
          'I’ll decide later',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      children: [
        const SizedBox(height: 4),
        const EntranceFade(child: _Heading('What brings you here?')),
        const SizedBox(height: 10),
        const EntranceFade(
          delay: Duration(milliseconds: 120),
          child: _Body('Pick one to start with. You can do all three later.'),
        ),
        const SizedBox(height: 22),
        for (final (
              int i,
              (OnboardingIntent intent, IconData icon, String label),
            )
            in options.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: EntranceFade(
              delay: Duration(milliseconds: 200 + i * 90),
              child: _IntentCard(
                icon: icon,
                label: label,
                selected: selected == intent,
                onTap: () => onSelect(intent),
              ),
            ),
          ),
      ],
    );
  }
}

class _IntentCard extends StatelessWidget {
  const _IntentCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? Brand.primarySurface : Brand.surface,
          borderRadius: BorderRadius.circular(Brand.radiusSurface),
          border: Border.all(
            color: selected ? Brand.primary : Brand.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: Brand.primary, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: Brand.ink,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded, color: Brand.primary),
          ],
        ),
      ),
    );
  }
}

// ── 3. Explain the journey ──────────────────────────────────────────────────

class _JourneyPage extends StatefulWidget {
  const _JourneyPage({required this.onNext});

  final VoidCallback onNext;

  @override
  State<_JourneyPage> createState() => _JourneyPageState();
}

class _JourneyPageState extends State<_JourneyPage> {
  static const List<(IconData, String)> _steps = [
    (Icons.chat_bubble_outline_rounded, 'Tell us what is bothering you.'),
    (Icons.checklist_rounded, 'Answer a few simple questions.'),
    (Icons.explore_outlined, 'Receive clear guidance about what to do next.'),
  ];

  /// How many steps are showing. Steps reveal on tap, and also unfold on their
  /// own so nobody has to discover the interaction.
  int _shown = 1;

  /// Cancelled on dispose — a reveal that fires after the page is gone would
  /// outlive the widget.
  final List<Timer> _revealTimers = [];

  @override
  void initState() {
    super.initState();
    for (var i = 2; i <= _steps.length; i++) {
      _revealTimers.add(
        Timer(Duration(milliseconds: 900 * (i - 1)), () {
          if (mounted && _shown < i) setState(() => _shown = i);
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final timer in _revealTimers) {
      timer.cancel();
    }
    super.dispose();
  }

  /// Tapping reveals the next step. It deliberately does NOT fall through to
  /// "advance the page" once every step is showing: the copy says "tap to
  /// follow along", the steps also unfold on their own, and a reader who taps
  /// a moment after they finish would be thrown forward without asking.
  /// Moving on is the button's job.
  void _revealNext() {
    if (_shown < _steps.length) setState(() => _shown += 1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _revealNext,
      child: _Page(
        action: _PrimaryButton(label: 'Next', onPressed: widget.onNext),
        children: [
          const SizedBox(height: 4),
          const _Heading('Three simple steps'),
          const SizedBox(height: 10),
          const _Body('Tap to follow along.'),
          const SizedBox(height: 24),
          for (final (int i, (IconData icon, String text)) in _steps.indexed)
            AnimatedOpacity(
              opacity: i < _shown ? 1 : 0.18,
              duration: const Duration(milliseconds: 280),
              child: _JourneyStep(
                index: i + 1,
                icon: icon,
                text: text,
                active: i < _shown,
              ),
            ),
        ],
      ),
    );
  }
}

class _JourneyStep extends StatelessWidget {
  const _JourneyStep({
    required this.index,
    required this.icon,
    required this.text,
    required this.active,
  });

  final int index;
  final IconData icon;
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: active ? Brand.primary : Brand.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 22,
              color: active ? Colors.white : Brand.inkSoft,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Brand.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 4. Build trust ──────────────────────────────────────────────────────────

class _TrustPage extends StatelessWidget {
  const _TrustPage({required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _Page(
      action: _PrimaryButton(label: 'I understand', onPressed: onNext),
      children: const [
        SizedBox(height: 4),
        EntranceFade(child: _Heading('What WellaPath is')),
        SizedBox(height: 18),
        EntranceFade(
          delay: Duration(milliseconds: 120),
          child: _TrustCard(
            icon: Icons.explore_outlined,
            title: 'It helps you decide what to do next',
            body: 'Guidance based on the answers you give, on your phone.',
          ),
        ),
        SizedBox(height: 12),
        EntranceFade(
          delay: Duration(milliseconds: 210),
          child: _TrustCard(
            icon: Icons.medical_services_outlined,
            title: 'It does not replace a doctor',
            body: 'It is not a diagnosis and not a medical opinion.',
          ),
        ),
        SizedBox(height: 12),
        EntranceFade(
          delay: Duration(milliseconds: 300),
          child: _TrustCard(
            icon: Icons.emergency_outlined,
            title: 'If you feel seriously unwell, seek urgent help',
            body: 'Call emergency services straight away — do not wait.',
            emphasis: true,
          ),
        ),
      ],
    );
  }
}

class _TrustCard extends StatelessWidget {
  const _TrustCard({
    required this.icon,
    required this.title,
    required this.body,
    this.emphasis = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final Color accent = emphasis ? Brand.emergency : Brand.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: emphasis ? Brand.emergencySurface : Brand.surfaceMuted,
        borderRadius: BorderRadius.circular(Brand.radiusSurface),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: emphasis ? Brand.emergency : Brand.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: Brand.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 5. Begin ────────────────────────────────────────────────────────────────

class _BeginPage extends StatelessWidget {
  const _BeginPage({required this.onStart, required this.replay});

  final VoidCallback onStart;
  final bool replay;

  @override
  Widget build(BuildContext context) {
    return _Page(
      action: _PrimaryButton(
        label: replay ? 'Back to WellaPath' : 'Start with WellaPath',
        onPressed: onStart,
      ),
      children: [
        const SizedBox(height: 12),
        const Center(
          child: EntranceFade(
            duration: Duration(milliseconds: 520),
            offset: 16,
            child: Wella(size: 172, mood: WellaMood.celebrating),
          ),
        ),
        const SizedBox(height: 22),
        const EntranceFade(
          delay: Duration(milliseconds: 180),
          child: _Heading('You’re all set'),
        ),
        const SizedBox(height: 12),
        const EntranceFade(
          delay: Duration(milliseconds: 280),
          child: _Body(
            'Wella is ready when you are. You can replay this introduction '
            'any time from How WellaPath works.',
          ),
        ),
      ],
    );
  }
}

// ── Progress dots ───────────────────────────────────────────────────────────

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${index + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == index ? Brand.primary : Brand.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}
