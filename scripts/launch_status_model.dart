/// Data model for the internal launch command centre
/// (`scripts/launch_dashboard.dart`).
///
/// This file is deliberately free of `dart:io` and of any Flutter import: it
/// is pure data + invariants, so the rules below are unit-testable without a
/// filesystem and can never be pulled into the shipping app.
///
/// THE CENTRAL INVARIANT
///
/// A metric may only carry a value when that value was actually obtained.
/// When a system is switched off, not instrumented, not yet reporting or
/// simply unverified, the metric carries NO value and renders as a word
/// ("Disabled", "Not instrumented", "Awaiting data", "Not verified").
///
/// This exists because a dashboard that prints `0` for a disabled subsystem
/// is not merely unhelpful, it is wrong: `0 crashes` and `crash reporting is
/// off` are opposite facts, and reading the first when the second is true is
/// exactly how a launch decision gets made on evidence that does not exist.
/// The invariant is enforced in the constructor, not left to the renderer.
library;

/// How a metric's value was obtained — or why there is no value.
enum MetricState {
  /// Measured during this run against a live external system (for example an
  /// HTTP probe of `/config`). Carries a value and a measurement timestamp.
  live('Live', true),

  /// Computed from committed repository sources (pubspec, flag defaults, the
  /// build-identity registry). Reproducible offline. Carries a value.
  derived('Derived', true),

  /// A human observation that no repository source can supply — console
  /// state, a clinical sign-off, a physical-device test. Carries a value plus
  /// an observer and an observation date.
  manual('Manual', true),

  /// The subsystem is implemented but switched off in the build under
  /// review. There is no data because nothing is running. NEVER a number.
  disabled('Disabled', false),

  /// No measurement of this exists anywhere yet — the code to produce it has
  /// not been written. NEVER a number.
  notInstrumented('Not instrumented', false),

  /// Instrumented and enabled, but no data has arrived yet. NEVER a number.
  awaitingData('Awaiting data', false),

  /// A claim exists but has not been checked by this tooling, or a manual
  /// entry has gone past its freshness window. NEVER a number.
  notVerified('Not verified', false);

  const MetricState(this.label, this.carriesValue);

  /// The exact word shown in place of a value. Rendering must use this and
  /// must never substitute a zero, a dash or an empty cell.
  final String label;

  /// Whether this state is permitted to carry a value at all.
  final bool carriesValue;

  static MetricState byName(String name) => MetricState.values.firstWhere(
    (MetricState s) => s.name == name,
    orElse: () => throw ArgumentError('unknown metric state: $name'),
  );
}

/// How urgent an outstanding launch action is.
enum Severity {
  blocker('Blocker'),
  high('High'),
  medium('Medium'),
  low('Low'),
  info('Info');

  const Severity(this.label);

  final String label;

  static Severity byName(String name) => Severity.values.firstWhere(
    (Severity s) => s.name == name,
    orElse: () => throw ArgumentError('unknown severity: $name'),
  );
}

/// How much of a panel a machine established, worst-state-wins.
enum PanelKind {
  /// Backed by a real-time measurement; nothing missing, nothing typed in.
  live('Live'),

  /// Reproducible from committed repository sources alone. Trustworthy and
  /// automatic, but it reflects what is committed, not what is happening.
  derived('Derived'),

  /// Contains at least one hand-entered observation. Only as good as the
  /// person who entered it and the date they entered it.
  manual('Manual'),

  /// Contains at least one fact nobody has supplied yet. The panel is not
  /// reporting good news; it is reporting an absence.
  incomplete('Incomplete');

  const PanelKind(this.label);

  final String label;
}

/// Thrown when a metric would violate the central invariant.
class MetricInvariantError extends ArgumentError {
  MetricInvariantError(super.message);
}

/// A single fact on the dashboard.
class Metric {
  Metric({
    required this.key,
    required this.label,
    required this.state,
    this.value,
    this.source,
    this.observer,
    this.observedAt,
    this.note,
  }) {
    if (!state.carriesValue && value != null) {
      throw MetricInvariantError(
        'metric "$key" is ${state.name} and must not carry a value '
        '(got "$value"). A disabled or uninstrumented system reports its '
        'state, never a number.',
      );
    }
    if (state.carriesValue && (value == null || value!.trim().isEmpty)) {
      throw MetricInvariantError(
        'metric "$key" is ${state.name} and must carry a non-empty value; '
        'use disabled/notInstrumented/awaitingData/notVerified instead.',
      );
    }
    if (state == MetricState.manual) {
      if (observer == null || observer!.trim().isEmpty) {
        throw MetricInvariantError(
          'manual metric "$key" must name the person who observed it',
        );
      }
      if (observedAt == null) {
        throw MetricInvariantError(
          'manual metric "$key" must record when it was observed',
        );
      }
    }
    if (state == MetricState.live && observedAt == null) {
      throw MetricInvariantError(
        'live metric "$key" must record the measurement time',
      );
    }
  }

  /// Stable machine key, `snake_case`.
  final String key;

  /// Human label shown on the dashboard.
  final String label;

  final MetricState state;

  /// The value, as already-formatted display text. Null unless
  /// [MetricState.carriesValue] is true.
  final String? value;

  /// Where the fact came from: a repository path, a URL, or a console name.
  final String? source;

  /// Who observed a [MetricState.manual] fact.
  final String? observer;

