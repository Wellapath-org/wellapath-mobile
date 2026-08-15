/// Build-time gate for the Vocabulary 2.0 evaluation path.
///
/// Follows the same two-key shape as `CrashConfig` and `TelemetryConfig`:
/// nothing is enabled by default, enabling requires an explicit define, and
/// production is blocked behind a second, separately named key.
///
/// ## What "enabled" does and does not mean
///
/// Enabled means *an internal evaluation surface may load the candidate and
/// run searches against it.* It does **not** mean the candidate becomes the
/// scoring vocabulary. Token dictionary 1.1 remains the live artifact in every
/// build, the live manifest is untouched, and the assessment flow's picker is
/// unchanged. This gate exists so the consumer can be exercised internally
/// before any of that is even proposed.
///
/// ## Why presence of the candidate cannot enable anything
///
/// The candidate ships only as a test fixture. There is no asset entry for it,
/// so a normal build cannot read it at all, and even a build that could would
/// still need this flag. Two independent conditions, neither satisfied by
/// accident.
library;

/// Resolved state of the Vocabulary 2.0 evaluation gate.
class VocabularyConfig {
  const VocabularyConfig({
    required this.evaluationEnabled,
    required this.environment,
  });

  /// True only when the internal-evaluation define is set and the build is not
  /// a blocked production build.
  final bool evaluationEnabled;

  final String environment;

  /// The safe default: the candidate is inert.
  static const VocabularyConfig disabled = VocabularyConfig(
    evaluationEnabled: false,
    environment: 'disabled',
  );

  /// Resolves from build-time defines.
  ///
  /// | Define                                 | Meaning                                          |
  /// | -------------------------------------- | ------------------------------------------------ |
  /// | `VOCABULARY_V2_EVALUATION`             | Gate 1. Only `true` (trimmed, any case) enables   |
  /// | `APP_ENV`                              | `production`/`prod` forces disabled               |
  /// | `VOCABULARY_V2_PRODUCTION_APPROVED`    | The only key that can lift the production block   |
  ///
  /// [defines] is injectable so the gate is testable without rebuilding.
  factory VocabularyConfig.fromEnvironment({Map<String, String>? defines}) {
    final Map<String, String> source = defines ?? _dartDefines;

    String read(String key) => (source[key] ?? '').trim();

    final bool enabledFlag =
        read('VOCABULARY_V2_EVALUATION').toLowerCase() == 'true';
    if (!enabledFlag) return disabled;

    final String appEnv = read('APP_ENV').toLowerCase();
    final bool isProduction = appEnv == 'production' || appEnv == 'prod';

    // Production stays off. The candidate is clinically unreviewed with zero
    // approved labels; there is no build of the shipping app in which showing
    // it to a user is correct. The override key exists only so the block is
    // explicit rather than implicit, and turning it on would still not make
    // the candidate the scoring vocabulary.
    if (isProduction &&
        read('VOCABULARY_V2_PRODUCTION_APPROVED').toLowerCase() != 'true') {
      return disabled;
    }

    return VocabularyConfig(
      evaluationEnabled: true,
      environment: appEnv.isEmpty ? 'internal-evaluation' : appEnv,
    );
  }

  /// Compile-time defines. Each key must be spelled out because
  /// `String.fromEnvironment` is only resolved for a const key.
  static const Map<String, String> _dartDefines = <String, String>{
    'VOCABULARY_V2_EVALUATION': String.fromEnvironment(
      'VOCABULARY_V2_EVALUATION',
    ),
    'VOCABULARY_V2_PRODUCTION_APPROVED': String.fromEnvironment(
      'VOCABULARY_V2_PRODUCTION_APPROVED',
    ),
    'APP_ENV': String.fromEnvironment('APP_ENV'),
  };

  Map<String, Object?> toDiagnostics() => <String, Object?>{
    'evaluation_enabled': evaluationEnabled,
    'environment': environment,
    'is_scoring_vocabulary': false,
    'live_token_dictionary_version': '1.1',
  };
}
