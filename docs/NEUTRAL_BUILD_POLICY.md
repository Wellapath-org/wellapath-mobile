# Neutral build-path policy and mandatory symbol-artifact scan

**Why this exists.** The build-214 controlled verification
(docs/CRASH_VERIFICATION_214_REPORT.md) proved that Sentry's server-side
symbolication reproduces build-time absolute paths embedded in uploaded
debug information, and one symbolicated frame exposed the build
engineer's macOS username and worktree name. Neutral-path remediation is
a mandatory precondition for any distributable build. This policy is
that remediation.

## 1. Neutral build roots

Every **potentially distributable** Android or iOS build, and **every
symbol upload** associated with one, must originate from an approved
non-personal build root:

* `/Users/Shared/wellapath-build-<number>` on a controlled Mac;
* a documented CI or service-account workspace (for example
  `/home/runner/…` on GitHub-hosted runners);
* another **explicitly approved** neutral root containing no personal
  username, recorded in this document and mirrored in the scanner's
  approved lists (`scripts/symbol_artifact_scanner.dart`,
  `ScanRules.defaultApprovedRootPrefixes` / the `--approve-root` flag).

**A normal developer home directory is prohibited for distributable
builds.** Local-verification builds on abandoned branches are the only
historical exception, and their numbers are burned in the registry.

Approvals are explicit and testable: nothing is neutral by convention.
Standard CI accounts such as `runner` are non-personal and approved; a
blanket rule that rejects every `/home/<name>/` or `/Users/<name>/`
would be wrong, and a blanket rule that accepts them would be worse —
the scanner therefore allowlists exact account names and root prefixes.

## 2. The scanner

`scripts/scan_symbol_artifacts.dart` is the repository-owned,
deterministic gate (pure Dart, runs identically on macOS and Linux with
the existing Flutter toolchain):

```
dart run scripts/scan_symbol_artifacts.dart \
  [--personal-name=NAME]... [--approve-root=PREFIX]... \
  [--approve-user=NAME]... <input>...
```

* Inputs are explicit files/directories; every regular file inside them
  is inspected recursively.
* Content is scanned as raw bytes (no UTF-8 assumption) in streamed
  chunks with an overlap window, so a prohibited string crossing a read
  boundary is still detected.
* **Fail closed:** missing, unreadable or empty inputs — or an input
  set resolving to zero regular files — abort with exit 2, which
  dominates everything: an incomplete scan certifies nothing.
* **Exit contract:** `0` = all inputs scanned, clean · `1` = prohibited
  path detected · `2` = scan incomplete/invalid.
* Artifacts are opened read-only and never modified.
* Output is redaction-safe: artifact name, rule category and a redacted
  match only. Personal usernames and full personal paths never appear;
  `--personal-name` values can be supplied via the
  `WELLAPATH_PERSONAL_NAMES` environment variable to keep them out of
  shell history.

### Rules

Fatal categories: `personal_home_macos` (`/Users/<name>/` outside the
approved users/roots) · `personal_home_linux` (`/home/<name>/` outside
approved CI/service roots) · `personal_profile_windows`
(`C:\Users\<name>\` outside approved accounts) ·
`verification_worktree_name` (`wp-dist-*`, `wp-*-verification`,
`wp-sentry`, `wp-crash-*`, `wp-pr*` — the local worktrees used for
builds 212–214) · `configured_personal_name` (the developer's own
username, when configured for a local build).

Informational (reported for release evidence, never a failure by
itself): `toolchain_path` — generic non-personal prefixes such as
`/opt/homebrew/…`.

## 3. Coverage

The policy and scan cover **every symbol artifact that may be uploaded
or used for symbolication**, not just Android and not just `.symbols`
files:

* Flutter/Dart split-debug `.symbols` (all ABIs);
* Android native libraries, unstripped/native debug-symbol directories,
  and mapping/symbol-map artifacts if produced;
* iOS `.dSYM` bundles and the DWARF binaries inside them;
* anything else passed to `sentry_dart_plugin` or Sentry CLI.

## 4. Mandatory pre-upload procedure

Immediately before **every** symbol upload:

1. Identify the exact upload inputs (the directories/files the upload
   command will consume — e.g. `build/symbols/`, the dSYM output
   directory).
2. Run the scanner against **those exact inputs**, with
   `--personal-name` (or `WELLAPATH_PERSONAL_NAMES`) set to the local
   builder's username when building outside CI. In CI, omit it: the
   runner's account name is a non-personal service identity, and a
   configured personal name deliberately overrides every allowlist —
   configuring `runner` would fail every clean CI artifact.
3. **Any non-zero exit stops the release step.** There is no bypass
   flag and no warning-only mode, deliberately; the scanner has none to
   offer.
4. Preserve the scan output (it is redaction-safe by construction) as
   release evidence alongside the artifact hashes.
5. **Re-run after every rebuild** — debug IDs and embedded paths change
   with every build, so a previous clean result proves nothing about a
   new binary.

This is an explicit, reviewed release step. No automatic build or
upload hook runs the scanner; wiring it into CI is a separate,
reviewed change.
