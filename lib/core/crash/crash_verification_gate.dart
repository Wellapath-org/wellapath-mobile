/// LOCAL-VERIFICATION-ONLY — NEVER MERGE, NEVER DISTRIBUTE.
///
/// Compile-time gate for the build-213 controlled transport verification UI
/// (docs/CRASH_VERIFICATION_213.md). Two explicit, visibly test-only
/// controls exist on this branch: the Home-screen doorway card to the
/// status screen and the status screen's confirmed synthetic-error button.
/// Both are conditioned on this single gate — one gate, one removal (the
/// branch is abandoned unmerged), no drift between the two.
///
/// The gate passes only when ALL of the following build-time defines hold:
///
///  1. `CRASH_VERIFICATION_TRIGGER_ENABLED=true` — the dedicated opt-in;
///     nothing else reads it and no documented build command outside the
///     213 procedure sets it;
///  2. `CRASH_REPORTING_ENABLED=true` — a trigger without a reporter
///     proves nothing;
///  3. `CRASH_REPORTING_PRODUCTION_APPROVED=true` — the founder-approval
///     key the 213 build carries;
///  4. `CRASH_REPORTING_CONTEXT=internal-testing` — the closed-vocabulary
///     label; a production-context build must never expose the trigger.
///
/// Absent, malformed or different values fail CLOSED: an ordinary build, a
/// production build and every partial combination render neither control.
/// Values are trimmed and case-normalised exactly as `CrashConfig` treats
/// the same defines, so the gate cannot disagree with the reporter about
/// what a build is.
library;

class CrashVerificationGate {
  const CrashVerificationGate._();

  /// The resolved gate for this binary. Evaluated once from the
  /// compile-time defines; widget code reads this, tests inject [evaluate].
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
