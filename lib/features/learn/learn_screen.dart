/// The Learn tab — short topics, and a light "Myth or fact?" to make them
/// stick.
///
/// Interactive without becoming an article directory: a handful of topic
/// cards you can read in about a minute each, and six myth prompts that
/// answer immediately. **Answers live in this widget's State only.** Nothing
/// is scored, ranked, stored or sent; leaving the tab forgets everything, on
/// purpose — a health app that keeps a record of what you were curious about
/// is keeping a health record.
///
/// All content is bundled (see `learn_content.dart`), so Learn works
/// offline.
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Brand.gutter,
          Brand.space4,
          Brand.gutter,
          Brand.space8,
        ),
        children: [
          Row(
            children: [
              const Wella(size: 44, semanticLabel: 'Wella'),
              const SizedBox(width: Brand.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Learn', style: Brand.display.copyWith(fontSize: 24)),
                    const SizedBox(height: 2),
                    const Text(
                      'Short, plain explanations of how WellaPath works.',
                      style: Brand.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Brand.space5),

          const Text('MYTH OR FACT?', style: Brand.label),
          const SizedBox(height: Brand.space2),
          const EntranceFade(child: _MythDeck()),
          const SizedBox(height: Brand.space6),

          const Text('TOPICS', style: Brand.label),
          const SizedBox(height: Brand.space2),
          for (final (int i, LearnCard card) in LearnContent.cards.indexed)
            EntranceFade(
              delay: Duration(milliseconds: 60 * i),
              child: _TopicCard(card: card),
            ),

          const SizedBox(height: Brand.space4),
          _ReplayRow(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const OnboardingScreen(replay: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One statement at a time. Answering reveals the explanation and offers the
/// next one; there is no score and no progress to lose.
class _MythDeck extends StatefulWidget {
  const _MythDeck();

  @override
  State<_MythDeck> createState() => _MythDeckState();
}

class _MythDeckState extends State<_MythDeck> {
  int _index = 0;

  /// The answer the reader gave for the current card, or null before they
  /// answer. In memory only, and reset on every card.
  bool? _answeredFact;

  MythCard get _card => LearnContent.myths[_index % LearnContent.myths.length];

  void _answer(bool fact) => setState(() => _answeredFact = fact);

  void _next() => setState(() {
    _index += 1;
    _answeredFact = null;
  });

  @override
  Widget build(BuildContext context) {
    final MythCard card = _card;
    final bool? given = _answeredFact;
    final bool correct = given == card.isFact;

    return Container(
      padding: const EdgeInsets.all(Brand.space4),
      decoration: BoxDecoration(
        color: Brand.surfaceMuted,
        borderRadius: BorderRadius.circular(Brand.radiusSurface),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(card.statement, style: Brand.cardTitle),
          const SizedBox(height: Brand.space4),

          if (given == null)
            Row(
              children: [
                Expanded(
                  child: _AnswerButton(
                    label: 'Myth',
                    onTap: () => _answer(false),
                  ),
                ),
                const SizedBox(width: Brand.space3),
                Expanded(
                  child: _AnswerButton(
                    label: 'Fact',
                    onTap: () => _answer(true),
                  ),
                ),
              ],
            )
          else ...[
            Row(
              children: [
                // Outcome is carried by an icon and a word, never by colour
                // alone.
                Icon(
                  correct ? Icons.check_circle_rounded : Icons.info_rounded,
                  size: 20,
                  color: correct ? Brand.successText : Brand.warningText,
                ),
                const SizedBox(width: Brand.space2),
                Expanded(
                  child: Text(
                    correct
                        ? 'Correct — it is ${card.isFact ? 'a fact' : 'a myth'}.'
                        : 'Not quite — it is ${card.isFact ? 'a fact' : 'a myth'}.',
                    style: Brand.bodyStrong.copyWith(
                      color: correct ? Brand.successText : Brand.warningText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Brand.space2),
            Text(card.explanation, style: Brand.body),
            const SizedBox(height: Brand.space2),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _next,
                style: TextButton.styleFrom(
                  foregroundColor: Brand.primary,
                  minimumSize: const Size(0, Brand.minTapTarget),
                  padding: const EdgeInsets.symmetric(horizontal: Brand.space2),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text(
                  'Next one',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.primary,
        side: const BorderSide(color: Brand.primary),
        backgroundColor: Brand.surface,
        minimumSize: const Size.fromHeight(Brand.minTapTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radiusControl),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// A topic: heading, title, a minute of reading. Expands in place rather
/// than pushing a route, so Learn stays one screen.
class _TopicCard extends StatefulWidget {
  const _TopicCard({required this.card});

  final LearnCard card;

  @override
  State<_TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends State<_TopicCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Brand.space2),
      child: Material(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(Brand.radiusSurface),
        child: InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(Brand.radiusSurface),
          child: Container(
            padding: const EdgeInsets.all(Brand.space4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Brand.radiusSurface),
              border: Border.all(color: Brand.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.card.topic.toUpperCase(),
                            style: Brand.label.copyWith(
                              fontSize: 11,
                              color: Brand.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(widget.card.title, style: Brand.cardTitle),
                        ],
                      ),
                    ),
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: Brand.inkSoft,
                    ),
                  ],
                ),
                if (_open) ...[
                  const SizedBox(height: Brand.space2),
                  Text(widget.card.body, style: Brand.body),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplayRow extends StatelessWidget {
  const _ReplayRow({required this.onTap});

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
              const Icon(Icons.replay_rounded, color: Brand.primary, size: 22),
              const SizedBox(width: Brand.space3),
              const Expanded(
                child: Text('Replay introduction', style: Brand.cardTitle),
              ),
              const Icon(Icons.chevron_right_rounded, color: Brand.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}
