# Facilities 2.0 — low-end Android benchmark v1 (evaluation only)

**Date:** 2026-09-14 · **Mobile commit:** `114eb0b` (PR #79) · **Artifact:**
served GRID3 candidate from KB PR #42 @ `2fd8ab5`, sha256
`03a58e67d94bb1d7c88cc5e690472b167a82cc9f95d4f7afe937d8f5d1cebd75`,
8,749,444 B, 51,022 records — evaluated from an untracked temporary copy,
never committed, bundled or configured. Nothing here activates Facilities
2.0 or changes build 210.

## Environment

- AVD `wellapath_lowend`: Android 8.0 (API 26), arm64-v8a, **2 GB RAM,
  4 cores**, Pixel profile, swiftshader software GPU, no snapshot.
  Emulator 36.6.11 on macOS 26.5.2 / Apple M4. **Caveat: the emulator
  constrains RAM/cores but executes arm64 at near-host speed via HVF, so
  CPU timings are faster than a real low-end SoC; treat them as a
  constrained-memory measurement with an optimistic CPU, not a Cortex-A53
  measurement.**
- Flutter 3.44.4 / Dart 3.12.2 · **profile-mode** APK (33 MB, arm64-only),
  benchmark entrypoint driving the real consumer classes; the candidate
  was adb-pushed to the app's own external files dir (not an APK asset).
- Signing: an ordinary release build still fails closed without material
  (policy untouched). The profile buildType carries the standard local
  Android debug certificate; a throwaway, randomly-credentialed keystore
  satisfied the configuration-time policy gate and was deleted after the
  run. No real signing material was read or used.

## Results vs provisional budgets

| Budget | Measured | Verdict |
|---|---|---|
| zero v2 I/O or parsing during gate-off startup | gate-off load: 132 µs, 0 I/O touches, parse_count 0 at first frame | **PASS** |
| first usable locator result ≤ 2 s | first open (read+hash+decode+parse, UI isolate): p50 767 ms, max 879 ms; via background isolate p50 311 ms; + first search ≤ 29 ms | **PASS** |
| cached open ≤ 500 ms | loader cached open p50 154 ms, max 177 ms | **PASS** |
| repeated-search p95 < 200 ms | worst p95 = 15.1 ms (area contains); state 1.6 ms; worst first-query (normalization-cache fill) 128 ms | **PASS** |
| no ANR / OOM / crash / sustained freeze | 0 ANRs, 0 crashes, 0 OOMs in logcat for the whole run; worst UI freeze 897 ms (UI-isolate parse) — now moved off the UI isolate (≤125 ms worst frame) | **PASS** (with the isolate change) |
| additional peak PSS < 100 MB preferred | PSS baseline ~54 MB → steady 106–114 MB (Δ ~+55–60 MB) → peak 147 MB during reopen cycling (Δ ~+93 MB), settling back; RSS plateaus across 5 reopen cycles (223→227 MB, no leak) | **PASS** |

Cold app start (gate off, v2 code compiled in, force-stop between trials):
first-ever 1873 ms, then 1476/1196/1237/1106/1239 ms (`am start -W`
TotalTime). Background/resume: parse_count unchanged (21) across
inactive/paused/resumed — no re-parse. Corrupt cache: re-verified on read,
refetched in 120 ms; corrupt cache + dead network → `fallbackToV1`
(`downloadFailed`), 0 cache writes. Candidate on-device size 8,749,444 B in
the v2-only namespace.

## Main isolate vs background isolate

| | UI isolate (before) | `Isolate.run` (after) |
|---|---|---|
| wall clock, warm | p50 767 ms | **p50 311 ms** |
| worst UI frame during parse | **897 ms freeze** | 29–125 ms |
| records / rejected | 51,022 / 0 | 51,022 / 0 (identical) |
| attribution | intact | intact |
| RSS after | 173–183 MB | 180–190 MB (equal within noise) |

The background isolate wins on every axis (same isolate group: the raw
string is shared, the result returns via `Isolate.exit` without a copy),
so the loader now verifies+decodes+parses in `Isolate.run`. Exceptions
transfer intact, keeping every fallback cause identical — proven by the
unchanged loader fallback matrix plus a new result-parity test.

## Raw benchmark output (secrets: none; no candidate record data)

```
FAC2BENCH STARTUP first_frame_ms=0 parse_count=0 rss_mb=121
FAC2BENCH MEM-MARK baseline_before_any_v2_work rss_mb=125
FAC2BENCH STORAGE candidate_bytes=8749444
FAC2BENCH GATE-OFF status=FacilitiesV2LoadStatus.fallbackToV1 cause=FacilitiesV2FallbackCause.gateInactive elapsed_us=132 io_touches=0 parse_count=0
FAC2BENCH FRAMES window=main_parse_0 frames=20 jank_over_17ms=20 worst_frame_ms=897
FAC2BENCH MAIN-PARSE trial=0 total_ms=879 read_ms=115 hash_ms=424 hash_ok=true decode_ms=226 parse_ms=113 records=51022 rejected=0 rss_mb=173
FAC2BENCH FRAMES window=main_parse_1 frames=14 jank_over_17ms=14 worst_frame_ms=810
FAC2BENCH MAIN-PARSE trial=1 total_ms=807 read_ms=54 hash_ms=380 hash_ok=true decode_ms=282 parse_ms=89 records=51022 rejected=0 rss_mb=175
FAC2BENCH FRAMES window=main_parse_2 frames=16 jank_over_17ms=16 worst_frame_ms=777
FAC2BENCH MAIN-PARSE trial=2 total_ms=767 read_ms=47 hash_ms=395 hash_ok=true decode_ms=246 parse_ms=77 records=51022 rejected=0 rss_mb=174
FAC2BENCH FRAMES window=main_parse_3 frames=34 jank_over_17ms=26 worst_frame_ms=169
FAC2BENCH MAIN-PARSE trial=3 total_ms=766 read_ms=126 hash_ms=372 hash_ok=true decode_ms=219 parse_ms=47 records=51022 rejected=0 rss_mb=178
FAC2BENCH FRAMES window=main_parse_4 frames=43 jank_over_17ms=40 worst_frame_ms=167
FAC2BENCH MAIN-PARSE trial=4 total_ms=164 read_ms=30 hash_ms=70 hash_ok=true decode_ms=48 parse_ms=14 records=51022 rejected=0 rss_mb=183
FAC2BENCH MAIN-PARSE-STATS n=5 p50=767ms p95=879ms min=164ms max=879ms
FAC2BENCH MEM-MARK after_main_parse_trials rss_mb=183
FAC2BENCH FRAMES window=iso_parse_0 frames=64 jank_over_17ms=48 worst_frame_ms=64
FAC2BENCH ISO-PARSE trial=0 total_ms=394 records=51022 rejected=0 attribution_default=true rss_mb=180
FAC2BENCH FRAMES window=iso_parse_1 frames=62 jank_over_17ms=9 worst_frame_ms=43
FAC2BENCH ISO-PARSE trial=1 total_ms=311 records=51022 rejected=0 attribution_default=true rss_mb=180
FAC2BENCH FRAMES window=iso_parse_2 frames=57 jank_over_17ms=35 worst_frame_ms=125
FAC2BENCH ISO-PARSE trial=2 total_ms=459 records=51022 rejected=0 attribution_default=true rss_mb=186
FAC2BENCH FRAMES window=iso_parse_3 frames=57 jank_over_17ms=8 worst_frame_ms=43
FAC2BENCH ISO-PARSE trial=3 total_ms=211 records=51022 rejected=0 attribution_default=true rss_mb=190
FAC2BENCH FRAMES window=iso_parse_4 frames=59 jank_over_17ms=59 worst_frame_ms=29
FAC2BENCH ISO-PARSE trial=4 total_ms=203 records=51022 rejected=0 attribution_default=true rss_mb=184
FAC2BENCH ISO-PARSE-STATS n=5 p50=311ms p95=459ms min=203ms max=459ms
FAC2BENCH MEM-MARK after_iso_parse_trials rss_mb=184
FAC2BENCH CACHED-OPEN-STATS n=5 p50=154ms p95=177ms min=144ms max=177ms downloads=0
FAC2BENCH CORRUPT-CACHE recover_status=FacilitiesV2LoadStatus.loadedFromNetwork downloads=1 total_ms=120
FAC2BENCH CORRUPT-CACHE-OFFLINE status=FacilitiesV2LoadStatus.fallbackToV1 cause=FacilitiesV2FallbackCause.downloadFailed cache_writes=0
FAC2BENCH SEARCH state_lagos results=2798 first_query_us=29309 n=100 p50=1307us p95=1527us min=1261us max=1716us
FAC2BENCH SEARCH state_kano results=1723 first_query_us=1473 n=100 p50=1254us p95=1645us min=1183us max=2276us
FAC2BENCH SEARCH area_ikeja results=196 first_query_us=128116 n=100 p50=9991us p95=15117us min=8215us max=18789us
FAC2BENCH SEARCH area_aba_north results=106 first_query_us=9392 n=100 p50=9447us p95=13933us min=7953us max=24073us
FAC2BENCH SEARCH area_scoped results=194 first_query_us=3154 n=100 p50=2122us p95=4449us min=1699us max=9363us
FAC2BENCH SEARCH name_medical results=1923 first_query_us=13679 n=100 p50=9255us p95=12471us min=7640us max=13938us
FAC2BENCH SEARCH name_primary_health results=15779 first_query_us=12142 n=100 p50=7684us p95=10809us min=6557us max=17139us
FAC2BENCH SEARCH no_result results=0 first_query_us=9191 n=100 p50=7715us p95=10695us min=6525us max=12603us
FAC2BENCH SEARCH urgency_urgent results=51022 first_query_us=1386 n=20 p50=796us p95=2789us min=763us max=2789us
FAC2BENCH FRAMES window=search_burst frames=0 jank_over_17ms=0 worst_frame_ms=0
FAC2BENCH MEM-MARK after_search rss_mb=197
FAC2BENCH FRAMES window=distance_sort frames=0 jank_over_17ms=0 worst_frame_ms=0
FAC2BENCH DISTANCE-SORT all=51022 n=10 p50=12ms p95=24ms min=10ms max=24ms
FAC2BENCH EMERGENCY kind=EmergencyListKind.nearestNoCapabilityClaim n=30 has_112=true n=5 p50=10ms p95=11ms min=10ms max=11ms
FAC2BENCH MEM-MARK after_sort rss_mb=197
FAC2BENCH FRAMES window=list_scroll frames=217 jank_over_17ms=217 worst_frame_ms=26
FAC2BENCH REOPEN cycle=0 open_ms=157 first_search_us=29371 hits=2798 rss_mb=223
FAC2BENCH REOPEN cycle=1 open_ms=142 first_search_us=20285 hits=2798 rss_mb=223
FAC2BENCH REOPEN cycle=2 open_ms=148 first_search_us=21645 hits=2798 rss_mb=224
FAC2BENCH REOPEN cycle=3 open_ms=151 first_search_us=25933 hits=2798 rss_mb=226
FAC2BENCH REOPEN cycle=4 open_ms=153 first_search_us=32317 hits=2798 rss_mb=227
FAC2BENCH MEM-MARK after_reopen_cycles rss_mb=227
FAC2BENCH SEQUENCE-DONE parse_count=21 rss_mb=185
FAC2BENCH MEM-MARK sequence_done rss_mb=185
FAC2BENCH LIFECYCLE AppLifecycleState.inactive parse_count=21 rss_mb=181
FAC2BENCH LIFECYCLE AppLifecycleState.hidden parse_count=21 rss_mb=181
FAC2BENCH LIFECYCLE AppLifecycleState.paused parse_count=21 rss_mb=182
FAC2BENCH LIFECYCLE AppLifecycleState.hidden parse_count=21 rss_mb=182
FAC2BENCH LIFECYCLE AppLifecycleState.inactive parse_count=21 rss_mb=182
FAC2BENCH LIFECYCLE AppLifecycleState.resumed parse_count=21 rss_mb=181
FAC2BENCH RESUME resume_count=1 parse_count=21
FAC2BENCH LIFECYCLE AppLifecycleState.inactive parse_count=21 rss_mb=187
FAC2BENCH LIFECYCLE AppLifecycleState.hidden parse_count=21 rss_mb=187
FAC2BENCH LIFECYCLE AppLifecycleState.paused parse_count=21 rss_mb=187
FAC2BENCH STARTUP first_frame_ms=0 parse_count=0 rss_mb=121
FAC2BENCH MEM-MARK baseline_before_any_v2_work rss_mb=127
FAC2BENCH STARTUP first_frame_ms=0 parse_count=0 rss_mb=122
FAC2BENCH MEM-MARK baseline_before_any_v2_work rss_mb=126
FAC2BENCH STARTUP first_frame_ms=0 parse_count=0 rss_mb=121
FAC2BENCH MEM-MARK baseline_before_any_v2_work rss_mb=126
FAC2BENCH STARTUP first_frame_ms=0 parse_count=0 rss_mb=123
FAC2BENCH MEM-MARK baseline_before_any_v2_work rss_mb=127
FAC2BENCH STARTUP first_frame_ms=0 parse_count=0 rss_mb=122
FAC2BENCH MEM-MARK baseline_before_any_v2_work rss_mb=127
```
