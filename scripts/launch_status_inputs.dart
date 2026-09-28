/// Human-entered facts and the live production probe.
///
/// These are the two sources that are NOT the repository itself: testimony
/// (`docs/launch/manual_status.json`) and a live HTTP measurement of the
/// production config endpoint. Both are treated with more suspicion than a
/// committed file, not less:
///
///  * every manual entry is rendered with a MANUAL badge, the observer's name
///    and the observation date, and expires into "Not verified" once it is
///    past the file's freshness window;
///  * the probe runs only when explicitly requested, and a probe that is not
///    run leaves its metrics "Not verified" rather than reusing an old result.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'launch_status_model.dart';
import 'launch_status_sources.dart';

// ---------------------------------------------------------------------------
// Manual entries
// ---------------------------------------------------------------------------

/// The states a manual-status entry is allowed to declare.
const Set<String> kAllowedManualStates = <String>{
  'manual',
  'notVerified',
  'disabled',
  'notInstrumented',
  'awaitingData',
};

class ManualStatus {
  ManualStatus({required this.entries, required this.freshnessWindow});

  final Map<String, Metric> entries;
  final Duration freshnessWindow;

  /// Returns the metric for [key], aged against [now], or a `notVerified`
  /// placeholder when the key is absent. A missing manual fact is an absent
  /// fact, never an implied-good one.
  Metric lookup(String key, String label, DateTime now) {
    final Metric? found = entries[key];
    if (found == null) {
      return Metric(
        key: key,
        label: label,
        state: MetricState.notVerified,
        source: 'docs/launch/manual_status.json',
        note: 'No entry for "$key". Nobody has recorded this.',
      );
    }
    return found.agedAt(now, freshnessWindow);
  }

  static ManualStatus load(RepoSources repo) {
    const String path = 'docs/launch/manual_status.json';
    final String? text = repo.read(path);
    if (text == null) {
      return ManualStatus(
        entries: const <String, Metric>{},
        freshnessWindow: const Duration(days: 14),
      );
    }
    final Map<String, Object?> parsed =
        jsonDecode(text) as Map<String, Object?>;
    final int windowDays =
        (parsed['freshness_window_days'] as num?)?.toInt() ?? 14;
    final Map<String, Object?> raw =
        (parsed['entries'] as Map<String, Object?>? ?? <String, Object?>{});

    final Map<String, Metric> out = <String, Metric>{};
    raw.forEach((String key, Object? value) {
      if (value is! Map<String, Object?>) {
        return;
      }
      final String stateName = '${value['state']}';
      if (!kAllowedManualStates.contains(stateName)) {
        throw FormatException(
          'manual entry "$key" declares state "$stateName", which is not one '
          'of ${kAllowedManualStates.join(', ')}. A hand-entered fact may '
          'never claim to be a live or derived measurement.',
        );
      }
      final String? observedRaw = value['observed_at'] as String?;
      out[key] = Metric(
        key: key,
        label: '${value['label'] ?? key}',
        state: MetricState.byName(stateName),
        value: value['value'] as String?,
        source: value['source'] as String?,
        observer: value['observer'] as String?,
        observedAt: observedRaw == null ? null : DateTime.parse(observedRaw),
        note: value['note'] as String?,
      );
    });
    return ManualStatus(
      entries: out,
      freshnessWindow: Duration(days: windowDays),
    );
  }
}

// ---------------------------------------------------------------------------
// Live production probe
// ---------------------------------------------------------------------------

/// Result of probing the production `/config` endpoint.
class ProbeResult {
  ProbeResult({
    required this.url,
    required this.at,
    this.statusCode,
    this.bytes,
    this.sha256Hex,
    this.canonicalSha256Hex,
    this.artifactVersions,
    this.error,
  });

  final String url;
  final DateTime at;
  final int? statusCode;
  final int? bytes;

  /// sha256 of the bytes exactly as served.
  final String? sha256Hex;

  /// sha256 of the canonical form: JSON re-serialised with recursively sorted
  /// keys and compact separators, UTF-8, no trailing newline. This is the
  /// figure the release baseline records, because it survives insignificant
  /// re-serialisation by the backend while still catching a real content
  /// change.
  final String? canonicalSha256Hex;

  final Map<String, String>? artifactVersions;
  final String? error;

  bool get ok => error == null && statusCode == 200;
}

