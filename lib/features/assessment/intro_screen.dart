import 'package:flutter/material.dart';
import 'assessment_controller.dart';
import 'sex_screen.dart';

class IntroScreen extends StatelessWidget {
  final AssessmentController assessmentController;
  final VoidCallback onCancel;

  const IntroScreen({
    super.key,
    required this.assessmentController,
    required this.onCancel,
  });

  static const Color _primary = Color(0xFF6B4EFF);

  /// Advances to the next step, recording that it was displayed.
  ///
  /// The step view is recorded at the transition rather than in the next
  /// screen's `initState` so that the stateless step screens stay stateless —
  /// converting them purely to host an analytics call would be a structural
  /// change for no product reason. The boundary is identical either way.
  void _goToNextStep(BuildContext context) {
    assessmentController.telemetrySession.recordStepView();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SexScreen(
          assessmentController: assessmentController,
          onCancel: onCancel,
        ),
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
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "Let's take a few minutes to answer questions about your symptoms. "
                      "Then we'll help you decide your next course of action",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 32),
                    _DisclaimerBox(),
                  ],
                ),
              ),
            ),
            _buildNextButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF6B4EFF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Symptom assessment 1%',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 22),
                onPressed: onCancel,
              ),
            ],
          ),
        ),
        LinearProgressIndicator(
          value: 0.01,
          backgroundColor: const Color(0xFFEEEEEE),
          color: _primary,
          minHeight: 3,
        ),
      ],
    );
  }

  Widget _buildNextButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => _goToNextStep(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Next',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _DisclaimerBox extends StatelessWidget {
  const _DisclaimerBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'WellaPath can help you assess your symptoms and will tell you '
              'if you need emergency care but it is not a substitute for emergency services.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
