# I1 Telemetry — Low-End Android Validation

**Phase:** I1 (Observability & Baseline) · **Workstream:** W1 (Privacy-Safe Product Analytics)
**Gate:** low-end Android emulator validation, telemetry OFF vs ON
**Recommendation:** **PASS** — see §14 for the scope of that recommendation.

> **I1 is not complete.** The crash-monitoring provider decision is a separate,
> still-open I1 gate (`docs/TELEMETRY_MOBILE.md` §10). Physical low-end handset
> validation is also carried forward as a pre-external-beta gate (§13).

---

## 1. Source under test

| | |
| --- | --- |
| Mobile source commit | `8ac29ad735c105cc55c489678acf4dfe0faf3ac6` |
| Enablement fix | PR #62, merge `e48655ce1e181df5155f8c3b0ddd8edf1a6cbe47` |
| `os_version` fix | PR #63, merge `8ac29ad735c105cc55c489678acf4dfe0faf3ac6` |
| Telemetry feature | PR #61, merge `e853125b65dde333c0454654e0f8d5b7b2266f46` |
| Backend contract | telemetry **v1.0**, `5e13379f19c53ec90cee7958dc029d908c342dcd` |
| Flutter | 3.44.4 stable |
| Frozen artifacts | token_dictionary 1.1 · knowledge_base 2.4 · rules 2.2 · facilities 1.1 |

Both comparison APKs were built from that commit, `--target-platform android-arm64`,
release, signed from the project keystore. The OFF APK's SHA-256 reproduced
byte-identically across two independent builds, confirming provenance.

| Build | Enablement |
| --- | --- |
| OFF | default configuration, no telemetry define |
| ON | `--dart-define=TELEMETRY_ENABLED=true` plus a base URL define |

Effective state was confirmed on-device before any measurement: the OFF build
logs `Telemetry disabled by configuration`, the ON build logs `Telemetry enabled`.
Production telemetry was never enabled; the production double-gate is unchanged
and covered by 36 automated tests.

---

## 2. Emulator profile

| | |
| --- | --- |
| AVD | `wellapath_lowend` |
| Device | Google Pixel |
| Android | 8.0.0 "Oreo", **API 26** |
| ABI / cores | `arm64-v8a`, 4 |
| RAM | 2 GB configured |
| Screen | **720×1280 @ density 320** → logical 360×640 |
| System image | `google_apis/arm64-v8a`, Play Store disabled |
| GPU | `hw.gpu.enabled=no` — **software rendering** |

The resource profile was not modified at any point. Verified at runtime each
session: `720x1280`, density `320`, API `26`, `arm64-v8a`.

---

## 3. Verified interaction methodology

`uiautomator dump` returns no text for a Flutter surface by default. Enabling an
accessibility service makes Flutter publish its semantics tree, after which every
control is addressable by its **visible label and reported bounds**.

Every action followed the same protocol:

1. dump the UI hierarchy and assert the **current** screen matches the expected checkpoint;
2. resolve the target control from **that dump's** labels and bounds;
3. tap the resolved centre;
4. wait for the UI to settle;
5. dump again and assert the **resulting** screen matches the expected next checkpoint;
6. stop immediately on any mismatch.

No coordinate was ever carried across screens. Checkpoints were logged with mode,
step, expected/observed screens, resolved control, bounds, result, PID and
evidence reference.

**Accessibility setup and restoration.** `enabled_accessibility_services` and
`accessibility_enabled` were set to activate the semantics tree, with
`touch_exploration_enabled` held at `0` so single taps were not reinterpreted as
explore-by-touch. Both settings were **restored afterwards**
(`accessibility_enabled=0`, `enabled_accessibility_services` deleted). No
application behaviour was modified to facilitate testing.

### A harness defect found and fixed mid-validation

Control resolution originally used a first-substring match. Asked for the `Next`
button on the intro screen, it matched the body copy *"…decide your next course
of action"* and silently tapped a paragraph. This produced a run of apparent
"flaky taps" that were in fact precise taps on the wrong element. Resolution now
ranks **exact label → whole-word (short label) → substring**.

This could only ever cause false *failures*, never false passes: a mis-tap cannot
produce the asserted next screen, so the post-condition check fails. All results
in this document were confirmed after the fix.

---

