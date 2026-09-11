/// Build-environment identity and cross-environment gates.
///
/// This build line is **internal testing against staging only**. Two mistakes
/// must be impossible to ship silently:
///
///  1. an internal/staging build that points at a production backend, and
///  2. a production build that points at the staging backend.
///
/// [BuildEnvironment.validate] enforces both and is called from `main()`
/// before the first frame. A violation throws [StateError] and the app does
/// not start — the same crash-is-acceptable posture the boot sequence already
/// takes for a missing `.env` (CLAUDE.md boot order, steps 1–2).
///
/// No production endpoint exists anywhere in this repository (`RC-BLK-005`),
/// and this module deliberately does not invent one: an `APP_ENV=production`
/// build therefore always fails validation today, which is correct — shipping
/// to production is not yet an authorized configuration.
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// The environments this app recognises. Anything else is a misconfiguration.
enum AppEnvironment { staging, production }

class BuildEnvironment {
  const BuildEnvironment._();

  /// Hosts that are the staging backend/artifact origin. An internal build
  /// must use only these; a production build must use none of them.
  ///
  /// This is an allowlist of known-staging hosts, not a guess at what
  /// production will look like.
  static const Set<String> kStagingHosts = {
    'wellapath-backend-staging.onrender.com',
    'pub-8bc2ba0d7e7647799d89662d70f23c45.r2.dev',
  };

  /// The marker shown to testers in nonclinical UI (home footer). Fixed
  /// wording — release notes and tester instructions quote it.
  static const String kInternalBuildMarker = 'Internal testing — staging';

  static String _read(String key, Map<String, String>? env) {
    Map<String, String> source;
    if (env != null) {
      source = env;
    } else {
      try {
        source = dotenv.env;
      } on Object {
        // dotenv not initialised (widget tests). Reads resolve to empty;
        // validate() still fails on the missing API_BASE_URL, and
        // isInternal() defaults to showing the internal marker.
        source = const {};
      }
    }
    return (source[key] ?? '').trim();
  }

  /// The declared environment. Throws [StateError] on an unknown value —
  /// an unrecognised environment must not fall back to anything.
  static AppEnvironment environment({Map<String, String>? env}) {
    final raw = _read('APP_ENV', env).toLowerCase();
    switch (raw) {
      case 'staging':
        return AppEnvironment.staging;
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      default:
        throw StateError(
          'APP_ENV is "$raw" — not a recognised environment. '
          'Expected "staging" or "production". Refusing to start with an '
          'ambiguous environment.',
        );
    }
  }

  /// True when this build should show the internal-testing marker.
  static bool isInternal({Map<String, String>? env}) {
    try {
      return environment(env: env) == AppEnvironment.staging;
    } on StateError {
      // An ambiguous environment fails validate() at boot; a widget asking
      // afterwards should still render rather than rethrow.
      return true;
    }
  }

  /// Fails the boot on any cross-environment configuration.
  ///
  /// | Build declares | URL points at | Result |
  /// |---|---|---|
  /// | staging | staging hosts only | OK |
  /// | staging | any non-staging host | **StateError** |
  /// | production | any staging host | **StateError** |
  /// | production | (no production config exists) | **StateError** |
  static void validate({Map<String, String>? env}) {
    final resolved = environment(env: env);

    final urls = <String, String>{
      'API_BASE_URL': _read('API_BASE_URL', env),
      'ARTIFACT_BASE_URL': _read('ARTIFACT_BASE_URL', env),
      'TELEMETRY_BASE_URL': _read('TELEMETRY_BASE_URL', env),
    }..removeWhere((_, v) => v.isEmpty);

    if (urls['API_BASE_URL'] == null) {
      throw StateError('API_BASE_URL is not configured.');
    }

    for (final entry in urls.entries) {
      final host = Uri.tryParse(entry.value)?.host ?? '';
      if (host.isEmpty) {
        throw StateError('${entry.key} ("${entry.value}") has no host.');
      }
      final isStagingHost = kStagingHosts.contains(host);

      if (resolved == AppEnvironment.staging && !isStagingHost) {
        throw StateError(
          'Internal/staging build points outside staging: ${entry.key} is '
          '"$host", which is not an approved staging host. An internal build '
          'must never reach a production service.',
        );
      }
      if (resolved == AppEnvironment.production && isStagingHost) {
        throw StateError(
          'Production build points at staging: ${entry.key} is "$host". '
          'A production build must never depend on the staging backend.',
        );
      }
    }

    if (resolved == AppEnvironment.staging &&
        _read('TELEMETRY_PRODUCTION_APPROVED', env).toLowerCase() == 'true') {
      throw StateError(
        'TELEMETRY_PRODUCTION_APPROVED=true in a staging build. The '
        'production-approval flag must never travel in an internal build.',
      );
    }
  }
}
