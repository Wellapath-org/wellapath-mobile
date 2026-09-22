import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/crash/crash_pipeline_diagnostic.dart';
import '../../core/crash/crash_transport_probe.dart';
import '../../core/crash/crash_verification_gate.dart';
import '../../shared/widgets/confirmation_dialog.dart';
import '../assessment/assessment_controller.dart';
import '../assessment/intro_screen.dart';
import '../boot/boot_controller.dart';

class SystemStatusScreen extends StatelessWidget {
  final BootResult result;

  /// Test-only override for widget tests proving the synthetic-crash trigger
  /// is unavailable outside the gated 212 verification build. `null` (every
  /// production call site) defers to [CrashVerificationGate.enabled].
  final bool? crashVerificationTriggerEnabled;

  /// Test-only override for the pipeline-diagnostic panel. `null` (every
  /// production call site) defers to [CrashPipelineDiagnostic.isEnabled].
  final bool? crashPipelineDiagnosticEnabled;

  const SystemStatusScreen({
    super.key,
    required this.result,
    this.crashVerificationTriggerEnabled,
    this.crashPipelineDiagnosticEnabled,
  });

  static const Color _primary = Color(0xFF6B4EFF);

  bool get _verificationEnabled =>
      crashVerificationTriggerEnabled ?? CrashVerificationGate.enabled;

  /// Confirmation for the 212 synthetic error (docs/CRASH_VERIFICATION_212.md
  /// §3). Only the confirmed 'Send test error' action throws, and it throws
  /// synchronously inside the button's gesture callback so the error reaches
  /// `FlutterError.onError` and flows through the CrashReporter boundary
  /// exactly like a real framework error. The `StateError` message survives
  /// the sanitiser untouched, by design, as proof the pipeline preserves what
  /// it is allowed to preserve.
  void _confirmSyntheticError(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send synthetic test error?'),
        content: const Text(
          'This sends exactly one synthetic engineering error to the '
          'crash-reporting pipeline for the build-212 internal verification. '
          'It contains no real personal or health information.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              throw StateError('synthetic crash verification 212');
            },
            child: const Text('Send test error'),
          ),
        ],
      ),
    );
  }

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
            const SizedBox(height: 16),
            const _BuildRow(),
            // The 212 synthetic-error control: rendered ONLY when the
            // four-define CrashVerificationGate passes. Every other build
            // emits nothing here — no placeholder, gesture or semantics node.
            if (_verificationEnabled) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _confirmSyntheticError(context),
                icon: const Icon(Icons.science_outlined, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB45309),
                  side: const BorderSide(color: Color(0xFFB45309)),
                ),
                label: const Text('Send synthetic Sentry test error'),
              ),
            ],
            // Rendered ONLY in the five-define no-network diagnostic build:
            // closed-vocabulary stage names and a numeric item count, nothing
            // else. Every other build emits nothing here.
            if (crashPipelineDiagnosticEnabled ??
                CrashPipelineDiagnostic.isEnabled) ...[
              const SizedBox(height: 16),
              const _PipelineDiagnosticPanel(),
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

/// LOCAL-VERIFICATION-ONLY: live view of [CrashPipelineDiagnostic.stages].
/// Renders closed-vocabulary stage names only — the recorder itself refuses
/// anything outside its vocabulary, so nothing sensitive can appear here.
class _PipelineDiagnosticPanel extends StatelessWidget {
  const _PipelineDiagnosticPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF9CA3AF)),
      ),
      child: ValueListenableBuilder<List<String>>(
        valueListenable: CrashPipelineDiagnostic.stages,
        builder: (context, stages, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pipeline diagnostic — no-network build',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (stages.isEmpty)
                const Text(
                  '(no stages recorded yet)',
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                )
              else
                for (final stage in stages)
                  Text(
                    stage,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
              const SizedBox(height: 8),
              // One event-free empty-body POST over the SDK-identical HTTP
              // stack; CrashTransportProbe enforces at most one request.
              OutlinedButton(
                onPressed: () => unawaited(CrashTransportProbe.run()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF374151),
                  side: const BorderSide(color: Color(0xFF9CA3AF)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
                child: const Text(
                  'Run transport probe (no event)',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Display-only build-identity row. Carries no gesture handler: the 212
/// synthetic-error control is the explicit gated button above, never a hidden
/// interaction (docs/CRASH_VERIFICATION_212.md §3).
class _BuildRow extends StatelessWidget {
  const _BuildRow();

  static const String _version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );
  static const String _build = String.fromEnvironment(
    'APP_BUILD',
    defaultValue: '0',
  );

  @override
  Widget build(BuildContext context) {
    return Text(
      'Build $_version+$_build',
      style: const TextStyle(color: Colors.grey, fontSize: 12),
    );
  }
}