## 4. Excluded evidence

The following were produced during earlier attempts and are **excluded from every
conclusion here**:

| Excluded | Why |
| --- | --- |
| Fixed-coordinate walkthrough memory series | Actions ran behind the UI; a screenshot labelled "result" was actually the body-area screen. Labels unreliable. |
| Screenshots from that run | Incorrectly labelled against the state they captured. |
| Pre-fix `os_version` payloads | Captured before PR #63; carry the defective `"os_version":"64"` value. Retained only as the defect record in §11. |
| Any measurement taken before screen verification | Superseded by verified equivalents. |
| Partial/failed harness runs | Superseded. |
| First after-flush memory pair (+13.1%) | Single paired observation with unequal preceding activity — see §9. |

---

## 5. Startup comparison (final code)

20 observations per mode per kind, interleaved **OFF/ON/ON/OFF** over 10 cycles.
Constant across all runs: source commit, Flutter version, AVD profile, release
build, network state, app data (never wiped after initial install), settle
timings, measurement command (`am start-activity -W`, `TotalTime`).

**Cold** — force-stop then launch, identical data policy each time.
**Warm** — background and resume the same initialised process, no force-stop,
with the driver waiting until the app genuinely left the foreground.

| | n | min | median | mean | p95 | max | sd |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Cold OFF | 20 | 205 | 299.5 | 335.7 | 583 | 1007 | 178.0 |
| Cold ON | 20 | 215 | 288.0 | 321.8 | 506 | 648 | 110.1 |
| Warm OFF | 20 | 68 | 100.5 | 121.7 | 237 | 267 | 60.6 |
| Warm ON | 20 | 61 | 85.0 | 131.2 | 220 | 681 | 135.8 |

Cold: **−13.9 ms (−4.2 %)** mean, Welch t = −0.30.
Warm: **+9.6 ms (+7.9 %)** mean, **−15.5 ms (−15.4 %)** median, Welch t = +0.29.

Both deltas are **0.09 pooled standard deviations** with fully overlapping ranges.

> **No measurable regression at this sample size.** The signs disagree between
> mean and median on warm start, which is what noise looks like, not a cost.

---

## 6. Equivalent-state memory

TOTAL PSS, captured only after positively verifying the screen, with the same
settling interval and the same command, and with the process PID recorded before
and after each capture (stable in every case — no restart mid-measurement).

| State | OFF (kB) | ON (kB) | Δ | Δ % |
| --- | --- | --- | --- | --- |
| Home, settled after startup | 46,461 | 44,664 | −1,797 | −3.9 % |
| Active assessment (same verified step) | 51,294 | 52,613 | +1,319 | +2.6 % |
| Result (same completed assessment) | 69,663 | 64,186 | −5,477 | −7.9 % |
| Locator (same search state) | 80,252 | 76,497 | −3,755 | −4.7 % |

Deltas run in both directions and are consistent with allocator variation rather
than a telemetry cost.

---

## 7. Repeated after-flush memory

The initial after-flush pair showed ON +9,271 kB (+13.1 %). That was a **single
paired observation with unequal immediately preceding activity** and was treated
as inconclusive rather than as a result.

Repeated under controlled equivalent conditions — identical starting screen,
identical drained queue, identical flush window, identical sink, identical
settling interval, verified final screen, verified process identity — and
interleaved OFF/ON, ON/OFF, OFF/ON:

| Pair | OFF (kB) | ON (kB) | ON − OFF |
| --- | --- | --- | --- |
| 1 (OFF→ON) | 45,004 | 44,329 | −675 |
| 2 (ON→OFF) | 44,373 | 44,422 | +49 |
| 3 (OFF→ON) | 44,311 | 44,576 | +265 |

| | OFF | ON | Δ | Δ % |
| --- | --- | --- | --- | --- |
| median | 44,373 | 44,422 | **+49** | **+0.11 %** |
| mean | 44,563 | 44,442 | **−120** | **−0.27 %** |
| range | 44,311–45,004 | 44,329–44,576 | | |

The paired deltas **change sign** (−675, +49, +265), and the mean delta of 120 kB
is a fraction of the 693 kB within-mode spread of the OFF samples alone.

> **No persistent material telemetry memory regression.** The original +13.1 %
> was an artefact of unequal preceding activity, now resolved by controlled
> pairing. No optimisation was implemented — none is indicated.

