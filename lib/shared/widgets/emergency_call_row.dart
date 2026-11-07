/// The app's one "call 112" control and the action behind it.
///
/// Extracted unchanged from the home screen so every surface that offers the
/// emergency number shows the same wording, the same look and the same dial
/// behaviour. Used by the home screen and, for WP-024, by the clinic
/// locator's states that show no facilities (empty, failed, offline,
/// out of region, location unavailable).
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/telemetry/contract/telemetry_event.dart';
import '../../core/telemetry/telemetry.dart';
import '../motion/motion.dart';
import '../theme/brand.dart';

/// Opens the dialer with 112 entered. The `tel:` scheme uses ACTION_DIAL,
/// which does not place the call — the user still presses dial. That is the
/// confirmation step, so no extra "are you sure" is added here: friction in
/// front of an emergency number is its own harm.
Future<void> callEmergencyNumber() async {
  // Captured before the handoff, and not awaited: `capture` returns
  // immediately and the dialer opens exactly as fast as it did before.
  // Carries the action type only — this control is reachable without an
  // assessment, and the contract rejects a session ID here regardless.
  Telemetry.capture(
    const EmergencyActionEvent(
      actionType: EmergencyActionType.callEmergencyNumber,
    ),
  );
  await launchUrl(Uri(scheme: 'tel', path: '112'));
}

/// Emergency help: unmistakable, never frightening. No pulse, no flash.
class EmergencyCallRow extends StatelessWidget {
  const EmergencyCallRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: 'Need urgent help? Call emergency services on 112',
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
                    'Call emergency services on 112',
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
