import 'package:flutter/material.dart';
import '../../core/engine/engine_controller.dart';
import '../../core/engine/models/engine_output.dart';
import '../../core/network/staged_artifact_loader.dart';
import '../../core/storage/storage_service.dart';
import '../boot/boot_controller.dart';
import '../results/red_flag_interrupt_screen.dart';
import '../results/results_screen.dart';
import '../status/system_status_screen.dart';
import 'assessment_controller.dart';
import 'engine_input_builder.dart';
import 'symptom_selection_screen.dart';

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
  bool _isFirstLaunchOffline = false;
  bool _noSymptomsSelected = false;

  @override
  void initState() {
    super.initState();
    _runAssessment();
  }

  ArtifactSpec? _specFor(
    Map<String, dynamic> artifacts,
    String key,
    String cacheKey,
  ) {
    final entry = artifacts[key] as Map?;
    final url = entry?['url'] as String?;
    if (url == null) return null;
    return ArtifactSpec(
      url: url,
      cacheKey: cacheKey,
      version: entry?['version'] as String? ?? '1.0',
      hash: entry?['hash'] as String?,
    );
  }

  Future<void> _runAssessment() async {
    StagedArtifactLoader.instance.reset();

    // Guard before anything else — with no symptoms the engine still scores
    // every condition on base_weight alone and returns whichever has the
    // highest one, presenting a fabricated result the user never described.
    // The symptom selection screen already disables its Continue button when
    // nothing is selected, so this is defence in depth on the last step
    // before the engine, not the only gate.
    if (widget.assessmentController.symptomTokens.isEmpty) {
      debugPrint('Assessment blocked — no symptoms selected');
      if (!mounted) return;
      setState(() => _noSymptomsSelected = true);
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _step1Complete = true);

    EngineOutput? output;

    try {
      final assessmentInput = widget.assessmentController.buildInput();
      final config = StorageService.getLastKnownConfig();

      if (config != null) {
        final artifacts = config['artifacts'];
        if (artifacts is Map) {
          final artifactsMap = Map<String, dynamic>.from(artifacts);
          final tokenDictSpec = _specFor(
            artifactsMap,
            'token_dictionary',
            ArtifactCacheKeys.tokenDict,
          );
          final rulesSpec = _specFor(
            artifactsMap,
            'rules',
            ArtifactCacheKeys.rules,
          );
          final kbSpec = _specFor(
            artifactsMap,
            'knowledge_base',
            ArtifactCacheKeys.kb,
          );
          final facilitiesSpec = _specFor(
            artifactsMap,
            'facilities',
            ArtifactCacheKeys.facilities,
          );

          if (tokenDictSpec != null && rulesSpec != null && kbSpec != null) {
            // Core artifacts (token dictionary, rules, knowledge base) are
            // downloaded in parallel — small files, needed before the engine
            // can run. Facilities (the largest artifact) are not needed for
            // this assessment itself, only if the user later opens the
            // locator, so they are kicked off in the background and never
            // block the assessment from proceeding.
            final coreArtifacts = await StagedArtifactLoader.instance
                .loadCoreArtifacts(
                  tokenDict: tokenDictSpec,
                  rules: rulesSpec,
                  kb: kbSpec,
                );

            if (facilitiesSpec != null) {
              StagedArtifactLoader.instance.loadFacilitiesInBackground(
                facilitiesSpec,
              );
            } else {
              debugPrint('Facilities artifact URL missing — locator skipped');
            }

            final engine = EngineController(
              rules: coreArtifacts.rules,
              tokenDictionary: coreArtifacts.tokenDictionary,
              knowledgeBase: coreArtifacts.conditions,
              configMetadata: Map<String, dynamic>.from(config),
              // Seasonal modifiers on 21 conditions depend on this. Nothing
              // currently assigns AssessmentInput.season, so it is null today
              // and the seasonal path stays inert — but the plumbing is now
              // complete, so a season source can be dropped in without
              // touching the engine. See PROGRESS.md (E8 wiring fix).
              currentSeason: assessmentInput.season,
            );

            // Demographics, season and candidate conditions were all
            // discarded here before E8: the input was built with
            // `candidateConditionIds: const []`, which closed every gate the
            // engine reads them through. See engine_input_builder.dart.
            final engineInput = buildEngineInput(
              assessmentInput: assessmentInput,
              knowledgeBase: coreArtifacts.conditions,
            );

            output = engine.run(engineInput);
            // PHI rule: never log the urgency level or any other part of the
            // assessment result — this is a completion marker only.
            debugPrint('Assessment complete');
          } else {
            debugPrint('Artifact URLs missing — engine skipped');
          }
        } else {
          debugPrint('Artifacts config missing — engine skipped');
        }
      } else {
        debugPrint('No config cached — engine skipped');
      }
    } on FirstLaunchOfflineException {
      debugPrint('First-launch offline — no cached artifacts and no network');
      if (!mounted) return;
      setState(() => _isFirstLaunchOffline = true);
      return;
    } catch (_) {
      // Generic log only — never log artifact content or symptom tokens
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

    final resolvedOutput = output;
    if (resolvedOutput == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const SystemStatusScreen(
            result: BootResult(status: BootStatus.success),
          ),
        ),
      );
    } else if (resolvedOutput.redFlagTriggered) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RedFlagInterruptScreen(
            engineOutput: resolvedOutput,
            assessmentController: widget.assessmentController,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResultsScreen(
            engineOutput: resolvedOutput,
            assessmentController: widget.assessmentController,
          ),
        ),
      );
    }
  }

  void _retry() {
    setState(() {
      _step1Complete = false;
      _step2Complete = false;
      _hasError = false;
      _isFirstLaunchOffline = false;
      _noSymptomsSelected = false;
    });
    _runAssessment();
  }

  /// Returns to the symptom selection screen. The route is matched by name
  /// (set where `body_area_screen.dart` pushes it) rather than by popping a
  /// fixed number of times, since the follow-up screen's question count
  /// varies. Falls back to the first route so a missing name can never empty
  /// the navigator stack.
  void _returnToSymptomSelection() {
    Navigator.of(context).popUntil(
      (Route<dynamic> route) =>
          route.settings.name == kSymptomSelectionRouteName || route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_noSymptomsSelected) return _buildNoSymptomsView();
    if (_isFirstLaunchOffline) return _buildFirstLaunchOfflineView();
    if (_hasError) return _buildErrorView(context);
    return _buildLoadingView();
  }

  Widget _buildNoSymptomsView() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.checklist_rtl, size: 64, color: _primary),
                const SizedBox(height: 20),
                const Text(
                  'Please select at least one symptom to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _returnToSymptomSelection,
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
                    'Select symptoms',
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
              ValueListenableBuilder<BootProgress>(
                valueListenable: StagedArtifactLoader.instance.progress,
                builder: (context, bootProgress, _) {
                  // The download is in flight for the whole window between
                  // the initial tap and step 2 (engine done) — step 1 flips
                  // true almost immediately as a cosmetic "we've started"
                  // marker, well before the download itself begins, so it
                  // must not gate this label.
                  final showBootLabel =
                      !_step2Complete && bootProgress.step > 0;
                  return Text(
                    showBootLabel ? bootProgress.label : 'Just a moment...',
                    style: const TextStyle(fontSize: 15, color: Colors.black54),
                  );
                },
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

  Widget _buildFirstLaunchOfflineView() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 64, color: _primary),
                const SizedBox(height: 20),
                const Text(
                  'WellaPath needs a brief internet connection the first '
                  'time. Please connect and try again.',
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
