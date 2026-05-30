import 'package:flutter/material.dart';
import 'assessment_controller.dart';
import 'body_area_screen.dart';
import 'pregnancy_screen.dart';

class MedicalConditionsScreen extends StatefulWidget {
  final AssessmentController assessmentController;
  final VoidCallback onCancel;

  const MedicalConditionsScreen({
    super.key,
    required this.assessmentController,
    required this.onCancel,
  });

  @override
  State<MedicalConditionsScreen> createState() =>
      _MedicalConditionsScreenState();
}

class _MedicalConditionsScreenState extends State<MedicalConditionsScreen> {
  static const Color _primary = Color(0xFF6B4EFF);

  static const List<String> _conditionKeys = [
    'Diabetes',
    'Smoking',
    'Hypertension',
    'Allergy history',
  ];

  static const Map<String, String> _questionText = {
    'Diabetes': 'Do you have diabetes?',
    'Smoking': 'Do you smoke?',
    'Hypertension': 'Do you have hypertension?',
    'Allergy history':
        'I, or my parents, siblings or grandparents have an allergic disease '
        'e.g asthma, or food allergy.',
  };

  final Map<String, String?> _selections = {
    'Diabetes': null,
    'Smoking': null,
    'Hypertension': null,
    'Allergy history': null,
  };

  void _onOptionChanged(String conditionKey, String value) {
    setState(() => _selections[conditionKey] = value);
    widget.assessmentController.setMedicalCondition(
      conditionKey,
      value == 'yes',
    );
  }

  void _onNext(BuildContext context) {
    if (widget.assessmentController.shouldShowPregnancyScreen) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PregnancyScreen(
            assessmentController: widget.assessmentController,
            onCancel: widget.onCancel,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BodyAreaScreen(
            assessmentController: widget.assessmentController,
            onCancel: widget.onCancel,
          ),
        ),
      );
    }
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
                  children: [
                    const Text(
                      'How does each of these statements relate to you?',
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
                    for (final key in _conditionKeys)
                      _buildConditionQuestion(key),
                  ],
                ),
              ),
            ),
            _buildBottomButtons(context),
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
              const Text(
                'Symptom assessment 15%',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 22),
                onPressed: widget.onCancel,
              ),
            ],
          ),
        ),
        LinearProgressIndicator(
          value: 0.15,
          backgroundColor: const Color(0xFFEEEEEE),
          color: _primary,
          minHeight: 3,
        ),
      ],
    );
  }

  Widget _buildConditionQuestion(String conditionKey) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _questionText[conditionKey]!,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSmallRadio('Yes', 'yes', conditionKey),
              const SizedBox(width: 20),
              _buildSmallRadio('No', 'no', conditionKey),
              const SizedBox(width: 20),
              _buildSmallRadio("Don't know", 'dont_know', conditionKey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallRadio(String label, String value, String conditionKey) {
    final isSelected = _selections[conditionKey] == value;
    return GestureDetector(
      onTap: () => _onOptionChanged(conditionKey, value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? _primary : const Color(0xFFBDBDBD),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: isSelected
                ? Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context) {
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
              onPressed: () => _onNext(context),
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
        ],
      ),
    );
  }
}
