# Store readiness — 0.3.0+210 (`org.wellapath.app`)

**Scope:** everything preparable for Play internal testing and TestFlight
internal testing **without console access**. **Nothing was uploaded,
submitted, or enabled for external testing.** Prepared 2026-09-11 on the
authorized signing machine.

## 1. Application identifier — resolved to `org.wellapath.app`

`RC-BLK-010` (platform identifier mismatch) is **closed** before any store
record exists. Evidence, gathered before the change:

| Check | Result |
|---|---|
| wellapath.org identity | WellaPath's own live site ("Join the waitlist · WellaPath", `lang="en-NG"`, /brand/wordmark.webp); registrar-managed DNS; CLAUDE.md names `api-staging.wellapath.org` as the project backend |
| Play listing for `org.wellapath.app` | HTTP **404** — never published |
| App Store lookup (`itunes.apple.com/lookup?bundleId=org.wellapath.app`) | `resultCount: 0` — never published |
| Repo history (`git log --all -S 'org.wellapath.app'`) | zero prior uses |
| Build registry | every prior distributable build is under the old identifiers |

Changes: Android `applicationId`, iOS `PRODUCT_BUNDLE_IDENTIFIER` (all
Runner configs + RunnerTests), and the map tile `userAgentPackageName`
(the only external service that carried the old identifier). Android
`namespace` and the Kotlin package stay `org.wellapath.wellapath_mobile` —
code-internal, no store meaning. No Firebase, deep-link, OAuth or
notification configuration exists to update (verified: no
`google-services.json`, no `GoogleService-Info.plist`, no intent-filter
beyond MAIN/LAUNCHER, no entitlements). Sentry is DSN-based and
identifier-independent. Parity is pinned by
`test/release/app_name_test.dart` (both platforms must equal
`org.wellapath.app`; retired IDs must not reappear).

## 2. Build identity — 0.3.0+210

209 was appended to the append-only registry
(`test/release/build_identity_test.dart`): it was attached to signed
distributable AABs/APK under the old identifier, never uploaded. **210 has
never been distributed or uploaded** — no tag, no CI release identifier,
no rollback record, no registry entry, no history hit; the registry test
fails on any reuse or regression.

## 3. Internal-build configuration

- `lib/core/config/build_environment.dart`, validated in `main()` before
  the first frame: an internal/staging build pointing at any non-staging
  host **refuses to start**; a production-declared build pointing at
  staging **refuses to start**; `TELEMETRY_PRODUCTION_APPROVED=true`
  cannot travel in a staging build; unknown `APP_ENV` fails. No
  production endpoint exists and none was invented — `APP_ENV=production`
  therefore always fails today (`RC-BLK-005` intact by design).
- Visible marker **"Internal testing — staging"** on the home footer
  (nonclinical), internal builds only; widget-tested.
- Telemetry disabled (`TELEMETRY_ENABLED=false` shipped), crash reporting
  disabled (no DSN), no production secrets (secret scans clean).
- Release notes lead with "Internal testing — staging"
  (`INTERNAL_TESTING_0.3.0_210.md`), pinned by test.

## 4. Android artifact — signed AAB

| | |
|---|---|
| File | `app-release.aab` — **internal testing only, NOT uploaded** |
| Authoritative build | clean detached worktree at `ca2abec`, fail-closed reconfirmed first (no signing material ⇒ build refused) |
| SHA256 | `a599ab746e77aef55bf4779888b4e382c05639cb3041b396a13ccaa240a08e5a` |
| Bytes | 62,090,831 (477 zip entries) |
| Superseded main-checkout build of the same tree | `aa05853c…3cf1b` (62,090,591 B) — all 461 non-per-build, non-path-dependent entries CRC-identical to the authoritative build |
| Signature | `jar verified`, single signer `CN=John Oluwaseyi, O=Wellapath` — **0 debug-certificate matches** |
| Identity | `org.wellapath.app` · versionName 0.3.0 · versionCode 210 · label WellaPath |
| SDK | minSdk 24 · targetSdk 36 · `debuggable` absent |
| `bundletool 1.18.1 validate` | exit 0, no errors |
| Bundled `.env` | staging URLs only; `TELEMETRY_ENABLED=false`; `TELEMETRY_PRODUCTION_APPROVED=false`; no DSN, no secret |
| Secret scan | no key material, DSNs or credentials in any ABI's `libapp.so` or the repo; 0 signing files tracked |
| Excluded symbols | IM003/ClosureGraph, QuestionFlow (4), Vocabulary (4) consumers **absent from all three ABIs**; 9 engine controls present; retired locator strings gone |
| Payload manifest | `AAB_210_PAYLOAD_MANIFEST.txt` — per-entry CRC32+size for all 477 entries; 4 PER-BUILD entries (R8 `buildTimeNs` → signing chain) and 12 PATH-DEPENDENT entries (Dart AOT embeds the absolute build directory in `libapp.so`/`libdartjni.so` + `.sym`) are tagged. Compare the 461 untagged entries, never the container hash |

