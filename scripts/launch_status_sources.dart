/// Readers that turn real repository files into dashboard metrics.
///
/// Every reader here obeys one rule: **if the source cannot be read or parsed,
/// the metric becomes `notVerified` with the reason attached.** No reader ever
/// falls back to a default, a zero or a remembered value, because a dashboard
/// that quietly substitutes a plausible number for a failed read is worse than
/// one that says nothing.
///
/// Several readers parse Dart or dotenv source with deliberately strict
/// regular expressions. That is fragile by nature, so each pattern is pinned by
/// a test in `test/scripts/launch_dashboard_test.dart` against the real file:
/// if an upstream rename breaks a pattern, the test fails rather than the
/// dashboard silently reporting "Not verified" forever.
library;

import 'dart:convert';
import 'dart:io';

import 'launch_status_model.dart';

/// Reads repository files relative to a root directory.
class RepoSources {
  RepoSources(this.root);

  /// Repository root (the directory containing `pubspec.yaml`).
  final Directory root;

  String path(String relative) => '${root.path}/$relative';

  /// Returns the file's text, or null when it does not exist.
  String? read(String relative) {
    final File file = File(path(relative));
    if (!file.existsSync()) {
      return null;
    }
    try {
      return file.readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  /// A metric whose source file is missing or unparseable.
  static Metric unreadable(
    String key,
    String label,
    String source,
    String why,
  ) => Metric(
    key: key,
    label: label,
    state: MetricState.notVerified,
    source: source,
    note: why,
  );

  /// Extracts the first capture group of [pattern] from [text], or null.
  static String? firstMatch(String? text, RegExp pattern) {
    if (text == null) {
      return null;
    }
    return pattern.firstMatch(text)?.group(1);
  }
}

// ---------------------------------------------------------------------------
// Build identity
// ---------------------------------------------------------------------------

/// `version: 0.3.0+216` in pubspec.yaml. Anchored to the line start so the
/// stale explanatory comment above it can never be matched instead.
final RegExp kPubspecVersion = RegExp(
  r'^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$',
  multiLine: true,
);

/// `const int kCurrentBuildNumber = 216;`
final RegExp kCurrentBuildConst = RegExp(
  r'const\s+int\s+kCurrentBuildNumber\s*=\s*(\d+)\s*;',
);

/// Registry keys: lines shaped `  215: '...'` inside kKnownDistributedBuilds.
final RegExp kRegistryEntry = RegExp(r'^\s{2}(\d+):\s', multiLine: true);

const String kBuildIdentityPath = 'test/release/build_identity_test.dart';

List<Metric> buildIdentityMetrics(RepoSources repo) {
  final List<Metric> metrics = <Metric>[];

  final String? pubspec = repo.read('pubspec.yaml');
  final String? version = RepoSources.firstMatch(pubspec, kPubspecVersion);
  metrics.add(
    version == null
        ? RepoSources.unreadable(
            'candidate_version',
            'Next candidate build',
            'pubspec.yaml',
            'No `version:` line matched. The dashboard will not guess a build '
                'number.',
          )
        : Metric(
            key: 'candidate_version',
            label: 'Next candidate build',
            state: MetricState.derived,
            value: version,
            source: 'pubspec.yaml',
            note:
                'Not yet built. This is the number the next build would '
                'take, not a build that exists.',
          ),
  );

  final String? identity = repo.read(kBuildIdentityPath);
  final String? current = RepoSources.firstMatch(identity, kCurrentBuildConst);
  final List<int> consumed =
      identity == null
            ? const <int>[]
            : kRegistryEntry
                  .allMatches(identity)
                  .map((RegExpMatch m) => int.parse(m.group(1)!))
                  .toList()
        ..sort();

  metrics.add(
    consumed.isEmpty
        ? RepoSources.unreadable(
            'highest_consumed_build',
            'Highest consumed build number',
            kBuildIdentityPath,
            'The append-only build registry could not be parsed.',
          )
        : Metric(
            key: 'highest_consumed_build',
            label: 'Highest consumed build number',
            state: MetricState.derived,
            value: '${consumed.last}',
            source: '$kBuildIdentityPath (kKnownDistributedBuilds)',
            note:
                '${consumed.length} build numbers are consumed and can '
                'never be reused: ${consumed.join(', ')}.',
          ),
  );

  if (current != null && version != null) {
    final String pubspecBuild = version.split('+').last;
    final bool agree = pubspecBuild == current;
    metrics.add(
      Metric(
        key: 'build_number_consistency',
        label: 'pubspec and registry agree',
        state: MetricState.derived,
        value: agree
            ? 'Yes — both $current'
            : 'NO — pubspec $pubspecBuild '
                  'vs kCurrentBuildNumber $current',
        source: 'pubspec.yaml + $kBuildIdentityPath',
        note: agree
            ? null
            : 'These must match. The release gate test fails while they do '
                  'not.',
      ),
    );
  }

  return metrics;
}

// ---------------------------------------------------------------------------
// Environment / .env
// ---------------------------------------------------------------------------

/// Parses the tracked dotenv file into key/value pairs, ignoring comments.
Map<String, String> parseDotenv(String text) {
  final Map<String, String> out = <String, String>{};
  for (final String raw in const LineSplitter().convert(text)) {
    final String line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final int eq = line.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    out[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
  }
  return out;
}

List<Metric> environmentMetrics(RepoSources repo) {
  final String? envText = repo.read('.env');
  if (envText == null) {
    return <Metric>[
      RepoSources.unreadable(
        'app_env',
        'Bundled environment',
        '.env',
        'The tracked .env is missing. It is bundled into every build, so its '
            'absence is itself a release blocker.',
      ),
    ];
  }
  final Map<String, String> env = parseDotenv(envText);

  Metric fromEnv(String key, String label, {String? note}) {
    final String? value = env[key];
    return value == null || value.isEmpty
        ? RepoSources.unreadable(
            key.toLowerCase(),
            label,
            '.env',
            '`$key` is absent from the bundled .env.',
          )
        : Metric(
            key: key.toLowerCase(),
            label: label,
            state: MetricState.derived,
            value: value,
            source: '.env',
            note: note,
          );
  }

  return <Metric>[
    fromEnv(
      'APP_ENV',
      'Bundled environment',
      note:
          'Bundled through the asset bundle, so it is fixed at build '
          'time and cannot be overridden on device.',
    ),
    fromEnv('API_BASE_URL', 'Bundled API base URL'),
    fromEnv('API_TIMEOUT_MS', 'API timeout (ms)'),
  ];
}

// ---------------------------------------------------------------------------
// Feature flags — the subsystems that must never render as a number
// ---------------------------------------------------------------------------

/// A compile-time-gated subsystem and how to prove its default state.
class FlagProbe {
  const FlagProbe({
    required this.key,
    required this.label,
    required this.path,
    required this.pattern,
    required this.offNote,
  });

  final String key;
  final String label;
  final String path;

  /// Must capture the literal default in group 1.
  final RegExp pattern;

  /// Explains what "off" means for this subsystem specifically.
  final String offNote;
}

final List<FlagProbe> kFlagProbes = <FlagProbe>[
  FlagProbe(
    key: 'feedback',
    label: 'In-app feedback',
    path: 'lib/core/config/feature_flags.dart',
    pattern: RegExp(
      r"bool\.fromEnvironment\(\s*'FEEDBACK_ENABLED'(?:\s*,\s*defaultValue:\s*(\w+))?",
    ),
    offNote:
        'No define is passed in any release build, and the control '
        'strings are tree-shaken out of the binary entirely.',
  ),
  FlagProbe(
    key: 'support_chat',
    label: 'Support chat',
    path: 'lib/core/config/feature_flags.dart',
    pattern: RegExp(
      r"bool\.fromEnvironment\(\s*'SUPPORT_CHAT_ENABLED'(?:\s*,\s*defaultValue:\s*(\w+))?",
    ),
    offNote:
        'No define is passed in any release build, and the control '
        'strings are tree-shaken out of the binary entirely.',
  ),
];

List<Metric> featureAvailabilityMetrics(RepoSources repo) {
  final List<Metric> metrics = <Metric>[];
  for (final FlagProbe probe in kFlagProbes) {
    final String? text = repo.read(probe.path);
    if (text == null || !probe.pattern.hasMatch(text)) {
      metrics.add(
        RepoSources.unreadable(
          probe.key,
          probe.label,
          probe.path,
          'The flag declaration could not be located, so its state is unknown. '
          'It is NOT assumed to be off.',
        ),
      );
      continue;
    }
    final String? explicitDefault = RepoSources.firstMatch(text, probe.pattern);
    // `bool.fromEnvironment` with no defaultValue is false by definition.
    final bool isOn = explicitDefault == 'true';
    metrics.add(
      Metric(
        key: probe.key,
        label: probe.label,
        // A subsystem that is off carries NO value — this is the rule the
        // whole dashboard exists to honour.
        state: isOn ? MetricState.derived : MetricState.disabled,
        value: isOn ? 'Enabled by default' : null,
        source: probe.path,
        note: isOn ? null : probe.offNote,
      ),
    );
  }
  return metrics;
}

// ---------------------------------------------------------------------------
// Sentry (engineering diagnostics) — separate from telemetry, deliberately
// ---------------------------------------------------------------------------

/// `String.fromEnvironment('CRASH_REPORTING_ENABLED',)` — no `defaultValue`,
/// so the gate defaults to the empty string and the subsystem stays off.
final RegExp kCrashEnabledDefine = RegExp(
  r"String\.fromEnvironment\(\s*'CRASH_REPORTING_ENABLED'\s*,?\s*\)",
);

/// Same for the DSN: define-only, never a committed default.
final RegExp kSentryDsnDefine = RegExp(
  r"String\.fromEnvironment\(\s*'SENTRY_DSN'\s*,?\s*\)",
);

List<Metric> sentryMetrics(RepoSources repo) {
  const String configPath = 'lib/core/crash/crash_config.dart';
  final String? text = repo.read(configPath);
  if (text == null) {
    return <Metric>[
      RepoSources.unreadable(
        'sentry_state',
        'Crash reporting',
        configPath,
        'Crash configuration source not found.',
      ),
    ];
  }

  // All three gates default to the empty string, which the config treats as
  // off. We assert the absence of a baked-in default rather than its value.
  // The `,?` matters: these calls are wrapped across lines by the formatter
  // and carry a trailing comma.
  final bool enabledDefaultsEmpty = kCrashEnabledDefine.hasMatch(text);
  final bool dsnDefaultsEmpty = kSentryDsnDefine.hasMatch(text);

  return <Metric>[
    Metric(
      key: 'sentry_state',
      label: 'Crash reporting (Sentry)',
      state: MetricState.disabled,
      source: configPath,
      note:
          'Three independent gates must all be satisfied by --dart-define '
          'and none is set in any release build: CRASH_REPORTING_ENABLED, a '
          'structurally valid SENTRY_DSN, and '
          'CRASH_REPORTING_PRODUCTION_APPROVED (required because the bundled '
          '.env declares production).',
    ),
    Metric(
      key: 'sentry_dsn_bundled',
      label: 'DSN present in the build',
      state: MetricState.derived,
      value: dsnDefaultsEmpty && enabledDefaultsEmpty
          ? 'No — define-only, never committed'
          : 'Unconfirmed — check the gate defaults',
      source: configPath,
      note:
          'The DSN can only arrive via --dart-define. It is absent from '
          '.env, from source and from the verified 215 binaries.',
    ),
    Metric(
      key: 'crash_free_rate',
      label: 'Crash-free session rate',
      // The point of the whole exercise: this is NOT "100%" and NOT "0".
      state: MetricState.notInstrumented,
      source: configPath,
      note:
          'Automatic session tracking is deliberately switched off, so no '
          'crash-free rate exists for any build. This figure cannot be '
          'produced until Sentry is enabled AND session tracking is '
          'separately approved.',
    ),
    Metric(
      key: 'native_crash_capture',
      label: 'Native crash capture',
      state: MetricState.disabled,
      source: 'lib/core/crash/sentry_crash_sink.dart',
      note:
          'Native envelopes bypass the beforeSend sanitiser, so native '
          'crash handling is switched off by design. Native fatals are '
          'therefore not reported even once Sentry is enabled.',
    ),
  ];
}

// ---------------------------------------------------------------------------
// Telemetry (product analytics) — separate from Sentry, deliberately
// ---------------------------------------------------------------------------

List<Metric> telemetryMetrics(RepoSources repo) {
  final String? envText = repo.read('.env');
  final Map<String, String> env = envText == null
      ? <String, String>{}
      : parseDotenv(envText);
  final String? enabled = env['TELEMETRY_ENABLED'];
  final String? approved = env['TELEMETRY_PRODUCTION_APPROVED'];

  final List<Metric> metrics = <Metric>[];

  if (enabled == null) {
    metrics.add(
      RepoSources.unreadable(
        'telemetry_state',
        'Product analytics',
        '.env',
        'TELEMETRY_ENABLED is absent.',
      ),
    );
  } else {
    metrics.add(
      Metric(
        key: 'telemetry_state',
        label: 'Product analytics (telemetry)',
        state: enabled.toLowerCase() == 'true'
            ? MetricState.derived
            : MetricState.disabled,
        value: enabled.toLowerCase() == 'true' ? 'Enabled' : null,
        source:
            '.env (TELEMETRY_ENABLED=$enabled, '
            'TELEMETRY_PRODUCTION_APPROVED=$approved)',
        note:
            'Two gates, both false in the bundled .env. There is also no '
            'TELEMETRY_BASE_URL, which fails the config closed independently.',
      ),
    );
  }

  metrics.addAll(<Metric>[
    Metric(
      key: 'telemetry_events_received',
      label: 'Events received',
      // Never "0" — nothing is sending, so there is no denominator.
      state: MetricState.disabled,
      source: 'lib/core/telemetry/telemetry_config.dart',
      note:
          'No events are emitted by any build. "0 events" would wrongly '
          'imply a working pipeline reporting no activity.',
    ),
    Metric(
      key: 'telemetry_consent',
      label: 'Analytics consent decision',
      state: MetricState.notVerified,
      source: 'docs/TELEMETRY_MOBILE.md §9',
      note:
          'Unresolved. Owner: Product / Privacy. Required before any '
          'external cohort. No consent flow exists in the app.',
    ),
    Metric(
      key: 'telemetry_backend',
      label: 'Telemetry backend endpoint',
      state: MetricState.disabled,
      source: 'POST /v1/telemetry/events',
      note:
          'The staging backend returns 503 telemetry_disabled. The endpoint '
          'is not accepting events, by the backend\'s own configuration.',
    ),
  ]);

  return metrics;
}

// ---------------------------------------------------------------------------
// Clinical
// ---------------------------------------------------------------------------

List<Metric> clinicalMetrics(RepoSources repo) {
  final List<Metric> metrics = <Metric>[];

  final String? findingsText = repo.read('test/fixtures/known_findings.json');
  if (findingsText == null) {
    metrics.add(
      RepoSources.unreadable(
        'known_findings',
        'Open clinical findings',
        'test/fixtures/known_findings.json',
        'The known-findings registry is missing.',
      ),
    );
  } else {
    try {
      final Map<String, Object?> parsed =
          jsonDecode(findingsText) as Map<String, Object?>;
      final List<Object?> findings =
          (parsed['findings'] as List<Object?>? ?? const <Object?>[]);
      final List<String> ids = findings
          .whereType<Map<String, Object?>>()
          .map((Map<String, Object?> f) => '${f['id'] ?? f['case_id'] ?? '?'}')
          .toList();
      metrics.add(
        Metric(
          key: 'known_findings',
          label: 'Open clinical findings',
          state: MetricState.derived,
          value: ids.isEmpty ? 'None' : '${ids.length} — ${ids.join(', ')}',
          source: 'test/fixtures/known_findings.json',
          note:
              'Tracked findings carried by the shipped engine. Each one '
              'needs clinical adjudication before an external cohort.',
        ),
      );
    } on FormatException catch (e) {
      metrics.add(
        RepoSources.unreadable(
          'known_findings',
          'Open clinical findings',
          'test/fixtures/known_findings.json',
          'Registry is not valid JSON: $e',
        ),
      );
    }
  }

  final String? caseBank = repo.read('test/fixtures/case_bank_v1.json');
  if (caseBank == null) {
    metrics.add(
      RepoSources.unreadable(
        'case_bank_size',
        'Clinical case bank',
        'test/fixtures/case_bank_v1.json',
        'Case bank fixture missing.',
      ),
    );
  } else {
    try {
      final Map<String, Object?> parsed =
          jsonDecode(caseBank) as Map<String, Object?>;
      final List<Object?> cases =
          (parsed['cases'] as List<Object?>? ?? const <Object?>[]);
      metrics.add(
        Metric(
          key: 'case_bank_size',
          label: 'Clinical case bank',
          state: MetricState.derived,
          value: '${cases.length} cases',
          source: 'test/fixtures/case_bank_v1.json',
          note:
              'The committed input. The pass/fail result is produced by '
              'running the suite — see the regression metric.',
        ),
      );
    } on FormatException catch (e) {
      metrics.add(
        RepoSources.unreadable(
          'case_bank_size',
          'Clinical case bank',
          'test/fixtures/case_bank_v1.json',
          'Fixture is not valid JSON: $e',
        ),
      );
    }
  }

  // The regression RESULT is generated into build/ and gitignored, so it is
  // genuinely absent unless the suite has been run in this checkout.
  final File report = File(
    repo.path('build/e8_case_bank/case_bank_results_v1.json'),
  );
  if (!report.existsSync()) {
    metrics.add(
      Metric(
        key: 'clinical_regression',
        label: 'Clinical regression result',
        state: MetricState.awaitingData,
        source: 'build/e8_case_bank/case_bank_results_v1.json',
        note:
            'The harness writes this file only when the suite runs, and it '
            'is gitignored. Run `flutter test '
            'test/engine/case_bank_validation_test.dart` in this checkout to '
            'populate it. No remembered figure is shown here.',
      ),
    );
  } else {
    try {
      final Map<String, Object?> parsed =
          jsonDecode(report.readAsStringSync()) as Map<String, Object?>;
      final Map<String, Object?> classification =
          (parsed['classification'] as Map<String, Object?>? ??
          <String, Object?>{});
      final Object? executed = classification['executed'];
      final Object? passed = classification['passed'];
      final Object? known = classification['known_findings'];
      final Object? unexpected = classification['unexpected_failures'];
      metrics.add(
        Metric(
          key: 'clinical_regression',
          label: 'Clinical regression result',
          state: MetricState.live,
          value:
              '$executed executed · $passed passed · $known known · '
              '$unexpected unexpected',
          source: 'build/e8_case_bank/case_bank_results_v1.json',
          observedAt: report.lastModifiedSync().toUtc(),
        ),
      );
    } on Object catch (e) {
      metrics.add(
        RepoSources.unreadable(
          'clinical_regression',
          'Clinical regression result',
          'build/e8_case_bank/case_bank_results_v1.json',
          'Report present but unreadable: $e',
        ),
      );
    }
  }

  return metrics;
}

// ---------------------------------------------------------------------------
// Facility data
// ---------------------------------------------------------------------------

List<Metric> facilityMetrics(RepoSources repo) {
  const String frozen = 'docs/release/RC_FROZEN_INPUTS.json';
  final String? text = repo.read(frozen);
  if (text == null) {
    return <Metric>[
      RepoSources.unreadable(
        'facilities_version',
        'Facility dataset',
        frozen,
        'Frozen-inputs record missing.',
      ),
    ];
  }
  try {
    final Map<String, Object?> parsed =
        jsonDecode(text) as Map<String, Object?>;
    final Map<String, Object?> artifacts =
        (parsed['active_artifacts'] as Map<String, Object?>? ??
        <String, Object?>{});
    final Map<String, Object?> facilities =
        (artifacts['facilities'] as Map<String, Object?>? ??
        <String, Object?>{});
    final Object? version = facilities['version'];
    final Object? generated = parsed['generated_utc'];
    if (version == null) {
      return <Metric>[
        RepoSources.unreadable(
          'facilities_version',
          'Facility dataset',
          frozen,
          'No facilities entry in active_artifacts.',
        ),
      ];
    }
    return <Metric>[
      Metric(
        key: 'facilities_version',
        label: 'Facility dataset (frozen record)',
        state: MetricState.derived,
        value: 'v$version · ${facilities['record_count'] ?? '?'} records',
        source: frozen,
        note:
            'This is the frozen snapshot taken $generated, NOT what /config '
            'serves today. The app pins no facilities version — it uses '
            'whatever /config names. Run with --probe to check the live '
            'value.',
      ),
      Metric(
        key: 'facilities_coverage',
        label: 'Facility coverage',
        state: MetricState.derived,
        value: facilities['coverage_is_national'] == true
            ? 'National'
            : 'Partial — ${(facilities['coverage_states'] as Map<String, Object?>? ?? <String, Object?>{}).keys.join(', ')}',
        source: frozen,
        note:
            'Coverage is not national. Users outside these states will find '
            'no nearby facility.',
      ),
    ];
  } on FormatException catch (e) {
    return <Metric>[
      RepoSources.unreadable(
        'facilities_version',
        'Facility dataset',
        frozen,
        'Not valid JSON: $e',
      ),
    ];
  }
}
