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

---

## 5. iOS distribution export options — symbols must travel with the build

**Why this section exists.** Build 216 was exported and uploaded with
`uploadSymbols` set to `false`. No dSYMs reached App Store Connect, so automatic
Apple-side symbolication is unavailable for that build. The cause was not a
reviewed decision that turned out badly — it was that the `ExportOptions.plist`
was **hand-authored in an untracked build directory**. Nothing in version
control described what a distribution export must contain, so nothing could
disagree with it. Section 2's scanner had the same gap before it was written:
a rule that lives only in someone's memory is not a control.

### 5.1 The rule

**Every potentially distributable iOS export — `destination=export` and
`destination=upload` alike — must set `uploadSymbols` to `true`.** This applies
to build **217 and every later build**. An export-only run is the artifact that
gets hashed and scanned before anyone uploads anything; if it lacks symbols it
is not the thing that later gets uploaded.

`uploadSymbols` is **not** a tunable. `scripts/export_options_policy.dart`
holds it as the constant `kRequiredUploadSymbols` and exposes no parameter to
disable it, so the generator cannot express the 216 regression.

### 5.2 Distribution mode is explicit, and is not this rule

`testFlightInternalTestingOnly` is **deliberately not** forced on for every
release. It bars external testing and Beta App Review by construction, which is
correct for an internal cohort and wrong for an external or public candidate.
The generator therefore requires an explicit `--mode`:

* `--mode=internal-testing` → emits `testFlightInternalTestingOnly`
* `--mode=app-store` → emits no internal-only marker

There is no default. An internal-only marker must never be inherited silently,
and its absence on an external candidate must never be accidental.

### 5.3 Generating the file

```
dart run scripts/export_options_tool.dart generate \
    --mode=internal-testing|app-store \
    --destination=export|upload \
    --team-id=<TEAM ID> \
    --out=<path>/ExportOptions.plist
```

A team identifier is an organisation identifier, not a secret. **Keystore paths,
passwords, key aliases and certificate private material never belong in an
export-options file**; `verifyExportOptionsFile` rejects a file that carries any of
them.

### 5.4 Mandatory pre-export and pre-upload verification

Immediately before **every** `xcodebuild -exportArchive`, whether exporting or
uploading:

```
dart run scripts/export_options_tool.dart verify <path>/ExportOptions.plist
```

* Exit contract: `0` = clean · `1` = policy violation · `2` = input unusable,
  nothing certified. **Fail closed**, exactly as in section 2.
* **Any non-zero exit stops the release step.** There is no bypass flag and no
  warning-only mode, deliberately.
* It verifies any plist however it was produced, **including by hand** — which
  is how build 216 went wrong, so a generator alone would not have caught it.
* Preserve the output as release evidence alongside the artifact hashes.

**Apple's parser decides, not a text scanner.** The verifier shells out to
`/usr/bin/plutil`:

1. `plutil` must exist and be executable, else **exit 2**. There is deliberately
   **no regex or string-scanner fallback** — a fallback is the defeated scanner
   under a different name.
2. `plutil -lint` must pass. A malformed plist is **never** certified (exit 2).
3. The file is read through `plutil -convert json`, and the **root** object is
   inspected: `uploadSymbols` must be **present at the root**, of **boolean**
   type, and **`true`**.

| Observed | Exit |
|---|---|
| root boolean `true` | **0** |
| root boolean `false` | **1** |
| root key omitted | **1** |
| key present only in a nested dictionary or array | **1** |
| wrong type — string `"true"`, integer `1` | **1** |
| invalid/unparseable plist, missing file, missing `plutil`, parser failure | **2** |

Three shapes are **exit 2 (fail closed)** rather than being verified, and that is
a known limitation rather than a judgement about them: a **binary** plist
(`plutil -convert binary1`), a **UTF-16** plist, and a plist containing a
`<data>` or `<date>` value. The first two are rejected because the file is read
as UTF-8 text before `plutil` is consulted; the third because `-convert json`
refuses those types. All three are valid input to `xcodebuild`, so a release
using one would be blocked and would need either conversion to UTF-8 XML or a
change here to query the single key with `plutil -extract` instead of converting
the whole file. Failing closed is the right direction, but it is not the same as
verifying.

**Why this is not a scanner.** Two earlier string-scanning versions were
defeated by independent review. The first read the *first* occurrence of a key
while Apple resolves the *last*, and matched keys inside XML comments. The
second, after that was fixed, still had no model of nesting — so an
`uploadSymbols` buried in the legitimate `provisioningProfiles` sub-dictionary
was reported CLEAN while Apple saw no root-level key at all, which is the
"omitted" state this policy calls the build-216 regression. Both escapes shared
one cause: text has no structure. Apple's parser cannot disagree with itself.

**There is no duplicate-key lint**, by design. `plutil` resolves a duplicated key
to the last occurrence — exactly what `xcodebuild` does — so a duplicate cannot
make the verdict differ from what ships. A text-based duplicate check also could
not tell nesting levels apart, and rejected legitimate files; an inaccurate check
that fails good input is worse than none.

**The cost, stated plainly:** verification requires macOS. That is where iOS
archives are exported. A mandatory macOS CI job
(`macos-export-options-guard`) runs these cases, because a guard whose verdict
was mocked to keep Linux green would be testing the mock.

