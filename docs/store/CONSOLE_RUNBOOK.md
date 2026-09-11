# Console runbook — exact steps that require store access

Everything the repository could prepare for internal testing is done at
build 0.3.0+210. The steps below **cannot** be performed without console
access and explicit authorization, and none of them has been performed.

## Prerequisites (before either console)

- [ ] Founder designates the support email + page and approves the privacy
      policy; both go live on wellapath.org
      (`SUPPORT_AND_PRIVACY_POLICY.md`)
- [ ] Founder + engineering lead authorize account creation and uploads

## Google Play (internal testing)

1. Create/join the Play developer account (organisation), pay the fee.
2. Create the app: name **WellaPath**, package **`org.wellapath.app`**
   (this permanently fixes the identifier — confirm it matches
   `test/release/app_name_test.dart` first).
3. **Enrol in Play App Signing before the first upload** — checklist in
   `PLAY_DECLARATIONS.md §4`; register the existing keystore as the
   upload key. (Decision recorded; do not skip.)
4. App content declarations, from the prepared evidence:
   - Privacy policy URL (prerequisite above)
   - Data safety → `PLAY_DATA_SAFETY.md`
   - Health apps declaration → `PLAY_DECLARATIONS.md §1`
   - Content rating questionnaire → `PLAY_DECLARATIONS.md §3`
   - Ads: **No ads**
   - Target audience: 18+ or 13+ per founder/product call (no
     child-directed content)
5. Internal testing track → create release:
   - upload `app-release.aab`
     (sha256 `aa05853c1634febcdf85306729184cc57ebdefd1ac0cc475c2eae559c743cf1b`,
     62,090,591 bytes — verify the hash before upload)
   - release name `0.3.0 (210) — internal, staging`
   - release notes from `docs/release/INTERNAL_TESTING_0.3.0_210.md`
6. Add internal testers (max 100 email addresses), share the opt-in link
   with the tester instructions.
7. **Stop.** Do not promote to closed/open testing or production; do not
   submit for any review beyond what the internal track itself requires.

## Apple (TestFlight internal)

1. Apple Developer Program enrolment (organisation).
2. Register App ID `org.wellapath.app` (explicit, no capabilities), create
   the Apple Distribution certificate and App Store provisioning profile —
   exact list in `APP_STORE_CONNECT_METADATA.md §6`. Store the certificate
   key per `docs/release/SIGNING_CONTINUITY.md` rules.
3. Create the App Store Connect app record from
   `APP_STORE_CONNECT_METADATA.md §1–4`.
4. On the signing machine: configure the team in Xcode, then
   `flutter build ipa --release` and upload with Transporter. (The
   repository's unsigned `Runner.app` proves the build; the ipa must be
   rebuilt signed — expect the same 0.3.0/210 identity.)
5. TestFlight → internal testing group (App Store Connect users only) →
   add the What to Test notes from
   `docs/release/INTERNAL_TESTING_0.3.0_210.md`.
6. **Stop.** No external group, no App Review submission.

## Explicitly out of scope until CB_211 (issue #35) is adjudicated

External/closed beta with outside testers, open testing, production
release, App Review submission for public release. `RC-BLK-005` (no
production backend) and `RC-BLK-006` (listing assets) also stand.
