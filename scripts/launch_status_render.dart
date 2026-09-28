/// Renders a [LaunchStatus] as a self-contained HTML page.
///
/// No network, no CDN, no fonts, no scripts: the page is a single file that
/// opens from disk and works offline, because a launch dashboard that needs
/// the internet to tell you the internet is down is not much use.
///
/// The renderer has one job beyond layout, and it is a correctness job: a
/// metric without a value renders its state word in muted type, never a zero
/// and never an empty cell. The model already forbids such a metric from
/// carrying a value, so this is the second of two independent guards.
library;

import 'launch_status_model.dart';

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _stateClass(MetricState state) => switch (state) {
  MetricState.live => 'st-live',
  MetricState.derived => 'st-derived',
  MetricState.manual => 'st-manual',
  MetricState.disabled => 'st-off',
  MetricState.notInstrumented => 'st-off',
  MetricState.awaitingData => 'st-wait',
  MetricState.notVerified => 'st-unknown',
};

String _severityClass(Severity s) => switch (s) {
  Severity.blocker => 'sev-blocker',
  Severity.high => 'sev-high',
  Severity.medium => 'sev-medium',
  Severity.low => 'sev-low',
  Severity.info => 'sev-info',
};

String _metricRow(Metric m) {
  final StringBuffer b = StringBuffer();
  b.writeln('<div class="metric">');
  b.writeln('  <div class="m-label">${_escape(m.label)}');
  if (m.isManual) {
    b.writeln('    <span class="badge manual">Manual</span>');
  }
  b.writeln('  </div>');
  b.writeln(
    '  <div class="m-value ${_stateClass(m.state)}">'
    '${_escape(m.display)}</div>',
  );

  final List<String> meta = <String>[];
  if (m.isManual) {
    final String when = m.observedAt!.toIso8601String().split('T').first;
    meta.add('observed by ${_escape(m.observer!)} on $when');
  } else if (m.state == MetricState.live && m.observedAt != null) {
    meta.add('measured ${m.observedAt!.toIso8601String()}');
  }
  if (m.source != null) {
    meta.add(_escape(m.source!));
  }
  if (meta.isNotEmpty) {
    b.writeln('  <div class="m-meta">${meta.join(' &middot; ')}</div>');
  }
  if (m.note != null) {
    b.writeln('  <div class="m-note">${_escape(m.note!)}</div>');
  }
  b.writeln('</div>');
  return b.toString();
}

String _panelBadge(PanelKind kind) => switch (kind) {
  PanelKind.live => '<span class="badge live">Live</span>',
  PanelKind.derived => '<span class="badge derived">Derived</span>',
  PanelKind.manual => '<span class="badge manual">Manual</span>',
  PanelKind.incomplete => '<span class="badge placeholder">Incomplete</span>',
};

String _panel(Panel p) {
  final StringBuffer b = StringBuffer();
  final String badge = _panelBadge(p.kind);
  b.writeln('<section class="panel">');
  b.writeln('  <h2>${_escape(p.title)} $badge</h2>');
  if (p.summary != null) {
    b.writeln('  <p class="p-summary">${_escape(p.summary!)}</p>');
  }
  for (final Metric m in p.metrics) {
    b.write(_metricRow(m));
  }
  b.writeln('</section>');
  return b.toString();
}

