import 'package:flutter/material.dart';
import 'assessment_controller.dart';
import 'age_screen.dart';

class SexScreen extends StatelessWidget {
  final AssessmentController assessmentController;
  final VoidCallback onCancel;

  const SexScreen({
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
                        "So let's start. What is your biological sex?",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Biological sex affects the risk of certain health conditions. '
                        'Your response helps ensure an accurate assessment.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.black54,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      RadioGroup<String>(
                        groupValue: assessmentController.sex,
                        onChanged: (v) {
                          if (v != null) assessmentController.setSex(v);
                        },
                        child: Column(
                          children: [
                            _buildRadioOption('Male', 'male'),
                            _buildRadioOption('Female', 'female'),
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
                'Symptom assessment 5%',
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
          value: 0.05,
          backgroundColor: const Color(0xFFEEEEEE),
          color: _primary,
          minHeight: 3,
        ),
      ],
    );
  }

  Widget _buildRadioOption(String label, String value) {
    final isSelected = assessmentController.sex == value;
    return Container(
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
        value: value,
        title: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
        ),
        activeColor: _primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context) {
    final isEnabled = assessmentController.sex != null;
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
                        builder: (_) => AgeScreen(
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