/// Recursively sorts map keys so a canonical encoding is stable.
Object? canonicalise(Object? value) {
  if (value is Map) {
    final List<String> keys = value.keys.map((Object? k) => '$k').toList()
      ..sort();
    return <String, Object?>{
      for (final String k in keys) k: canonicalise(value[k]),
    };
  }
  if (value is List) {
    return value.map(canonicalise).toList();
  }
  return value;
}

/// The canonical encoding whose sha256 the release baseline records.
String canonicalJson(Object? value) => jsonEncode(canonicalise(value));

/// Fetches `<apiBaseUrl>/config` and summarises it.
///
/// The response body is hashed and its artifact versions read, but the body
/// itself is never logged or written anywhere — the same discipline the app's
/// own networking layer follows.
Future<ProbeResult> probeConfig(
  String apiBaseUrl, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final String url = '${apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/config';
  final DateTime at = DateTime.now().toUtc();
  final HttpClient client = HttpClient()..connectionTimeout = timeout;
  try {
    final HttpClientRequest request = await client
        .getUrl(Uri.parse(url))
        .timeout(timeout);
    final HttpClientResponse response = await request.close().timeout(timeout);
    final List<int> body = await response
        .fold<List<int>>(<int>[], (List<int> a, List<int> b) {
          a.addAll(b);
          return a;
        })
        .timeout(timeout);

    Map<String, String>? versions;
    String? canonicalHex;
    try {
      final Object? parsed = jsonDecode(utf8.decode(body));
      canonicalHex = sha256
          .convert(utf8.encode(canonicalJson(parsed)))
          .toString();
      if (parsed is Map<String, Object?>) {
        final Object? artifacts = parsed['artifacts'];
        if (artifacts is Map<String, Object?>) {
          versions = <String, String>{
            for (final MapEntry<String, Object?> e in artifacts.entries)
              if (e.value is Map<String, Object?>)
                e.key: '${(e.value as Map<String, Object?>)['version']}',
          };
        }
      }
    } on Object {
      versions = null;
      canonicalHex = null;
    }

    return ProbeResult(
      url: url,
      at: at,
      statusCode: response.statusCode,
      bytes: body.length,
      sha256Hex: sha256.convert(body).toString(),
      canonicalSha256Hex: canonicalHex,
      artifactVersions: versions,
    );
  } on Object catch (e) {
    return ProbeResult(url: url, at: at, error: '$e');
  } finally {
    client.close(force: true);
  }
}

/// Turns a probe into metrics, or into honest absences when no probe ran.
List<Metric> probeMetrics(ProbeResult? probe, {String? baselineSha256}) {
  if (probe == null) {
    return <Metric>[
      Metric(
        key: 'config_endpoint',
        label: 'Production /config reachability',
        state: MetricState.notVerified,
        note:
            'No probe was run. Re-run with --probe to measure it. The last '
            'known result is deliberately not shown, because a stale '
            'reachability check is indistinguishable from a current one.',
      ),
      Metric(
        key: 'config_integrity',
        label: 'Production /config integrity',
        state: MetricState.notVerified,
        note: 'No probe was run.',
      ),
    ];
  }

  final List<Metric> metrics = <Metric>[
    Metric(
      key: 'config_endpoint',
      label: 'Production /config reachability',
      state: probe.ok ? MetricState.live : MetricState.notVerified,
      value: probe.ok ? 'HTTP ${probe.statusCode} · ${probe.bytes} B' : null,
      source: probe.url,
      observedAt: probe.ok ? probe.at : null,
      note: probe.ok
          ? null
          : 'Probe failed: ${probe.error ?? 'HTTP ${probe.statusCode}'}. '
                'Treated as unverified, not as an outage — the failure may be '
                'local.',
    ),
  ];

  if (probe.ok && baselineSha256 != null && probe.canonicalSha256Hex != null) {
    final bool match = probe.canonicalSha256Hex == baselineSha256;
    metrics.add(
      Metric(
        key: 'config_integrity',
        label: 'Production /config integrity',
        state: MetricState.live,
        value: match
            ? 'Matches frozen baseline'
            : 'DIFFERS from frozen baseline',
        source: probe.url,
        observedAt: probe.at,
        note: match
            ? 'Canonical sha256 ${probe.canonicalSha256Hex!.substring(0, 12)}… '
                  '— compared in canonical form (recursively sorted keys, '
                  'compact separators), so harmless re-serialisation by the '
                  'backend does not raise a false alarm.'
            : 'Served canonical sha256 '
                  '${probe.canonicalSha256Hex!.substring(0, 12)}… vs baseline '
                  '${baselineSha256.substring(0, 12)}…. A change is not '
                  'necessarily wrong, but it must be accounted for before a '
                  'release.',
      ),
    );
  } else {
    metrics.add(
      Metric(
        key: 'config_integrity',
        label: 'Production /config integrity',
        state: MetricState.notVerified,
        note: probe.ok
            ? 'No committed baseline hash to compare against.'
            : 'Probe did not succeed.',
      ),
    );
  }

  if (probe.ok && probe.artifactVersions != null) {
    final Map<String, String> v = probe.artifactVersions!;
    metrics.add(
      v.isEmpty
          ? Metric(
              key: 'served_artifacts',
              label: 'Artifacts served by /config',
              state: MetricState.notVerified,
              source: probe.url,
              note: 'The response carried no parseable artifacts block.',
            )
          : Metric(
              key: 'served_artifacts',
              label: 'Artifacts served by /config',
              state: MetricState.live,
              value: v.entries
                  .map((MapEntry<String, String> e) => '${e.key} ${e.value}')
                  .join(' · '),
              source: probe.url,
              observedAt: probe.at,
            ),
    );
  }

  return metrics;
}

