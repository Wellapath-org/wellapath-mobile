/// The support-chat entry screen — designed, not enabled.
///
/// Unreachable in any ordinary build: `HelpScreen` only links here when
/// `FeatureFlags.supportChatEnabled` is on, and it is off. It exists so the
/// experience can be reviewed and agreed before anyone is asked to staff it.
///
/// Everything below the fold is the promise support has to keep before this
/// is switched on: what support is for, what it is not for, that it needs a
/// connection, and when a human is actually there. **Nothing is composed or
/// stored here** — there is no message box, and no draft is kept on the
/// device, because a queued message nobody receives is the worst outcome for
/// someone who is unwell.
///
/// No third-party chat SDK (Intercom, Zendesk, Crisp or similar) is used or
/// added; when this is built it will speak to WellaPath's own backend.
library;

import 'package:flutter/material.dart';

import '../../shared/theme/brand.dart';
import '../../shared/widgets/wella.dart';

class SupportChatIntroScreen extends StatelessWidget {
  const SupportChatIntroScreen({
    super.key,
    this.hours = 'Monday to Friday, 9am – 5pm EAT',
    this.responseTime = 'Usually within one working day',
    this.canStartChat = false,
  });

  /// Published operating hours. Shown before anyone starts a conversation,
  /// so nobody waits on a closed desk.
  final String hours;
  final String responseTime;

  /// Whether the backend is live. False means the start control is absent —
  /// not greyed out — so the screen never offers something it cannot do.
  final bool canStartChat;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: AppBar(
        backgroundColor: Brand.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Message support', style: Brand.title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Brand.gutter,
            Brand.space3,
            Brand.gutter,
            Brand.space8,
          ),
          children: [
            Row(
              children: [
                const Wella(size: 56, semanticLabel: 'Wella'),
                const SizedBox(width: Brand.space3),
                const Expanded(
                  child: Text(
                    'Support helps you use WellaPath.',
                    style: Brand.cardTitle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Brand.space5),

            const _Point(
              icon: Icons.build_outlined,
              text:
                  'We can help with using the app — finding a clinic, '
                  'starting a symptom check, or something not working.',
            ),
            const _Point(
              icon: Icons.medical_information_outlined,
              text:
                  'Support does not give medical advice. We cannot tell you '
                  'what is wrong or what treatment to have.',
            ),
            const _Point(
              icon: Icons.privacy_tip_outlined,
              text:
                  'Please do not share symptoms, medical records, or details '
                  'that identify you.',
              emphasis: true,
            ),
            const _Point(
              icon: Icons.emergency_outlined,
              text:
                  'Never use support for an emergency. Nobody is watching '
                  'these messages around the clock — call 112 instead.',
              emphasis: true,
            ),
            const _Point(
              icon: Icons.wifi_outlined,
              text: 'Messaging needs an internet connection.',
            ),

            const SizedBox(height: Brand.space4),
            Container(
              padding: const EdgeInsets.all(Brand.space4),
              decoration: BoxDecoration(
                color: Brand.surfaceMuted,
                borderRadius: BorderRadius.circular(Brand.radiusSurface),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('When we are here', style: Brand.label),
                  const SizedBox(height: Brand.space2),
                  Text(hours, style: Brand.bodyStrong),
                  const SizedBox(height: Brand.space1),
                  Text(responseTime, style: Brand.caption),
                ],
              ),
            ),

            if (canStartChat) ...[
              const SizedBox(height: Brand.space6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {},
                  style: FilledButton.styleFrom(
                    backgroundColor: Brand.primary,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Brand.radiusControl),
                    ),
                  ),
                  child: const Text(
                    'Start a conversation',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text, this.emphasis = false});

  final IconData icon;
  final String text;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Brand.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: emphasis ? Brand.emergencyText : Brand.primary,
          ),
          const SizedBox(width: Brand.space3),
          Expanded(
            child: Text(
              text,
              style: emphasis
                  ? Brand.body.copyWith(
                      color: Brand.emergencyText,
                      fontWeight: FontWeight.w600,
                    )
                  : Brand.body,
            ),
          ),
        ],
      ),
    );
  }
}
