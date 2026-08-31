# Mobile Release Candidate — Readiness Checklist

**Branch:** `release/rc-frozen-baseline`
**Base:** `develop` @ `d820d6c`
**Build identity:** `0.3.0+209` (versionCode 209)
**Status:** frozen, unmerged, **not** submitted to any store
**Step 2 applied:** build identity · fail-closed signing · display name · bounded
cold-start recovery · neutral facility wording · CB_211 disposition
**Machine-readable inputs:** [`RC_FROZEN_INPUTS.json`](./RC_FROZEN_INPUTS.json)

This candidate is built from the currently active and verified Backend
configuration only. It authorizes nothing: not a merge, not an upload, not a
store submission.

---

## 1. Frozen inputs

| Input | Expected | Observed | |
|---|---|---|---|
| `/config` canonical SHA256 | `3b2bbb1c…78ed` | `3b2bbb1c…78ed` | ✅ |
| token_dictionary | 1.1 | 1.1 | ✅ |
| knowledge_base | 2.4 | 2.4 | ✅ |
| rules | 2.2 | 2.2 | ✅ |
| facilities | 1.1 | 1.1, hash re-verified | ✅ |
| Backend `/health` | ok | ok, database ok | ✅ |
| Backend `/version` | — | `0.1.0` / staging | ✅ |

The declared canonical hash is the **key-sorted, compact** serialisation of the
`/config` body — not the raw bytes. Both values are recorded in the frozen
inputs so the distinction cannot be lost. The raw body hashes to
`183a15bd…d3b`; matching on raw bytes alone would have produced a false
mismatch.

Backend `develop` @ `2485ce0c` is carried from the brief. **Mobile cannot
verify it** — there is no Backend checkout here — and it is flagged as
unverified rather than reported as confirmed.

## 2. Exclusions — proven, not asserted

| Excluded | Proven by |
|---|---|
| **Mobile PR #76** | not an ancestor of HEAD; all 14 files absent; test count delta exactly −49; `IM003` symbols absent from both binaries |
| **Question Flow 1.1** | zero cross-imports; tree-shaken out of `libapp.so` and `App.framework/App`; no artifact bundled |
| **Vocabulary / token_dictionary 2.0** | zero cross-imports; symbols absent from both binaries; gate defaults off; active dictionary stays 1.1 |
| **facilities 2.0** | zero references in `lib/`; `/config` publishes 1.1 only |
| **Runtime manifests** | no manifest route called; only `artifacts[*].{url,version,hash}` are read |
| **KB candidate artifacts** | runtime loads only what `/config` names; candidates live under `test/fixtures/` |

PR #76 is **left open and unmerged**, as instructed.

