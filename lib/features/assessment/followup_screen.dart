import 'package:flutter/material.dart';
import '../../core/constants/symptom_display_map.dart';
import 'assessment_controller.dart';
import 'loading_screen.dart';

class FollowupScreen extends StatefulWidget {
  final AssessmentController assessmentController;
  final VoidCallback onCancel;
  final String primarySymptomLabel;

  const FollowupScreen({
    super.key,
    required this.assessmentController,
    required this.onCancel,
    required this.primarySymptomLabel,
  });

  @override
  State<FollowupScreen> createState() => _FollowupScreenState();
}

class _FollowupScreenState extends State<FollowupScreen> {
  static const Color _primary = Color(0xFF6B4EFF);

  double _sliderValue = 0.0;
  String? _durationSelection;
  final Set<String> _additionalSelected = {};

  static const List<String> _additionalSymptoms = [
    'Fatigue',
    'Feeling sick or queasy',
    'Fever',
    'Vomiting',
    'Dizziness',
    'Muscle pain',
  ];

  static const Map<String, String> _durationTokens = {
    'Less than 3 days': 'days_1_3',
    '3 to 7 days': 'days_3_7',
    '8 to 14 days': 'days_7_plus',
    'More than 14 days': 'weeks_2_plus',
  };

  void _onSliderChanged(double value) {
    setState(() => _sliderValue = value);
    if (value <= 0.25) {
      widget.assessmentController.setSeverityToken('mild');
    } else if (value <= 0.5) {
      widget.assessmentController.setSeverityToken('moderate');
    } else if (value <= 0.75) {
      widget.assessmentController.setSeverityToken('severe');
    } else {
      widget.assessmentController.setSeverityToken('very_severe');
    }
  }

  void _onDurationChanged(String? token) {
    if (token == null) return;
    setState(() => _durationSelection = token);
    widget.assessmentController.setDurationToken(token);
  }

  void _onAdditionalToggled(String displayName, bool? checked) {
    final token = kSymptomDisplayMap[displayName];
    if (token == null) return;
    if (checked == true) {
      widget.assessmentController.addSymptomToken(token);
      setState(() => _additionalSelected.add(displayName));
    } else {
      widget.assessmentController.removeSymptomToken(token);
      setState(() => _additionalSelected.remove(displayName));
    }
  }

  void _onNext(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LoadingScreen(
          assessmentController: widget.assessmentController,
          onCancel: widget.onCancel,
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
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSeveritySection(),
                    const SizedBox(height: 36),
                    _buildDurationSection(),
                    const SizedBox(height: 36),
                    _buildAdditionalSymptomsSection(),
                    const SizedBox(height: 16),
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
                'Symptom assessment 12%',
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
          value: 0.12,
          backgroundColor: const Color(0xFFEEEEEE),
          color: _primary,
          minHeight: 3,
        ),
      ],
    );
  }

  Widget _buildSeveritySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How strong is the ${widget.primarySymptomLabel}?',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 20),
        Slider(
          value: _sliderValue,
          onChanged: _onSliderChanged,
          activeColor: _primary,
          inactiveColor: const Color(0xFFE0E0E0),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Mild',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              Text(
                'Moderate',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              Text(
                'Severe',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              Text(
                'Unbearable',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDurationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How long have you had the symptoms',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        RadioGroup<String>(
          groupValue: _durationSelection,
          onChanged: _onDurationChanged,
          child: Column(
            children: _durationTokens.entries.map((entry) {
              final isSelected = _durationSelection == entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected ? _primary : const Color(0xFFE0E0E0),
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: RadioListTile<String>(
                  value: entry.value,
                  title: Text(
                    entry.key,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  activeColor: _primary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAdditionalSymptomsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Do you have any of the following symptoms',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        ..._additionalSymptoms.map((name) {
          return CheckboxListTile(
            title: Text(name, style: const TextStyle(fontSize: 15)),
            value: _additionalSelected.contains(name),
            onChanged: (v) => _onAdditionalToggled(name, v),
            activeColor: _primary,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            visualDensity: const VisualDensity(vertical: -2),
          );
        }),
      ],
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
