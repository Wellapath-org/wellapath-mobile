# Sentry activation checklist — build 216 and later

**Status: nothing in this document has been done. This is a plan, not a
record.** Sentry remains disabled in build 215 and in every build to date. No
DSN exists in any artifact, no production key has been created, and no event
has been sent from a distributed build.

**Scope:** engineering crash diagnostics only. Product analytics is a separate
subsystem with separate gates, separate data and a separate decision: see
`TELEMETRY_MVP_PROPOSAL.md`.

This document does not restate how crash reporting works. `CRASH_MONITORING.md`
is the reference for the gating, the sanitiser, the transport and the symbol
upload procedure, and remains authoritative for all of it. What follows is only
the sequence that has to be completed before the subsystem is switched on.

---

## 0. What is already true

Recorded so the checklist below is not mistaken for work that is missing.

| | |
|---|---|
| Implementation | Complete: config gating, privacy sanitiser, first-party transport, Dart symbolication |
| Controlled verification | Builds 212 and 214 exercised the full path with synthetic events |
| Gating | Three independent `--dart-define` gates, all unset in every release build |
| DSN | Never committed. Define-only. Absent from source, `.env` and the verified 215 binaries |
| Event sanitising | Allowlist rebuild, not a denylist: user, request, breadcrumbs, contexts, extra, modules, threads, message, transaction and fingerprint are all dropped |
| Store declarations | Both stores currently declare "no data collected" — correct while disabled |

The three gates, all of which must be satisfied simultaneously:

```
--dart-define=CRASH_REPORTING_ENABLED=true
--dart-define=SENTRY_DSN=<structurally valid DSN>
--dart-define=CRASH_REPORTING_PRODUCTION_APPROVED=true
```

The third is required because the bundled `.env` declares `APP_ENV=production`,
and the config helper fails closed to production when dotenv is unreadable.

---

## 1. Dedicated production key

- [ ] Create a **new Sentry client key** used by nothing else, scoped to the
      production project.
- [ ] Confirm it is distinct from the build-212 key (`internal-212`), the
      build-214-only key and the project's legacy default key.
- [ ] Store it as a CI secret. It must never enter the repository, `.env`,
      a shell history file or a PROGRESS entry.
- [ ] Verify the DSN passes `CrashConfig.isValidDsn` — https scheme, non-empty
      public key, non-empty host, numeric trailing path segment, and none of
      the placeholder substrings.
- [ ] Record only the key's **name and creation date** in the release record.
      Never the DSN itself.

## 2. Production context and release tagging

- [ ] Pass `CRASH_REPORTING_CONTEXT=production` explicitly rather than relying
      on the fallback, so the label is deliberate.
- [ ] Pass `APP_VERSION` and `APP_BUILD` so the release tag resolves to
      `wellapath-mobile@0.3.0+216` and not the `0.0.0+0` default.
- [ ] Confirm the context define is **labelling only** and cannot act as a
      gate — the existing readiness test asserts this; re-run it.
- [ ] Create the matching release in Sentry before the build is distributed, so
      the first event does not create it implicitly with wrong metadata.

## 3. Symbols, and the neutral-path requirement

This is the item most likely to be skipped and the one that leaked a personal
path in the build-214 audit.

- [ ] Build from an approved neutral root per `docs/NEUTRAL_BUILD_POLICY.md`.
- [ ] **iOS specifically:** pass an explicit neutral `-derivedDataPath`. A
      neutral build root alone does *not* give neutral symbols — Xcode's
      DerivedData defaults to the user's home directory regardless of where the
      source tree lives. This caught 8 prohibited findings during the 215
      archive and will recur silently on every iOS build until it is made
      standard.
- [ ] Run `dart run scripts/scan_symbol_artifacts.dart` over the exact upload
      inputs. Exit 0 required. There is no bypass and no warning-only mode.
- [ ] Preserve the scan output as release evidence, and re-run it after every
      rebuild — a rebuild invalidates the previous scan.