String _actions(List<LaunchAction> actions) {
  final List<Severity> order = <Severity>[
    Severity.blocker,
    Severity.high,
    Severity.medium,
    Severity.low,
    Severity.info,
  ];
  final List<LaunchAction> sorted = List<LaunchAction>.of(actions)
    ..sort(
      (LaunchAction a, LaunchAction b) =>
          order.indexOf(a.severity).compareTo(order.indexOf(b.severity)),
    );

  final StringBuffer b = StringBuffer();
  b.writeln('<section class="panel wide">');
  b.writeln(
    '  <h2>Outstanding launch actions '
    '<span class="badge placeholder">Register</span></h2>',
  );
  if (sorted.isEmpty) {
    b.writeln(
      '  <p class="p-summary">No actions recorded. That is a claim '
      'about the register, not about the project.</p>',
    );
    b.writeln('</section>');
    return b.toString();
  }
  b.writeln('  <table>');
  b.writeln(
    '    <thead><tr><th>Severity</th><th>Action</th><th>Owner</th>'
    '<th>Reference</th></tr></thead>',
  );
  b.writeln('    <tbody>');
  for (final LaunchAction a in sorted) {
    b.writeln('      <tr>');
    b.writeln(
      '        <td><span class="sev ${_severityClass(a.severity)}">'
      '${a.severity.label}</span></td>',
    );
    b.write('        <td><strong>${_escape(a.title)}</strong>');
    if (a.note != null) {
      b.write('<div class="m-note">${_escape(a.note!)}</div>');
    }
    b.writeln('</td>');
    b.writeln('        <td>${_escape(a.owner)}</td>');
    b.writeln('        <td class="ref">${_escape(a.reference ?? a.id)}</td>');
    b.writeln('      </tr>');
  }
  b.writeln('    </tbody>');
  b.writeln('  </table>');
  b.writeln('</section>');
  return b.toString();
}

