/// Configuration gates for crash monitoring.
///
/// Crash transmission requires **two independent gates**, both supplied at
/// build time and neither present by default:
///
///  1. `CRASH_REPORTING_ENABLED=true`
///  2. a syntactically valid, non-placeholder `SENTRY_DSN`
///
/// Either one missing means the app keeps the no-op sink and transmits
/// nothing. That is the state of every ordinary build, every local build and
/// every test run.
///
/// ### Why `--dart-define` and not `.env`
///
/// `.env` is a **tracked** file. A DSN placed there is one `git add` away from
/// being published, and this repository is public. A define cannot be
/// committed. This mirrors the telemetry enablement decision — see
/// `docs/TELEMETRY_MOBILE.md` §2 — and `.env.local` is deliberately not a
/// supported path here either: `flutter_dotenv` reads through the asset
/// bundle, so a gitignored file cannot be loaded at all.
///
/// **The DSN is never hard-coded, never committed and never logged.**
library;

/// Where crash reports may be sent, and whether they may be sent at all.
class CrashConfig {
  const CrashConfig({
    required this.enabled,
    required this.dsn,
    required this.environment,
    required this.release,
  });

  /// True only when both gates are satisfied.
  final bool enabled;

  /// Empty whenever [enabled] is false. Never logged, never included in an
  /// error message, never written to diagnostics.
  final String dsn;

  /// `internal-beta` for approved internal builds.
  final String environment;

  /// `wellapath-mobile@<version>+<build>` — version identity only. Contains no
  /// account, user, installation, device or assessment identifier.
  final String release;

  /// The safe default: collect nothing, send nothing.
  static const CrashConfig disabled = CrashConfig(
    enabled: false,
    dsn: '',
    environment: 'disabled',
    release: '',
  );

  /// A DSN must look like `https://<key>@<host>/<projectId>`.
  ///
  /// Validated structurally rather than trusted, so a truncated CI secret, an
  /// unexpanded `${SENTRY_DSN}`, or a copy-paste of the documentation
  /// placeholder resolves to *disabled* instead of to a half-configured SDK
  /// pointing somewhere unintended.
  static bool isValidDsn(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return false;
    // Reject the obvious placeholders before parsing, so a literal
    // "<your-dsn>" can never satisfy the gate.
    final lower = value.toLowerCase();
    for (final placeholder in const [
      'your-dsn',
      'your_dsn',
      'changeme',
      'example.com',
      'placeholder',
      'todo',
      r'${',
      '<',
    ]) {
      if (lower.contains(placeholder)) return false;
    }
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    if (uri.scheme != 'https') return false;
    if (uri.userInfo.isEmpty) return false; // the public key
    if (uri.host.isEmpty) return false;
    // Path must carry a numeric project id.
    final projectId = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (projectId.isEmpty || int.tryParse(projectId) == null) return false;
    return true;
  }

  /// Resolves configuration from build-time defines.
  ///
  /// | Define                                | Meaning                                        |
  /// | ------------------------------------- | ---------------------------------------------- |
  /// | `CRASH_REPORTING_ENABLED`             | Gate 1. Only `true` (trimmed, any case) enables |
  /// | `SENTRY_DSN`                          | Gate 2. Must be structurally valid             |
  /// | `APP_ENV`                             | `production`/`prod` forces disabled            |
  /// | `CRASH_REPORTING_PRODUCTION_APPROVED` | The only key that can lift the production block |
  /// | `APP_VERSION` / `APP_BUILD`           | Release identity                               |
  ///
  /// [defines] is injectable so the gate logic is testable without rebuilding.
  factory CrashConfig.fromEnvironment({Map<String, String>? defines}) {
    final source = defines ?? _dartDefines;

    String read(String key) => (source[key] ?? '').trim();

    final enabledFlag = read('CRASH_REPORTING_ENABLED').toLowerCase() == 'true';
    if (!enabledFlag) return disabled;

    final dsn = read('SENTRY_DSN');
    if (!isValidDsn(dsn)) return disabled;

    // Production and public beta stay off until separately approved, by the
    // same two-key rule telemetry uses. One flag flipped by accident cannot
    // start collecting from the public.
    final appEnv = read('APP_ENV').toLowerCase();
    final isProduction = appEnv == 'production' || appEnv == 'prod';
    if (isProduction &&
        read('CRASH_REPORTING_PRODUCTION_APPROVED').toLowerCase() != 'true') {
      return disabled;
    }

    final version = read('APP_VERSION').isEmpty ? '0.0.0' : read('APP_VERSION');
    final build = read('APP_BUILD').isEmpty ? '0' : read('APP_BUILD');

    return CrashConfig(
      enabled: true,
      dsn: dsn,
      // Anything that is not production and has cleared both gates is an
      // approved internal build.
      environment: appEnv.isEmpty ? 'internal-beta' : appEnv,
      release: 'wellapath-mobile@$version+$build',
    );
  }

  /// Compile-time defines. Each must be spelled out because
  /// `String.fromEnvironment` is only resolved for a const key.
  static const Map<String, String> _dartDefines = {
    'CRASH_REPORTING_ENABLED': String.fromEnvironment(
      'CRASH_REPORTING_ENABLED',
    ),
    'SENTRY_DSN': String.fromEnvironment('SENTRY_DSN'),
    'CRASH_REPORTING_PRODUCTION_APPROVED': String.fromEnvironment(
      'CRASH_REPORTING_PRODUCTION_APPROVED',
    ),
    'APP_ENV': String.fromEnvironment('APP_ENV'),
    'APP_VERSION': String.fromEnvironment('APP_VERSION'),
    'APP_BUILD': String.fromEnvironment('APP_BUILD'),
  };

  /// A description safe to print. **Never includes the DSN.**
  Map<String, Object?> toDiagnostics() => {
    'enabled': enabled,
    'environment': environment,
    'release': release,
    'dsn_configured': dsn.isNotEmpty,
  };
}
