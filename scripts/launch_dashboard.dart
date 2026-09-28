/// Internal launch command centre — generator.
///
/// Usage:
///   dart run scripts/launch_dashboard.dart [options]
///
/// Options:
///   --probe          Also measure the live production /config endpoint.
///                    Off by default so an ordinary run is deterministic and
///                    works offline.
///   --out=DIR        Output directory (default: docs/launch).
///   --root=DIR       Repository root (default: the current directory).
///   --stdout-summary Print a short text summary as well.
///
/// Exit codes: 0 generated · 2 could not generate (fail closed).
///
/// This tool is NOT part of the shipping application. It imports nothing from
/// `lib/`, adds no bytes to any build, and reads no patient or symptom data of
/// any kind — only build metadata, configuration flags, committed fixtures and
/// the hand-entered notes in `docs/launch/manual_status.json`.
library;

import 'dart:convert';
import 'dart:io';

import 'launch_status_inputs.dart';
import 'launch_status_model.dart';
import 'launch_status_render.dart';
import 'launch_status_sources.dart';

Future<void> main(List<String> args) async {
  bool probe = false;
  String outDir = 'docs/launch';
  String root = Directory.current.path;
  bool summary = false;

  for (final String arg in args) {
    if (arg == '--probe') {
      probe = true;
    } else if (arg == '--stdout-summary') {
      summary = true;
    } else if (arg.startsWith('--out=')) {
      outDir = arg.substring('--out='.length);
    } else if (arg.startsWith('--root=')) {
      root = arg.substring('--root='.length);
    } else if (arg == '-h' || arg == '--help') {
      stdout.writeln(
        'dart run scripts/launch_dashboard.dart '
        '[--probe] [--out=DIR] [--root=DIR] [--stdout-summary]',
      );
      return;
    } else {
      stderr.writeln('launch_dashboard: unknown option "$arg"');
      exitCode = 2;
      return;
    }
  }

  final RepoSources repo = RepoSources(Directory(root));
  if (!File(repo.path('pubspec.yaml')).existsSync()) {
    stderr.writeln(
      'launch_dashboard: $root does not look like the repository '
      'root (no pubspec.yaml). Refusing to guess.',
    );
    exitCode = 2;
    return;
  }

  final DateTime now = DateTime.now().toUtc();
  final ManualStatus manual = ManualStatus.load(repo);

  // --- live probe (opt-in) ------------------------------------------------
  ProbeResult? probeResult;
  // The committed canonical baseline for /config, if one is recorded.
  String? baselineSha;
  final String? frozenText = repo.read('docs/release/RC_FROZEN_INPUTS.json');
  if (frozenText != null) {
    try {
      final Map<String, Object?> frozen =
          jsonDecode(frozenText) as Map<String, Object?>;
      final Map<String, Object?> backend =
          (frozen['backend_baseline'] as Map<String, Object?>? ??
          <String, Object?>{});
      baselineSha = backend['config_canonical_sha256_declared'] as String?;
    } on FormatException {
      baselineSha = null;
    }
  }
  if (probe) {
    final String? envText = repo.read('.env');
    final String? base = envText == null
        ? null
        : parseDotenv(envText)['API_BASE_URL'];
    if (base == null || base.isEmpty) {
      stderr.writeln(
        'launch_dashboard: --probe requested but API_BASE_URL is '
        'absent from .env; skipping the probe rather than guessing a host.',
      );
    } else {
      probeResult = await probeConfig(base);
    }
  }

  // --- panels -------------------------------------------------------------
  final List<Panel> panels = <Panel>[
    Panel(
      key: 'builds',
      title: 'Build status',
      summary: 'What exists, and what number the next build would take.',
      metrics: <Metric>[
        ...buildIdentityMetrics(repo),
        manual.lookup(
          'ios_processing_status',
          'iOS 215 App Store Connect processing',
          now,
        ),
        manual.lookup(
          'ios_build_visible',
          'iOS 215 visible as 0.3.0 (215)',
          now,
        ),
        manual.lookup(
          'android_215_uploaded',
          'Android 215 uploaded to Play Internal testing',
          now,
        ),
      ],
    ),
    Panel(
      key: 'testers',
      title: 'Internal tester availability',
      summary:
          'Console state. Nothing here can be observed from the '
          'repository.',
      metrics: <Metric>[
        manual.lookup(
          'ios_internal_tester_availability',
          'iOS 215 internal testers',
          now,
        ),
        manual.lookup(
          'android_internal_tester_availability',
          'Android internal testers',
          now,
        ),
        manual.lookup(
          'ios_211_still_available',
          'iOS 211 still available and unexpired',
          now,
        ),
        manual.lookup(
          'android_211_live_release',
          'Android 211 live on Internal testing',
          now,
        ),
        manual.lookup(
          'play_app_signing_prompt',
          'Play App Signing enrolment prompt absent',
          now,
        ),
      ],
    ),
    Panel(
      key: 'clinical',
      title: 'Clinical review',
      summary:
          'The engine is a decision-support tool; every open finding '
          'gates external users.',
      metrics: <Metric>[
        manual.lookup('clinical_review_status', 'Clinical review', now),
        ...clinicalMetrics(repo),
      ],
    ),
    Panel(
      key: 'devices',
      title: 'Physical-device smoke tests',
      summary: 'Emulator and CI runs do not substitute for a real handset.',
      metrics: <Metric>[
        manual.lookup(
          'device_smoke_test_android',
          'Physical Android device',
          now,
        ),
        manual.lookup('device_smoke_test_ios', 'Physical iOS device', now),
      ],
    ),
    Panel(
      key: 'api',
      title: 'Production API and configuration',
      summary:
          'The app pins no artifact versions — it uses whatever /config '
          'names, so this is what actually determines behaviour.',
      metrics: <Metric>[
        ...environmentMetrics(repo),
        ...probeMetrics(probeResult, baselineSha256: baselineSha),
      ],
    ),
    Panel(
      key: 'facilities',
      title: 'Facility data',
      metrics: facilityMetrics(repo),
    ),
    Panel(
      key: 'feedback',
      title: 'Feedback and support',
      summary:
          'Both are compile-time gated off and tree-shaken out of the '
          'binary.',
      metrics: <Metric>[
        ...featureAvailabilityMetrics(repo),
        manual.lookup('support_contact', 'Support contact', now),
        manual.lookup('privacy_policy_url', 'Published privacy policy', now),
      ],
    ),
    Panel(
      key: 'sentry',
      title: 'Sentry — engineering diagnostics',
      summary:
          'Crash reporting. Deliberately kept separate from product '
          'analytics: different purpose, different data, different gates.',
      metrics: sentryMetrics(repo),
    ),
    Panel(
      key: 'telemetry',
      title: 'Telemetry — product analytics',
      summary:
          'Anonymous aggregate product usage. Never symptoms, answers, '
          'results or location.',
      metrics: telemetryMetrics(repo),
    ),
  ];

  final LaunchStatus status = LaunchStatus(
    generatedAt: now,
    commit: _git(root, <String>['rev-parse', '--short', 'HEAD']) ?? 'unknown',
    branch:
        _git(root, <String>['rev-parse', '--abbrev-ref', 'HEAD']) ?? 'unknown',
    panels: panels,
    actions: loadActions(repo),
    probesAttempted: probeResult != null,
  );

  // --- write --------------------------------------------------------------
  final Directory out = Directory('${repo.root.path}/$outDir');
  out.createSync(recursive: true);

  final File json = File('${out.path}/LAUNCH_STATUS.json');
  json.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(status.toJson())}\n',
  );

  final File html = File('${out.path}/launch_dashboard.html');
  html.writeAsStringSync(renderDashboard(status));

  stdout.writeln('launch_dashboard: wrote ${json.path}');
  stdout.writeln('launch_dashboard: wrote ${html.path}');

  if (summary) {
    stdout.writeln('');
    for (final Panel p in status.panels) {
      stdout.writeln(
        '[${p.kind.label.toLowerCase().padRight(10)}] '
        '${p.title}',
      );
      for (final Metric m in p.metrics) {
        stdout.writeln('    ${m.label.padRight(42)} ${m.display}');
      }
    }
    stdout.writeln('');
    stdout.writeln(
      '${status.blockers.length} blocker(s), '
      '${status.actions.length} outstanding action(s).',
    );
  }
}

String? _git(String root, List<String> args) {
  try {
    final ProcessResult r = Process.runSync(
      'git',
      args,
      workingDirectory: root,
    );
    if (r.exitCode != 0) {
      return null;
    }
    final String s = '${r.stdout}'.trim();
    return s.isEmpty ? null : s;
  } on ProcessException {
    return null;
  }
}
