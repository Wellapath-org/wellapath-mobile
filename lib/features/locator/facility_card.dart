import 'package:flutter/material.dart';

class FacilityCard extends StatelessWidget {
  final Map<String, dynamic> facility;
  final VoidCallback onDirectionsTap;
  final VoidCallback? onCallTap;

  const FacilityCard({
    super.key,
    required this.facility,
    required this.onDirectionsTap,
    this.onCallTap,
  });

  static const Color _primary = Color(0xFF6B4EFF);

  @override
  Widget build(BuildContext context) {
    final name = facility['name'] as String? ?? '';
    final cityArea = facility['city_area'] as String? ?? '';
    final state = facility['state'] as String? ?? '';
    final address = [
      cityArea,
      state,
    ].where((part) => part.isNotEmpty).join(', ');
    final distanceKm = facility['distance_km'] as double?;
    final openingHours = facility['opening_hours'];
    final phone = facility['phone'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              address,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ],
          if (distanceKm != null || openingHours != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (distanceKm != null)
                  Text(
                    '${distanceKm.toStringAsFixed(1)} km away',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _primary,
                    ),
                  ),
                if (distanceKm != null && openingHours != null)
                  const Text(
                    '  •  ',
                    style: TextStyle(fontSize: 13, color: Colors.black38),
                  ),
                if (openingHours != null)
                  const Text(
                    'Open now',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF22C55E),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (phone != null) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onCallTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary.withValues(alpha: 0.1),
                      foregroundColor: _primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.call, size: 16),
                    label: const Text('Call'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onDirectionsTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A2E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.directions, size: 16),
                  label: const Text('Directions'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