// ---------------------------------------------------------------------------
// Outstanding launch actions
// ---------------------------------------------------------------------------

/// Loads the committed action register, then appends checks the repository can
/// make for itself.
List<LaunchAction> loadActions(RepoSources repo) {
  const String path = 'docs/launch/launch_actions.json';
  final List<LaunchAction> actions = <LaunchAction>[];

  final String? text = repo.read(path);
  if (text != null) {
    final Map<String, Object?> parsed =
        jsonDecode(text) as Map<String, Object?>;
    for (final Object? raw
        in (parsed['actions'] as List<Object?>? ?? const <Object?>[])) {
      if (raw is! Map<String, Object?>) {
        continue;
      }
      actions.add(
        LaunchAction(
          id: '${raw['id']}',
          title: '${raw['title']}',
          owner: '${raw['owner']}',
          severity: Severity.byName('${raw['severity']}'),
          state: MetricState.manual,
          reference: raw['reference'] as String?,
          note: raw['note'] as String?,
        ),
      );
    }
  }

  actions.addAll(derivedActions(repo));
  return actions;
}

/// Checks the repository can perform on itself, so they never go stale.
List<LaunchAction> derivedActions(RepoSources repo) {
  final List<LaunchAction> out = <LaunchAction>[];

  final String? pubspec = repo.read('pubspec.yaml');
  final String? version = RepoSources.firstMatch(pubspec, kPubspecVersion);
  final String? identity = repo.read(kBuildIdentityPath);
  final String? current = RepoSources.firstMatch(identity, kCurrentBuildConst);

  if (version != null && current != null) {
    final String pubspecBuild = version.split('+').last;
    if (pubspecBuild != current) {
      out.add(
        LaunchAction(
          id: 'DERIVED-BUILD-MISMATCH',
          title:
              'pubspec build $pubspecBuild does not match '
              'kCurrentBuildNumber $current',
          owner: 'Engineering',
          severity: Severity.blocker,
          state: MetricState.derived,
          reference: kBuildIdentityPath,
        ),
      );
    }
  }

  // The stale-comment check: prose inside pubspec that names a build number
  // other than the real one has already caused a wrong conclusion once.
  if (pubspec != null && version != null) {
    final String pubspecBuild = version.split('+').last;
    final Iterable<RegExpMatch> commentNumbers = RegExp(
      r'^\s*#.*?\b(2[01]\d)\b',
      multiLine: true,
    ).allMatches(pubspec);
    final Set<String> mentioned = commentNumbers
        .map((RegExpMatch m) => m.group(1)!)
        .where((String n) => n != pubspecBuild)
        .toSet();
    if (mentioned.isNotEmpty) {
      out.add(
        LaunchAction(
          id: 'DERIVED-STALE-PUBSPEC-COMMENT',
          title:
              'pubspec comments mention build ${mentioned.join(', ')} '
              'while the version line is $pubspecBuild',
          owner: 'Engineering',
          severity: Severity.low,
          state: MetricState.derived,
          reference: 'pubspec.yaml',
          note:
              'Prose only — the version line and the registry constant are '
              'authoritative. Worth correcting so a reader is not misled.',
        ),
      );
    }
  }

  return out;
}