- [ ] Upload symbols only via explicit `dart run sentry_dart_plugin`.

## 4. Server-side enrichment — decide before enabling, not after

Server symbolication re-adds `abs_path` values from the uploaded DWARF. These
are **build-host paths, not client data**, and they bypass every client-side
control in this repository.

- [ ] Confirm, on a real symbolicated event, that no `abs_path` contains a
      personal username or a personal worktree name.
- [ ] Apply the founder-side Sentry rule `Remove · Anything · $user.geo.**`
      and verify on a live event. "Prevent Storing IP Addresses" does **not**
      suppress GeoIP enrichment. Note that the corrected rule leaves a
      null-valued scrub shell plus `_meta` annotations — a qualified pass, not
      a clean one.
- [ ] Decide explicitly about `contexts.trace` and the envelope `_dsc` header
      (trace id, release, environment, DSN public key). These are currently
      **not** suppressed, by decision. Re-affirm or change that decision.

## 5. Store and privacy disclosure

Must ship in the **same release** that first enables Sentry — not before, and
not after.

- [ ] Update the Apple privacy declaration: Crash Data and Diagnostics, not
      linked to identity, not used for tracking.
- [ ] Update the Play Data Safety declaration: Crash logs and Diagnostics,
      shared with Sentry as a processor.
- [ ] Add the five-field debug-image disclosure (`type`, `image_addr`,
      `debug_id`, `code_id`, `code_file`).
- [ ] Add the server-enrichment reality from §4 — the declaration must describe
      what is actually stored, including anything enrichment adds.
- [ ] Confirm the published privacy policy covers crash diagnostics. It does
      not currently exist at all, which is a separate blocker.

## 6. Legacy key cleanup

- [ ] Inventory every client key on the `wellapath-mobile` project.
- [ ] Confirm no distributed build references the legacy default key.
- [ ] Disable the legacy key, and the two per-build verification keys, once the
      production key is proven.
- [ ] Record which keys were disabled and when.

## 7. Final production-diff review

- [ ] Diff the enabling build against the last disabled build. The only
      differences should be the defines, the version bump, and the store
      declarations.
- [ ] Confirm no clinical path changed: `lib/core/engine`, `lib/features/assessment`,
      question flow, vocabulary.
- [ ] Re-run the full suite, the clinical regression and the release gates.
- [ ] Confirm the first-party `WellaPathTransport` is in use. Production Sentry
      is a **no-go** on the default SDK transport, which lost two controlled
      events in obfuscated release builds during the 212 test.
- [ ] Verify the build number is unconsumed in the append-only registry.

---

## Resolve before activation, not during

**The DPA record contradicts itself.** `docs/I1_OBSERVABILITY_BASELINE_CLOSURE.md`
and `docs/CRASH_MONITORING.md` §13 both say the Sentry DPA is *pending formal
electronic acceptance*, which would block any Sentry-enabled distribution
beyond the authorised internal engineering group. `docs/store/CRASH_PRIVACY_DECLARATIONS.md`
and `docs/CRASH_VERIFICATION_212.md` say it was *signed and effective
2026-09-21*. The later document ordinarily supersedes, but the earlier one was
never updated, so the contradiction is unresolved on paper. Settle it and
correct whichever document is wrong **before** enabling, because the honest
answer determines whether activation is permitted at all.

## Known limitations that activation does not remove

State these plainly wherever crash metrics are reported, so nobody reads a
partial picture as a complete one:

- **Native crash capture stays off.** Native envelopes bypass the `beforeSend`
  sanitiser, so native fatals are not reported even once Sentry is live.
- **Session tracking stays off**, so there is no crash-free session rate. The
  dashboard reports this as *Not instrumented* rather than a percentage,
  deliberately.
- **No runtime kill switch.** Disabling requires a new build or revoking the
  DSN key.
- **BAA is unavailable on the Team plan** and is not relied upon. PHI is
  excluded from Sentry by architecture, not by contract.
