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
import '../learn/learn_screen.dart';
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
  void _onHowItWorks() {
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
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                children: [
                  const _Greeting(),
                  const SizedBox(height: 16),

                  // The primary action, given the weight the brief asks for: one
                  // large card, its own illustration, and a plain sentence saying
                  // what happens next.
                  EntranceFade(child: _PrimaryActionCard(onTap: _onStart)),
                  const SizedBox(height: 14),

                  // Emergency: always visible, never the loudest thing on screen.
                  // A permanently alarming home screen trains people to ignore the
                  // one colour that should mean "act now", so this is a tinted card
                  // with a red accent rather than a full red panel. The ACTION is
                  // unchanged — it opens the dialer with 112 entered.
                  EntranceFade(
                    delay: const Duration(milliseconds: 90),
                    child: _EmergencyCard(onTap: _onCallEmergency),
                  ),
                  const SizedBox(height: 14),

                  EntranceFade(
                    delay: const Duration(milliseconds: 170),
                    child: _SecondaryAction(
                      icon: Icons.location_on_outlined,
                      title: 'Find a clinic',
                      subtitle: 'See hospitals and clinics sorted by distance.',
                      onTap: _onFindClinic,
                    ),
                  ),
                  const SizedBox(height: 10),
                  EntranceFade(
                    delay: const Duration(milliseconds: 240),
                    child: _SecondaryAction(
                      icon: Icons.lightbulb_outline_rounded,
                      title: 'How WellaPath works',
                      subtitle:
                          'A one-minute tour, and what it does with your answers.',
                      onTap: _onHowItWorks,
                    ),
                  ),
                ],
              ),
            ),
            // LOCKED PRINCIPLE #1. Two of the three services skip the
            // assessment entirely, so a user can reach care without ever
            // seeing the modal that carries this wording. It is PINNED below
            // the scroll area rather than placed at the end of it: in a
            // scrolling list this line would sit below the fold on a small
            // screen, and the one sentence that says "this is not a
            // diagnosis" must never be the thing a user has to go looking
            // for.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Column(
                children: [
                  const Text(
                    'WellaPath helps you decide what to do next. It is not a '
                    'diagnosis and not a substitute for emergency services.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: Brand.inkSoft,
                    ),
                  ),
                  // Internal-build marker: nonclinical, always visible on
                  // internal/staging builds so a tester (and a store
                  // reviewer) can tell this build is not production. Never
                  // shown on a production build.
                  if (BuildEnvironment.isInternal()) ...[
                    const SizedBox(height: 8),
                    Text(
                      BuildEnvironment.kInternalBuildMarker,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Brand.inkSoft,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Warm greeting: Wella, then the question, then a short line of reassurance.
class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const EntranceFade(
          duration: Duration(milliseconds: 520),
          child: Wella(size: 58, mood: WellaMood.waving),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: EntranceFade(
            delay: Duration(milliseconds: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello',
                  style: TextStyle(fontSize: 14.5, color: Brand.inkSoft),
                ),
                SizedBox(height: 4),
                Text(
                  'How can WellaPath help you today?',
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.25,
                    fontWeight: FontWeight.w800,
                    color: Brand.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The one card that should catch the eye first.
class _PrimaryActionCard extends StatelessWidget {
  const _PrimaryActionCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: 'Check your symptoms',
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Brand.primary, Brand.primaryDeep],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Brand.primary.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.checklist_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'About 2 minutes',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Check your symptoms',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Answer a few simple questions to understand what to do next.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.white.withValues(alpha: 0.94),
              ),
            ),
            const SizedBox(height: 14),
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

/// Emergency help: visible at a glance, calm until it is needed.
class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: 'Need urgent help? Call emergency services on 112',
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Brand.emergencyTint,
          borderRadius: BorderRadius.circular(Brand.radiusCard),
          border: Border.all(color: Brand.emergency.withValues(alpha: 0.38)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Brand.emergency,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.call_rounded,
                color: Colors.white,
                size: 21,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Need urgent help?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Brand.emergency,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Call emergency services on 112.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: Brand.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Brand.emergency),
          ],
        ),
      ),
    );
  }
}

/// A quiet row for the supporting actions.
class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
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
      borderRadius: BorderRadius.circular(Brand.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radiusCard),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radiusCard),
            border: Border.all(color: Brand.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Brand.primaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Brand.primary, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Brand.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: Brand.inkSoft,
                      ),
                    ),
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
