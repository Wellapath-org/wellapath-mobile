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
| **Play App Signing not yet enrolled** | Google holds no copy. The key exists in exactly one place on earth. |
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
