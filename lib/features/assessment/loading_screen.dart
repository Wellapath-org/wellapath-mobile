import 'package:flutter/material.dart';
import '../../core/engine/engine_controller.dart';
import '../../core/engine/models/engine_input.dart';
import '../../core/storage/storage_service.dart';
import '../boot/boot_controller.dart';
import '../status/system_status_screen.dart';
import 'assessment_controller.dart';

class LoadingScreen extends StatefulWidget {
  final AssessmentController assessmentController;
  final VoidCallback onCancel;

  const LoadingScreen({
    super.key,
    required this.assessmentController,
    required this.onCancel,
  });

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  static const Color _primary = Color(0xFF6B4EFF);

  bool _step1Complete = false;
  bool _step2Complete = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _runAssessment();
  }

  Future<void> _runAssessment() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _step1Complete = true);

    try {
      final assessmentInput = widget.assessmentController.buildInput();
      final config = StorageService.getLastKnownConfig();

      if (config != null) {
        final rules =
            (config['rules'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final tokenDict = config['token_dictionary'] != null
            ? Map<String, dynamic>.from(config['token_dictionary'] as Map)
            : <String, dynamic>{};
        final kb =
            (config['knowledge_base'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        final meta = config['metadata'] != null
            ? Map<String, dynamic>.from(config['metadata'] as Map)
            : <String, dynamic>{};

        final engine = EngineController(
          rules: rules,
          tokenDictionary: tokenDict,
          knowledgeBase: kb,
          configMetadata: meta,
        );
        final engineInput = EngineInput(
          symptomTokens: assessmentInput.symptomTokens,
          candidateConditionIds: const [],
        );
        final output = engine.run(engineInput);
        debugPrint('Assessment complete — urgency: ${output.urgency}');
      } else {
        debugPrint('No config cached — engine skipped');
      }
    } catch (_) {
      // Generic log to avoid leaking PHI from exception messages
      debugPrint('Engine run failed — assessment incomplete');
      if (!mounted) return;
      setState(() => _hasError = true);
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _step2Complete = true);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const SystemStatusScreen(
          result: BootResult(status: BootStatus.success),
        ),
      ),
    );
  }

  void _retry() {
    setState(() {
      _step1Complete = false;
      _step2Complete = false;
      _hasError = false;
    });
    _runAssessment();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) return _buildErrorView(context);
    return _buildLoadingView();
  }

  Widget _buildLoadingView() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.radar, color: _primary, size: 40),
              ),
              const SizedBox(height: 28),
              const Text(
                'Just a moment...',
                style: TextStyle(fontSize: 15, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              const Text(
                'We are running your assessment right now!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  height: 1.3,
                ),
              ),
              const Spacer(),
              AnimatedOpacity(
                opacity: _step1Complete ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: _buildStep('Analyzing your submission', _step1Complete),
              ),
              const SizedBox(height: 16),
              AnimatedOpacity(
                opacity: _step2Complete ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: _buildStep('Preparing your result', _step2Complete),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(String label, bool isDone) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone ? _primary : Colors.transparent,
            border: Border.all(
              color: isDone ? _primary : Colors.grey[300]!,
              width: 2,
            ),
          ),
          child: isDone
              ? const Icon(Icons.check, color: Colors.white, size: 16)
              : null,
        ),
        const SizedBox(width: 14),
        Text(
          label,
          style: const TextStyle(fontSize: 15, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildErrorView(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 20),
                const Text(
                  'Something went wrong running your assessment.\nPlease try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _retry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Try again',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
