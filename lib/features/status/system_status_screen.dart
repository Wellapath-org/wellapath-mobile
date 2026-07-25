import 'package:flutter/material.dart';
import '../../shared/widgets/confirmation_dialog.dart';
import '../assessment/assessment_controller.dart';
import '../assessment/intro_screen.dart';
import '../boot/boot_controller.dart';

class SystemStatusScreen extends StatelessWidget {
  final BootResult result;

  const SystemStatusScreen({super.key, required this.result});

  static const Color _primary = Color(0xFF6B4EFF);

  void _startAssessment(BuildContext context) {
    final controller = AssessmentController();
    final myRoute = ModalRoute.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IntroScreen(
          assessmentController: controller,
          onCancel: () => _confirmCancelAssessment(context, myRoute),
        ),
      ),
    );
  }

  Future<void> _confirmCancelAssessment(
    BuildContext context,
    ModalRoute<void>? myRoute,
  ) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Cancel Assessment',
      message: 'Are you sure you want to cancel your symptom assessment?',
      cancelLabel: 'No, continue',
      confirmLabel: 'Yes, cancel',
    );
    if (confirmed && context.mounted) {
      Navigator.of(context).popUntil((r) => r == myRoute || r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WellaPath')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusChip(),
            if (result.config?['version'] != null) ...[
              const SizedBox(height: 16),
              Text('Config version: ${result.config!['version']}'),
            ],
            if (result.errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                result.errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _startAssessment(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Start Symptom Assessment',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip() {
    switch (result.status) {
      case BootStatus.success:
        return const Chip(
          label: Text('Online'),
          backgroundColor: Colors.green,
          labelStyle: TextStyle(color: Colors.white),
        );
      case BootStatus.offline:
        return const Chip(
          label: Text('Offline — using cached config'),
          backgroundColor: Colors.orange,
          labelStyle: TextStyle(color: Colors.white),
        );
      case BootStatus.failed:
        return const Chip(
          label: Text('Failed to load'),
          backgroundColor: Colors.red,
          labelStyle: TextStyle(color: Colors.white),
        );
    }
  }
}
