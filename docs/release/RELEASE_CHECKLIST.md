# Mobile Release Candidate — Readiness Checklist

**Branch:** `release/rc-frozen-baseline`
**Base:** `develop` @ `d820d6c`
**Status:** frozen, unmerged, **not** submitted to any store
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
| `dart format` | 165 files, 0 changed ✅ |
| `flutter analyze` | No issues found ✅ |
| Full test suite | **1,150 passed · 7 skipped · 0 failed** ✅ |
| Clinical case bank | **239 executed · 238 passed · 1 known finding (CB_211) · 0 unexpected failures** ✅ |
| Global red-flag rules | 13/13 exercised ✅ |
| Android release build | APK built and **release-signed** ✅ |
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
| Android signing | release keystore works ✅, but exists only on one machine |
| Android artifact | universal APK — Play requires an **AAB**; none produced |
| App name on device | **`wellapath_mobile`** ⚠️ |
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
| `RC-BLK-001` | **`versionCode` is 1** and `version: 1.0.0+1` has been unchanged across all three beta tags. Play rejects a duplicate `versionCode`; testers cannot upgrade in place. Must be bumped before any distribution. |
| `RC-BLK-002` | **Release signing exists on one machine only.** `key.properties` and the keystore are gitignored (correctly). Any other builder silently falls back to **debug keys** — the build succeeds and prints only a warning, so an unsigned-for-distribution APK can be produced without anyone noticing. |
| `RC-BLK-003` | **First launch fails against a cold backend.** Staging is Render free-tier; measured `/config` latencies of 12.8 s, then repeated 60 s+ stalls, against a 10 s per-attempt timeout. Device-verified: the app lands on the first-launch-offline screen and the user must tap "Try again". Graceful, but a poor first run. |
| `RC-BLK-004` | **App name shows as `wellapath_mobile`** on the Android launcher; iOS shows "Wellapath Mobile" (also not the "WellaPath" brand casing). |

### BLOCKS_STORE_SUBMISSION

| ID | Finding |
|---|---|
| `RC-BLK-005` | **The build points at staging.** `APP_ENV=staging`, `API_BASE_URL` is the staging host, and **no production configuration exists anywhere in the repo.** A production endpoint and artifact origin must exist before submission. |
| `RC-BLK-006` | **No store presence at all** — no listing, screenshots, privacy-policy URL, support contact or data-safety declarations. The location permission and the Sentry dependency both require data-safety answers. |
| `RC-BLK-007` | **No Android App Bundle.** Only a 64.6 MB universal APK was produced. |
| `RC-BLK-009` | **iOS app-target privacy manifest absent.** Dependencies ship their own; confirm whether first-party code touches a required-reason API and add `PrivacyInfo.xcprivacy` if so. Not codesigned, and no provisioning profile has been exercised. |
| `RC-BLK-010` | **Application ID differs across platforms** — `org.wellapath.wellapath_mobile` (Android) vs `org.wellapath.wellapathMobile` (iOS). Fix before store records are created; changing it afterwards is not possible. |

### POST_RELEASE

| ID | Finding |
|---|---|
| `RC-BLK-008` | No distance cap in `getNearbyFacilities` (see §5). Product decision. |
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

## 9. Next action required for internal distribution

1. Bump `version:` in `pubspec.yaml` above every previously distributed
   `versionCode` (`RC-BLK-001`).
2. Decide how release signing reaches CI or a second machine, and make an
   unsigned release build **fail** rather than warn (`RC-BLK-002`).
3. Set the Android `android:label` and confirm the display name
   (`RC-BLK-004`).
4. Accept or mitigate the cold-start first-launch failure (`RC-BLK-003`) — a
   keep-warm ping, a longer first-attempt timeout, or an explicit product
   decision to accept it.
5. Produce an **AAB** for track upload (`RC-BLK-007`).

Store submission additionally requires the production configuration
(`RC-BLK-005`), the full listing (`RC-BLK-006`), the iOS privacy/codesigning
work (`RC-BLK-009`) and the application-ID decision (`RC-BLK-010`).

**Stop here.** Nothing is merged, uploaded or submitted.
