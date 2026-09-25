/// The More tab — what this app is, what it does with your information, and
/// how to see the introduction again.
///
/// Deliberately link-free. The store documents list the privacy policy URL as
/// *suggested* rather than confirmed live, and a settings screen whose only
/// button opens a dead page is worse than one that simply tells you the
/// facts. The summary below is in-app text drawn from
/// `docs/store/SUPPORT_AND_PRIVACY_POLICY.md`; the external links can be
/// added in a one-line change once the founder confirms the URLs are
/// reachable.
///
/// Nothing here toggles anything: there are no settings to change, because
/// the app collects nothing to configure.
library;

import 'package:flutter/material.dart';

import '../../core/config/build_environment.dart';
import '../../shared/motion/motion.dart';
import '../../shared/theme/brand.dart';
import '../onboarding/onboarding_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const String _version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.3.0',
  );
  static const String _build = String.fromEnvironment(
    'APP_BUILD',
    defaultValue: 'dev',
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          const Text(
            'More',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Brand.ink,
            ),
          ),
          const SizedBox(height: 20),

          const EntranceFade(
            child: _Panel(
              icon: Icons.info_outline_rounded,
              title: 'About WellaPath',
              body:
                  'WellaPath helps you decide what to do next when you are '
                  'unwell. It is a clinical decision support tool — it is not '
                  'a diagnosis, and it does not replace a doctor. If you feel '
                  'seriously unwell, seek urgent medical help.',
            ),
          ),
          const SizedBox(height: 14),

          const EntranceFade(
            delay: Duration(milliseconds: 110),
            child: _Panel(
              icon: Icons.lock_outline_rounded,
              title: 'Your information',
              body:
                  'Your symptom answers are worked out on this device and are '
                  'never sent to WellaPath. Location, if you allow it, is used '
                  'on the device to sort nearby facilities. Viewing the clinic '
                  'map requests map tiles from the map provider.',
            ),
          ),
          const SizedBox(height: 14),

          EntranceFade(
            delay: const Duration(milliseconds: 200),
            child: _ActionRow(
              icon: Icons.replay_rounded,
              label: 'Replay introduction',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const OnboardingScreen(replay: true),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),

          Center(
            child: Column(
              children: [
                Text(
                  'WellaPath $_version ($_build)',
                  style: const TextStyle(fontSize: 13, color: Brand.inkSoft),
                ),
                if (BuildEnvironment.isInternal()) ...[
                  const SizedBox(height: 6),
                  Text(
                    BuildEnvironment.kInternalBuildMarker,
                    style: const TextStyle(
                      fontSize: 12,
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
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Brand.surfaceMuted,
        borderRadius: BorderRadius.circular(Brand.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Brand.primary, size: 20),
              const SizedBox(width: 10),
              // Expanded so a long title (or a large system font) wraps
              // instead of overflowing the row on a 360dp screen.
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    color: Brand.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              fontSize: 15,
              height: 1.55,
              color: Brand.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
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
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radiusCard),
            border: Border.all(color: Brand.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: Brand.primary, size: 21),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Brand.ink,
                  ),
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
