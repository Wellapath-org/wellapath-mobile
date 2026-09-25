import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/build_environment.dart';
import '../../shared/motion/motion.dart';
import '../../shared/theme/brand.dart';
import '../../shared/widgets/wella.dart';
import '../../core/telemetry/contract/telemetry_event.dart';
import '../../core/telemetry/telemetry.dart';
import '../../shared/widgets/confirmation_dialog.dart';
import '../assessment/assessment_controller.dart';
import '../assessment/intro_screen.dart';
import '../help/help_screen.dart';
import '../learn/learn_screen.dart';
import '../learn/wella_today_card.dart';
import '../locator/locator_screen.dart';
import '../shell/app_shell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _infoShown = false;

  /// Opening the locator without an assessment still needs an urgency, since
  /// it drives which facility types are returned. `non_urgent` yields
  /// hospitals and clinics — the right set for someone browsing for care.
  ///
  /// Not an arbitrary placeholder: `_typesForUrgency` returns an *empty* set
  /// for any unrecognised value, so an invented urgency would silently show
  /// an empty locator.
  static const String _browseUrgency = 'non_urgent';

  void _onFindClinic() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LocatorScreen(urgency: _browseUrgency),
      ),
    );
  }

  /// Opens the dialer with 112 entered. The `tel:` scheme uses ACTION_DIAL,
  /// which does not place the call — the user still presses dial. That is the
  /// confirmation step, so no extra "are you sure" is added here: friction in
  /// front of an emergency number is its own harm.
  Future<void> _onCallEmergency() async {
    // Captured before the handoff, and not awaited: `capture` returns
    // immediately and the dialer opens exactly as fast as it did before.
    // Carries the action type only — this card is reachable without an
    // assessment, and the contract rejects a session ID here regardless.
    Telemetry.capture(
      const EmergencyActionEvent(
        actionType: EmergencyActionType.callEmergencyNumber,
      ),
    );
    await launchUrl(Uri(scheme: 'tel', path: '112'));
  }

  void _onStart() {
    if (_infoShown) {
      _goToIntro();
    } else {
      _showInfoModal();
    }
  }

  void _showInfoModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (sheetContext) => _InfoModal(
        onOkay: () {
          Navigator.of(sheetContext).pop();
          setState(() => _infoShown = true);
          _goToIntro();
        },
      ),
    );
  }

  void _goToIntro() {
    final controller = AssessmentController();
    // The assessment begins here: one controller, one session ID, one
    // `assessment_start`. A previous attempt's ID is never carried forward
    // because a previous attempt's controller is never carried forward.
    controller.telemetrySession.recordStart(
      entryPoint: AssessmentEntryPoint.home,
    );
    // Step 0 is the intro screen about to be pushed. Every later step records
    // itself from the transition that displays it.
    controller.telemetrySession.recordStepView();
    final homeRoute = ModalRoute.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IntroScreen(
          assessmentController: controller,
          onCancel: () => _confirmCancelAssessment(homeRoute, controller),
        ),
      ),
    );
  }

  Future<void> _confirmCancelAssessment(
    ModalRoute<void>? homeRoute,
    AssessmentController controller,
  ) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Cancel Assessment',
      message: 'Are you sure you want to cancel your symptom assessment?',
      cancelLabel: 'No, continue',
      confirmLabel: 'Yes, cancel',
    );
    if (confirmed && mounted) {
      // A user-initiated exit. `abandoned` describes who stopped it, not what
      // was found — no result exists at this point and none is referenced.
      controller.telemetrySession.recordComplete(CompletionStatus.abandoned);
      Navigator.of(context).popUntil((r) => r == homeRoute || r.isFirst);
    }
  }

  /// Switches to the Learn tab when the shell is above us; falls back to
  /// pushing Learn as its own route when this screen is used standalone.
  void _onLearn() {
    final ShellScope? shell = ShellScope.maybeOf(context);
    if (shell != null) {
      shell.select(ShellTab.learn);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: LearnScreen()),
      ),
    );
  }

  void _onHelp() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Brand.gutter,
                  Brand.space1,
                  Brand.gutter,
                  Brand.space4,
                ),
                children: [
                  const _Greeting(),
                  const SizedBox(height: Brand.space4),

                  // 1 — the strongest action on the screen.
                  EntranceFade(child: _PrimaryActionCard(onTap: _onStart)),
                  const SizedBox(height: Brand.space3),

                  // 2 — the locator stays a first-class home action. It is
                  // never demoted into Learn, More or a carousel: people
                  // arrive needing a clinic as often as they arrive needing
                  // questions.
                  EntranceFade(
                    delay: const Duration(milliseconds: 80),
                    child: _ActionRow(
                      icon: Icons.location_on_outlined,
                      title: 'Find a clinic',
                      subtitle: 'Health facilities, sorted by distance.',
                      onTap: _onFindClinic,
                    ),
                  ),
                  const SizedBox(height: Brand.space2),

                  // 3 — always visible, never alarming. Tinted surface and a
                  // red accent rather than a red panel: a home screen that
                  // shouts all day teaches people to ignore the one colour
                  // that should mean "act now". The action is unchanged —
                  // it opens the dialer with 112 entered.
                  EntranceFade(
                    delay: const Duration(milliseconds: 140),
                    child: _EmergencyRow(onTap: _onCallEmergency),
                  ),
                  const SizedBox(height: Brand.space5),

                  // 4 — one calm reason to come back.
                  const EntranceFade(
                    delay: Duration(milliseconds: 200),
                    child: WellaTodayCard(),
                  ),
                  const SizedBox(height: Brand.space3),

                  // 5 and 6.
                  EntranceFade(
                    delay: const Duration(milliseconds: 240),
                    child: _ActionRow(
                      icon: Icons.lightbulb_outline_rounded,
                      title: 'Learn',
                      subtitle: 'How WellaPath works, in one minute.',
                      onTap: _onLearn,
                    ),
                  ),
                  const SizedBox(height: Brand.space2),
                  EntranceFade(
                    delay: const Duration(milliseconds: 280),
                    child: _ActionRow(
                      icon: Icons.help_outline_rounded,
                      title: 'Help and support',
                      subtitle: 'Answers that work offline.',
                      onTap: _onHelp,
                    ),
                  ),
                ],
              ),
            ),
            // LOCKED PRINCIPLE #1. Two of the actions above skip the
            // assessment entirely, so someone can reach care without ever
            // seeing the sheet that carries this wording. Pinned below the
            // scroll area, never inside it: the one sentence that says "this
            // is not a diagnosis" must not be something you scroll to find.
            const _Disclaimer(),
          ],
        ),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Brand.gutter,
        Brand.space2,
        Brand.gutter,
        Brand.space2,
      ),
      child: Column(
        children: [
          Text(
            'WellaPath helps you decide what to do next. It is not a '
            'diagnosis and not a substitute for emergency services.',
            textAlign: TextAlign.center,
            style: Brand.caption.copyWith(fontSize: 12.5),
          ),
          // Internal-build marker: nonclinical, always visible on
          // internal/staging builds so a tester (and a store reviewer) can
          // tell this build is not production.
          if (BuildEnvironment.isInternal()) ...[
            const SizedBox(height: Brand.space2),
            Text(
              BuildEnvironment.kInternalBuildMarker,
              textAlign: TextAlign.center,
              style: Brand.caption.copyWith(fontSize: 11, letterSpacing: 0.3),
            ),
          ],
        ],
      ),
    );
  }
}

