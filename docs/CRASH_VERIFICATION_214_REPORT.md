# Build 214 controlled transport verification — execution report

**HISTORICAL EXECUTION REPORT — evidence only, intentionally durable.**
This document records what the build-214 controlled verification did and
found. It is the durable, mergeable record; the branch that carried the
temporary verification UI, gate and trigger
(`build/214-transport-verification`, its procedure doc
`CRASH_VERIFICATION_214.md`) was **never to be merged** and remains
abandoned unmerged, taking every line of verification code with it.
Build 214 is **local verification only — consumed/burned, never
distributed and never distributable**. Its one permitted synthetic
event was sent and the budget is spent; no second event may ever be
sent from it. The earliest potentially distributable Sentry-enabled
candidate is **build 215 or higher**.

## What was verified

One obfuscated release APK, `0.3.0+214`, sha256
`f45be13bc4f1564657e8142b1154c57e6c024d5824fefa19230adc7104a2d86f`,
release-signed (cert sha256 `94e7c574…9083d836`), `org.wellapath.app`
versionCode 214, bundled `.env` byte-identical to tracked production,
installed only on the `wellapath_lowend` emulator after a
pull-and-rehash of the installed `base.apk`. Fresh symbols were
uploaded first (`SENTRY_RELEASE=wellapath-mobile@0.3.0+214`; arm64
debug ID `098518b7-57d7-7fd7-1ab8-0642754b65d3` confirmed on the
project before install). Exactly one confirmed synthetic event was
sent through the visible gated UI at **2026-09-23T08:48:04Z** (tap
bracketed 08:48:03.942Z–08:48:04.040Z). The founder-supplied stored
Event JSON was audited fields-only; the event's `_dsc.public_key`
fingerprint matched the build-214-only client key.

Preconditions honoured: the corrected Advanced Data Scrubbing rule
`Remove · Anything · $user.geo.**` saved before the event; a fresh
build-214-only client key; a CI-permission-only upload token through
gitignored `sentry.properties`; Stable Jay disabled throughout.

## Final audit verdict — PASS 5/5, with two qualified representations and one finding

1. **Geo — PASS (qualified).** No populated geographic value survived:
   all four `user.geo` leaves (city, country_code, region, subdivision)
   arrived null with per-field scrub annotations (`_meta` remark
   `project:0`/`x`). Sentry retained only this **null-valued scrub
   shell and its rule annotations** — the corrected `$user.geo.**`
   rule's first operational proof. Qualification: the registered
   wording "`user.geo` completely absent" is met in substance (no
   value), not in literal shape (the empty container remains).
2. **Debug metadata — PASS (qualified).** The client transmitted
   **exactly the five approved fields** (`type=elf`, `image_addr`,
   `debug_id` = the arm64 ID above, `code_id`, constant
   `code_file=libapp.so`). Sentry's symbolicator later added four
   server-side keys to the stored image — `arch`, `candidates`,
   `debug_status`, `features` — which are enrichment, not client
   transmission.
3. **Symbolication — PASS, with the build-path finding.** 26/26 frames
   symbolicated, 26/26 functions resolved to names, zero raw
   addresses; the trigger and gesture path resolved. **No source
   contents, context lines or variables anywhere**
   (`has_sources=false`; zero `context_line`/`pre_context`/
   `post_context`/`vars`). **FINDING:** server symbolication from the
   uploaded DWARF added build-time `filename`, `lineno` and `abs_path`
   metadata; 21 `abs_path` values are absolute build-host paths, and
   **one — the app's own frame — exposed the build engineer's macOS
   username and worktree name.** This is build-host data, not end-user
   data, and was absent from the raw client frames. **Neutral-path
   remediation is required before any distribution** (a neutral build
   path or CI build, or server-side path scrubbing, plus aligning the
   declared frame shape in the privacy declarations).
4. **Privacy inventory — PASS.** No end-user personal, health or
   location data stored. Absent: request, breadcrumbs, extra, threads,
   modules, spans, measurements, server_name, logentry, transaction,
   attachments, replay data, ip_address, and every probed sensitive
   term. `contexts` carried only the documented `trace` transport
   metadata; `_dsc` only the documented envelope header fields. The
   criterion-3 build-host path is the only inventory-shape deviation.
5. **Identity — PASS, exact.** Release `wellapath-mobile@0.3.0+214`,
   environment `internal-testing`, dist `214`, exception `StateError`
   with value exactly `Bad state: synthetic [redacted] verification
   214` (`[redacted]` is the documented fail-safe over-redaction of
   the word "crash" by the clinical `rash` stem), client tags exactly
   `crash_source=flutter_framework` and `severity=non_fatal`.

Transport delivery was live-proven by the received event; the
rate-limit backoff remains **test-verified only**, per the plan.

The founder accepted the two qualified representations as substantive
passes; the build-path finding is a mandatory pre-distribution work
item for the 215 line.

## Cleanup (founder-confirmed, 2026-09-23)

The test event was deleted (ordinary Delete, not Delete-and-Discard);
the temporary CI token was revoked; the build-214 client key was
disabled; the credential-bearing sessions were closed; no build-214
credential remains active locally. `event_214.json` and
`sentry.properties` were deleted and were never tracked.

## What stands between here and a distributable build 215+

1. Neutral-path remediation for symbolicated `abs_path` values (build
   environment or server-side scrubbing) and the corresponding
   privacy-declaration frame-shape alignment.
2. Store privacy declarations updated, including the five-field
   debug-image disclosure and the server-enrichment reality recorded
   above.
3. The founder's production context/key model decision and the
   legacy-key disablement assessment.
4. A reviewed release procedure that never reuses a burned number:
   211–214 are consumed (see `test/release/build_identity_test.dart`).