---

## 8. Scoring equivalence

Case **LOWEND-A**, a non-red-flag assessment. Identical inputs in both modes, 21
verified checkpoints each. Clinical answers are held in controlled test evidence
and are deliberately not reproduced here.

| | OFF | ON |
| --- | --- | --- |
| Screen sequence | identical | identical |
| Conditional branching | pregnancy step skipped | **same** |
| Steps reached | 8 | 8 |
| Urgency | URGENT | URGENT |
| Guidance | "You should consult a doctor" | identical |
| Ranked output | 1 Malaria · 2 Pneumonia (Children) · 3 Dysentery | **identical** |
| Explanations | — | identical |

Matches the E9 expectation. No input was adjusted to force the expected output.
No visible delay attributable to telemetry; no telemetry failure affected
progression.

---

## 9. Red-flag comparison

Case **LOWEND-RF-01**, the established red-flag regression case from E4.3 TEST 1
and the E9 device pass (global red-flag token, rule *"Active Seizures"*). Not a
new clinical case; inputs unmodified.

| | OFF | ON |
| --- | --- | --- |
| Triggering step | same | same |
| Interruption point | immediately after the final input | **same** |
| Presentation | `EMERGENCY` · "Seek medical care immediately" · *"Active Seizures — this is a universal danger sign"* | **identical** |
| Emergency actions | Call Emergency, Find Nearby Care | **identical** |
| Scoring path shown | none | none |
| Additional screens | none | none |
| Time from final input to interruption | **3.3 s** | **3.3 s** |

A third run, with a **populated queue and no connectivity**, reached the
interruption in **3.2 s** — no degradation under the worst configuration tested.

Red-flag evaluation precedes scoring: the interrupt screen carries no
`Possible Conditions` section and no ranked output, so scoring never took
precedence.

**Timing method and limits.** Measured wall-clock from issuing the final tap to
the interrupt screen being observed in the hierarchy, polled at ~1 s. It includes
a scripted loading animation of roughly 1.6 s. Resolution is therefore about
±1 s and these figures are **not** a frame-level latency measurement. No
threshold is asserted; the finding is that OFF and ON are indistinguishable
within the method's resolution.

### Telemetry indistinguishability

| | Ordinary (LOWEND-A) | Red flag (LOWEND-RF-01) |
| --- | --- | --- |
| Sequence | `assessment_start` → `assessment_step_view` ×8 → `assessment_complete` → `result_view` | `assessment_start` → `assessment_step_view` ×7 → `assessment_complete` → `result_view` |
| `completion_status` | `completed` | **`completed`** |
| `result_view` emitted | yes | **yes** |

Structurally identical. The step count differs because the two cases have
different follow-up depth — a property of the flow the user walked, which varies
in non-red-flag assessments too, not a red-flag signal. `duration_ms` and the
opaque IDs differ, as expected.

Notably `emergency_action` appeared in the **ordinary** run (the user opened the
locator from the results screen) and not in the red-flag run — the opposite of a
red-flag detector.

> **No event name or property acts as a red-flag detector.**

---

## 10. Offline, restart and reconnection

Connectivity was severed by disabling Wi-Fi and data and setting airplane mode,
verified by `Network is unreachable` from the device.

| Checkpoint | Observation |
| --- | --- |
| Offline cold launch | reaches home from cached config; telemetry reports enabled |
| Assessment offline | completed end to end, 18 verified checkpoints |
| Result offline | **URGENT / Malaria — identical to the online result** |
| Scoring | on-device throughout |
| Navigation | never blocked by telemetry |
| Events delivered while offline | **0** |
| Send failures | 15, all contained inside the telemetry layer |
| Crashes / ANRs | 0 |

**Termination and restart while still offline** (force-stop, no data cleared):
the app launched normally, the queue survived, no malformed-entry recovery was
triggered, no corruption occurred, and **no assessment or clinical navigation
repeated** — the app resumed at home, not mid-assessment.

**Reconnection**, with the app running and the recovered queue intact:

