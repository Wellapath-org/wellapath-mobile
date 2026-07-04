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
        return 'Seek urgent care';
      case 'non_urgent':
        return 'Seek non-urgent care';
      case 'self_care':
        return 'Self-care recommended';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final conditionName = widget.condition['condition_name'] as String? ?? '';
    final urgency = widget.condition['urgency'] as String? ?? '';
    final explanation = widget.condition['explanation'] as String? ?? '';
    final color = _colorForUrgency(urgency);
    final careLabel = _careLabelForUrgency(urgency);

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
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFF3F4F6),
                child: Text(
                  '${widget.rank}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  conditionName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (urgency.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    urgency.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final maxBarWidth = constraints.maxWidth;
              final barWidth = maxBarWidth * widget.barFraction.clamp(0.0, 1.0);
              return Container(
                height: 6,
                width: maxBarWidth,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 6,
                    width: barWidth,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              );
            },
          ),
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 12),
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
          if (careLabel.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              careLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
