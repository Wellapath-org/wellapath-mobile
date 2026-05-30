import 'package:flutter/material.dart';
import 'assessment_controller.dart';
import 'medical_conditions_screen.dart';

class AgeScreen extends StatelessWidget {
  final AssessmentController assessmentController;
  final VoidCallback onCancel;

  const AgeScreen({
    super.key,
    required this.assessmentController,
    required this.onCancel,
  });

  static const Color _primary = Color(0xFF6B4EFF);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: assessmentController,
      builder: (context, _) => Scaffold(
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
                    children: [
                      const Text(
                        'What is your age range?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Select one answer for each statement',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.black54,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // labels must exactly match AssessmentController._ageTokenMap keys
                      RadioGroup<String>(
                        groupValue: assessmentController.ageToken,
                        onChanged: (_) {},
                        child: Column(
                          children: [
                            _buildAgeOption('0–12', 'children_under_5'),
                            _buildAgeOption('13–17', 'children_school_age'),
                            _buildAgeOption('18–40', 'adults'),
                            _buildAgeOption('41–60', 'over_40'),
                            _buildAgeOption('60+', 'elderly'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _buildBottomButtons(context),
            ],
          ),
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
              const Text(
                'Symptom assessment 10%',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
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
          value: 0.10,
          backgroundColor: const Color(0xFFEEEEEE),
          color: _primary,
          minHeight: 3,
        ),
      ],
    );
  }

  // token is RadioListTile value; label is passed to setAgeRange so it must
  // match the key in AssessmentController._ageTokenMap exactly.
  Widget _buildAgeOption(String label, String token) {
    final isSelected = assessmentController.ageToken == token;
    return GestureDetector(
      onTap: () => assessmentController.setAgeRange(label),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? _primary : const Color(0xFFE0E0E0),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: RadioListTile<String>(
          value: token,
          title: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
          ),
          activeColor: _primary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context) {
    final isEnabled = assessmentController.ageToken != null;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primary,
                side: const BorderSide(color: _primary),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Back',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: isEnabled
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MedicalConditionsScreen(
                          assessmentController: assessmentController,
                          onCancel: onCancel,
                        ),
                      ),
                    )
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE0E0E0),
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
        ],
      ),
    );
  }
}
