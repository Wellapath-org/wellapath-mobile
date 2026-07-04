import 'package:flutter/material.dart';

class ConditionCard extends StatefulWidget {
  final Map<String, dynamic> condition;
  final int rank;

  const ConditionCard({super.key, required this.condition, required this.rank});

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
  static const Color _inactiveDashColor = Color(0xFFE5E7EB);
  static const int _dashCount = 4;

  Color _colorForUrgency(String urgency) =>
      _urgencyColors[urgency] ?? _fallbackColor;

  String _careLabelForUrgency(String urgency) {
    switch (urgency) {
      case 'emergency':
        return 'Seek emergency care';
      case 'urgent':
        return 'Seek medical advice';
      case 'non_urgent':
      case 'self_care':
        return 'This can be managed at home';
      default:
        return '';
    }
  }

  int get _coloredDashCount => switch (widget.rank) {
    1 => 4,
    2 => 3,
    3 => 2,
    _ => 1,
  };

  Widget _buildDashes(Color color) {
    final coloredCount = _coloredDashCount;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_dashCount, (index) {
        final isColored = index < coloredCount;
        return Container(
          width: 14,
          height: 4,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: isColored ? color : _inactiveDashColor,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
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
              _buildDashes(color),
            ],
          ),
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
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded ? 'Show less' : 'Read More',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B4EFF),
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 18,
                        color: const Color(0xFF6B4EFF),
                      ),
                    ],
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
