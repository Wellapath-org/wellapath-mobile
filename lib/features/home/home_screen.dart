import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/widgets/confirmation_dialog.dart';
import '../assessment/assessment_controller.dart';
import '../assessment/intro_screen.dart';
import '../locator/locator_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color _primary = Color(0xFF6B4EFF);
  static const Color _emergencyRed = Color(0xFFDC2626);
  static const Color _ink = Color(0xFF1A1A2E);

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
    final homeRoute = ModalRoute.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IntroScreen(
          assessmentController: controller,
          onCancel: () => _confirmCancelAssessment(homeRoute),
        ),
      ),
    );
  }

  Future<void> _confirmCancelAssessment(ModalRoute<void>? homeRoute) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Cancel Assessment',
      message: 'Are you sure you want to cancel your symptom assessment?',
      cancelLabel: 'No, continue',
      confirmLabel: 'Yes, cancel',
    );
    if (confirmed && mounted) {
      Navigator.of(context).popUntil((r) => r == homeRoute || r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFF3D1F9E)],
            stops: [0.35, 1.0],
          ),
        ),
        child: SafeArea(
          // Scrollable with a minimum height of the viewport: on a tall
          // screen the Spacer pushes the disclaimer to the bottom as
          // designed, and on a short one the content scrolls instead of
          // clipping. Measured clipping the disclaimer mid-sentence on a
          // 720x1280 device — and that copy is LOCKED PRINCIPLE #1, so it
          // must never be the thing that gets cut off.
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          Center(
                            child: Image.asset(
                              'assets/images/logo_icon.png',
                              width: 40,
                              height: 40,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Hello and welcome!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Color(0xFF4A4A5A),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'How can we help you today?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _ServiceCard(
                            icon: Icons.checklist_rounded,
                            accent: _primary,
                            title: 'Check your symptoms',
                            subtitle:
                                'Answer a few questions and see how urgent it is.',
                            onTap: _onStart,
                          ),
                          const SizedBox(height: 12),
                          _ServiceCard(
                            icon: Icons.location_on_rounded,
                            accent: _primary,
                            title: 'Find a clinic near me',
                            subtitle:
                                'See hospitals and clinics sorted by distance.',
                            onTap: _onFindClinic,
                          ),
                          const SizedBox(height: 12),
                          _ServiceCard(
                            icon: Icons.call_rounded,
                            accent: _emergencyRed,
                            title: 'Call emergency — 112',
                            subtitle:
                                'Opens your dialer. No assessment needed.',
                            onTap: _onCallEmergency,
                            emphasised: true,
                          ),
                          const Spacer(),
                          // The disclaimer is on the home screen itself now, not only
                          // inside the assessment modal. Two of the three services skip
                          // the assessment entirely, so a user can reach care without
                          // ever opening that modal — and LOCKED PRINCIPLE #1 requires
                          // WellaPath never read as a diagnosis engine.
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16, top: 12),
                            child: Text(
                              'WellaPath helps you decide what to do next. It '
                              'is not a diagnosis and not a substitute for '
                              'emergency services.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One of the three home services. White on the gradient so it reads against
/// both the pale top and the deep purple bottom.
class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasised = false,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// The emergency card. Distinct by accent colour and a tinted border rather
  /// than a solid red fill — it must stand out without reading as an alarm on
  /// a screen the user sees every time they open the app.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: emphasised
                  ? accent.withValues(alpha: 0.45)
                  : const Color(0xFFE8E8EF),
              width: emphasised ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: emphasised ? accent : const Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Color(0xFF6B6B7B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: emphasised ? accent : const Color(0xFFB0B0BF),
              ),
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

  static const Color _primary = Color(0xFF6B4EFF);

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
                color: _primary,
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
                color: _primary,
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
                  backgroundColor: _primary,
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
            child: CircleAvatar(radius: 3, backgroundColor: _primary),
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
