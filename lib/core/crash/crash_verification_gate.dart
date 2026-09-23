/// LOCAL-VERIFICATION-ONLY — NEVER MERGE, NEVER DISTRIBUTE.
///
/// Compile-time gate for the build-214 controlled transport verification UI
/// (docs/CRASH_VERIFICATION_214.md). Exactly two visibly test-only controls
/// exist on this branch — the Home-screen doorway card to the status screen
/// and the status screen's confirmed synthetic-error button — and both read
/// this single gate. One gate, one removal: the branch is abandoned
/// unmerged and the trigger goes with it.
///
/// ### The gate is the reporter's own answer, not a second opinion
///
/// 214 may send exactly ONE event, and the procedure forbids a retry
/// whatever happens. So the trigger must never be reachable in a build that
/// cannot deliver that event correctly. Re-deriving the reporter's rules
/// here would be two places to keep in step; instead the gate ASKS
/// [CrashConfig] and additionally requires:
///
///  1. `CRASH_VERIFICATION_TRIGGER_ENABLED=true` — the dedicated opt-in;
///     nothing else reads it, and no documented build command outside the
///     214 procedure sets it;
///  2. `CrashConfig.enabled` — which already requires
///     `CRASH_REPORTING_ENABLED=true`, a **structurally valid `SENTRY_DSN`**
///     and, because the bundled `.env` is production, the founder-approval
///     key `CRASH_REPORTING_PRODUCTION_APPROVED=true`;
///  3. the resolved environment label is exactly [kExpectedEnvironment] —
///     a production-context build can never expose the trigger;
///  4. the resolved release is exactly [kExpectedRelease] — a build that
///     forgot `APP_VERSION`/`APP_BUILD` would stamp
///     `wellapath-mobile@0.0.0+0` and spend the one-event budget on an
///     event that fails audit criterion 5.
///
/// (2)–(4) read the same resolved values the SDK is configured with, so a
/// visible trigger means the next confirmed tap produces a correctly
/// identified event or no UI at all. Absent, malformed or partial defines
/// fail CLOSED: an ordinary build, a production build and every partial
/// combination render nothing.
library;

import 'crash_config.dart';

abstract final class CrashVerificationGate {
  /// The exact Sentry environment label build 214's events must carry.
  static const String kExpectedEnvironment = 'internal-testing';

  /// The exact Sentry release build 214's events must carry. Bound to this
  /// branch's build number on purpose: a 213 or 215 identity must not open
  /// the 214 trigger.
  static const String kExpectedRelease = 'wellapath-mobile@0.3.0+214';

  /// The resolved gate for this binary, evaluated once from the
  /// compile-time defines. Widget code reads this; tests exercise
  /// [evaluate] directly with an explicit map.
  static final bool enabled = evaluate(_dartDefines);

  /// Pure gate logic over an explicit define map, so the full matrix is
  /// testable without rebuilding the binary.
  ///
  /// [bundledIsProduction] is forwarded to [CrashConfig.fromEnvironment] so
  /// tests state the bundled-environment assumption explicitly instead of
  /// depending on whether dotenv happens to be loaded.
  static bool evaluate(
    Map<String, String> defines, {
    bool? bundledIsProduction,
  }) {
    final trigger = (defines['CRASH_VERIFICATION_TRIGGER_ENABLED'] ?? '')
        .trim()
        .toLowerCase();
    if (trigger != 'true') return false;

    // The reporter's own resolution — same defines, same rules, one source.
    final config = CrashConfig.fromEnvironment(
      defines: defines,
      bundledIsProduction: bundledIsProduction,
    );

    return config.enabled &&
        config.environment == kExpectedEnvironment &&
        config.release == kExpectedRelease;
  }

  /// Compile-time defines. Every key [CrashConfig] consults is spelled out
  /// alongside the trigger, because `String.fromEnvironment` resolves only
  /// for a const key.
  static const Map<String, String> _dartDefines = {
    'CRASH_VERIFICATION_TRIGGER_ENABLED': String.fromEnvironment(
      'CRASH_VERIFICATION_TRIGGER_ENABLED',
    ),
    'CRASH_REPORTING_ENABLED': String.fromEnvironment(
      'CRASH_REPORTING_ENABLED',
    ),
    'SENTRY_DSN': String.fromEnvironment('SENTRY_DSN'),
    'CRASH_REPORTING_PRODUCTION_APPROVED': String.fromEnvironment(
      'CRASH_REPORTING_PRODUCTION_APPROVED',
    ),
    'CRASH_REPORTING_CONTEXT': String.fromEnvironment(
      'CRASH_REPORTING_CONTEXT',
    ),
    'APP_ENV': String.fromEnvironment('APP_ENV'),
    'APP_VERSION': String.fromEnvironment('APP_VERSION'),
    'APP_BUILD': String.fromEnvironment('APP_BUILD'),
  };
}
