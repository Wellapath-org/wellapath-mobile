# WellaPath Internal Beta — Artifact Freeze & Rollback Procedure

Owner: Mobile Engineer. Phase E9.1.
Applies to the `v0.1.0-beta.1` internal beta release candidate.

---

## 1. Frozen artifact versions

Locked as of this release candidate. **No artifact changes after this point
without engineering lead approval.**

| Artifact | Version | sha256 |
|---|---|---|
| knowledge_base | **2.4** | `6c00d8257f8417e86bd5e237630bf8a4623ad72e2e46b1b071dd447c067cec2b` |
| rules | **2.2** | `1d27e854cba95b179577a88f92445400f494a7fe8e6a53a60fcaa98b3870d1c4` |
| token_dictionary | **1.1** | `0cc47ad9537c0bd4c6ef3aec8f1931eb9b4c62103a8809d16544f94a90b5c019` |
| facilities | **1.1** | `25684c714367abf2f3c305c8a5597b5f7eb0d11baaf658c5b9e2f8f5e2982398` |

Verified against `GET /config` on `wellapath-backend-staging.onrender.com`.
The same three core hashes are pinned in
`test/engine/case_bank/artifact_fixtures.dart`, which fails loudly if a
fixture and its published hash ever drift apart.

### Previous versions, still resolvable for rollback

R2 is append-only by policy — artifacts are never overwritten, only added —
so every prior version remains fetchable at its own URL:

| Artifact | Previous | Notes |
|---|---|---|
| knowledge_base | 2.3 | Pre-E8.2 headache weight (3 rather than 6) |
| rules | 2.1 | Includes dead `rf_147`, retired in 2.2 |

This is what makes artifact rollback possible without a client release.

---

## 2. Rollback procedure

Two independent levers. **Artifact rollback is strongly preferred** — it is
server-side, takes effect on the next assessment, and needs no action from
testers.

### Lever A — artifact rollback (server-side, minutes)

Use when the defect is in clinical content: wrong urgency, wrong ranking, a
red flag rule that misfires.

1. Engineering lead approves the rollback and names the target versions.
2. Backend engineer edits `/config` to point the affected artifact back at its
   previous version URL **and** its previous sha256. Both must change together
   — a stale hash against a rolled-back file fails the client integrity check
   and blocks the assessment entirely.
3. No client release required. `StagedArtifactLoader` keys its Hive cache by
   `<cacheKey>_v<version>`, so a version change is a cache miss and the client
   downloads the rolled-back artifact on the next assessment.
4. Confirm by re-running the case bank harness against the rolled-back
   versions before declaring the rollback good:
   `flutter test test/engine/case_bank_validation_test.dart --dart-define=CASE_BANK_PATH=<bank>`

**Recovery time:** minutes. **Tester action required:** none.

### Lever B — APK rollback (client-side, hours)

Use when the defect is in app code: a crash, a broken screen, a wiring fault
like #34.

1. Engineering lead approves.
2. Re-distribute the previous APK build to testers through the same channel
   the beta was distributed on.
3. Testers install over the existing app. **This only works if both builds
   carry the same signing key** — see the open risk in section 4.

**Recovery time:** hours, gated on testers actually installing.
**Tester action required:** yes.

### Which lever

| Symptom | Lever |
|---|---|
| Wrong urgency / wrong top condition / bad ranking | A |
| Red flag rule fires wrongly or fails to fire | A |
| Facility data wrong or missing | A |
| App crashes, hangs, or a screen is broken | B |
| Engine input wiring wrong (cf. #34) | B |
| Assessment blocked by a failed integrity check | A — re-check the `/config` hash matches the file byte-for-byte |

---

## 3. Build provenance

| | |
|---|---|
| APK | `build/app/outputs/flutter-apk/app-release.apk` |
| Size | 58.8 MB |
| sha256 | `1f10ee12a62440e060a65b9236b052448f4a317fcf89fcb91fcac02b701d583c` |
| Package | `org.wellapath.wellapath_mobile` |
| versionName / versionCode | `1.0.0` / `1` |
| minSdk / targetSdk | 24 / 36 |
| Flutter | 3.44.4 |

Keep the APK and its sha256 for every beta build. Lever B is only usable if
the previous APK is actually retained somewhere retrievable — a build that
exists solely in a CI cache is not a rollback plan.

---

## 4. Open risks against this plan

**The release APK is signed with debug keys.**
`android/app/build.gradle.kts` still carries Flutter's scaffold
(`signingConfig = signingConfigs.getByName("debug")`), and there is no
`android/key.properties`. Consequences:

- The debug keystore is per-machine, so a rebuild elsewhere produces a
  different signature and **testers cannot upgrade in place** — which breaks
  Lever B, the APK rollback path.
- Moving to a real release key later forces every tester to uninstall and
  reinstall, losing cached artifacts and the `onboarding_seen` flag.
- The Android debug key is a shared well-known key and is not appropriate for
  a build distributed to people.

Fixing this needs a keystore generated and stored deliberately, with
`android/key.properties` gitignored per LOCKED PRINCIPLE #6. Raised for
engineering lead decision — not actioned unilaterally, since it is a
credential decision.

**`/config` itself has no rollback lever.** If `/config` becomes unreachable
on a fresh install with no cached config, the client cannot obtain artifact
URLs at all. The retry fix for this is on `feat/e9-config-retry` (PR #26) and
is **not on `develop`**, so it is not in this build.

---

## 5. Verification before declaring any rollback complete

1. `GET /config` returns the intended versions and hashes.
2. Hash in `/config` matches the artifact file byte-for-byte
   (`shasum -a 256 <file>`), or clients will reject it.
3. Case bank harness re-run green against the rolled-back versions.
4. One full assessment completed end to end on a device.