| Metric | Value |
| --- | --- |
| Envelopes | 2 |
| Events delivered | 12 (11 recovered + 1 post-reconnection) |
| Largest batch | **11 events** (≤ 20 ✓) |
| Largest request | **2,328 bytes** (≤ 32,768 ✓) |
| Event IDs unique | yes |
| Duplicates / rejected / non-retryable drops | 0 / 0 / 0 |
| Clinical navigation repeated | none |

Occurrence time was preserved across the outage **and** the restart:

```
assessment_start   client_ts = 17:15:41.875Z    sent_at = 17:21:32.763Z
assessment_complete client_ts = 17:19:19.484Z   sent_at = 17:21:32.763Z
```

~6 minutes between occurrence and transmission, with `client_ts` intact — which
is exactly what the queue is required to guarantee. Flush was asynchronous and
the UI remained responsive throughout.

A subsequent termination and restart after reconnection showed the drained queue
stayed drained; accepted events were not recreated.

---

## 11. Queue capacity, ordering and concurrency

Per the brief, existing telemetry test support was used rather than driving 500
clinical journeys through the UI. No queue-stress traffic was sent to staging;
device-level queue work drained to a controlled local sink.

| Property | Evidence | Result |
| --- | --- | --- |
| Capacity exactly 500 | `queue_test.dart` | PASS |
| 501st event drops the **oldest**, retains newest | `queue_test.dart` | PASS |
| Large overflow drops exactly the excess | `queue_test.dart` | PASS |
| FIFO ordering | `queue_test.dart` | PASS |
| `event_id` / `client_ts` survive round trip | `queue_test.dart` | PASS |
| 30-day expiry | `queue_test.dart` | PASS |
| Corrupted / wrong-schema record discarded, queue still drains | `queue_test.dart` | PASS |
| Concurrent flush: overlapping flushes share one pass | `service_test.dart` | PASS |
| Concurrent flush: no event sent twice when flushes race | `service_test.dart` | PASS |
| Interrupted flush leaves the batch queued, not half-removed | `service_test.dart` | PASS |
| Restart re-sends queued events with original IDs | `service_test.dart` | PASS |
| `event_id` stable across every retry | `service_test.dart` | PASS |

Ordering proofs use non-clinical sequential fixture identifiers. No symptom,
answer, condition, red flag, location or identity value is used as a test marker.

**Device behaviour with a populated queue** (queue populated offline through
ordinary lifecycle events, then a full red-flag assessment run):

| Check | Result |
| --- | --- |
| App launches | PASS |
| Home responsive | PASS (hierarchy resolved in ~1.2 s) |
| Assessment begins and navigates | PASS, 14 verified checkpoints |
| Red-flag evaluation immediate | **PASS — 3.2 s** |
| Scoring on-device | PASS |
| Crash / ANR / memory-pressure termination | **none** |
| Queue corruption | none |

---

## 12. Captured-payload privacy

Payloads were captured through a controlled **local** sink so the exact bytes the
device transmits could be inspected. The complete ON clinical journey — a full
assessment producing URGENT/Malaria, plus a locator search and facility
interaction — produced **18 events**:

```
app_open ×3 · assessment_start ×1 · assessment_step_view ×8
assessment_complete ×1 · result_view ×1 · emergency_action ×1
facility_search ×1 · facility_view ×1 · directions_open ×1
```

Representative events, unmodified:

```json
{"event_name":"assessment_complete","assessment_session_id":"<opaque>",
 "completion_status":"completed","duration_ms":468469,"step_count":8, ...}
{"event_name":"facility_search","search_mode":"nearby","result_count":30, ...}
{"event_name":"facility_view","facility_id":"ng_lag_1261","source":"map", ...}
"app": {"platform":"android","app_version":"0.2.0","app_build":"207"}
```

| Check | Result |
| --- | --- |
| Undeclared keys on any event | **NONE** |
| Envelope keys | exactly `contract_version`, `sent_at`, `app`, `events` |
| `app` block | exactly three keys |
| `os_version` | **absent** |
| `question_id`, `urgency_category`, `admin_area_code` | **absent** |
| Symptom / complaint / answer / condition / score / red flag / rule / urgency | **absent** |
| Clinical narrative, pregnancy status, free text | **absent** |
| Coordinates, address, raw query, location history | **absent** |
| Identity, credentials, arbitrary metadata | **absent** |