### 5.5 This does NOT replace the archive and dSYM scan

The export-options check and the neutral-path scan are **separate mandatory
gates** and neither substitutes for the other. Section 4 stands unchanged: the
archive, the `.dSYM` bundles and the DWARF binaries inside them must still be
scanned with `scripts/scan_symbol_artifacts.dart` before any symbol upload, and
re-scanned after every rebuild.

With `uploadSymbols: true` the dSYMs now actually leave the machine, so that
scan matters **more** than it did for 216, not less: a contaminated dSYM that
previously stayed local would reach Apple.

### 5.6 Archive retention for every distributed build

**Retain the matching `.xcarchive`, with its complete dSYM contents, for every
build distributed to any cohort — internal or external — for at least the life
of that build's observation period.**

Without the matching archive, a crash report from a distributed build cannot be
symbolicated at all once Apple-side symbols are missing or expired. The archive
is the only copy of the debug information that maps a crash address back to a
line of code, and the UUIDs must match the shipped binaries — verify with
`dwarfdump --uuid` against the binaries inside the exported `.ipa`, not merely
against the archive, since an archive can be rebuilt while the shipped artifact
cannot.

Retention is required even when `uploadSymbols` was `true`: Apple's copy is a
convenience, not an archive of record. Build 216's archive and dSYMs are
retained for exactly this reason, because for that build Apple has no copy at
all.

### 5.7 The guard sits in front of the export, not beside it

A check is only as good as someone's memory of running it. Build 216's
`ExportOptions.plist` was hand-authored and nothing stood between it and
`xcodebuild`. Use the wrapper:

```
dart run scripts/guarded_export.dart \
    --archive-path=<path>/Runner.xcarchive \
    --export-options=<path>/ExportOptions.plist \
    --export-path=<path>/export
```

It takes the export-options pathname, verifies **that exact pathname**, and
invokes `xcodebuild -exportArchive` **only** on exit 0 — passing through the same
pathname it verified. On any non-zero verdict it stops and `xcodebuild` is never
invoked.

The substitution point matters as much as the verdict: a wrapper that verified
one file and exported another would satisfy every verifier test while shipping an
unverified plist. `runGuardedExport` therefore returns the arguments it actually
used, and a test asserts the verified path is the one passed to
`-exportOptionsPlist`. Nothing regenerates or substitutes a plist between
verification and export.

**What this does NOT guarantee.** Nothing forces a release engineer through this
wrapper: calling `xcodebuild -exportArchive` directly still works and skips the
check entirely, exactly as §4 concedes for the neutral-path scanner. The wrapper
removes the chance of *forgetting* the check when you use it; it does not make the
check unavoidable. Making it unavoidable would mean removing direct `xcodebuild`
invocation from the documented release path, which is a separate, reviewed change.

**The wrapper is authoritative for the plist path.** Two hardenings follow from
that:

* `extraArguments` **may not supply or override `-exportOptionsPlist`** in any
  form — bare flag, inline `-exportOptionsPlist=/path`, double-dashed, or any
  casing. Such a call is refused with exit 2 **before** verification and before
  any invocation. Unrelated extras such as `-allowProvisioningUpdates` pass
  through untouched.

  **What this check is and is not for.** Measured on Xcode 26.6 (Build 17F113),
  `xcodebuild` **refuses** a repeated flag outright — `error: option
  '-exportOptionsPlist' may only be provided once`, **exit 64**, nothing exported
  — rather than preferring the later value. So the wrapper is not what prevents a
  substituted plist here; Apple's own argument parser does. The check exists so
  the refusal is **attributable and early**: a message naming the misuse, before
  verification and before any invocation, instead of an opaque exit 64 from a tool
  that has already been handed the command.

  An earlier revision of this section claimed `xcodebuild` "takes the later value
  of a repeated flag". That was false — an untested extrapolation from the
  separate and correct finding that Apple resolves a duplicated plist **key** to
  the last one (§5.4). Duplicate plist keys and duplicate CLI flags behave
  differently.
* `xcodebuild` is resolved through the fixed absolute path
  **`/usr/bin/xcodebuild`**, never `PATH`, for the same reason `plutil` is. A
  review of an earlier version demonstrated the asymmetry by placing a fake
  `xcodebuild` first on `PATH` and watching it get invoked. A missing or
  non-executable `/usr/bin/xcodebuild` is exit 2 **before** export. Tests inject a
  process runner at the `XcodebuildRunner` seam; they do **not** put a fake
  earlier on `PATH`, because that is the behaviour the fixed path exists to rule
  out.

### 5.8 Build 217 and later: the wrapper is the release path

**For build 217 and every later build, the iOS export must go through
`scripts/guarded_export.dart`.** A direct `xcodebuild -exportArchive` invocation
is **not acceptable** for those builds.

**Preserve the wrapper's successful verification and export output as release
evidence**, alongside the artifact hashes and the neutral-path scan output. The
log is the record that the plist which was exported is the plist that was
verified — that is the whole claim, and an unrecorded claim is not evidence.

This is a procedural requirement, not a technical one: as §5.7 says, nothing
prevents someone calling `xcodebuild` by hand. The requirement exists because
build 216 was exported by hand with `uploadSymbols: false` and nothing in the
process noticed.
