/// The Learn tab — how WellaPath works, and a card of the day.
///
/// Everything here is product education (see `learn_content.dart`) and runs
/// entirely on the device: no network call, no analytics, no stored reading
/// history. The replay entry point for the Wella introduction lives here, as
/// the brief asks, under *How WellaPath works*.
library;

import 'package:flutter/material.dart';

import '../../shared/motion/motion.dart';
import '../../shared/theme/brand.dart';
import '../../shared/widgets/wella.dart';
import '../onboarding/onboarding_screen.dart';
import 'learn_content.dart';

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key, this.today});

  /// Injectable for tests; production uses the current date.
  final DateTime? today;

  void _replayIntroduction(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const OnboardingScreen(replay: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LearnCard card = LearnContent.forDate(today ?? DateTime.now());

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          const Text(
            'Learn',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Brand.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Short, plain explanations of how WellaPath works.',
            style: TextStyle(fontSize: 15, height: 1.5, color: Brand.inkSoft),
          ),
          const SizedBox(height: 20),

          EntranceFade(child: _DailyCard(card: card)),
          const SizedBox(height: 14),

          EntranceFade(
            delay: const Duration(milliseconds: 110),
            child: _HowItWorksCard(
              onReplay: () => _replayIntroduction(context),
            ),
          ),
          const SizedBox(height: 14),

          const EntranceFade(
            delay: Duration(milliseconds: 200),
            child: _TipsCard(),
          ),
        ],
      ),
    );
  }
}

class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.card});

  final LearnCard card;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.primary, Brand.primaryDeep],
        ),
        borderRadius: BorderRadius.circular(Brand.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'LEARN IN ONE MINUTE',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            card.title,
            style: const TextStyle(
              fontSize: 19,
              height: 1.3,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            card.body,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.94),
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard({required this.onReplay});

  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        color: Brand.surfaceMuted,
        borderRadius: BorderRadius.circular(Brand.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Wella(size: 54, semanticLabel: 'Wella'),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'How WellaPath works',
                  style: TextStyle(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w800,
                    color: Brand.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _Step(number: '1', text: 'Tell us what is bothering you.'),
          const _Step(number: '2', text: 'Answer a few simple questions.'),
          const _Step(
            number: '3',
            text: 'Receive clear guidance about what to do next.',
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onReplay,
              style: TextButton.styleFrom(
                foregroundColor: Brand.primary,
                minimumSize: const Size(0, Brand.minTapTarget),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.replay_rounded, size: 19),
              label: const Text(
                'Replay introduction',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Brand.primaryTint,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Brand.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: Brand.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(Brand.radiusCard),
        border: Border.all(color: Brand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Good to know',
            style: TextStyle(
              fontSize: 17.5,
              fontWeight: FontWeight.w800,
              color: Brand.ink,
            ),
          ),
          const SizedBox(height: 12),
          for (final card in LearnContent.cards.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 10),
                    child: CircleAvatar(
                      radius: 3,
                      backgroundColor: Brand.primary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      card.title,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: Brand.ink,
                      ),
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
