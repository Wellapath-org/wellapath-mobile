import 'package:flutter/material.dart';
import '../../core/constants/symptom_display_map.dart';

class SymptomSummaryWidget extends StatelessWidget {
  final List<String> symptomTokens;

  const SymptomSummaryWidget({super.key, required this.symptomTokens});

  String? _displayNameForToken(String token) {
    for (final entry in kSymptomDisplayMap.entries) {
      if (entry.value == token) return entry.key;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        title: const Text(
          'Symptom summary',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: symptomTokens.map((token) {
              final label = _displayNameForToken(token) ?? token;
              return Chip(
                label: Text(label, style: const TextStyle(fontSize: 13)),
                backgroundColor: const Color(0xFFF3F4F6),
                side: BorderSide.none,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
