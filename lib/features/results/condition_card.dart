import 'package:flutter/material.dart';

class ConditionCard extends StatefulWidget {
  final Map<String, dynamic> condition;
  final int rank;
  final double barFraction;

  const ConditionCard({
    super.key,
    required this.condition,
    required this.rank,
    required this.barFraction,
  });

  @override
  State<ConditionCard> createState() => _ConditionCardState();
}

class _ConditionCardState extends State<ConditionCard> {
  bool _expanded = false;

  static const Map<String, Color> _urgencyColors = {
    'emergency': Color(0xFFDC2626),
    'urgent': Color(0xFFF59E0B),
    'non_urgent': Color(0xFF22C55E),
    'self_care': Color(0xFF22C55E),
  };

  static const Color _fallbackColor = Color(0xFF9CA3AF);

  Color _colorForUrgency(String urgency) =>
      _urgencyColors[urgency] ?? _fallbackColor;

  String _careLabelForUrgency(String urgency) {
    switch (urgency) {
      case 'emergency':
        return 'Seek emergency care';
      case 'urgent':
        return 'Seek medical advice';
      case 'non_urgent':
        return 'Seek non-urgent care';
      case 'self_care':
        return 'This can be managed at home';
      default:
        return '';
    }
  }

  /// Buckets [barFraction] (this condition's score relative to the top
  /// condition's score) into one of 4 discrete match-strength levels,
  /// matching the "Match Strength Key" shown in the Understanding Your
  /// Result explainer (Strong/Moderate/Fair/Low). No exact scoring
  /// thresholds were specified for this bucketing — these cut points are a
  /// reasonable first pass, not a clinical determination, and may need
  /// tuning once real distributions are reviewed.
  int _matchLevel(double fraction) {
    if (fraction >= 0.85) return 4;
    if (fraction >= 0.6) return 3;
    if (fraction >= 0.35) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final conditionName = widget.condition['condition_name'] as String? ?? '';
    final urgency = widget.condition['urgency'] as String? ?? '';
    final explanation = widget.condition['explanation'] as String? ?? '';
    final color = _colorForUrgency(urgency);
    final careLabel = _careLabelForUrgency(urgency);
    final matchLevel = _matchLevel(widget.barFraction);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${widget.rank}. $conditionName',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: MatchStrengthBar(level: matchLevel, color: color),
              ),
            ],
          ),
          if (careLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              careLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              explanation,
              maxLines: _expanded ? null : 2,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _expanded ? 'Show less' : 'Read More',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B4EFF),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The 4-segment discrete bar used both on each condition card and in the
/// "Understanding your result" Match Strength Key — [level] is 1-4
/// (Low/Fair/Moderate/Strong), with that many segments filled in [color]
/// and the rest shown as a light neutral track.
class MatchStrengthBar extends StatelessWidget {
  final int level;
  final Color color;

  const MatchStrengthBar({super.key, required this.level, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        final filled = index < level;
        return Container(
          margin: EdgeInsets.only(left: index == 0 ? 0 : 3),
          width: 14,
          height: 6,
          decoration: BoxDecoration(
            color: filled ? color : const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
