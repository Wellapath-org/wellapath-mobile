import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/engine/models/engine_output.dart';
import '../assessment/assessment_controller.dart';
import '../locator/locator_screen.dart';

class RedFlagInterruptScreen extends StatefulWidget {
  final EngineOutput engineOutput;
  final AssessmentController assessmentController;

  const RedFlagInterruptScreen({
    super.key,
    required this.engineOutput,
    required this.assessmentController,
  });

  @override
  State<RedFlagInterruptScreen> createState() => _RedFlagInterruptScreenState();
}

class _RedFlagInterruptScreenState extends State<RedFlagInterruptScreen> {
  static const Color _primary = Color(0xFF6B4EFF);
  static const Color _emergencyRed = Color(0xFFDC2626);

  void _onPopInvoked(bool didPop, void result) {
    if (didPop) return;
    _showLeaveConfirmationDialog();
  }

  Future<void> _showLeaveConfirmationDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Are you sure you want to leave this screen?'),
        content: const Text('You have been advised to seek emergency care.'),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              widget.assessmentController.clearAll();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _primary,
              side: const BorderSide(color: _primary),
            ),
            child: const Text('Leave'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Stay'),
          ),
        ],
      ),
    );
  }

  Future<void> _callEmergency() async {
    final Uri emergencyUri = Uri(scheme: 'tel', path: '112');
    await launchUrl(emergencyUri);
  }

  void _showFindCareSheet() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LocatorScreen(urgency: widget.engineOutput.urgency),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _buildBanner(),
              _buildExplanationCard(),
              _buildCTAs(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _buildPossibleConditions(),
                ),
              ),
              _buildDisclaimer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      width: double.infinity,
      color: _emergencyRed,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EMERGENCY',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Seek medical care immediately',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildExplanationCard() {
    final ruleName = widget.engineOutput.matchedRuleName;
    final text = ruleName != null
        ? '$ruleName — this is a universal danger sign'
        : 'A critical danger sign was detected';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: _emergencyRed, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, color: Colors.black87),
      ),
    );
  }

  Widget _buildCTAs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _callEmergency,
              style: ElevatedButton.styleFrom(
                backgroundColor: _emergencyRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Call Emergency',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton(
              onPressed: _showFindCareSheet,
              style: OutlinedButton.styleFrom(
                foregroundColor: _primary,
                side: const BorderSide(color: _primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Find Nearby Care',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPossibleConditions() {
    final topCauses = widget.engineOutput.topCauses;
    if (topCauses.isEmpty) return const SizedBox.shrink();

    final explanationPoints = widget.engineOutput.explanationPoints;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Possible Conditions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        if (explanationPoints.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...explanationPoints.map(
            (point) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                point,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        ...topCauses.map((cause) {
          final conditionName = cause['condition_name'] as String? ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conditionName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Seek emergency care',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _emergencyRed,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDisclaimer() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Text(
        'This is not a diagnosis. Please seek immediate professional '
        'care. Do not delay.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Colors.black54),
      ),
    );
  }
}
