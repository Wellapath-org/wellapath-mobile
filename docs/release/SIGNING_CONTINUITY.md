# Android release signing — continuity and recovery risk

Written for Release Step 3 §4. This records an **operational risk**. It is not
an argument for weakening the fail-closed signing policy, and no credential was
copied, moved, backed up or uploaded to produce it.

**Nothing in this document contains a password, a key, a certificate
fingerprint, or a keystore path.** Those live only on the signing machine.

## 1. Where the authorized signing operation is currently possible

**Exactly one place: the founder/engineer workstation that holds the keystore.**

| Fact | State |
|---|---|
| `android/key.properties` present on that machine | yes |
| `android/key.properties` tracked in Git | **no** — gitignored (LOCKED PRINCIPLE #6) |
| Keystore file present on that machine | yes |
| Keystore stored inside the repository tree | **no** — outside it, so no `git clean` or worktree operation can touch it |
| Keystore or `key.properties` in any CI secret | **no** — the repo has one environment, `internal-beta`, and it carries only the Sentry DSN |
| Any second machine, vault, or backup known to this repo | **none** |

Every other environment — CI, a fresh clone, a new laptop, any other engineer —
has **no** signing material. Since Step 2 those environments do not silently
produce a debug-signed artifact; the release build **fails**, or produces an
explicitly unsigned, non-distributable one when
`WELLAPATH_ALLOW_UNSIGNED_RELEASE=true` is set. That is the intended behaviour
and it is what makes this a *continuity* risk rather than a *correctness* one.

## 2. Recovery risk if that machine is lost

**If the keystore is lost, it cannot be regenerated.** An Android signing key
is not recoverable: there is no reissue path, and no amount of repository
access substitutes for it. The consequences, worst first:

| Impact | Consequence |
|---|---|
| **Play App Signing not yet enrolled** (status **unverified**, see §6.1) | Google holds no copy. The key exists in exactly one place on earth. |
| **Existing testers cannot upgrade** | A new key produces a different signature. Every tester must uninstall and reinstall, losing cached artifacts and the `onboarding_seen` flag. |
| **APK rollback lever is void** | `docs/BETA_ROLLBACK.md` Lever B depends on re-distributing a previously signed build. A build signed with a key that no longer exists cannot be paired with new builds. |
| **A published listing would be unrecoverable** | Once an app is published under a key, that key is the app's identity for its lifetime. Losing it after publication means a new listing and the loss of every installed user. This has not happened yet — which is precisely why the window to fix it is now. |
| **Build number continuity survives** | `versionCode` 209 and the registry in `test/release/build_identity_test.dart` are in Git and would be unaffected. Numbering is not the risk; identity is. |

Current exposure is bounded only by the fact that **nothing has been published
to a store yet**. That bound disappears at first submission.

## 3. Required future action — secure backup and second location

None of this is done under this task. Recorded so it is a decision, not an
oversight:

1. **Enrol in Play App Signing** at or before first upload. Google then holds
   the app signing key and the local key becomes an *upload* key, which **can**
   be reset if lost. This single step removes most of §2 and should be treated
   as the primary mitigation.
2. **Back up the keystore and its credentials to a founder-controlled secret
   store** — a password manager or KMS entry, encrypted at rest, access logged.
   Not a cloud drive, not email, not a repository, not a chat message.
3. **Second authorized location.** One additional machine or a break-glass
   vault entry, so a single lost laptop does not end the signing capability.
4. **Record a recovery drill.** A backup nobody has restored is not a backup.
   Restore to a scratch machine, build, confirm the signature matches, and
   record the date — with no fingerprint published unless repository policy
   changes to treat it as public release metadata.
5. **If CI ever needs to sign**, deliver the keystore as an environment-scoped,
   protected secret with required reviewers — the shape the `internal-beta`
   environment already uses for the Sentry DSN — never as a repository-wide
   secret, and never committed.

Until step 1 is done, treat the signing machine as the single point of failure
for the product's Android identity.

## 4. Who must authorize credential transfer

**Founder + engineering lead, jointly.** This matches LOCKED PRINCIPLE #8 for
architecture-level decisions and #6 for credential handling. Specifically:

| Action | Authorization |
|---|---|
| Copying the keystore anywhere | founder + engineering lead |
| Adding signing material to CI | founder + engineering lead |
| Enrolling in Play App Signing | founder (it changes who holds the key) |
| Granting a second engineer signing capability | founder + engineering lead |
| Publishing the certificate fingerprint as release metadata | founder — it is currently withheld because no policy makes it public |

An engineer may **not** move signing material on their own initiative, and no
release task — including this one — constitutes that authorization.

## 5. What this task did and did not do

- **Did:** built a signed AAB on the already-authorized machine, referencing
  the existing `key.properties` **in place via a symlink** into a temporary
  worktree. No credential content was duplicated, and the worktree is
  disposable.
- **Did not:** copy, back up, upload, transmit, print, commit, or publish any
  keystore, password, alias or certificate fingerprint.
- **Did not:** weaken the fail-closed policy to work around the single-machine
  constraint. The clean worktree with no signing material was confirmed to
  **fail** the AAB build before signing material was linked.

Tracked as `RC-BLK-002-FOLLOWON` — an operational blocker for durable internal
distribution, distinct from the now-closed `RC-BLK-002` (which was the silent
debug-key fallback).

## 6. Play App Signing continuity checklist (RC-BLK-002-FOLLOWON)

Added 2026-11-07. Every step is a **founder** action, with the engineering lead
where §4 says so. Nothing here was executed by engineering. No step may put a
keystore, password, alias or fingerprint into Git, CI, chat, email, a ticket or
this document.

**Status correction.** §2 and `RELEASE_CHECKLIST.md` say Play App Signing is
"not enrolled". That was written before the first Play upload. Since then:

- AABs for builds 211, 215 and 216 were uploaded to the existing Play
  **Internal testing** track (`PROGRESS.md`);
- Google Play requires Play App Signing for AAB publishing on apps created
  after August 2021.

So the app is **probably** enrolled, and the local key is probably the
*upload* key. This is inferred, **not verified**: nobody has looked at the
console for it. §6.1 settles it.

### 6.1 Verify enrolment (founder, about 5 minutes, read-only)

1. Play Console → **WellaPath** (`org.wellapath.app`) → **Test and release** →
   **Setup** → **App integrity** → **App signing** tab. Labels move; older
   consoles show **Release → Setup → App integrity**.
2. Record the outcome in the table in §6.5, using one word: **enrolled** or
   **not enrolled**.
   - **Enrolled:** the page shows an **App signing key certificate** (held by
     Google) *and* a separate **Upload key certificate**.
   - **Not enrolled:** the page offers to set up Play App Signing.
3. If enrolled, compare the **upload key certificate SHA-256** on that page
   with the fingerprint of the key that signed build 217. Do this on the
   signing machine only, for example with `keytool -printcert -jarfile` on
   the AAB.
   - Record **match** or **no match**, never the fingerprint itself (§4: it
     is withheld).
   - The AAB carries the certificate, so the keystore does not have to be
     opened for this check.
4. **If not enrolled:** stop, and do not publish anything to a production
   track. The founder and the engineering lead decide whether to enrol.
   - Enrolment is done from the same page. The usual choice is "Use a
     Google-generated key" or "Export and upload a key from Java keystore".
   - The decision changes who holds the app's identity (§4). Do it before
     anything else in §6.

### 6.2 Encrypted offline backup of the upload keystore (founder)

**What:** the upload keystore file and the four values in
`android/key.properties`:

- store password;
- key password;
- key alias;
- the keystore's file name.

The values go into a password manager, never into a document.

**Where: two independent places, neither on the signing machine.**

| # | Location | Form |
|---|---|---|
| A | Founder's password manager vault, which must have MFA on and its access logged | Keystore as an encrypted file attachment. The three secrets as separate fields in the same item, named "WellaPath Android upload key" |
| B | Offline media (USB drive) kept physically apart from the laptop, for example in a home safe or bank box | An encrypted container: macOS Disk Utility "APFS (Encrypted)" image, or `age -p` / `gpg --symmetric --cipher-algo AES256`. Its passphrase is stored in A, never on the media |

**Never:** an unencrypted cloud drive, email, chat, a Git repository, a CI
secret (§3 step 5 has its own rules), a screenshot, or a second laptop without
the §4 sign-off.

**How (outline; run on the signing machine, and print nothing):**

1. Locate the keystore through the existing `android/key.properties`
   (`storeFile`). Do not move or rename the original.
2. Create the encrypted container (B) and copy the keystore into it. Unmount
   it.
3. Attach the keystore and enter the three values in the vault item (A).
4. Check each copy without printing secrets: `shasum -a 256` of the original
   and of each restored copy must be equal. Compare on screen; do not write
   the digest down anywhere shared.
5. Record in §6.5 the date, both locations by description only (for example
   "1Password vault, founder" and "USB-1, home safe"), and the restore-drill
   result.

**Restore drill (§3 step 4).**

1. On a scratch checkout, restore from B.
2. Point a temporary `key.properties` at it, outside the repository.
3. Build a signed AAB and confirm its certificate matches the upload key
   certificate in the console (§6.1 step 3), as match or no match.
4. Delete the scratch copy.
5. Repeat every 6 months, and after any change of laptop.

### 6.3 Upload-key reset procedure (only if Play App Signing is enrolled)

Use this if the upload keystore or its password is lost or compromised.
Existing installs are **not** affected: Google's app signing key does not
change.

1. **Account owner** (the founder) opens Play Console → app → **App integrity**
   → **App signing** → **Request upload key reset** and gives the reason (lost
   or compromised).
2. On a founder-controlled machine, generate a new upload key outside the
   repository, and keep the passwords in the vault, not on the command line
   history:
   `keytool -genkeypair -v -keystore <new-upload-keystore>.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000`
3. Export its **certificate** (public, not the key):
   `keytool -export -rfc -keystore <new-upload-keystore>.jks -alias upload -file upload_certificate.pem`
4. Upload `upload_certificate.pem` in the reset request and submit.
5. Google confirms by email. The new key can be used only after the
   **waiting period the console states**, which has been about 48 hours. Until
   then, uploads signed with either key may be rejected.
6. Update `android/key.properties` on the signing machine to the new keystore,
   redo §6.2 for the new key, and destroy the backups of the old key once the
   new one has been accepted.
7. Build, upload to **Internal testing** only, and confirm Play accepts it.
   Record the date and the upload key change in `PROGRESS.md` and in the
   workspace `CHANGELOG.md`, without the fingerprint.

**If Play App Signing is not enrolled and the key is lost, there is no reset.**
The app needs a new package name and a new listing, and every tester must
reinstall (§2).

### 6.4 Exit criteria for RC-BLK-002-FOLLOWON

The blocker closes only when §6.1 shows **enrolled**, §6.2 shows two
verified backups, and one restore drill has passed. Each fact is recorded in
§6.5 by the founder.

### 6.5 Record (founder fills in; no secret values)

| Check | Result | Date | By |
|---|---|---|---|
| Play App Signing enrolled (§6.1) | | | |
| Upload certificate matches build 217 signer (§6.1 step 3) | match / no match | | |
| Backup A, password manager (§6.2) | location description only | | |
| Backup B, offline encrypted media (§6.2) | location description only | | |
| Restore drill passed (§6.2) | | | |