A literal scan of the raw captured bytes for the clinical terms actually on
screen during the journey — `malaria`, `fever`, `chills`, `urgent`, `seizure`,
`danger`, `lagos`, `hospital` — returned **no matches**.

`facility_id` is `ng_lag_1261`, the versioned facilities artifact identifier —
**not** the facility name displayed on screen. `assessment_step_view` carries
`step_index` only, with no `step_count`, as designed.

The red-flag run was inspected separately with the same result: zero prohibited
terms, including `seizure`, `rule`, `urgency` and `danger`.

### The `os_version` defect this validation caught

Before PR #63, a device running **Android 8.0.0** transmitted
`"os_version":"64"`. Dart's `Platform.operatingSystemVersion` returns a kernel
uname string on Android, and the normaliser took its leading numeric fragment.
The value was contract-*valid*, so the backend accepted it with a 202 and no
server-side validation could have detected it. The field is now omitted
entirely. Those pre-fix payloads are excluded from the evidence above.

---

## 13. Limitations

- **Software rendering.** `hw.gpu.enabled=no`. Frame-level rendering behaviour on
  this emulator **does not represent physical hardware** and no frame timing is
  claimed here. The emulator was used to detect gross stalls, ANRs, crashes and
  comparative functional degradation — for which it is suitable and conservative.
- **Timing resolution** for the red-flag measurement is roughly ±1 s and includes
  a scripted loading animation; it is a comparative figure, not a latency budget.
- **Sample sizes** are 20 per mode per kind for startup and 3 pairs for
  after-flush memory. Adequate to exclude a material regression; not adequate to
  resolve differences smaller than run-to-run variation.
- **Physical low-end handset validation remains required before external beta.**
  This gate does not substitute for it.

---

## 14. Recommendation

**The low-end Android emulator gate PASSES.**

| Gate | Result |
| --- | --- |
| Startup, OFF vs ON | PASS — no measurable regression |
| Equivalent-state memory | PASS |
| Repeated after-flush memory | PASS |
| Scoring equivalence | PASS — identical output |
| Red-flag precedence and immediacy | PASS — identical, 3.3 s both modes |
| Red-flag telemetry indistinguishability | PASS |
| Offline assessment | PASS — on-device, identical result |
| Queue persistence across restart | PASS |
| Reconnection and bounded flush | PASS |
| Queue capacity, drop-oldest, concurrency, interruption | PASS |
| Populated-queue clinical responsiveness | PASS |
| Locator behaviour and privacy | PASS |
| Captured-payload privacy | PASS — no prohibited data, no `os_version` |
| Automated regression | PASS |

Crashes, fatal exceptions, ANRs, memory-pressure terminations, queue corruption,
unexpected retries: **zero** across every run in either mode. Telemetry send
failures occurred only while connectivity was deliberately severed and were fully
contained inside the telemetry layer.

### Still open

- **Crash-monitoring provider — unresolved.** A separate I1 gate. No provider was
  added; the boundary and sanitiser collect and transmit nothing.
- **Physical low-end handset validation** — carried forward to pre-external-beta.
- Analytics consent (Product/Privacy) and the `admin_area_code` artifact mapping
  (facilities owner) remain open, neither blocking this gate.

> **I1 remains open pending the crash-monitoring decision.**

---

## 15. Automated regression at time of sign-off

Source `8ac29ad`. `flutter analyze`: no issues. `dart format --set-exit-if-changed`: clean.

| Suite | Result |
| --- | --- |
| Complete Flutter suite | **577 passing, 13 skipped** |
| With staging gate enabled | **584 passing, 6 skipped** |
| Contract parity | 11 passing |
| Privacy / adversarial | 84 passing |
| `os_version` omission | 21 passing |
| Enablement safety | 36 passing |
| Session & configuration | 34 passing |
| Queue | 19 passing |
| Service (retry, offline, concurrency) | 40 passing |
| Schema conformance | 19 passing |
| Transport classification | 26 passing |
| Clinical regression | 10 passing |
| Clinical / Top-50 | **241 passing, 6 skipped** |

The 6 remaining skips are the pre-existing case-bank validation tests, which skip
when no case bank is present at the default path — awaiting
`wellapath-knowledge-base/testing/case_bank_v1.json`. **No new non-network
skips.** The 13 skips in the ungated run are those 6 plus 7 network-gated staging
integration tests.
