/// Compile-time gate for the build-212 synthetic-crash verification UI.
///
/// Two explicit, visibly test-only controls exist on the 212 branch: the
/// Home-screen doorway card to [SystemStatusScreen] and the status screen's
/// confirmed synthetic-error button (docs/CRASH_VERIFICATION_212.md §3).
/// Neither may exist in any build that was not deliberately produced for the
/// internal verification, so both are conditioned on this single gate rather
/// than on their own flags — one gate, one removal, no drift between the
/// doorway and the trigger.
///
/// The gate passes only when ALL of the following build-time defines hold:
///
///  1. `CRASH_VERIFICATION_TRIGGER_ENABLED=true` — the dedicated opt-in;
///     nothing else in the app reads it, and no documented build command
///     outside the 212 procedure sets it;
///  2. `CRASH_REPORTING_ENABLED=true` — a trigger without a reporter proves
///     nothing and teaches testers a dead gesture;
///  3. `CRASH_REPORTING_PRODUCTION_APPROVED=true` — the founder-approval key
///     the 212 build already carries;
///  4. `CRASH_REPORTING_CONTEXT=internal-testing` — the closed-vocabulary
///     label; a production-context build must never expose the trigger.
///
/// Absent, malformed or different values fail CLOSED: an ordinary build, a
/// production build, and every partial combination render neither control.
/// The values are trimmed and case-normalised exactly as
/// `CrashConfig` treats the same defines, so the gate cannot disagree with
/// the reporter about what a build is.
library;

class CrashVerificationGate {
  const CrashVerificationGate._();

  /// The resolved gate for this binary. Evaluated once from the compile-time
  /// defines; widget code reads this, tests inject [evaluate] directly.
  static final bool enabled = evaluate(_dartDefines);

  /// Pure gate logic over an explicit define map, so the full matrix is
  /// testable without rebuilding.
  static bool evaluate(Map<String, String> defines) {
    String read(String key) => (defines[key] ?? '').trim().toLowerCase();

    return read('CRASH_VERIFICATION_TRIGGER_ENABLED') == 'true' &&
        read('CRASH_REPORTING_ENABLED') == 'true' &&
        read('CRASH_REPORTING_PRODUCTION_APPROVED') == 'true' &&
        read('CRASH_REPORTING_CONTEXT') == 'internal-testing';
  }

  /// Compile-time defines. Each must be spelled out because
  /// `String.fromEnvironment` is only resolved for a const key.
  static const Map<String, String> _dartDefines = {
    'CRASH_VERIFICATION_TRIGGER_ENABLED': String.fromEnvironment(
      'CRASH_VERIFICATION_TRIGGER_ENABLED',
    ),
    'CRASH_REPORTING_ENABLED': String.fromEnvironment(
      'CRASH_REPORTING_ENABLED',
    ),
    'CRASH_REPORTING_PRODUCTION_APPROVED': String.fromEnvironment(
      'CRASH_REPORTING_PRODUCTION_APPROVED',
    ),
    'CRASH_REPORTING_CONTEXT': String.fromEnvironment(
      'CRASH_REPORTING_CONTEXT',
    ),
  };
}
