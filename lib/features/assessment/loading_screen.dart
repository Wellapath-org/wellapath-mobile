import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/engine/engine_controller.dart';
import '../../core/engine/models/engine_input.dart';
import '../../core/engine/models/engine_output.dart';
import '../../core/storage/storage_service.dart';
import '../boot/boot_controller.dart';
import '../results/red_flag_interrupt_screen.dart';
import '../results/results_screen.dart';
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

  // Artifacts (knowledge base, rules, token dictionary, facilities) are cached in
  // their own Hive box — separate from the config cache — so they are downloaded
  // once and reused on subsequent assessments instead of re-fetched every time.
  static const String _artifactBoxName = 'artifact_cache';
  static const String _artifactKbKey = 'artifact_kb';
  static const String _artifactRulesKey = 'artifact_rules';
  static const String _artifactTokenDictKey = 'artifact_token_dict';
  static const String _artifactFacilitiesKey = 'artifact_facilities';

  static const String _facilityBoxName = 'facility_cache';
  static const String _facilityDataKey = 'facilities_data';

  bool _step1Complete = false;
  bool _step2Complete = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _runAssessment();
  }

  /// Returns the artifact JSON for [url], reading from the Hive cache first and
  /// only downloading (then caching) on a cache miss. The cache key is scoped
  /// by [version] so a new artifact version is never served stale data cached
  /// under an older version.
  ///
  /// If [expectedHash] (the `sha256:<hex>` value from /config) is provided,
  /// the raw artifact bytes are verified against it on every read — both on
  /// a fresh download and on a cache hit. A corrupted or tampered cached
  /// entry is discarded and re-downloaded rather than silently served; a
  /// corrupted fresh download is retried once before being rejected outright.
  Future<Map<String, dynamic>> _loadArtifact(
    Dio dio,
    Box<dynamic> box,
    String url,
    String cacheKey,
    String version,
    String? expectedHash,
  ) async {
    final versionedKey = '${cacheKey}_v$version';
    final cachedRaw = box.get(versionedKey) as String?;

    if (cachedRaw != null) {
      if (_matchesHash(cachedRaw, expectedHash)) {
        return Map<String, dynamic>.from(jsonDecode(cachedRaw) as Map);
      }
      // Cached artifact failed integrity verification — never serve it.
      debugPrint(
        'Artifact integrity check failed for cached $cacheKey — discarding and re-downloading',
      );
      await box.delete(versionedKey);
    }

    for (var attempt = 1; attempt <= 2; attempt++) {
      final response = await dio.get<dynamic>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final rawBody = response.data as String;

      if (_matchesHash(rawBody, expectedHash)) {
        await box.put(versionedKey, rawBody);
        return Map<String, dynamic>.from(jsonDecode(rawBody) as Map);
      }

      debugPrint(
        'Artifact integrity check failed for downloaded $cacheKey (attempt $attempt) — rejecting',
      );
    }

    throw StateError('Artifact integrity check failed for $cacheKey');
  }

  /// Compares the SHA256 of [rawBody] against [expectedHash] (format
  /// `sha256:<hex>`). Returns true if no hash was provided — some artifacts
  /// may not carry one, and absence of a hash is not itself corruption.
  bool _matchesHash(String rawBody, String? expectedHash) {
    if (expectedHash == null || expectedHash.isEmpty) return true;
    final expectedHex = expectedHash.startsWith('sha256:')
        ? expectedHash.substring('sha256:'.length)
        : expectedHash;
    final actualHex = sha256.convert(utf8.encode(rawBody)).toString();
    return actualHex.toLowerCase() == expectedHex.toLowerCase();
  }

  Future<void> _runAssessment() async {
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
          final kbUrl =
              (artifacts['knowledge_base'] as Map?)?['url'] as String?;
          final rulesUrl = (artifacts['rules'] as Map?)?['url'] as String?;
          final tokenDictUrl =
              (artifacts['token_dictionary'] as Map?)?['url'] as String?;
          final facilitiesUrl =
              (artifacts['facilities'] as Map?)?['url'] as String?;

          if (kbUrl != null && rulesUrl != null && tokenDictUrl != null) {
            final kbVersion =
                (artifacts['knowledge_base'] as Map?)?['version'] as String? ??
                '1.0';
            final rulesVersion =
                (artifacts['rules'] as Map?)?['version'] as String? ?? '1.0';
            final tokenVersion =
                (artifacts['token_dictionary'] as Map?)?['version']
                    as String? ??
                '1.0';
            final facilitiesVersion =
                (artifacts['facilities'] as Map?)?['version'] as String? ??
                '1.0';

            final kbHash =
                (artifacts['knowledge_base'] as Map?)?['hash'] as String?;
            final rulesHash = (artifacts['rules'] as Map?)?['hash'] as String?;
            final tokenHash =
                (artifacts['token_dictionary'] as Map?)?['hash'] as String?;
            final facilitiesHash =
                (artifacts['facilities'] as Map?)?['hash'] as String?;

            final dio = Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

            final artifactBox = Hive.isBoxOpen(_artifactBoxName)
                ? Hive.box(_artifactBoxName)
                : await Hive.openBox(_artifactBoxName);

            final artifactData = await Future.wait([
              _loadArtifact(
                dio,
                artifactBox,
                kbUrl,
                _artifactKbKey,
                kbVersion,
                kbHash,
              ),
              _loadArtifact(
                dio,
                artifactBox,
                rulesUrl,
                _artifactRulesKey,
                rulesVersion,
                rulesHash,
              ),
              _loadArtifact(
                dio,
                artifactBox,
                tokenDictUrl,
                _artifactTokenDictKey,
                tokenVersion,
                tokenHash,
              ),
              if (facilitiesUrl != null)
                _loadArtifact(
                  dio,
                  artifactBox,
                  facilitiesUrl,
                  _artifactFacilitiesKey,
                  facilitiesVersion,
                  facilitiesHash,
                ),
            ]);

            final kbData = artifactData[0];
            final rulesData = artifactData[1];
            final tokenDictData = artifactData[2];

            if (facilitiesUrl != null) {
              final facilitiesData = artifactData[3];
              final facilitiesList =
                  (facilitiesData['facilities'] as List?)
                      ?.map((e) => Map<String, dynamic>.from(e as Map))
                      .toList() ??
                  <Map<String, dynamic>>[];

              final facilityBox = Hive.isBoxOpen(_facilityBoxName)
                  ? Hive.box(_facilityBoxName)
                  : await Hive.openBox(_facilityBoxName);
              await facilityBox.put(_facilityDataKey, facilitiesList);
            } else {
              debugPrint('Facilities artifact URL missing — locator skipped');
            }

            final conditions =
                (kbData['conditions'] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e as Map))
                    .toList() ??
                [];
            final rules =
                (rulesData['rules'] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e as Map))
                    .toList() ??
                [];

            final engine = EngineController(
              rules: rules,
              tokenDictionary: tokenDictData,
              knowledgeBase: conditions,
              configMetadata: Map<String, dynamic>.from(config),
            );

            final engineInput = EngineInput(
              symptomTokens: assessmentInput.symptomTokens,
              candidateConditionIds: const [],
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
