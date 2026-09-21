# Crash monitoring — store privacy worksheets (Apple App Privacy & Google Data Safety)

Derived from the **exact outbound payload** the sanitiser can produce
(`sentry_event_sanitiser.dart`, allowlist architecture: the event is rebuilt
from named fields; everything unnamed is dropped). Nothing here is guessed.
These declarations apply **only from the first build that ships with crash
reporting enabled** (earliest 212, internal). Builds 210/211 collect nothing
and declare nothing.

## 1. What Sentry COULD transmit (complete field inventory)

| Field | Content | Identifier? |
|---|---|---|
| `event_id`, `timestamp` | random UUID per event + crash time | per-event only, not per-user/device |
| `platform`, `level` | `dart` / severity enum | no |
| `release` | `wellapath-mobile@0.3.0+212` | no |
| `environment` | `internal-beta` or `production` | no |
| `dist` | build number | no |
| `exceptions[].type` | Dart class name (regex-validated identifier, else `[redacted]`) | no |
| `exceptions[].value` | message after 10 scrub passes (URL query, credential headers, quoted strings, coordinates, emails, phones, opaque tokens, snake_case ids, SCREAMING_CASE, clinical vocabulary), ≤240 chars | no |
| `exceptions[].stacktrace.frames[]` | file basename / package path, function, line/col, in-app flag, symbolication addresses; **no** source lines, **no** local variables | no |
| `tags` | `crash_source` ∈ 5 fixed values, `severity` ∈ {fatal, non_fatal} | no |

Transport metadata: the envelope reaches Sentry over TLS; Sentry sees the
sending IP (server-side) but `sendDefaultPii=false` means the IP is **not
stored on the event**.

## 2. What is excluded client-side (every exclusion, with its mechanism)

| Exclusion | Mechanism |
|---|---|
| Symptom / assessment / answers / question IDs / urgency | snake_case + SCREAMING_CASE + vocabulary scrub in messages; contexts/extras/breadcrumbs never copied by the allowlist rebuild |
| Facility searches, selections | same scrubs; URL query strings stripped to scheme+host+path |
| Coordinates / location | coordinate regex in messages; location never collected by the app beyond the on-device locator, and no location API feeds Sentry |
| Free text | quoted-literal scrub + 240-char cap + allowlist (no `message`, `extra`, `contexts`) |
| Auth headers, cookies, tokens, query strings | credential-header regex, opaque-token regex, URL-query scrub |
| Emails, phones, account identifiers | dedicated regexes + opaque-token rule |
| User identity | `sendDefaultPii=false`; `user` never copied; no login exists in the app |
| Persistent device/install ID | none is created anywhere in the app; `LoadContextsIntegration` removed so the SDK's device context is never gathered |
| Screen content | screenshots off, view hierarchy off, replay rates pinned null |
| Sessions / traces / profiles | session tracking off, `tracesSampleRate`/`profilesSampleRate` null, performance integrations removed |
| Native crash envelopes (bypass `beforeSend`) | native SDK never initialised |
| Breadcrumbs / routes / UI labels | `maxBreadcrumbs=0`, `beforeBreadcrumb→null`, every auto-breadcrumb flag off, and the allowlist omits `breadcrumbs` — quadruple-stopped |

## 3. Draft declarations (submit only with an enabled build)

**Apple App Privacy** — Data type: **Crash Data** (under Diagnostics).
"Linked to you": **No** (no account, no persistent identifier). "Used for
tracking": **No**. Purpose: App Functionality. Everything else (Health &
Fitness, Location, Identifiers, Usage Data): **not collected** — unchanged
from today.

**Google Data Safety** — Data collected: **Crash logs** and **Diagnostics**
(App info and performance). Shared with third parties: **Yes — Sentry as a
service provider/processor** (declare under data sharing with the processor
qualification). Ephemeral: No. Optional: No (when enabled). Encrypted in
transit: Yes. Deletion request mechanism: n/a (no user-linked data; nothing
is attributable to a person). Everything else: not collected.

Both stores currently carry **"no data collected"** declarations — those
remain correct for 210/211 and must be updated in the same release that
first ships an enabled build, not before.

## 4. Founder decisions — CONFIRMED 2026-09-21

| Decision | Confirmed value |
|---|---|
| Data region | **European Union** — must be selected at org creation (immutable; US is the silent default) |
| Retention | **30 days** |
| Access | **Company owner only** initially; engineering access least-privilege when granted |
| DPA | **Signed, effective 2026-09-21.** Customer entity: WELLAPATH TECHNOLOGIES LIMITED. PDF sha256 `74abf15fc1c6646517d5b99d6564be1b2caa6a9af5011ed3431979c09ef37a5a` |
| Project | **Reuse existing `wellapath-mobile`** (corrected 2026-09-21 after live-org inspection; holds historical 0.2.0(208) metadata, which is preserved). Isolation via a new client key `internal-212` + release `wellapath-mobile@0.3.0+212` + environment `internal-testing`; the legacy key stays until the test succeeds, then is assessed for safe disablement |
| Live server-side protections (screenshot 2026-09-21) | EU ingestion endpoint · Data Scrubber enabled · Default Scrubbers enabled · IP-address storage prevented · minidump attachments disabled. Safe Fields confirmed EMPTY (`business-email` is the interface's placeholder text, not a value — founder screenshot 2026-09-21); additional sensitive-field list populated; replay-derived issue toggles disabled for clarity |
| Scope | Engineering diagnostics only — never product analytics. Nothing in the payload inventory (§1) can serve analytics: no user, device, session, screen, interaction or usage field exists in the rebuilt event |
| Initial activation surface | Native capture, replay, screenshots, view hierarchy, sessions, tracing, profiling all remain OFF |
