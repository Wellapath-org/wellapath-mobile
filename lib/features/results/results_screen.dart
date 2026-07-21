import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/engine/models/engine_output.dart';
import '../assessment/assessment_controller.dart';
import '../locator/locator_screen.dart';
import 'condition_card.dart';
import 'symptom_summary_widget.dart';

class ResultsScreen extends StatelessWidget {
  final EngineOutput engineOutput;
  final AssessmentController assessmentController;

  const ResultsScreen({
    super.key,
    required this.engineOutput,
    required this.assessmentController,
  });

  static const Color _primary = Color(0xFF6B4EFF);
  static const Color _emergencyRed = Color(0xFFDC2626);

  static const Map<String, Color> _urgencyColors = {
    'emergency': Color(0xFFDC2626),
    'urgent': Color(0xFFF59E0B),
    'non_urgent': Color(0xFF22C55E),
    'self_care': Color(0xFF22C55E),
  };

  Future<void> _callEmergency() async {
    final Uri emergencyUri = Uri(scheme: 'tel', path: '112');
    await launchUrl(emergencyUri);
  }

  void _showFindCareSheet(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LocatorScreen(urgency: engineOutput.urgency),
      ),
    );
  }

  void _showHomeCareSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Home care advice coming soon. Rest, stay hydrated, '
                'and monitor your symptoms.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primary,
                    side: const BorderSide(color: _primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCloseConfirmationDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close your assessment result?'),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              assessmentController.clearAll();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _primary,
              side: const BorderSide(color: _primary),
            ),
            child: const Text('Yes, close'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('No, continue'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback onPressed,
    required bool primary,
    required Color color,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: primary
          ? ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
    );
  }

  Widget _buildCTAPair(BuildContext context) {
    switch (engineOutput.urgency) {
      case 'emergency':
        return Column(
          children: [
            _buildActionButton(
              label: 'Call Emergency',
              onPressed: _callEmergency,
              primary: true,
              color: _emergencyRed,
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              label: 'Find Nearby Care',
              onPressed: () => _showFindCareSheet(context),
              primary: false,
              color: _primary,
            ),
          ],
        );
      case 'urgent':
      case 'non_urgent':
        return Column(
          children: [
            _buildActionButton(
              label: 'Find Nearby Care',
              onPressed: () => _showFindCareSheet(context),
              primary: true,
              color: _primary,
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              label: 'Call Emergency',
              onPressed: _callEmergency,
              primary: false,
              color: _emergencyRed,
            ),
          ],
        );
      case 'self_care':
        return Column(
          children: [
            _buildActionButton(
              label: 'Home Care Advice',
              onPressed: () => _showHomeCareSheet(context),
              primary: true,
              color: _primary,
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              label: 'Find Nearby Care',
              onPressed: () => _showFindCareSheet(context),
              primary: false,
              color: _primary,
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 22),
            onPressed: () => _showCloseConfirmationDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildUrgencyBanner() {
    final color = _urgencyColors[engineOutput.urgency] ?? _primary;
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            engineOutput.urgency.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            engineOutput.careInstruction,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildPossibleConditions() {
    final topCauses = engineOutput.topCauses;
    if (topCauses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(
          'No specific conditions identified',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
      );
    }

    final maxScore = (topCauses.first['score'] as num?)?.toDouble() ?? 0.0;
    final explanationText = engineOutput.explanationPoints.join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Text(
              'Possible Conditions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.info_outline, size: 18, color: Colors.black45),
          ],
        ),
        const SizedBox(height: 16),
        ...topCauses.asMap().entries.map((entry) {
          final index = entry.key;
          final cause = entry.value;
          final score = (cause['score'] as num?)?.toDouble() ?? 0.0;
          final barFraction = maxScore > 0 ? score / maxScore : 0.0;
          final enriched = <String, dynamic>{
            ...cause,
            'urgency': engineOutput.urgency,
            'explanation': explanationText,
          };
          return ConditionCard(
            condition: enriched,
            rank: index + 1,
            barFraction: barFraction,
          );
        }),
      ],
    );
  }

  Widget _buildDisclaimer() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        'This is a symptom assessment, not a diagnosis. Your symptoms may '
        'be caused by a condition not mentioned here.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Colors.black54),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildUrgencyBanner(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      child: _buildCTAPair(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildPossibleConditions(),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SymptomSummaryWidget(
                        symptomTokens: assessmentController.symptomTokens,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDisclaimer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                      child: _buildCTAPair(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