> Question Flow 1.1 and Vocabulary 2.0 consumer code is **already on `develop`**
> (merged PRs #75 and #72). It could not be excluded by branch choice. It is
> excluded from the *product* instead — unreachable and tree-shaken — and that
> is what the binary checks above establish. Removing the source would mean
> reverting merged PRs, which is outside a release-safe change.

## 3. Verification of artifact consumption

- `/config` fields read: `artifacts[*].url`, `.version`, `.hash`. Nothing else.
- **SHA256 verification is implemented** — on every cached read *and* every
  fresh download, with one re-download on mismatch and a hard `StateError`
  after that. A rejected artifact is never used.
- ⚠️ **Soft-fail:** a `null` or empty `hash` is treated as valid. Integrity
  therefore depends on `/config` always publishing a hash. All four currently
  do; nothing in the app enforces it.
- Versioned cache keys (`<key>_v<version>`) — an existing version is never
  overwritten (locked principle #4).
- Offline: cached config on `/config` failure; first-launch-offline screen when
  there is no cache and no network. **No crash** — verified on device.
- Scoring runs on-device only; red-flag override precedence intact.

## 4. Release-critical testing

| Gate | Result |
|---|---|
| `dart format` | 174 files, 0 changed ✅ |
| `flutter analyze` | No issues found ✅ |
| Full test suite | **1,292 passed · 7 skipped · 0 failed** ✅ |
| Clinical case bank | **239 executed · 238 passed · 1 known finding (CB_211) · 0 unexpected failures** ✅ |
| Global red-flag rules | 13/13 exercised ✅ |
| Android release build (signing machine) | APK built and **release-signed** ✅ |
| Android CI build (no signing material) | **unsigned**, verified unsigned in CI ✅ |
| Release signing fails closed | all three outcomes exercised ✅ |
| iOS release build | `Runner.app` built (`--no-codesign`) ✅ |
| Cold start | reaches onboarding ✅ (device-verified) |
| Onboarding | renders ✅ (device-verified) |
| Offline / degraded network | graceful offline screen with retry ✅ (device-verified) |
| Facility search — Lagos / FCT / Kano | ✅ (new tests) |
| Empty-result handling | ✅ (new tests) |
| Location-permission handling | manual state fallback present ✅ |
| Backend `/health` `/version` `/config` | ✅ |
| Secret scan | no secrets, no keystore, no `.env.local` tracked ✅ |
| Release-mode logging | fixed-vocabulary only; no PHI ✅ |
| Package / application ID | verified — **mismatched across platforms** ⚠️ |
| Build identity | `0.3.0+209`, unique and monotonic ✅ |
| Display name | **WellaPath** on both platforms ✅ |
| Cold-start recovery | recovers one transient failure; bounded at 30 s ✅ |

**Login:** the app has no login. There is no account, credential or session
flow to test. "Login/onboarding" reduces to onboarding, which was verified.

**Assessment, red-flag and locator interaction** were verified through the
automated widget/unit suite (including the 27 QB-002 red-flag interruption
tests), **not** driven by hand on a device. Cold start, onboarding and the
offline path were driven on a simulator. Release mode cannot run on the iOS
simulator, so the interactive checks were debug-mode.

**PHI safety:** the Dio interceptor has `requestBody: false` / `responseBody:
false`; unknown-token logging carries a **count only**, never token values; the
one place an exception cause is printed sits behind an `assert`, so it is
debug-only.

## 4a. Cold-start recovery — measured against staging

Staging is Render free tier and spins down when idle. Measured `/config`:
**warm 0.50–1.74 s**, **cold 12.8 s and 22.7 s**, with two windows stalling
past **60 s**. A single 10 s attempt cannot outlast a spin-up — and lengthening
the timeout does not help, because the request that *triggers* the spin-up is
the one that hangs. The next request meets a warm instance, so the fix is a
bounded retry.

**Policy:** finite **10 s** per attempt · deterministic **1/2/3 s** backoff ·
**4 attempts** · **30 s total budget**, with the final attempt clamped to the
remaining budget · transient-only retries · `/health` is **not** used as an
application dependency · artifact integrity is untouched · nothing unvalidated
is returned, so nothing unvalidated is cached.

| Failure | Retried? |
|---|---|
| connect / receive / send timeout, connection error | ✅ yes |
| 408, 429, 5xx | ✅ yes |
| 4xx other than 408/429 | ❌ no — permanent |
| bad TLS certificate | ❌ no — permanent |
| malformed body / schema-invalid | ❌ no — permanent |

**Measured on device** (iPhone 17 simulator; release mode is not supported on
the simulator, so these are debug builds — the network behaviour is identical):

| Scenario | Result |
|---|---|
| **Cold backend, first launch** (app uninstalled, backend idle ~26 min) | **Reached onboarding in 15–18 s.** Did **not** fall through to the offline screen. Spinner + "Connecting…" visible at 12 s. Attempt 1 timed out at 10 s; after a 1 s backoff, attempt 2 met the warmed instance. |
| Warm backend, 3 launches | onboarding in **7.4 s**, **0** config failures |
| Repeated failure (`192.0.2.1`, unroutable) | offline screen at **30–33 s** — inside the 30 s budget plus the 2 s minimum splash. No crash. |

Under the previous policy this same class of cold start fell through to the
offline screen (device-verified in Step 1).

**`RC-BLK-017` — a live defect found while testing this.** "Try again" on the
first-launch-offline screen **threw** `This widget has been unmounted` and did
nothing: `pushReplacement` disposes the splash, so the callback closed over an
already-defunct context. The recovery button on the recovery screen was dead.
Pre-existing on `develop`. Fixed — the retry now navigates from the offline
route's own context, covered by `test/features/boot/splash_startup_test.dart`.

> The underlying spin-down is a **Backend/infra** property, not a Mobile one.
> Mobile now rides through it; a keep-warm ping or a paid tier would remove the
> wait entirely and remains a Backend decision.

## 5. Facility coverage disclosure — corrected

`facilities.ng.v1.1` holds **5,344 records in exactly three states**: Lagos
(2,690), Kano (2,040), FCT (614). It is not a national dataset.

The locator previously told an out-of-region user:

> "We are currently serving Nigeria and will expand to more countries soon."

That reads as national coverage and is not true of the shipped data. It also
promised an expansion the roadmap has not committed to.

**Correction made (Product wording only):**

- One source of truth in `nigeria_coverage.dart` — `kCoveredStates` and
  `kCoverageDisclosure`.
- The out-of-region message now names the actual coverage.
- The empty-result state now names it too — an empty list otherwise reads as
  "there is no care near you" rather than "we hold no data for your state".
- The manual state picker explains why it lists only three states, and now
  reads from `kCoveredStates` instead of its own duplicate literal.

**Not changed:** facility ranking, emergency-capable ordering, urgency→type
mapping, the sparse-coverage tier fallback, the Nigeria bounding box, and every
piece of clinical behaviour.

> **Open, not fixed here:** `getNearbyFacilities` applies **no distance cap**.
> A user in an uncovered state (say Enugu) is handed the 30 nearest facilities,
> which may be 300 km away, under a "nearby" heading. Capping distance would
> change ranking, which this release is not permitted to do. The disclosure is
> the release-safe mitigation; the cap is a Product decision. Recorded as
> `RC-BLK-008`.

## 6. Store readiness — inspected, nothing submitted

| Item | State |
|---|---|
| Store listing | **not started** — no listing metadata in repo |
| Screenshots | **none** |
| Privacy-policy link | **none found** |
| Support contact | **none found** |
| Data-safety / privacy declarations | **not prepared** |
| Android permissions | INTERNET, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION — all justified by the locator |
| Android target SDK | 36 — meets the Play requirement ✅ |
| Android signing | release keystore works ✅; fails closed without it; still only on one machine |
| Android artifact | universal APK — Play requires an **AAB**; none produced |
| App name on device | **WellaPath** ✅ |
| iOS deployment target | 13.0 ✅ |
| iOS privacy manifest | dependencies ship theirs; **app target has none** ⚠️ |
| iOS signing | not codesigned; no provisioning profile exercised |
| Tester / release tracks | none configured |

## 7. Blockers

### BLOCKS_BUILD
*None.* Both platforms build; analyze, format and the full suite are clean.

### BLOCKS_INTERNAL_TESTING

| ID | Finding |
|---|---|
| `RC-BLK-001` | ✅ **RESOLVED.** Version is now `0.3.0+209`. 209 is derived from every distribution record — pubspec/tags/BETA_ROLLBACK all used `1`, the internal-beta CI release identifier reached `208`. `test/release/build_identity_test.dart` fails the build on any reuse or regression. |
| `RC-BLK-002` | ✅ **RESOLVED.** Release signing fails closed. No keystore + no explicit opt-in → the build **fails** with a named remedy. The debug fallback is gone. CI uses an explicit unsigned path and verifies the artifact carries **no signature**, so a debug-signed APK can never be labelled release-signed. |
| `RC-BLK-003` | ⚠️ **MITIGATED, monitored.** Bounded retry policy: finite 10 s per attempt, deterministic 1/2/3 s backoff, **30 s total budget**, transient-only retries, visible loading/retry state, manual "Try again" preserved. Measured recovery of a 22.7 s cold start (§4a). The underlying Render free-tier spin-down is a Backend/infra issue, not a Mobile one. |
| `RC-BLK-004` | ✅ **RESOLVED.** Android `android:label` and iOS `CFBundleDisplayName`/`CFBundleName` are all **WellaPath**. Application ID and bundle ID deliberately unchanged (see `RC-BLK-010`). |
| `RC-BLK-017` | **NEW — was a live defect.** "Try again" on the first-launch-offline screen **threw** `This widget has been unmounted` and did nothing. `pushReplacement` disposes the splash, so the callback closed over a defunct context — the recovery button on the recovery screen was dead. Pre-existing on `develop`; found by the new splash tests. ✅ **FIXED** — the retry now navigates from the offline route's own context. |

### BLOCKS_STORE_SUBMISSION

| ID | Finding |
|---|---|
| `RC-BLK-005` | **The build points at staging.** `APP_ENV=staging`, `API_BASE_URL` is the staging host, and **no production configuration exists anywhere in the repo.** A production endpoint and artifact origin must exist before submission. |
| `RC-BLK-006` | **No store presence at all** — no listing, screenshots, privacy-policy URL, support contact or data-safety declarations. The location permission and the Sentry dependency both require data-safety answers. |
| `RC-BLK-007` | ✅ **RESOLVED.** Signed AAB built from a clean worktree, `bundletool validate` clean, checksummed, labelled internal-testing only. Not uploaded. |
| `RC-BLK-009` | **iOS app-target privacy manifest absent.** Dependencies ship their own; confirm whether first-party code touches a required-reason API and add `PrivacyInfo.xcprivacy` if so. Not codesigned, and no provisioning profile has been exercised. |
| `RC-BLK-016` | **CB_211 has no clinical or product adjudication.** An engineering-lead disposition (Option D) authorises carrying it, pinned and fail-closed, and it is unreachable through the UI, over-triage, and cannot suppress a red flag — so it does **not** block internal testing. The registry's own `review_trigger` requires resolution **before external beta**; issue #35 is open. Full record: `docs/release/CB_211_DISPOSITION.md`. |
| `RC-BLK-010` | **Application ID differs across platforms** — `org.wellapath.wellapath_mobile` (Android) vs `org.wellapath.wellapathMobile` (iOS). Fix before store records are created; changing it afterwards is not possible. |

### POST_RELEASE

| ID | Finding |
|---|---|
| `RC-BLK-008` | ⚠️ **MITIGATED by truthful wording, not resolved as a feature.** No distance cap was added and ranking is unchanged. Every user-visible "nearby" claim is gone — the locator now says "available facilities", distance stays prominent on every card ("X.X km away", emphasised), and the coverage disclosure is retained. Geographic search remains a Product decision. |
| `RC-BLK-011` | `/config` hash verification **soft-fails on a null/empty hash**. Consider requiring a hash for the three clinical artifacts. |
| `RC-BLK-012` | `targetSdk`/`compileSdk`/`minSdk` are **not pinned** — they follow whichever Flutter version builds. Pin them so the target SDK is a release decision. |
| `RC-BLK-013` | **Toolchain drift:** built on Flutter 3.44.4 / Dart 3.12.2; `CLAUDE.md` declares 3.41.5 / 3.11.3. Reconcile and pin CI. |
| `RC-BLK-014` | Two unused assets ship in the bundle — `illustration_misc.png` and `screenshot_ref.png` (a Figma reference screenshot). |
| `RC-BLK-015` | Kotlin Gradle Plugin deprecation warnings from `sentry_flutter`; future Flutter versions will fail the build. |

**No blocker above is obscured by signing, manifest, nationwide-facilities or
PR #76 work.** `RC-BLK-001` and `RC-BLK-003` are the two that bite the current
candidate first, and neither is related to any of those workstreams.

## 8. Locked principles

| # | Principle | State |
|---|---|---|
| 1 | CDSS, never a diagnosis engine | ✅ onboarding says "Clinical Support System"; results say "possible causes" and "match strength" |
| 2 | No symptom-level PHI server-side | ✅ interceptor bodies off; telemetry privacy guard; count-only token logging |
| 3 | Scoring on-device only | ✅ engine runs locally over downloaded artifacts |
| 4 | Artifacts versioned, never overwritten | ✅ versioned cache keys |
| 5 | Red flag overrides scoring | ✅ 13/13 global rules; 27/27 QB-002 tests |
| 6 | No hardcoded secrets | ✅ scan clean; keystore and `key.properties` gitignored |
| 7 | No out-of-scope features | ✅ wording correction only |
| 8 | No architecture changes | ✅ none |
| 9 | No phase blending | ✅ candidate work excluded and proven excluded |
| 10 | Never commit `.env` | ⚠️ `.env` **is** committed — the documented CLAUDE.md exception; contains staging URLs and flags only, no secrets |

## 8a. Artifacts produced

Nothing was uploaded or submitted. Certificate fingerprints are **not**
published here — the repository has no policy treating them as public release
metadata; only the presence of a valid signature is reported.

| Artifact | sha256 | Bytes | Distributable |
|---|---|---|---|
| **`app-release.aab`** (signing machine, clean worktree) | `cfa41692bcd3fc373665d9b9d79a92fb295aab504e42fa7e0b4bb123e401166e` | 62,078,226 | **YES** — `jar verified`, **internal testing only** |
| `app-release.apk` (signing machine) | `5f84ee9a75829e3842fbc37b3da3fc881e4aa5239757749185ee7aa5bc1ab2ce` | 64,601,706 | **YES** — release-signed |
| `app-release.apk` (CI, unsigned) | `00e406718d80d8267c31f39b0591a116f0d8f4760c774593eb0d80a3089e152b` | 64,593,514 | **NO** — no signature |
| `Runner.app/…/App` (iOS binary) | `08890d1a5bad8e05c507f0fd3bd24fc5ecbeb59667f139a0034b2f33e3711764` | — | **NO** — not codesigned |
| `Runner.app` (zipped bundle) | `84845e2d013115b4a95b086afefa22d04915b7b6da0732a4b660f8b99cf726e3` | 12,811,027 | **NO** — not codesigned |

The signed APK hash reproduced byte-identically across two independent builds.

**AAB (`RC-BLK-007` — closed).** Built from a **clean detached worktree** at
`5aa3680`, on the authorized signing machine. `bundletool 1.18.1 validate`
exits 0 with no errors. Manifest: package `org.wellapath.wellapath_mobile` ·
versionCode **209** · versionName **0.3.0** · label **WellaPath** · minSdk 24 ·
targetSdk 36 · permissions INTERNET + FINE/COARSE_LOCATION. **No debug
certificate, no `debuggable` flag, no bundled secret** — the only bundled
config is the staging `.env` (public URLs and off-by-default flags) and no
Sentry DSN is present. Excluded symbols absent and engine controls present in
the AAB's own `libapp.so`.

**Fail-closed reconfirmed on the bundle path:** the same clean worktree, with
no signing material, **refused** the AAB build and produced no artifact.
Signing material was then referenced **in place by symlink** — never copied.

The AAB is **not committed** and **not uploaded**. It is labelled
**internal-testing only**; no store track is authorized.

## 9. Next action required for internal distribution

✅ `RC-BLK-001`, `002`, `004` and `017` are **closed**; `003` and `008` are
mitigated and measured. What remains:

1. ✅ **AAB produced and verified** (`RC-BLK-007` closed) — signed, validated,
   checksummed, internal-testing only. Not uploaded; upload requires explicit
   authorization.
2. **Confirm the version-name decision.** Build number 209 is derived and not
   negotiable; the *name* moving `1.0.0 → 0.3.0` is a judgment call — it
   matches the real tag line and avoids claiming production maturity, but it
   reads as a downgrade to a tester who saw `1.0.0`. One line in `pubspec.yaml`
   reverses it. Android upgrade eligibility depends only on `versionCode`,
   which increases either way.
3. **Get signing material to a second location** — `RC-BLK-002-FOLLOWON`. The
   build now fails closed instead of producing a debug-signed APK, but the
   keystore exists on **exactly one machine**, is not in any CI secret, and
   Play App Signing is **not** enrolled, so Google holds no copy. An Android
   signing key cannot be regenerated. Full analysis, required actions and the
   authorization matrix: [`SIGNING_CONTINUITY.md`](./SIGNING_CONTINUITY.md).
   Enrolling in Play App Signing at or before first upload is the primary
   mitigation and removes most of the risk.
4. **Backend:** decide whether to remove the Render free-tier spin-down. Mobile
   rides through it now; the wait itself is a Backend property.

Store submission additionally requires the production configuration
(`RC-BLK-005`), the full listing (`RC-BLK-006`), the iOS privacy/codesigning
work (`RC-BLK-009`) and the application-ID decision (`RC-BLK-010`).

**Stop here.** Nothing is merged, uploaded or submitted.
