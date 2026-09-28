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
          // No opening-hours claim is rendered, deliberately.
          //
          // This card used to show a green "Open now" whenever `opening_hours`
          // was non-null. It never read the value: any string at all produced
          // "Open now", at any hour, on any day. It has never been visible in
          // production because `opening_hours` is null on all 5,344 records in
          // the shipped artifact, so this removes nothing a user has seen.
          //
          // It is removed rather than corrected because correcting it needs
          // things the app does not have: structured hours, a timezone, and a
          // notion of public holidays. Until those exist and the hours are
          // verified, the honest number of opening claims this card can make
          // is zero. Telling someone a clinic is open when it is closed is a
          // wasted journey by a person who is unwell.
          //
          // Do not reintroduce this by mapping a status field from a new data
          // source into `opening_hours`. GRID3's `functional` column is a
          // dataset-quality flag, not opening hours, and its own publisher
          // warns that abandoned facilities may be included.
          if (distanceKm != null) ...[
            const SizedBox(height: 6),
            Text(
              '${distanceKm.toStringAsFixed(1)} km away',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _primary,
              ),
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
