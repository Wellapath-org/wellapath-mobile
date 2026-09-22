import 'package:flutter/material.dart';
// LOCAL-VERIFICATION-ONLY import (build 214) — leaves with this branch.
import '../../core/crash/crash_verification_gate.dart';
import '../../shared/widgets/confirmation_dialog.dart';
import '../assessment/assessment_controller.dart';
import '../assessment/intro_screen.dart';
import '../boot/boot_controller.dart';

class SystemStatusScreen extends StatelessWidget {
  final BootResult result;

  /// Test seam only: the verification gate is compile-time, so widget tests
  /// cannot flip it. `null` (every production construction) reads
  /// [CrashVerificationGate.enabled].
  final bool? verificationOverride;

  const SystemStatusScreen({
    super.key,
    required this.result,
    this.verificationOverride,
  });

  /// LOCAL-VERIFICATION-ONLY (build 214): whether the synthetic-error
  /// button renders.
  bool get _verificationEnabled =>
      verificationOverride ?? CrashVerificationGate.enabled;

  /// LOCAL-VERIFICATION-ONLY (build 214): the confirmation dialog before
  /// the one permitted synthetic event. Only the confirm button throws —
  /// synchronously, inside its own gesture callback, so the report arrives
  /// through FlutterError.onError with crash_source=flutter_framework.
  Future<void> _confirmSyntheticError(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Send synthetic test error?'),
        content: const Text(
          'This sends exactly one synthetic engineering error to the '
          'crash-reporting pipeline for the build-214 internal '
          'verification. It contains no real personal or health '
          'information.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // The one permitted synthetic event. The word 'crash' is
              // expected to arrive as '[redacted]' (the documented
              // rash-stem over-redaction), and StateError.toString()
              // prefixes 'Bad state: ' — the audited stored message is
              // exactly: Bad state: synthetic [redacted] verification 214
              throw StateError('synthetic crash verification 214');
            },
            child: const Text('Send test error'),
          ),
        ],
      ),
    );
  }

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
            // LOCAL-VERIFICATION-ONLY (build 214): visible, labelled, and
            // rendered only when the four-define gate passes. Every other
            // build emits nothing here.
            if (_verificationEnabled) ...[
              const SizedBox(height: 16),
              Text(
                'Build ${const String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0')}'
                '+${const String.fromEnvironment('APP_BUILD', defaultValue: '0')}',
                style: const TextStyle(color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _confirmSyntheticError(context),
                icon: const Icon(
                  Icons.science_outlined,
                  color: Color(0xFF8A5B00),
                ),
                label: const Text(
                  'Send synthetic Sentry test error',
                  style: TextStyle(
                    color: Color(0xFF8A5B00),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFB4780A)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ],
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