String renderDashboard(LaunchStatus status) {
  final int automatic = status.panels.where((Panel p) => p.isAutomatic).length;
  final int incomplete = status.panels
      .where((Panel p) => p.kind == PanelKind.incomplete)
      .length;
  final int blockers = status.blockers.length;

  return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WellaPath Launch Status</title>
<style>
  :root {
    --bg: #f6f7f9; --card: #ffffff; --ink: #14181f; --muted: #667085;
    --line: #e3e6eb; --live: #0f7b4f; --derived: #2c5cc5; --manual: #8a5a00;
    --off: #667085; --wait: #8a5a00; --unknown: #9aa1ad;
    --blocker: #b42318; --high: #c2410c; --medium: #8a5a00; --low: #475467;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --bg: #0f1115; --card: #171a21; --ink: #e8eaed; --muted: #98a1b0;
      --line: #262b34; --live: #4ade80; --derived: #7aa2f7; --manual: #e0af68;
      --off: #98a1b0; --wait: #e0af68; --unknown: #6b7280;
      --blocker: #f87171; --high: #fb923c; --medium: #e0af68; --low: #98a1b0;
    }
  }
  :root[data-theme="dark"] {
    --bg: #0f1115; --card: #171a21; --ink: #e8eaed; --muted: #98a1b0;
    --line: #262b34; --live: #4ade80; --derived: #7aa2f7; --manual: #e0af68;
    --off: #98a1b0; --wait: #e0af68; --unknown: #6b7280;
    --blocker: #f87171; --high: #fb923c; --medium: #e0af68; --low: #98a1b0;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; background: var(--bg); color: var(--ink);
    font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
      Helvetica, Arial, sans-serif;
    padding: 0 16px 64px;
  }
  header { max-width: 1120px; margin: 0 auto; padding: 32px 0 8px; }
  h1 { font-size: 22px; margin: 0 0 4px; letter-spacing: -0.01em; }
  .sub { color: var(--muted); font-size: 13px; }
  .notice {
    max-width: 1120px; margin: 16px auto 0; padding: 12px 14px;
    border: 1px solid var(--line); border-left: 3px solid var(--manual);
    background: var(--card); border-radius: 8px; font-size: 13px;
    color: var(--muted);
  }
  .grid {
    max-width: 1120px; margin: 20px auto 0; display: grid; gap: 14px;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
  }
  .panel {
    background: var(--card); border: 1px solid var(--line);
    border-radius: 10px; padding: 16px 16px 6px;
  }
  .panel.wide { grid-column: 1 / -1; }
  h2 {
    font-size: 14px; margin: 0 0 10px; display: flex; align-items: center;
    gap: 8px; letter-spacing: 0.01em;
  }
  .p-summary { color: var(--muted); font-size: 12.5px; margin: -4px 0 12px; }
  .metric { padding: 9px 0; border-top: 1px solid var(--line); }
  .metric:first-of-type { border-top: 0; }
  .m-label {
    font-size: 12.5px; color: var(--muted); display: flex;
    align-items: center; gap: 6px;
  }
  .m-value { font-size: 15px; font-weight: 600; margin-top: 2px; }
  .m-meta { font-size: 11.5px; color: var(--muted); margin-top: 3px; }
  .m-note {
    font-size: 12px; color: var(--muted); margin-top: 5px; line-height: 1.45;
  }
  .st-live { color: var(--live); }
  .st-derived { color: var(--derived); }
  .st-manual { color: var(--manual); }
  .st-off, .st-unknown { color: var(--off); font-weight: 500;
    font-style: italic; }
  .st-wait { color: var(--wait); font-weight: 500; font-style: italic; }
  .badge {
    font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;
    padding: 2px 6px; border-radius: 4px; border: 1px solid var(--line);
    color: var(--muted); font-weight: 600;
  }
  .badge.live { color: var(--live); border-color: currentColor; }
  .badge.derived { color: var(--derived); border-color: currentColor; }
  .badge.placeholder { color: var(--unknown); }
  .badge.manual { color: var(--manual); border-color: currentColor; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th {
    text-align: left; font-size: 11px; text-transform: uppercase;
    letter-spacing: 0.05em; color: var(--muted); font-weight: 600;
    padding: 6px 8px 6px 0; border-bottom: 1px solid var(--line);
  }
  td { padding: 10px 8px 10px 0; border-bottom: 1px solid var(--line);
    vertical-align: top; }
  td.ref { color: var(--muted); font-size: 11.5px; word-break: break-word; }
  .sev { font-weight: 700; font-size: 11.5px; white-space: nowrap; }
  .sev-blocker { color: var(--blocker); }
  .sev-high { color: var(--high); }
  .sev-medium { color: var(--medium); }
  .sev-low { color: var(--low); }
  .sev-info { color: var(--muted); }
  footer {
    max-width: 1120px; margin: 24px auto 0; color: var(--muted);
    font-size: 11.5px; line-height: 1.6;
  }
  code { font-size: 11.5px; }
</style>
</head>
<body>
<header>
  <h1>WellaPath launch status</h1>
  <div class="sub">
    ${_escape(status.branch)} &middot; <code>${_escape(status.commit)}</code>
    &middot; generated ${status.generatedAt.toIso8601String()}
    &middot; $automatic of ${status.panels.length} panels machine-established,
    $incomplete incomplete
    &middot; $blockers blocker${blockers == 1 ? '' : 's'}
  </div>
</header>

<div class="notice">
  <strong>Reading this correctly.</strong> Each panel is labelled by its
  weakest fact. <em>Live</em> means a real-time measurement backs it;
  <em>Derived</em> means it reproduces from committed repository sources alone;
  <em>Manual</em> means someone typed at least one fact in, and it carries
  their name and the date; <em>Incomplete</em> means at least one fact is one
  nobody has supplied. Where a subsystem is switched off or was never
  instrumented, this page says so in words &mdash; it never prints
  <code>0</code>, because &ldquo;zero crashes&rdquo; and &ldquo;crash
  reporting is off&rdquo; are opposite facts.
  ${status.probesAttempted ? 'Live probes ran for this snapshot.' : 'No live probe ran for this snapshot; network-dependent facts read <em>Not verified</em>.'}
</div>

<div class="grid">
${status.panels.map(_panel).join('\n')}
${_actions(status.actions)}
</div>

<footer>
  Internal engineering and founder view. Not part of the shipping application:
  this page is generated by <code>scripts/launch_dashboard.dart</code> and adds
  no bytes to any build. It contains no patient data and no symptom data of any
  kind, by construction &mdash; it reads only build metadata, configuration
  flags and hand-entered operational notes.
</footer>
</body>
</html>
''';
}
