/// Tests for the internal launch command centre.
///
/// Two kinds of test live here, and the second kind is the important one:
///
///  1. Invariant tests — a metric in a non-reporting state can never carry a
///     value, and the rendered page can never print a bare `0` for one. These
///     are the reason the tool exists.
///  2. Source-pattern pins — the readers parse real Dart and dotenv files with
///     strict regular expressions. Each pattern is exercised against the
///     actual file in this repository, so a rename upstream fails the build
///     instead of silently degrading every panel to "Not verified".
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/launch_status_inputs.dart';
import '../../scripts/launch_status_model.dart';
import '../../scripts/launch_status_render.dart';
import '../../scripts/launch_status_sources.dart';

RepoSources get repo => RepoSources(Directory.current);

void main() {
  group('the central invariant — a non-reporting state carries no value', () {
    for (final MetricState state in MetricState.values.where(
      (MetricState s) => !s.carriesValue,
    )) {
      test('${state.name} rejects a value', () {
        expect(
          () => Metric(key: 'k', label: 'l', state: state, value: '0'),
          throwsA(isA<MetricInvariantError>()),
        );
      });

      test('${state.name} renders its word, never a zero', () {
        final Metric m = Metric(key: 'k', label: 'l', state: state);
        expect(m.display, state.label);
        expect(m.display, isNot('0'));
        expect(m.value, isNull);
      });
    }

    test('a reporting state rejects an empty value', () {
      expect(
        () => Metric(
          key: 'k',
          label: 'l',
          state: MetricState.derived,
          value: '   ',
        ),
        throwsA(isA<MetricInvariantError>()),
      );
    });

    test('a manual metric must name an observer and a date', () {
      expect(
        () => Metric(
          key: 'k',
          label: 'l',
          state: MetricState.manual,
          value: 'yes',
          observedAt: DateTime.utc(2026, 9, 25),
        ),
        throwsA(isA<MetricInvariantError>()),
      );
      expect(
        () => Metric(
          key: 'k',
          label: 'l',
          state: MetricState.manual,
          value: 'yes',
          observer: 'Founder',
        ),
        throwsA(isA<MetricInvariantError>()),
      );
    });

    test('a live metric must record when it was measured', () {
      expect(
        () => Metric(
          key: 'k',
          label: 'l',
          state: MetricState.live,
          value: 'HTTP 200',
        ),
        throwsA(isA<MetricInvariantError>()),
      );
    });
  });

  group('manual facts expire rather than quietly persisting', () {
    final Metric signOff = Metric(
      key: 'clinical_review_status',
      label: 'Clinical review',
      state: MetricState.manual,
      value: 'Approved',
      observer: 'Reviewer',
      observedAt: DateTime.utc(2026, 9, 1),
    );

    test('stays manual inside the window', () {
      final Metric aged = signOff.agedAt(
        DateTime.utc(2026, 9, 10),
        const Duration(days: 14),
      );
      expect(aged.state, MetricState.manual);
      expect(aged.display, 'Approved');
    });

    test('becomes Not verified past the window, losing the value', () {
      final Metric aged = signOff.agedAt(
        DateTime.utc(2026, 10, 1),
        const Duration(days: 14),
      );
      expect(aged.state, MetricState.notVerified);
      expect(aged.value, isNull);
      expect(aged.display, 'Not verified');
      // The original observation is preserved so nothing is lost, only
      // demoted.
      expect(aged.note, contains('2026-09-01'));
      expect(aged.note, contains('Reviewer'));
    });
  });

  group('panel labelling is worst-fact-wins', () {
    Metric derived(String k) =>
        Metric(key: k, label: k, state: MetricState.derived, value: 'v');
    Metric live(String k) => Metric(
      key: k,
      label: k,
      state: MetricState.live,
      value: 'v',
      observedAt: DateTime.utc(2026, 9, 25),
    );
    Metric manual(String k) => Metric(
      key: k,
      label: k,
      state: MetricState.manual,
      value: 'v',
      observer: 'Founder',
      observedAt: DateTime.utc(2026, 9, 25),
    );
    Metric absent(String k) =>
        Metric(key: k, label: k, state: MetricState.notVerified);

    test('all derived -> Derived', () {
      expect(
        Panel(key: 'p', title: 'p', metrics: <Metric>[derived('a')]).kind,
        PanelKind.derived,
      );
    });

    test('derived plus a live measurement -> Live', () {
      expect(
        Panel(
          key: 'p',
          title: 'p',
          metrics: <Metric>[derived('a'), live('b')],
        ).kind,
        PanelKind.live,
      );
    });

    test('any manual fact -> Manual, even alongside live ones', () {
      expect(
        Panel(
          key: 'p',
          title: 'p',
          metrics: <Metric>[live('a'), manual('b')],
        ).kind,
        PanelKind.manual,
      );
    });

    test('any missing fact -> Incomplete, outranking everything', () {
      expect(
        Panel(
          key: 'p',
          title: 'p',
          metrics: <Metric>[live('a'), manual('b'), absent('c')],
        ).kind,
        PanelKind.incomplete,
      );
    });

    test('a disabled subsystem is Derived, not Incomplete', () {
      // "Switched off" is a real, established fact about the build — the
      // panel is accurate, not missing.
      expect(
        Panel(
          key: 'p',
          title: 'p',
          metrics: <Metric>[
            Metric(key: 'x', label: 'x', state: MetricState.disabled),
          ],
        ).kind,
        PanelKind.derived,
      );
    });

    test('an empty panel is Incomplete, never Live', () {
      expect(
        Panel(key: 'p', title: 'p', metrics: const <Metric>[]).kind,
        PanelKind.incomplete,
      );
    });
  });

  group('the rendered page never prints a bare zero for an absent fact', () {
    test('every off-state metric renders its word', () {
      final LaunchStatus status = LaunchStatus(
        generatedAt: DateTime.utc(2026, 9, 28),
        commit: 'abc1234',
        branch: 'test',
        panels: <Panel>[
          Panel(
            key: 'p',
            title: 'Subsystems',
            metrics: <Metric>[
              Metric(key: 'a', label: 'Crashes', state: MetricState.disabled),
              Metric(
                key: 'b',
                label: 'Sessions',
                state: MetricState.notInstrumented,
              ),
              Metric(
                key: 'c',
                label: 'Events',
                state: MetricState.awaitingData,
              ),
              Metric(key: 'd', label: 'Review', state: MetricState.notVerified),
            ],
          ),
        ],
        actions: const <LaunchAction>[],
      );
      final String html = renderDashboard(status);

      for (final String word in <String>[
        'Disabled',
        'Not instrumented',
        'Awaiting data',
        'Not verified',
      ]) {
        expect(html, contains(word), reason: '"$word" must appear verbatim');
      }
      // No metric value cell may contain a lone zero.
      expect(
        RegExp(r'<div class="m-value[^"]*">\s*0\s*</div>').hasMatch(html),
        isFalse,
        reason: 'a metric rendered as a bare 0',
      );
    });

    test('html-escapes hostile text in a manual note', () {
      final LaunchStatus status = LaunchStatus(
        generatedAt: DateTime.utc(2026, 9, 28),
        commit: 'abc1234',
        branch: 'test',
        panels: <Panel>[
          Panel(
            key: 'p',
            title: 'p',
            metrics: <Metric>[
              Metric(
                key: 'a',
                label: '<script>alert(1)</script>',
                state: MetricState.notVerified,
                note: '<img onerror=x>',
              ),
            ],
          ),
        ],
        actions: const <LaunchAction>[],
      );
      final String html = renderDashboard(status);
      expect(html, isNot(contains('<script>alert(1)</script>')));
      expect(html, isNot(contains('<img onerror=x>')));
      expect(html, contains('&lt;script&gt;'));
    });
  });

  group('source patterns still match the real files', () {
    test('pubspec version line parses and ignores the comment above it', () {
      final String? text = repo.read('pubspec.yaml');
      expect(text, isNotNull);
      final String? version = RepoSources.firstMatch(text, kPubspecVersion);
      expect(
        version,
        isNotNull,
        reason: 'the `version:` line no longer matches',
      );
      expect(version, matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')));
    });

    test('the build registry and current-build constant still parse', () {
      final String? text = repo.read(kBuildIdentityPath);
      expect(text, isNotNull, reason: '$kBuildIdentityPath moved');
      expect(
        RepoSources.firstMatch(text, kCurrentBuildConst),
        isNotNull,
        reason: 'kCurrentBuildNumber no longer matches',
      );
      expect(
        kRegistryEntry.allMatches(text!).length,
        greaterThan(1),
        reason: 'kKnownDistributedBuilds entries no longer match',
      );
    });

    test('the Sentry gate defines are still define-only', () {
      final String? text = repo.read('lib/core/crash/crash_config.dart');
      expect(text, isNotNull);
      expect(
        kCrashEnabledDefine.hasMatch(text!),
        isTrue,
        reason:
            'CRASH_REPORTING_ENABLED gained a default or was renamed — '
            'if it gained a default, that is a release-blocking change',
      );
      expect(
        kSentryDsnDefine.hasMatch(text),
        isTrue,
        reason: 'SENTRY_DSN gained a committed default or was renamed',
      );
    });

    test('every feature-flag probe still finds its declaration', () {
      for (final FlagProbe probe in kFlagProbes) {
        final String? text = repo.read(probe.path);
        expect(text, isNotNull, reason: '${probe.path} moved');
        expect(
          probe.pattern.hasMatch(text!),
          isTrue,
          reason: '${probe.key} flag declaration no longer matches',
        );
      }
    });

    test('the tracked .env parses and still declares both gates off', () {
      final String? text = repo.read('.env');
      expect(text, isNotNull);
      final Map<String, String> env = parseDotenv(text!);
      expect(env['APP_ENV'], isNotNull);
      expect(env['API_BASE_URL'], isNotNull);
      // Not an assertion about policy — an assertion that the dashboard is
      // reading the same file the build bundles.
      expect(env.containsKey('TELEMETRY_ENABLED'), isTrue);
    });

    test('dotenv parsing ignores comments and blank lines', () {
      final Map<String, String> env = parseDotenv('''
# a comment
A=1

  # indented comment
B = two words
C=
''');
      expect(env, <String, String>{'A': '1', 'B': 'two words', 'C': ''});
    });
  });

  group('the committed input files are valid', () {
    test('manual_status.json parses and declares only permitted states', () {
      final ManualStatus manual = ManualStatus.load(repo);
      expect(manual.entries, isNotEmpty);
      for (final Metric m in manual.entries.values) {
        expect(
          kAllowedManualStates.contains(m.state.name),
          isTrue,
          reason: '${m.key} declares ${m.state.name}',
        );
      }
    });

    test('a manual entry may not claim to be a live measurement', () {
      final Directory tmp = Directory.systemTemp.createTempSync(
        'wp_manual_test',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      Directory('${tmp.path}/docs/launch').createSync(recursive: true);
      File('${tmp.path}/docs/launch/manual_status.json').writeAsStringSync(
        jsonEncode(<String, Object?>{
          'entries': <String, Object?>{
            'x': <String, Object?>{'label': 'x', 'state': 'live', 'value': 'v'},
          },
        }),
      );
      expect(
        () => ManualStatus.load(RepoSources(tmp)),
        throwsA(isA<FormatException>()),
      );
    });

    test('launch_actions.json parses and every severity is known', () {
      final List<LaunchAction> actions = loadActions(repo);
      expect(actions, isNotEmpty);
      for (final LaunchAction a in actions) {
        expect(a.owner, isNotEmpty);
        expect(a.title, isNotEmpty);
      }
    });

    test('no action or manual entry carries a contact detail', () {
      // The dashboard is shared; it records roles, not ways to reach people.
      final RegExp emailish = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+');
      // Nine or more digits with optional separators. ISO dates and the
      // numeric console identifiers are excluded explicitly rather than by
      // loosening the pattern, so a real number would still be caught.
      final RegExp phoneish = RegExp(r'(?<!\d)\+?[\d][\d\s()-]{7,}[\d](?!\d)');
      final RegExp isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
      for (final String path in <String>[
        'docs/launch/launch_actions.json',
        'docs/launch/manual_status.json',
      ]) {
        final String? text = repo.read(path);
        expect(text, isNotNull, reason: '$path missing');
        expect(
          emailish.hasMatch(text!),
          isFalse,
          reason: '$path contains something shaped like an email address',
        );
        final List<String> suspicious = phoneish
            .allMatches(text)
            .map((RegExpMatch m) => m.group(0)!.trim())
            .where((String s) => !isoDate.hasMatch(s))
            // Play's own account and app identifiers are pure digit runs and
            // are console references, not ways to reach a person.
            .where((String s) => !RegExp(r'^\d{16,}$').hasMatch(s))
            .toList();
        expect(
          suspicious,
          isEmpty,
          reason:
              '$path contains something shaped like a phone number: '
              '$suspicious',
        );
      }
    });
  });

  group('config canonicalisation matches the recorded baseline method', () {
    test('key order does not change the canonical hash', () {
      const String a = '{"b":2,"a":{"d":4,"c":3}}';
      const String b = '{"a":{"c":3,"d":4},"b":2}';
      expect(canonicalJson(jsonDecode(a)), canonicalJson(jsonDecode(b)));
    });

    test('canonical form uses compact separators and no trailing newline', () {
      final String out = canonicalJson(<String, Object?>{'a': 1, 'b': 2});
      expect(out, '{"a":1,"b":2}');
      expect(out.endsWith('\n'), isFalse);
    });

    test('list order is preserved — only keys are sorted', () {
      expect(canonicalJson(<Object?>[3, 1, 2]), '[3,1,2]');
    });
  });

  group('the generator is not part of the shipping app', () {
    test('no script imports anything from lib/', () {
      for (final String name in <String>[
        'launch_dashboard.dart',
        'launch_status_model.dart',
        'launch_status_sources.dart',
        'launch_status_inputs.dart',
        'launch_status_render.dart',
      ]) {
        final String source = File('scripts/$name').readAsStringSync();
        expect(
          source.contains("import 'package:wellapath_mobile/"),
          isFalse,
          reason: 'scripts/$name imports application code',
        );
        expect(
          source.contains('../lib/'),
          isFalse,
          reason: 'scripts/$name reaches into lib/',
        );
      }
    });

    test('no lib/ source imports the dashboard scripts', () {
      final List<File> sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      expect(sources, isNotEmpty);
      for (final File f in sources) {
        expect(
          f.readAsStringSync().contains('launch_status'),
          isFalse,
          reason: '${f.path} references the dashboard',
        );
        expect(
          f.readAsStringSync().contains('launch_dashboard'),
          isFalse,
          reason: '${f.path} references the dashboard',
        );
      }
    });

    test('no metric or action surfaces clinical vocabulary', () {
      // The guard that matters is on what the dashboard OUTPUTS, not on what
      // its source prose says — the footer legitimately promises there is no
      // symptom data, and a source-text scan would flag that promise itself.
      //
      // Deliberately clinical/PHI terms only. Ordinary English that happens
      // to appear in a note ("answer", "result") is not evidence of anything.
      const List<String> prohibited = <String>[
        'symptom',
        // "diagnosis" only — "diagnostics" is the engineering sense and is
        // used correctly throughout the Sentry panel.
        'diagnosis',
        'patient',
        'latitude',
        'longitude',
        'red_flag',
      ];

      final File generated = File('docs/launch/LAUNCH_STATUS.json');
      expect(
        generated.existsSync(),
        isTrue,
        reason: 'run `dart run scripts/launch_dashboard.dart` first',
      );
      final Map<String, Object?> status =
          jsonDecode(generated.readAsStringSync()) as Map<String, Object?>;

      void check(String where, Object? text) {
        if (text is! String) {
          return;
        }
        final String lower = text.toLowerCase();
        for (final String word in prohibited) {
          expect(
            lower.contains(word),
            isFalse,
            reason: '$where surfaces "$word": $text',
          );
        }
      }

      for (final Object? p
          in (status['panels'] as List<Object?>? ?? const <Object?>[])) {
        final Map<String, Object?> panel = p! as Map<String, Object?>;
        for (final Object? m
            in (panel['metrics'] as List<Object?>? ?? const <Object?>[])) {
          final Map<String, Object?> metric = m! as Map<String, Object?>;
          // Keys, labels and values are what a reader sees as data.
          check('metric key', metric['key']);
          check('metric label', metric['label']);
          check('metric value', metric['value']);
        }
      }
      for (final Object? a
          in (status['actions'] as List<Object?>? ?? const <Object?>[])) {
        final Map<String, Object?> action = a! as Map<String, Object?>;
        check('action title', action['title']);
        check('action owner', action['owner']);
      }
    });
  });
}
