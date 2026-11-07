# Release receipts

A release receipt is a single JSON record for one built app artifact (a signed AAB or IPA). It binds together:

- the version and build number;
- the git commit, and whether the tree was clean;
- the creation date;
- the artifact's sha256 and size;
- the `/config` clinical artifact versions and hashes the build was checked against;
- the test summary;
- the clinical status and the known blockers.

It is the "release receipt" called for in `REGULATORY_ENGINEERING_READINESS.md` §3, item 5.

> WellaPath is **not** NAFDAC approved or registered. A receipt is engineering evidence. Its default clinical status is `NOT CLINICALLY CLEARED — SAFETY-01/02/03 open`, and only an explicit, approved decision may change it.

- Schema: [`release_receipt.schema.json`](release_receipt.schema.json) (JSON Schema 2020-12, `wellapath.release_receipt.v1`)
- Generator: `scripts/make_release_receipt.dart` (logic in `scripts/release_receipt.dart`, tests in `test/scripts/release_receipt_test.dart`)
- Receipts are **append-only.** The tool refuses to overwrite an existing receipt. To correct one, issue a new receipt and say why in the release notes.

## Making a receipt (per build, after step 3 or 4 of the internal release process)

Run this from the repository root, at the exact commit the artifact was built from.

```sh
# 1. Save the /config response the build will meet. The tool never fetches it.
curl -s https://api.wellapath.org/config > /path/outside/repo/config-<build>.json

# 2. Write the receipt.
dart run scripts/make_release_receipt.dart \
  --artifact=/path/to/WellaPath-<build>.aab \
  --build-number=<build> \
  --config=/path/outside/repo/config-<build>.json \
  --tests-passed=<n> --tests-skipped=<n> --tests-failed=<n> \
  --tests-command="flutter test --exclude-tags plutil"
# Writes docs/release/receipts/receipt_<version>+<build>_android.json
```

Repeat with `--artifact=…/WellaPath-<build>.ipa` for iOS. That writes `…_ios.json`.

| Option | Default | Notes |
|---|---|---|
| `--artifact` | required | Must be `.aab` or `.ipa`. Streamed through sha256 |
| `--build-number` | required | Must equal the `+N` in `pubspec.yaml`, unless `--version` is given |
| `--config` | required | A saved `GET /config` body. Every artifact must have a version, url and a valid sha256, or the tool fails |
| `--tests-passed/-skipped/-failed` | required | Copy them from the full `flutter test` run for this commit. Failures are recorded (`all_passed: false`), not hidden |
| `--git-commit`, `--git-tree-clean` | read from `git` | Pass them explicitly when building outside the checkout |
| `--clinical-status` | `NOT CLINICALLY CLEARED — SAFETY-01/02/03 open` | Change it only with a recorded clinical decision |
| `--blocker` (repeatable) | added to the defaults | The defaults are SAFETY-01, SAFETY-02, SAFETY-03 and WP-027. `--no-default-blockers` requires an explicit `--clinical-status` |
| `--approver` | `null` | The engineering lead who approved the build, once one is recorded |
| `--date` | now (UTC) | ISO-8601 |
| `--out` | `docs/release/receipts/receipt_<version>+<build>_<platform>.json` | |

Commit the receipt alongside the build's `CHANGELOG.md` row and its release notes. Do not commit the AAB, the IPA or the saved `/config` file. A receipt holds hashes, not artifacts. It must not contain secrets, personal data or facility phone numbers. The tool only ever writes the fields shown in the schema.

**Build 217:** no receipt has been created here. Build 217 is built separately, and its receipt is made by whoever builds it, using the commands above.
