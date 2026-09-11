# Play Console — Health Apps declaration, permissions, content rating

**Build:** 0.3.0+210 · `org.wellapath.app` · prepared, nothing submitted.

---

## 1. Health Apps declaration — evidence

Play's Health Apps policy requires declaring health features and holding a
privacy policy. WellaPath's position:

| Question | Answer | Evidence |
|---|---|---|
| Is this a health app? | **Yes** — health assessment/reference category | The app assesses symptom urgency and locates facilities |
| Category | Health assessment & symptom checking (CDSS) | Onboarding and home copy: "Clinical Support", "not a diagnosis" |
| Is it a medical device / does it diagnose? | **No.** WellaPath is a Clinical Decision Support System. It never outputs a diagnosis; it maps symptoms to urgency guidance and possible causes with fixed care instructions | LOCKED PRINCIPLE #1; disclaimer on home screen, info modal, results screen |
| Does it handle health data? | Symptom input exists but **never leaves the device**; scoring is on-device; no server-side symptom storage | LOCKED PRINCIPLES #2/#3; `docs/TELEMETRY_MOBILE.md` privacy guard |
| Regulated/clinical claims | **None made.** No regulatory clearance is claimed anywhere; none may be added to the listing | This file; review package |
| Emergency features | Red-flag danger signs escalate to an EMERGENCY screen with a dial-112 action; red flags always override scoring | LOCKED PRINCIPLE #5; 13/13 global rules exercised in the clinical regression |
| Privacy policy URL | **REQUIRED — none exists yet.** Blocking item before the declaration can be completed | `SUPPORT_AND_PRIVACY_POLICY.md` |

## 2. Permissions inventory (Android)

Declared in `android/app/src/main/AndroidManifest.xml` — exactly three:

| Permission | Why | User-facing purpose |
|---|---|---|
| `android.permission.INTERNET` | `/config`, clinical artifacts, map tiles, (optional) staging telemetry | not user-visible |
| `android.permission.ACCESS_FINE_LOCATION` | sort facilities by distance, centre the map | requested in the facility locator only; manual state picker works without it |
| `android.permission.ACCESS_COARSE_LOCATION` | fallback granularity for the same feature | same |

No background location, no camera, no microphone, no storage, no contacts,
no `QUERY_ALL_PACKAGES`. The `<queries>` element covers only
`PROCESS_TEXT` (Flutter engine default) and the dialer is reached via
`ACTION_DIAL`-equivalent `url_launcher` (no permission needed).

iOS equivalent: `NSLocationWhenInUseUsageDescription` only —
"WellaPath uses your location to show nearby health facilities. Your
location never leaves your device."

## 3. Content rating questionnaire — prepared answers

Category: **Utility / reference / health**. Recommended answers, all "No"
unless stated:

- Violence, sexuality, profanity, drugs/alcohol/tobacco (glamorised),
  gambling, hate speech: **No**
- User-generated content or user interaction: **No** (no accounts, no chat)
- Shares user location with other users: **No**
- In-app purchases: **No**
- Health-related content: the app provides **health guidance with medical
  disclaimers**; answer any "does the app provide medical or health
  information" question **Yes** and point to the in-app disclaimers
- Expected rating: Everyone / PEGI 3 equivalent (rating authority decides)

## 4. Play App Signing — decision checklist (DO NOT enrol yet)

Recorded position: enrolling at or before first upload is the **primary
mitigation** for `RC-BLK-002-FOLLOWON` (the upload key exists on exactly one
machine and cannot be regenerated). Checklist for the moment console access
exists:

- [ ] Founder + engineering lead jointly authorise enrolment (credential
      policy in `docs/release/SIGNING_CONTINUITY.md`)
- [ ] Choose **"Use Google-generated app signing key"** and register the
      existing local keystore as the **upload key** — Google then holds the
      app signing key and a lost laptop no longer bricks the install base
- [ ] Verify the upload-key SHA-256 shown by Play matches the local
      keystore before the first upload
- [ ] Record the app-signing-key SHA-256 from Play in
      `SIGNING_CONTINUITY.md` afterwards (fingerprint only, never material)
- [ ] Only after enrolment: upload `app-release.aab` (0.3.0+210) to the
      **internal testing** track — nothing beyond internal
- [ ] Confirm rollback lever: with Play App Signing, in-place upgrade
      continuity is Google-held; update `docs/BETA_ROLLBACK.md`

The alternative (keeping self-managed signing) is rejected in
`SIGNING_CONTINUITY.md` analysis: an unrecoverable single-machine key is an
existential risk with no compensating benefit at this stage.
