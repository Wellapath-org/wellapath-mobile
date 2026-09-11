# App Store Connect — metadata, TestFlight, signing requirements

**Build:** 0.3.0 (210) · `org.wellapath.app` · **prepared only — no Apple
console access exists; nothing registered, uploaded or submitted.**

## 1. App record (create once access exists)

| Field | Value |
|---|---|
| Platform | iOS |
| Name | **WellaPath** |
| Primary language | English (U.K. or U.S. — founder call; app copy is en) |
| Bundle ID | `org.wellapath.app` (register explicitly in the Developer portal first — never a wildcard) |
| SKU | `wellapath-app` |
| User access | Full access (internal team) |

## 2. App information

| Field | Value |
|---|---|
| Subtitle (30 chars) | `Symptom check & care finder` |
| Category | Primary: **Medical**; Secondary: Health & Fitness |
| Content rights | does not use third-party content requiring rights (map tiles are CARTO-served under their terms — record attribution in-app before production) |
| Age rating | complete questionnaire; expect 12+ ("Medical/Treatment Information: Infrequent/Mild") — answer the medical-information question **Yes** |
| Privacy Policy URL | **REQUIRED — does not exist yet** (`SUPPORT_AND_PRIVACY_POLICY.md`) |
| Support URL | **REQUIRED — does not exist yet** |

## 3. App Privacy (labels) — must match `ios/Runner/PrivacyInfo.xcprivacy`

- Crash Data — not linked, no tracking, App Functionality
- Product Interaction — not linked, no tracking, Analytics
- Coarse Location — not linked, no tracking, Analytics
- Nothing else. **Never** declare health data collected — it does not leave
  the device.

## 4. Description (draft — review by founder before use)

> WellaPath helps you decide what to do next when you feel unwell. Answer a
> few questions about your symptoms and WellaPath shows how urgent your
> situation may be, what could be causing it, and where to find care near
> you in Lagos, Kano and FCT.
>
> WellaPath is a clinical decision support tool. It does not give a
> diagnosis and it is not a substitute for a doctor or for emergency
> services. If you have severe symptoms, call 112 or go to the nearest
> facility immediately.
>
> • Quick symptom assessment with clear urgency guidance
> • Immediate emergency guidance when danger signs are detected
> • Find hospitals and clinics, sorted by distance
> • Works offline after first setup

Keywords (100 chars): `symptom,checker,health,triage,clinic,hospital,urgent,care,Nigeria,Lagos,Kano,Abuja`

**Do not claim:** diagnosis, accuracy percentages, regulatory clearance,
nationwide coverage, or production readiness. Apple reviews medical apps
with greater scrutiny (App Review Guidelines §1.4 Physical Harm; §5.1.3
Health data) — metadata must be accurate, backend services must be
reachable during review, and the disclaimers must stay prominent.

## 5. TestFlight — internal testing

- **What to Test** (paste verbatim from
  `docs/release/INTERNAL_TESTING_0.3.0_210.md` — release notes + tester
  instructions; first line "Internal testing — staging").
- Internal testers only (App Store Connect Users, max 100). **External
  testing is blocked** by CB_211 (issue #35) — do not create an external
  group.
- Beta App Description: the release-notes block above. Beta App Review is
  **not** triggered for internal-only testing.
- Export compliance: uses standard HTTPS/ATS encryption only → answer
  "standard encryption, exempt" (`ITSAppUsesNonExemptEncryption=false` may
  be added to Info.plist later to skip the per-build prompt — not added
  yet).

## 6. Signing — exact requirements once access exists (NOT created yet)

Current state, verified: bundle ID `org.wellapath.app` on every
configuration; **no entitlements file, no capabilities** beyond the
implicit defaults (no push, no HealthKit, no app groups, no associated
domains); Release config builds; `MinimumOSVersion` 13.0; built
`Runner.app` is unsigned ("code object is not signed at all").

Required, in order:

1. Apple Developer Program membership (organisation), team agreed.
2. Register App ID `org.wellapath.app` — explicit, **no capabilities
   enabled** (matches the entitlements audit; enable nothing "just in
   case").
3. **Apple Distribution certificate** (one, held by the release manager;
   private key exported to the org's secure store — same continuity rules
   as `docs/release/SIGNING_CONTINUITY.md`).
4. **App Store distribution provisioning profile** for `org.wellapath.app`
   bound to that certificate.
5. In Xcode: Runner target → Signing (Release) → the org team, manual or
   automatic signing with the profile above; then
   `flutter build ipa --release` and upload via Transporter/altool.

Do **not** create or share certificates, keys or profiles before access
and authorization exist.

## 7. Assets still needed (cannot be produced from the repo)

- App Store screenshots (6.7" and 6.5" iPhone minimum) — internal
  TestFlight does not need them; the app record for review does.
- App icon already ships in the binary (Assets.car) — verify 1024px
  marketing icon slot in the asset catalog before store submission.
