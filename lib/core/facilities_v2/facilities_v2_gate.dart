/// Facilities 2.0 development gate — off by default, off in production,
/// and inert without an approved manifest.
///
/// Same two-key pattern as `VocabularyConfig` and `CrashConfig`:
/// a single flag flipped by accident cannot activate anything, and
/// production needs a second, separately named key that nothing sets.
/// On top of the flags, [FacilitiesV2Gate.evaluate] demands a manifest
/// whose artifact is explicitly `approved` **and** `may_publish: true` —
/// the current candidate is neither, so the v2 path cannot activate today
/// under any flag combination.
library;

import 'facilities_v2_manifest.dart';

class FacilitiesV2Gate {
  const FacilitiesV2Gate._({required this.active, required this.reason});

  /// Whether the v2 consumer may run. False means the locator uses the
  /// approved v1.1 path exactly as shipped in build 210.
  final bool active;

  /// Why the gate resolved the way it did — fixed vocabulary, safe to log.
  final String reason;

  static const FacilitiesV2Gate inactiveDefault = FacilitiesV2Gate._(
    active: false,
    reason: 'evaluation_flag_off',
  );

  /// | Input                                  | Meaning                                          |
  /// | -------------------------------------- | ------------------------------------------------ |
  /// | `FACILITIES_V2_EVALUATION`             | Gate 1. Only `true` (trimmed, any case) enables  |
  /// | `APP_ENV`                              | `production`/`prod` forces inactive              |
  /// | `FACILITIES_V2_PRODUCTION_APPROVED`    | The only key that can lift the production block  |
  /// | [manifest]                             | Gate 2. Must be approved + publishable           |
  ///
  /// All three defines default to absent; the tracked `.env` sets none of
  /// them, so every ordinary build — including build 210 — resolves
  /// [inactiveDefault] before the manifest is even looked at.
  factory FacilitiesV2Gate.evaluate({
    Map<String, String>? defines,
    FacilitiesV2Manifest? manifest,
  }) {
    final source = defines ?? _dartDefines;
    String read(String key) => (source[key] ?? '').trim();

    if (read('FACILITIES_V2_EVALUATION').toLowerCase() != 'true') {
      return inactiveDefault;
    }

    final appEnv = read('APP_ENV').toLowerCase();
    final isProduction = appEnv == 'production' || appEnv == 'prod';
    if (isProduction &&
        read('FACILITIES_V2_PRODUCTION_APPROVED').toLowerCase() != 'true') {
      return const FacilitiesV2Gate._(
        active: false,
        reason: 'production_blocked',
      );
    }

    if (manifest == null) {
      return const FacilitiesV2Gate._(active: false, reason: 'no_manifest');
    }
    if (!manifest.isApprovedForConsumption) {
      return const FacilitiesV2Gate._(
        active: false,
        reason: 'manifest_not_approved',
      );
    }

    return const FacilitiesV2Gate._(active: true, reason: 'approved_manifest');
  }

  /// Compile-time defines. Absent defines yield the empty string, which
  /// reads as "off" everywhere above.
  static const Map<String, String> _dartDefines = {
    'FACILITIES_V2_EVALUATION': String.fromEnvironment(
      'FACILITIES_V2_EVALUATION',
    ),
    'FACILITIES_V2_PRODUCTION_APPROVED': String.fromEnvironment(
      'FACILITIES_V2_PRODUCTION_APPROVED',
    ),
    'APP_ENV': String.fromEnvironment('APP_ENV'),
  };
}