## 5. iOS artifact — unsigned release build

| | |
|---|---|
| File | `build/ios/iphoneos/Runner.app` — **not codesigned** ("code object is not signed at all"), not distributable |
| Identity | `org.wellapath.app` · 0.3.0 · 210 · MinimumOSVersion 13.0 |
| App binary sha256 | `26f526ce2bcf2f815489e56c58a4008c6497b2b4d7149a78d905b6f16c222eec` (`App.framework/App`) |
| Zipped bundle sha256 | `a1117386279e41ab2874cd958ab5e2188450a64314e4d2358c8d97f96fe82e16` (12,805,930 B) |
| Privacy manifests | **7 present**: app-target `PrivacyInfo.xcprivacy` at bundle root (`plutil` OK) + Flutter.framework + Sentry.framework + shared_preferences / url_launcher / geolocator / package_info_plus bundles |
| Entitlements / capabilities | none (no entitlements file; stock AppDelegate/SceneDelegate; nothing to remove) |
| Excluded symbols | absent from `App.framework/App`; engine controls present |

App-target manifest (`ios/Runner/PrivacyInfo.xcprivacy`): no tracking, no
tracking domains; CrashData + ProductInteraction + CoarseLocation, all
not-linked/non-tracking; UserDefaults CA92.1. Audit:
`docs/store/IOS_PRIVACY_MANIFEST_AUDIT.md`. This closes the manifest half
of `RC-BLK-009`; codesigning/provisioning remain console-gated
(`docs/store/APP_STORE_CONNECT_METADATA.md §6`).

## 6. Verification at this tree

- `dart format` clean · `flutter analyze` no issues
- Full suite: **1,321 passed · 7 skipped · 0 failed** (was 1,292; +29 from
  the new identity/config/privacy gates and marker test)
- Clinical regression unchanged: **239 executed · 238 passed · 1 known
  finding (CB_211) · 0 unexpected failures**; 13/13 global red-flag rules;
  QB-002 27/27
- Release gates (`test/release/`): 85 passed — identity parity, build
  monotonicity, cross-environment gates, permissions inventory pinned
  (INTERNET + FINE/COARSE location only), iOS purpose strings, privacy
  manifest, signing policy, CB_211 disposition
- Cold-start/offline recovery: splash retry-policy suite green (device
  measurements recorded at 209; policy untouched)
- Facility-coverage wording: coverage-disclosure tests green (Lagos, Kano,
  FCT named; no nationwide claim)

## 7. What still blocks what

| Gate | Blockers |
|---|---|
| Upload to internal tracks | console access + authorization; support email + privacy-policy URL live; Play App Signing enrolment decision executed (`PLAY_DECLARATIONS.md §4`); iOS certificate + profile (`APP_STORE_CONNECT_METADATA.md §6`) |
| External beta | **CB_211 / issue #35 adjudication** (`RC-BLK-016`); carried-forward I1 items (native crash capture, physical-device validation, DPA acceptance, analytics consent) |
| Production / store release | `RC-BLK-005` (no production backend), `RC-BLK-006` (listing assets, screenshots), plus everything above |

Console-gated steps, in order: `docs/store/CONSOLE_RUNBOOK.md`.

**Nothing was uploaded or submitted to any store, track or tester group.**