/// Wella, then the question. Nothing else competes at the top of the screen.
class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const EntranceFade(
          duration: Duration(milliseconds: 520),
          child: Wella(size: 54, mood: WellaMood.waving),
        ),
        const SizedBox(width: Brand.space3),
        Expanded(
          child: EntranceFade(
            delay: const Duration(milliseconds: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hello', style: Brand.caption),
                const SizedBox(height: 2),
                Text(
                  'How can WellaPath help you today?',
                  style: Brand.display.copyWith(fontSize: 21),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The primary action. A flat, confident purple surface — no gradient, no
/// glow, no shadow theatre. It carries a title, a plain explanation, an
/// honest time estimate and a visible Start control.
class _PrimaryActionCard extends StatelessWidget {
  const _PrimaryActionCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: 'Check your symptoms. About 2 minutes. Start',
      child: Container(
        padding: const EdgeInsets.all(Brand.space4),
        decoration: BoxDecoration(
          color: Brand.primary,
          borderRadius: BorderRadius.circular(Brand.radiusSurface),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.checklist_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: Brand.space2),
                const Expanded(
                  child: Text(
                    'Check your symptoms',
                    style: TextStyle(
                      fontSize: 19,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: Brand.space2),
                // Time expectation as plain text on the same rule as the
                // title, not a floating pill.
                const Text(
                  'About 2 minutes',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Brand.space2),
            const Text(
              'Answer a few simple questions to understand what to do next.',
              style: TextStyle(
                fontSize: 14.5,
                height: 1.45,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: Brand.space3),
            Container(
              height: Brand.minTapTarget,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Brand.radiusControl),
              ),
              child: const Text(
                'Start',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Brand.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Emergency help: unmistakable, never frightening. No pulse, no flash.
class _EmergencyRow extends StatelessWidget {
  const _EmergencyRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: 'Need urgent help? Calls emergency services on 112',
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(
          horizontal: Brand.space4,
          vertical: Brand.space3,
        ),
        decoration: BoxDecoration(
          color: Brand.emergencySurface,
          borderRadius: BorderRadius.circular(Brand.radiusSurface),
          border: Border.all(color: Brand.emergency),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.emergency_outlined,
              color: Brand.emergency,
              size: 24,
            ),
            const SizedBox(width: Brand.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Need urgent help?',
                    style: Brand.cardTitle.copyWith(color: Brand.emergencyText),
                  ),
                  const SizedBox(height: 2),
                  // Says what the tap does. The brief suggested "View
                  // emergency guidance", but this control dials 112 and its
                  // behaviour is deliberately unchanged — labelling a dialer
                  // as a reading screen would mislead someone in a hurry.
                  Text(
                    'Calls emergency services on 112.',
                    style: Brand.caption.copyWith(color: Brand.emergencyText),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Brand.emergencyText),
          ],
        ),
      ),
    );
  }
}

/// A quiet supporting row. One shape for every secondary action.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.surface,
      borderRadius: BorderRadius.circular(Brand.radiusSurface),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radiusSurface),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(
            horizontal: Brand.space4,
            vertical: Brand.space3,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radiusSurface),
            border: Border.all(color: Brand.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: Brand.primary, size: 24),
              const SizedBox(width: Brand.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Brand.cardTitle),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Brand.caption),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Brand.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoModal extends StatelessWidget {
  final VoidCallback onOkay;

  const _InfoModal({required this.onOkay});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Check your symptoms',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Brand.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Quickly take a short assessment. We make sure the information '
              "you give is safe and won't be shared. Your results will include",
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            _bullet('Possible causes of the symptoms'),
            _bullet('Recommendations on what actions to take'),
            const SizedBox(height: 20),
            const Text(
              'Note that',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Brand.primary,
              ),
            ),
            const SizedBox(height: 8),
            _bullet(
              "The results is not a diagnosis. It's only for your information "
              'and not a qualified medical opinion',
            ),
            _bullet(
              'If you believe you are in immediate life-threatening danger, '
              'call emergency services now.',
            ),
            _bullet(
              'WellaPath can help you assess your symptoms and will tell you '
              'if you need emergency care but it is not a substitute for '
              'emergency services.',
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onOkay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Brand.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Okay',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7, right: 10),
            child: CircleAvatar(radius: 3, backgroundColor: Brand.primary),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