  /// When a manual or live fact was obtained (UTC).
  final DateTime? observedAt;

  /// Optional qualification shown beneath the value.
  final String? note;

  /// True when this fact came from a person rather than a system, and must be
  /// labelled as such wherever it is displayed.
  bool get isManual => state == MetricState.manual;

  /// What to render: the value when there is one, otherwise the state word.
  String get display => value ?? state.label;

  /// A manual fact older than [window] can no longer be trusted as current;
  /// it is re-stated as [MetricState.notVerified] with its original date kept
  /// in the note, so a stale sign-off never silently reads as a fresh one.
  Metric agedAt(DateTime now, Duration window) {
    if (state != MetricState.manual) {
      return this;
    }
    if (now.difference(observedAt!) <= window) {
      return this;
    }
    final String was = observedAt!.toIso8601String().split('T').first;
    return Metric(
      key: key,
      label: label,
      state: MetricState.notVerified,
      source: source,
      note:
          'last observed $was by $observer'
          '${note == null ? '' : ' — $note'} (past the '
          '${window.inDays}-day freshness window; re-observe to restore)',
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'label': label,
    'state': state.name,
    'state_label': state.label,
    'value': value,
    'display': display,
    'manual': isManual,
    if (source != null) 'source': source,
    if (observer != null) 'observer': observer,
    if (observedAt != null) 'observed_at': observedAt!.toIso8601String(),
    if (note != null) 'note': note,
  };
}

/// One outstanding action on the launch critical path.
class LaunchAction {
  LaunchAction({
    required this.id,
    required this.title,
    required this.owner,
    required this.severity,
    required this.state,
    this.reference,
    this.note,
  });

  final String id;
  final String title;

  /// The role accountable for it — never a personal contact detail.
  final String owner;

  final Severity severity;

  /// Where the action's status came from, using the same vocabulary as
  /// metrics (usually [MetricState.derived] or [MetricState.manual]).
  final MetricState state;

  /// A blocker id, document path or issue reference.
  final String? reference;

  final String? note;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'owner': owner,
    'severity': severity.name,
    'severity_label': severity.label,
    'state': state.name,
    'manual': state == MetricState.manual,
    if (reference != null) 'reference': reference,
    if (note != null) 'note': note,
  };
}

/// A group of related metrics.
class Panel {
  Panel({
    required this.key,
    required this.title,
    required this.metrics,
    this.summary,
  });

  final String key;
  final String title;
  final List<Metric> metrics;

  /// One line describing what the panel is for.
  final String? summary;

  /// How much of this panel a machine actually established.
  ///
  /// A panel is only as trustworthy as its weakest fact, so the worst state
  /// present decides the label. The distinction that matters to a reader is
  /// "did a system establish this, or did someone type it in" — which is why
  /// [PanelKind.manual] is a separate answer from [PanelKind.derived] rather
  /// than being folded into a single "placeholder" bucket.
  PanelKind get kind {
    if (metrics.isEmpty) {
      return PanelKind.incomplete;
    }
    if (metrics.any((Metric m) => m.state == MetricState.notVerified)) {
      return PanelKind.incomplete;
    }
    if (metrics.any((Metric m) => m.isManual)) {
      return PanelKind.manual;
    }
    if (metrics.any((Metric m) => m.state == MetricState.live)) {
      return PanelKind.live;
    }
    return PanelKind.derived;
  }

  /// True only when a real-time measurement backs this panel and nothing in
  /// it is testimony or missing.
  bool get isLive => kind == PanelKind.live;

  /// True when the panel needs no human input and reproduces from the
  /// repository alone — `derived` and `live` both qualify.
  bool get isAutomatic => kind == PanelKind.live || kind == PanelKind.derived;

  bool get hasManualEntries => metrics.any((Metric m) => m.isManual);

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'title': title,
    if (summary != null) 'summary': summary,
    'kind': kind.name,
    'kind_label': kind.label,
    'live': isLive,
    'automatic': isAutomatic,
    'has_manual_entries': hasManualEntries,
    'metrics': metrics.map((Metric m) => m.toJson()).toList(),
  };
}

/// The complete dashboard snapshot.
class LaunchStatus {
  LaunchStatus({
    required this.generatedAt,
    required this.commit,
    required this.branch,
    required this.panels,
    required this.actions,
    this.probesAttempted = false,
  });

  final DateTime generatedAt;
  final String commit;
  final String branch;
  final List<Panel> panels;
  final List<LaunchAction> actions;

  /// Whether live network probes ran. When false, every would-be live metric
  /// is [MetricState.notVerified] rather than silently stale.
  final bool probesAttempted;

  List<Panel> get placeholderPanels =>
      panels.where((Panel p) => !p.isLive).toList();

  List<LaunchAction> get blockers => actions
      .where((LaunchAction a) => a.severity == Severity.blocker)
      .toList();

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': 'wellapath.launch_status/1',
    'generated_at': generatedAt.toIso8601String(),
    'commit': commit,
    'branch': branch,
    'probes_attempted': probesAttempted,
    'panel_count': panels.length,
    'live_panel_count': panels.where((Panel p) => p.isLive).length,
    'panels': panels.map((Panel p) => p.toJson()).toList(),
    'actions': actions.map((LaunchAction a) => a.toJson()).toList(),
  };
}
