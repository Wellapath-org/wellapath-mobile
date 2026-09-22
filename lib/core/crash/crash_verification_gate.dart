/// LOCAL-VERIFICATION-ONLY — NEVER MERGE, NEVER DISTRIBUTE.
///
/// Compile-time gate for the build-214 controlled transport verification UI
/// (docs/CRASH_VERIFICATION_214.md). Exactly two visibly test-only controls
/// exist on this branch — the Home-screen doorway card to the status screen
/// and the status screen's confirmed synthetic-error button — and both read
/// this single gate. One gate, one removal: the branch is abandoned
/// unmerged and the trigger goes with it.
///
/// The gate passes only when ALL four build-time defines hold:
///
///  1. `CRASH_VERIFICATION_TRIGGER_ENABLED=true` — the dedicated opt-in;
///     nothing else reads it, and no documented build command outside the
///     214 procedure sets it;
///  2. `CRASH_REPORTING_ENABLED=true` — a trigger without a reporter proves
///     nothing;
///  3. `CRASH_REPORTING_PRODUCTION_APPROVED=true` — the founder-approval
///     key the 214 build carries;
///  4. `CRASH_REPORTING_CONTEXT=internal-testing` — the closed-vocabulary
///     label; a production-context build must never expose the trigger.
///
/// Absent, malformed, partial or different values fail CLOSED: an ordinary
/// build, a production build and every partial combination render neither
/// control. Values are trimmed and case-normalised exactly as `CrashConfig`
/// treats the same defines, so the gate can never disagree with the
/// reporter about what a build is.
library;

abstract final class CrashVerificationGate {
  /// The resolved gate for this binary, evaluated once from the
  /// compile-time defines. Widget code reads this; tests exercise
  /// [evaluate] directly with an explicit map.
  static final bool enabled = evaluate(_dartDefines);

  /// Pure gate logic over an explicit define map, so the full matrix is
  /// testable without rebuilding the binary.
  static bool evaluate(Map<String, String> defines) {
    String read(String key) => (defines[key] ?? '').trim().toLowerCase();

    return read('CRASH_VERIFICATION_TRIGGER_ENABLED') == 'true' &&
        read('CRASH_REPORTING_ENABLED') == 'true' &&
        read('CRASH_REPORTING_PRODUCTION_APPROVED') == 'true' &&
        read('CRASH_REPORTING_CONTEXT') == 'internal-testing';
  }

  /// Compile-time defines. Each key is spelled out because
  /// `String.fromEnvironment` resolves only for a const key.
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
