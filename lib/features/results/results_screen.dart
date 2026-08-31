import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/engine/models/engine_output.dart';
import '../../core/telemetry/contract/telemetry_event.dart';
import '../../core/telemetry/telemetry.dart';
import '../../shared/widgets/confirmation_dialog.dart';
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

  // Purely presentational — matches the wording in the Figma design. The
  // actual clinical content (careInstruction, explanationPoints, scoring)
  // still comes entirely from the engine; these are just the UI labels
  // wrapped around it, not new clinical logic.
  static const Map<String, String> _urgencyLabels = {
    'emergency': 'EMERGENCY',
    'urgent': 'URGENT',
    'non_urgent': 'NON-URGENT',
    'self_care': 'NON-URGENT',
  };

  static const Map<String, String> _headlines = {
    'emergency': 'Seek medical care immediately!',
    'urgent': 'You should consult a doctor',
    'non_urgent': 'Home self-care may be enough',
    'self_care': 'Home self-care may be enough',
  };

  static const Map<String, IconData> _urgencyIcons = {
    'emergency': Icons.emergency_rounded,
    'urgent': Icons.medical_services_rounded,
    'non_urgent': Icons.home_rounded,
    'self_care': Icons.home_rounded,
  };

  Future<void> _callEmergency() async {
    // Action type only. No session ID (the contract rejects one here), no
    // urgency, no red flag, no condition, no triggering symptom.
    Telemetry.capture(
      const EmergencyActionEvent(
        actionType: EmergencyActionType.callEmergencyNumber,
      ),
    );
    final Uri emergencyUri = Uri(scheme: 'tel', path: '112');
    await launchUrl(emergencyUri);
  }

  void _showFindCareSheet(BuildContext context) {
    // `open_nearest_facility` is an emergency-surface action in the contract's
    // vocabulary. `engineOutput.urgency` drives which facility types the
    // locator returns and is deliberately not recorded.
    Telemetry.capture(
      const EmergencyActionEvent(
        actionType: EmergencyActionType.openNearestFacility,
      ),
    );
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

  Future<void> _showCloseConfirmationDialog(BuildContext context) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Close Assessment Result',
      message: 'Are you sure you want to leave your symptom assessment result?',
      cancelLabel: 'No, continue',
      confirmLabel: 'Yes, close',
    );
    if (confirmed && context.mounted) {
      assessmentController.clearAll();
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _showMatchStrengthExplainer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          // The sheet's content can be taller than the screen (4 match
          // strength rows + explanatory text) — isScrollControlled only
          // lets the sheet itself grow, it doesn't make its content
          // scrollable, so without this the bottom rows overflow.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Understanding your result',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Note that',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _explainerBullet(
                  'Match strength shows how well the symptoms you entered '
                  "match the symptoms of each condition. It's not the "
                  'likelihood of having the condition.',
                ),
                _explainerBullet(
                  'Your symptoms may be consistent with one or more of these '
                  'conditions. This is not a diagnosis. Please seek '
                  'professional care to confirm.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Match Strength Key',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _matchStrengthKeyRow(
                  level: 4,
                  label: 'Strong Match',
                  description:
                      'The symptoms you entered are a strong match with the '
                      'symptoms of this condition.',
                ),
                _matchStrengthKeyRow(
                  level: 3,
                  label: 'Moderate Match',
                  description:
                      'The symptoms you entered are a moderate match with '
                      'the symptoms of this condition.',
                ),
                _matchStrengthKeyRow(
                  level: 2,
                  label: 'Fair Evidence',
                  description:
                      'The symptoms you entered are a fair match with the '
                      'symptoms of this condition.',
                ),
                _matchStrengthKeyRow(
                  level: 1,
                  label: 'Low Evidence',
                  description:
                      'The symptoms you entered are a low match with the '
                      'symptoms of this condition.',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primary,
                      side: const BorderSide(color: _primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Okay'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _explainerBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7, right: 10),
            child: CircleAvatar(radius: 3, backgroundColor: Colors.black54),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _matchStrengthKeyRow({
    required int level,
    required String label,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MatchStrengthBar(level: level, color: _primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
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
              label: 'Find Care',
              onPressed: () => _showFindCareSheet(context),
              primary: false,
              color: _primary,
            ),
          ],
        );
      case 'urgent':
        return Column(
          children: [
            _buildActionButton(
              label: 'Find Care',
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
      case 'non_urgent':
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
              label: 'Find Care',
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
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Your assessment result',
              style: TextStyle(
                fontSize: 12,
                color: _primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 22),
            onPressed: () => _showCloseConfirmationDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildIllustrationBanner() {
    final color = _urgencyColors[engineOutput.urgency] ?? _primary;
    final icon = _urgencyIcons[engineOutput.urgency] ?? Icons.info_outline;
    return ClipRect(
      child: Container(
        height: 150,
        width: double.infinity,
        color: color,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(top: -36, left: -24, child: _decorativeCircle(96)),
            Positioned(bottom: -50, right: -16, child: _decorativeCircle(130)),
            Positioned(top: 12, right: 56, child: _decorativeCircle(36)),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 34),
            ),
          ],
        ),
      ),
    );
  }

  Widget _decorativeCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
      ),
    );
  }

  Widget _buildResultHeadline() {
    final color = _urgencyColors[engineOutput.urgency] ?? _primary;
    final label = _urgencyLabels[engineOutput.urgency] ?? '';
    final headline = _headlines[engineOutput.urgency] ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.4,
              ),
            ),
          const SizedBox(height: 4),
          if (headline.isNotEmpty)
            Text(
              headline,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            engineOutput.careInstruction,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPossibleConditions(BuildContext context) {
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

    // Fallback only. Each cause carries its own 'explanation' from its own
    // condition's explanation_template; explanationPoints holds the top
    // condition's alone, so using it per card labelled every condition with
    // the top one's description.
    final fallbackExplanation = engineOutput.explanationPoints.join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Possible Conditions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _showMatchStrengthExplainer(context),
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Colors.black45,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...topCauses.asMap().entries.map((entry) {
          final index = entry.key;
          final cause = entry.value;
          final score = (cause['score'] as num?)?.toDouble() ?? 0.0;
          final barFraction = maxScore > 0 ? score / maxScore : 0.0;
          final causeExplanation = cause['explanation'] as String?;
          final enriched = <String, dynamic>{
            ...cause,
            'urgency': engineOutput.urgency,
            'explanation':
                (causeExplanation == null || causeExplanation.isEmpty)
                ? fallbackExplanation
                : causeExplanation,
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

  Widget _buildSymptomSummary() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SymptomSummaryWidget(
        symptomTokens: assessmentController.symptomTokens,
      ),
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
                    _buildIllustrationBanner(),
                    _buildResultHeadline(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      child: _buildCTAPair(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildPossibleConditions(context),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildSymptomSummary(),
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
