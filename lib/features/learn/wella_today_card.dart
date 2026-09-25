/// "Wella Today" — one short, useful thing, chosen by the device date.
///
/// A reason to open the app on a day you are well, without any of the
/// machinery that usually comes with one: no notification permission, no
/// account, no streak, no score, no reading history, no network call. The
/// card is picked from content bundled in the binary
/// (`LearnContent.cards`), so it works with the radio off.
///
/// **Show me another** walks the deck in memory. The step resets when the
/// widget is disposed, so nothing about what you read survives the screen —
/// there is deliberately nothing to store and nothing to profile.
library;

import 'package:flutter/material.dart';

import '../../shared/theme/brand.dart';
import '../../shared/widgets/wella.dart';
import 'learn_content.dart';

class WellaTodayCard extends StatefulWidget {
  const WellaTodayCard({super.key, this.today});

  /// Injectable for tests; production uses the device date.
  final DateTime? today;

  @override
  State<WellaTodayCard> createState() => _WellaTodayCardState();
}

class _WellaTodayCardState extends State<WellaTodayCard> {
  /// In-memory only — see the library comment.
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final LearnCard card = LearnContent.forDate(
      widget.today ?? DateTime.now(),
      step: _step,
    );

    return Container(
      padding: const EdgeInsets.all(Brand.space4),
      decoration: BoxDecoration(
        color: Brand.surfaceMuted,
        borderRadius: BorderRadius.circular(Brand.radiusSurface),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Wella(size: 36, semanticLabel: 'Wella'),
              const SizedBox(width: Brand.space2),
              const Expanded(child: Text('WELLA TODAY', style: Brand.label)),
            ],
          ),
          const SizedBox(height: Brand.space3),
          // The topic sits above the title on its own line. Alongside the
          // eyebrow it overflowed a 360dp row by 180px once a longer topic
          // came round in the rotation.
          Text(
            card.topic.toUpperCase(),
            style: Brand.label.copyWith(fontSize: 11, color: Brand.primary),
          ),
          const SizedBox(height: Brand.space1),
          Text(card.title, style: Brand.cardTitle),
          const SizedBox(height: Brand.space1),
          Text(card.body, style: Brand.body),
          const SizedBox(height: Brand.space2),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _step += 1),
              style: TextButton.styleFrom(
                foregroundColor: Brand.primary,
                minimumSize: const Size(0, Brand.minTapTarget),
                padding: const EdgeInsets.symmetric(horizontal: Brand.space2),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'Show me another',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
