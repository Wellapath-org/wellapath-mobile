/// Help and Support — available offline, always.
///
/// Every article is a compile-time constant (`help_content.dart`), so this
/// screen works with no connection, on first launch, and in a place with no
/// signal. Emergency guidance is pinned to the top and styled so it is found
/// without reading the list.
///
/// Two things are deliberately conditional:
///
///  * **Feedback** appears only when `FeatureFlags.feedbackEnabled` is on.
///    There is no backend, so in an ordinary build the row is absent rather
///    than greyed out — a disabled control still invites a tap and still
///    disappoints.
///  * **Support chat** appears only when `FeatureFlags.supportChatEnabled`
///    is on. It is designed (see [SupportChatIntroScreen]) but not reachable:
///    there is no backend and no staffed process, and a chat nobody answers
///    is worse than none. No third-party chat SDK is used or added.
library;

import 'package:flutter/material.dart';

import '../../core/config/feature_flags.dart';
import '../../shared/theme/brand.dart';
import '../../shared/widgets/wella.dart';
import '../feedback/feedback_screen.dart';
import 'help_content.dart';
import 'support_chat_intro_screen.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<HelpArticle> emergency = HelpContent.articles
        .where((a) => a.isEmergency)
        .toList();
    final List<HelpArticle> rest = HelpContent.articles
        .where((a) => !a.isEmergency)
        .toList();

    return Scaffold(
      backgroundColor: Brand.surface,
      // Always present: this screen is only ever pushed, so removing the app
      // bar would remove the only way back out of the route.
      appBar: AppBar(
        backgroundColor: Brand.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Help and support', style: Brand.title),
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
            const _OfflineNote(),
            const SizedBox(height: Brand.space4),

            for (final HelpArticle article in emergency) ...[
              _ArticleRow(article: article),
              const SizedBox(height: Brand.space4),
            ],

            const Text('Using WellaPath', style: Brand.label),
            const SizedBox(height: Brand.space2),
            for (final HelpArticle article in rest)
              _ArticleRow(article: article),

            if (FeatureFlags.feedbackEnabled) ...[
              const SizedBox(height: Brand.space6),
              const Text('Tell us how it is going', style: Brand.label),
              const SizedBox(height: Brand.space2),
              _ActionRow(
                icon: Icons.rate_review_outlined,
                title: 'Give feedback',
                subtitle: 'Two quick questions. No personal details, please.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FeedbackScreen(),
                  ),
                ),
              ),
            ],

            if (FeatureFlags.supportChatEnabled) ...[
              const SizedBox(height: Brand.space6),
              const Text('Message support', style: Brand.label),
              const SizedBox(height: Brand.space2),
              _ActionRow(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Message the support team',
                subtitle: 'Help using the app. Not medical advice.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SupportChatIntroScreen(),
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

/// Says plainly that this section does not need a connection — the question
/// people ask when they are somewhere with no signal.
class _OfflineNote extends StatelessWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Brand.space3),
      decoration: BoxDecoration(
        color: Brand.surfaceMuted,
        borderRadius: BorderRadius.circular(Brand.radiusSurface),
      ),
      child: Row(
        children: [
          const Wella(size: 44, semanticLabel: 'Wella'),
          const SizedBox(width: Brand.space3),
          const Expanded(
            child: Text(
              'These answers are stored in the app, so they work without a '
              'connection.',
              style: Brand.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  const _ArticleRow({required this.article});

  final HelpArticle article;

  @override
  Widget build(BuildContext context) {
    final bool emergency = article.isEmergency;
    return Padding(
      padding: const EdgeInsets.only(bottom: Brand.space2),
      child: Material(
        color: emergency ? Brand.emergencySurface : Brand.surface,
        borderRadius: BorderRadius.circular(Brand.radiusSurface),
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HelpArticleScreen(article: article),
            ),
          ),
          borderRadius: BorderRadius.circular(Brand.radiusSurface),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(
              horizontal: Brand.space4,
              vertical: Brand.space3,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radiusSurface),
              border: Border.all(
                color: emergency ? Brand.emergency : Brand.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  emergency
                      ? Icons.emergency_outlined
                      : Icons.help_outline_rounded,
                  size: 22,
                  color: emergency ? Brand.emergencyText : Brand.primary,
                ),
                const SizedBox(width: Brand.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        style: Brand.cardTitle.copyWith(
                          color: emergency ? Brand.emergencyText : Brand.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(article.summary, style: Brand.caption),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: emergency ? Brand.emergencyText : Brand.inkSoft,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
          constraints: const BoxConstraints(minHeight: 64),
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
              Icon(icon, size: 22, color: Brand.primary),
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

/// One article. Plain text, generous line height, nothing to tap.
class HelpArticleScreen extends StatelessWidget {
  const HelpArticleScreen({super.key, required this.article});

  final HelpArticle article;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: AppBar(
        backgroundColor: Brand.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(article.title, style: Brand.title),
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
            if (article.isEmergency)
              Container(
                margin: const EdgeInsets.only(bottom: Brand.space4),
                padding: const EdgeInsets.all(Brand.space4),
                decoration: BoxDecoration(
                  color: Brand.emergencySurface,
                  borderRadius: BorderRadius.circular(Brand.radiusSurface),
                  border: Border.all(color: Brand.emergency),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.emergency_outlined,
                      color: Brand.emergencyText,
                    ),
                    const SizedBox(width: Brand.space3),
                    Expanded(
                      child: Text(
                        'In an emergency, call 112 now.',
                        style: Brand.bodyStrong.copyWith(
                          color: Brand.emergencyText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            for (final String paragraph in article.paragraphs)
              Padding(
                padding: const EdgeInsets.only(bottom: Brand.space4),
                child: Text(paragraph, style: Brand.body),
              ),
          ],
        ),
      ),
    );
  }
}
