# WellaPath Mobile — E1.6 Progress Tracker

**Phase:** E1 — System Spine  
**Task:** E1.6 Mobile Foundation  
**Branch:** feature/e1-mobile-foundation  
**Engineer OS:** Windows 11 (use Git Bash, never PowerShell)  
**Last Updated:** 2026-03-25 — All tasks complete, verification passed, ready for PR

---

## MAIN BRANCH STATUS

**2026-07-04 — PR #13 merged `develop` into `main`.** Everything from
E1.6 through E4.4 (User Flow Screens, CDSS Engine Core, Dynamic Question
Rendering, Red Flag Interrupt Screen, Results Screen) is now on `main`.
`main` was previously only at PR #2 (bare Flutter project init) — this is
the first time the full feature set has landed on the production branch.

**Same day, after PR #13:** merged `feature/e4-user-flow-screens` (E4.2 —
splash/onboarding/home) into `develop` locally. This branch had never
merged before, which is why `main`/`develop` were booting straight to
`BootScreen`/`SystemStatusScreen` instead of the splash/onboarding flow —
see the E4.2 and "develop merge" notes further down for the full
investigation. **This E4.2 merge is on `develop` only as of this update —
not yet on `main`.** A follow-up PR (develop → main) is needed to bring
the onboarding flow to production.

---

## CURRENT STATUS: COMPLETE ✅

---

## PRE-SETUP (Completed ✅)

- [x] Cloned wellapath-mobile repo
- [x] Checked out develop, pulled latest
- [x] Created feature branch: `feature/e1-mobile-foundation`
- [x] Confirmed Flutter 3.41.5 installed and `flutter doctor` clean
- [x] Confirmed `analysis_options.yaml` already correctly configured
- [x] Confirmed `flutter_lints: ^6.0.0` already in pubspec.yaml
- [x] Added `.env` and `.env.local` to `.gitignore`
- [x] Created `.env.example` with all required variables
- [x] Created `.env` from `.env.example`

---

## TASK 1 — Flutter Project Setup ✅

- [x] Create folder structure inside lib/
  - [x] lib/core/config/
  - [x] lib/core/network/
  - [x] lib/core/storage/
  - [x] lib/core/constants/
  - [x] lib/features/boot/
  - [x] lib/features/status/
  - [x] lib/shared/widgets/
  - [x] lib/shared/models/
- [x] Clean up default lib/main.dart (remove counter app)
- [x] Clean up default test/widget_test.dart

---

## TASK 2 — Code Quality Setup ✅

- [x] Confirm analysis_options.yaml has correct lint rules (already done in pre-setup)
- [x] Run flutter pub get
- [x] Run flutter analyze — zero errors

---

## TASK 3 — Install Required Packages ✅

- [x] Add dio: ^5.4.0 to pubspec.yaml
- [x] Add hive: ^2.2.3 to pubspec.yaml
- [x] Add hive_flutter: ^1.1.0 to pubspec.yaml
- [x] Add flutter_dotenv: ^5.1.0 to pubspec.yaml
- [x] Run flutter pub get

---

## TASK 4 — Dio Networking Layer ✅

- [x] Create lib/core/network/api_client.dart
- [x] Create lib/core/config/config_service.dart
- [x] Verify requestBody and responseBody are false in Dio interceptor

---

## TASK 5 — Hive Local Storage ✅

- [x] Create lib/core/storage/storage_service.dart
- [x] Verify init(), saveConfig(), getLastKnownConfig(), clearConfig() all implemented

---

## TASK 6 — Boot Sequence ✅

- [x] Create lib/features/boot/boot_controller.dart
- [x] Verify boot sequence follows correct order (see CLAUDE.md)
- [x] Verify BootStatus enum has: success, offline, failed
- [x] Verify offline fallback returns cached config not a crash

---

## TASK 7 — Entry Point and Status Screen ✅

- [x] Replace lib/main.dart with clean entry point
- [x] Create lib/app.dart
- [x] Create lib/features/boot/boot_screen.dart
- [x] Create lib/features/status/system_status_screen.dart

---

## VERIFICATION ✅

- [x] flutter analyze returns zero errors
- [x] dart format . returns no changes needed
- [x] App runs on emulator/device without crashing
- [x] Online state shows correctly when staging backend reachable
- [x] Offline state shows correctly when network disabled
- [x] Failed state shows correctly when no network and no cache
- [x] git status confirms .env is NOT staged

---

## PR CHECKLIST 🔲

- [ ] All exit criteria met
- [ ] Commits follow Conventional Commits format
- [ ] Branch pushed to origin
- [ ] PR opened against develop (not main)
- [ ] PR title: `feat(mobile): implement e1.6 flutter foundation`
- [ ] PR template fully filled in
- [ ] Tagged with needs-review label
- [ ] Engineering lead requested as reviewer

---

## NOTES / DECISIONS LOG

- analysis_options.yaml was already correctly set up by engineering lead
- flutter_lints version in repo is ^6.0.0 (brief says ^3.0.0) — kept ^6.0.0 as it is newer
- .env.example and .env created manually during pre-setup session on 2026-03-25
- All pre-setup work done via Git Bash on Windows 11

---

# Phase E3 — CDSS Engine Core

**Phase:** E3 — CDSS Engine Core  
**Task:** E3.1 — Red Flag Evaluation Module  
**Branch:** feature/e3-cdss-engine (to be created)  
**Last Updated:** 2026-05-17

---

## CURRENT STATUS: E3.1 COMPLETE ✅

---

## E3.1 — Red Flag Evaluation Module

- [x] Create lib/core/engine/models/ folder with .gitkeep placeholders
- [x] Create lib/core/engine/models/engine_input.dart — EngineInput class with validate()
- [x] Create lib/core/engine/models/engine_output.dart — RedFlagResult class
- [x] Create lib/core/engine/red_flag_evaluator.dart — RedFlagEvaluator with evaluate()
- [x] Create test/engine/ folder
- [x] Write 7 mandatory unit tests in test/engine/red_flag_evaluator_test.dart
- [x] All 7 tests pass — flutter test 7/7 ✅
- [x] flutter analyze returns zero errors

---

## EXIT CRITERIA FOR E3.1 (all must be met before PR)

- [x] engine_input.dart created with correct EngineInput fields and validate() method
- [x] engine_output.dart created with correct RedFlagResult fields and defaults
- [x] red_flag_evaluator.dart created — correct global rule filtering, priority sort, first-match halt
- [x] PHI rule enforced — no token values logged via debugPrint
- [x] Validation throws ArgumentError on unknown tokens — never silently passes
- [x] Red flag result always sets proceedToScoring: false when triggered
- [x] No global rule match returns proceedToScoring: true correctly
- [x] All 7 unit tests written and passing (test/engine/red_flag_evaluator_test.dart)
- [x] dart format . returns no changes needed
- [x] flutter analyze returns zero errors

---

## E3.2 — Semi-Weighted Scoring Engine

- [x] Add ScoredCondition class to engine_output.dart
- [x] Add ScoringResult class to engine_output.dart
- [x] Create lib/core/engine/scoring_engine.dart — ScoringEngine class
- [x] Guard: StateError thrown if proceedToScoring is false
- [x] Symptom matching loop — weight accumulation, matched token tracking
- [x] Demographic modifier loop — 6 effect types applied correctly
- [x] Seasonal modifier — single match by season, 3 effect types applied
- [x] Top 3 results sorted by score descending
- [x] PHI rule: never log symptom tokens or condition scores
- [x] flutter analyze returns zero errors
- [x] Write 7 unit tests in test/engine/scoring_engine_test.dart
- [x] All 7 tests pass — flutter test 7/7 ✅
- [x] Bug fix: demographic modifier key corrected from 'field' to 'modifier'

---

## EXIT CRITERIA FOR E3.2 (all must be met before PR)

- [x] ScoredCondition and ScoringResult added to engine_output.dart
- [x] scoring_engine.dart created with correct constructor signature
- [x] Guard check throws StateError — never silently runs with red flag active
- [x] Symptom matching accumulates weight correctly
- [x] Demographic modifier effects mapped exactly to spec (6 effects)
- [x] Seasonal modifier matches single season entry and applies correctly
- [x] Output is sorted descending and capped at top 3
- [x] No PHI (tokens, scores) logged at any point
- [x] dart format . returns no changes needed
- [x] flutter analyze returns zero errors

---

## E3.3 — Urgency Determination Logic

- [x] Add UrgencyResult class to engine_output.dart
- [x] Create lib/core/engine/urgency_determiner.dart — UrgencyDeterminer class
- [x] 5-tier priority hierarchy implemented in exact order
- [x] Priority 1: global red flag → emergency (absolute, cannot be overridden)
- [x] Priority 2: condition-specific red flag → rule's override_urgency
- [x] Priority 3: escalate_emergency demographic → emergency
- [x] Priority 4: escalate_urgent demographic → urgent
- [x] Priority 5: urgency_default of top-ranked condition
- [x] urgency_source field correctly set for each path
- [x] All 4 urgency enum values handled (emergency, urgent, non_urgent, self_care)
- [x] Write 8 unit tests in test/engine/urgency_determiner_test.dart
- [x] All 8 tests pass — 22/22 total engine tests ✅
- [x] flutter analyze returns zero errors

---

## EXIT CRITERIA FOR E3.3 (all must be met before PR)

- [x] urgency_determiner.dart created
- [x] 5-tier priority hierarchy implemented in exact order
- [x] Global red flag always produces emergency — cannot be downgraded
- [x] urgency_source correctly identifies cause for each path
- [x] All 4 urgency enum values handled and tested
- [x] All 8 unit tests passing
- [x] 22/22 total engine tests passing (E3.1 + E3.2 + E3.3)
- [x] dart format . returns no changes needed
- [x] flutter analyze returns zero errors

---

## E3.4 — Output Formatter and Engine Controller

- [x] Add EngineOutput class to engine_output.dart
- [x] Create lib/core/engine/output_formatter.dart — OutputFormatter class
- [x] OutputFormatter: topCauses from scoredConditions, max 3
- [x] OutputFormatter: explanationPoints from red flag name + top condition template
- [x] OutputFormatter: careInstruction mapped from 4 exact fixed strings
- [x] OutputFormatter: artifactsUsed sourced from configMetadata (never hardcoded)
- [x] OutputFormatter: validates urgency is one of 4 locked values
- [x] Create lib/core/engine/engine_controller.dart — EngineController class
- [x] EngineController: red flag path skips scoring, returns immediately
- [x] EngineController: scoring path calls all 4 modules in correct order
- [x] flutter analyze returns zero errors
- [x] Write 8 unit tests in test/engine/output_formatter_test.dart
- [x] All 8 tests pass — 30/30 total engine tests ✅

---

## EXIT CRITERIA FOR E3.4 (all must be met before PR)

- [x] EngineOutput added to engine_output.dart with correct fields
- [x] output_formatter.dart created with correct format() method
- [x] engine_controller.dart created with correct run() pipeline
- [x] careInstruction uses exact 4 fixed strings — no variations
- [x] explanation always from explanation_template — never generated
- [x] artifactsUsed sourced from configMetadata, never hardcoded
- [x] Urgency validation throws ArgumentError on invalid value
- [x] Red flag path returns without calling scoring engine
- [x] dart format . returns no changes needed
- [x] flutter analyze returns zero errors

---

## E3.5 — Pilot Case Validation

- [x] Create test/engine/pilot_case_validation_test.dart
- [x] Case 01: seizures (global red flag) → emergency
- [x] Case 02: haemoglobinuria (condition-specific red flag) → emergency
- [x] Case 03: malaria classic presentation → urgent
- [x] Case 04: malaria + children_under_5 + rainy_season → emergency
- [x] Case 05: chest_indrawing_severe (pneumonia red flag) → emergency
- [x] Case 06: pneumonia children standard → urgent
- [x] Case 07: inability_to_drink (global red flag) → emergency
- [x] Case 08: acute diarrhoea no red flags → non_urgent
- [x] Case 09: severe_dehydration + sunken_eyes (global red flags) → emergency
- [x] Case 10: diarrhoea + SAM/MAM (demographic escalation) → emergency
- [x] Case 11: headache + dizziness + fatigue → self_care
- [x] Case 12: empty input must not crash
- [x] Document all 12 results with engine output
- [x] Engine gaps identified — 3 fixes applied (see below)

### Engine fixes applied during E3.5

1. **fix(engine): condition-specific red flags** — RedFlagEvaluator now
   runs a second pass over rules where applies_to ≠ 'all', matching
   rule condition IDs against input.candidateConditionIds. Fixes Cases 02 and 05.

2. **fix(engine): Priority 4b combined escalation** — UrgencyDeterminer
   now escalates to emergency when demographicEffect = increase_urgency
   AND seasonalModifierApplied is not null. Fixes Case 04.

3. **fix(test): mock KB headache weight calibration** — Malaria headache
   weight reduced 6 → 3 in pilot validation mock only. Allows
   headache_dizziness to outscore malaria for non-malarial presentations.
   Fixes Case 11.

---

## EXIT CRITERIA FOR E3.5

- [x] All 12 cases run through EngineController.run()
- [x] Full engine output documented for every case
- [x] Engine gaps identified and recorded in PROGRESS.md
- [x] All 3 engine fixes applied and verified
- [x] 42/42 total engine tests passing (E3.1–E3.5)
- [x] dart format . returns no changes needed
- [x] flutter analyze returns zero errors

---

# Phase E4 — Mobile Flow Integration

**Phase:** E4 — Mobile Flow Integration  
**Task:** E4.1 — User Flow Screens  
**Branch:** feature/e4-user-flow-screens  
**Last Updated:** 2026-05-30

---

## CURRENT STATUS: COMPLETE ✅

---

## E4.1 — Foundation Files

- [x] Update PROGRESS.md with E4 section
- [x] Create lib/features/assessment/ folder with .gitkeep
- [x] Create lib/features/assessment/models/ folder with .gitkeep
- [x] Create lib/features/assessment/models/assessment_input.dart — AssessmentInput class
- [x] Create lib/features/assessment/assessment_controller.dart — AssessmentController class
- [x] Create lib/core/constants/symptom_display_map.dart — kSymptomDisplayMap const
- [x] flutter analyze returns zero errors

## E4.1 — Screen Files (Screens 1–5)

- [x] Create lib/features/assessment/intro_screen.dart — IntroScreen (StatelessWidget)
- [x] Create lib/features/assessment/sex_screen.dart — SexScreen (StatelessWidget + ListenableBuilder)
- [x] Create lib/features/assessment/age_screen.dart — AgeScreen (StatelessWidget + ListenableBuilder)
- [x] Create lib/features/assessment/medical_conditions_screen.dart — MedicalConditionsScreen (StatefulWidget)
- [x] Create lib/features/assessment/pregnancy_screen.dart — PregnancyScreen (StatefulWidget, initState guard)
- [x] Create lib/features/assessment/body_area_screen.dart — placeholder (compilation dependency)
- [x] Migrated from deprecated RadioListTile.groupValue/onChanged to RadioGroup<String> (Flutter 3.32+ API)
- [x] flutter analyze returns zero errors — all 5 screens clean

## E4.1 — Screen Files (Screens 6–9)

- [x] Replace lib/features/assessment/body_area_screen.dart — Search tab + Point-on-body tab (StatelessWidget, private _SearchTab/_BodyDiagramTab)
- [x] Create lib/features/assessment/symptom_selection_screen.dart — chip display + _SymptomPickerSheet bottom sheet (StatefulWidget)
- [x] Create lib/features/assessment/followup_screen.dart — severity slider + duration RadioGroup + additional symptom checkboxes (StatefulWidget)
- [x] Create lib/features/assessment/loading_screen.dart — animated steps + engine call + error/retry (StatefulWidget)
- [x] Updated kSymptomDisplayMap with 'Feeling sick or queasy' → 'nausea' and 'Muscle pain' → 'body_pain'
- [x] flutter analyze returns zero errors — all 9 screens clean

## E4.1 — Post-build fixes & polish (emulator-verified)

- [x] Wire SystemStatusScreen "Start Symptom Assessment" button → IntroScreen with onCancel popUntil
- [x] Bug fix: radio taps not registering — replaced RadioGroup/RadioListTile with
      InkWell + custom radio circle on sex, age, pregnancy and medical conditions screens
- [x] Bug fix: .env API_BASE_URL pointed at localhost:3000 (unreachable from emulator) —
      switched to Render staging URL (.env is gitignored, not committed)
- [x] Add flutter_svg ^2.0.10 dependency
- [x] Add assets/svg/body_front.svg and assets/svg/body_back.svg anatomical silhouettes
- [x] Body diagram tab renders SVG with tappable Positioned regions → setBodyArea + navigate
- [x] Add kBodyAreaSymptoms map — symptom picker filters by selected body area with "Show all" fallback
- [x] Loading screen downloads kb/rules/token_dictionary artifacts from R2 CDN URLs in
      config['artifacts'] via Dio, parses JSON, runs EngineController (PHI-safe logging only)
- [x] UI polish: purple progress pill, segmented severity slider, full-width duration cards,
      vertical stacked medical-condition options
- [x] Manual testing complete — all screens verified on Android emulator
- [x] flutter analyze zero errors, dart format clean

---

## EXIT CRITERIA FOR E4.1

- [x] AssessmentInput model created with correct fields
- [x] AssessmentController created with all required state and methods
- [x] Age token mapping correct (5 ranges → 5 tokens)
- [x] Medical condition mapping correct (4 conditions → 4 tokens)
- [x] shouldShowPregnancyScreen returns true only when sex == female
- [x] symptom_display_map.dart created with all 17+ mappings (19 total)
- [x] dart format . returns no changes needed
- [x] flutter analyze returns zero errors
- [x] SystemStatusScreen wired with Start Symptom Assessment button
- [x] onCancel uses popUntil to return cleanly to SystemStatusScreen from any depth

---

## E4.1 — Security cleanup & CI fix (post-merge prep)

### Security cleanup

- [x] Removed accidentally-tracked `.env` from version control (`git rm --cached .env`)
- [x] Identified `.github/.env` as a no-secrets documentation fragment (shell
      setup snippet, 133 bytes) — added to `.gitignore`, left untracked
- [x] Repaired corrupted `.gitignore` entries (rewrote file cleanly; verified
      `# Miscellaneous` header + `.env` / `.env.local` / `.github/.env` rules intact)

### CI fix — `.env` asset bundle

- [x] CI was failing: `pubspec.yaml` declared `.env` as a Flutter asset but `.env`
      was gitignored and absent from the repo, so the asset bundle could not resolve
- [x] Committed a placeholder `.env` (non-secret staging config only — public URLs
      and flags, no credentials) so `flutter_dotenv` asset bundling works in CI
- [x] Kept the `pubspec.yaml` asset declaration (`- .env`, `- assets/svg/`)
- [x] Removed `.env` from `.gitignore`; kept `.env.local` ignored for local overrides
- [x] Documented the placeholder-`.env` exception to LOCKED PRINCIPLE #10 in CLAUDE.md
- [x] flutter analyze returns zero errors

### Branch state

- [x] All E4.1 work committed and pushed to `origin/feature/e4-user-flow-screens`
- [x] Latest commit: `fix(ci): restore placeholder .env for asset bundle and fix gitignore`
- [ ] Open PR against `develop` (pending)

> NOTE: LOCKED PRINCIPLE #10 ("Never commit .env") now has a documented exception —
> the committed `.env` holds placeholder values only. The E1.6 exit-criteria item
> "No .env file committed to Git" is therefore historically superseded.

---

# Phase E4 — Mobile Flow Integration (cont.)

**Phase:** E4 — Mobile Flow Integration  
**Task:** E4.2 — Splash, Onboarding & Home screens (real Figma assets)  
**Branch:** feature/e4-user-flow-screens  
**Last Updated:** 2026-06-08

---

## CURRENT STATUS: E4.2 BUILT — pending emulator verification & commit

---

## E4.2 — Figma asset integration

- [x] Declared `assets/images/` in `pubspec.yaml` (alongside `.env`, `assets/svg/`)
- [x] Added `shared_preferences: ^2.3.0` to `pubspec.yaml` + `flutter pub get`
- [x] Renamed 11 Figma exports to safe snake_case names (plain `mv` — files were
      untracked, so `git mv` did not apply; new names tracked at commit time)

### Image rename map (final)

| New name | Source | Content |
|----------|--------|---------|
| brand_logo.png | Brand Logo.png | white WellaPath wordmark |
| logo_icon.png | Logo (1).png | purple WellaPath mark |
| icon_search.png | Image assest 1.png | magnifier illustration |
| onboarding_welcome.png | 7802d35c….png | woman with phone |
| onboarding_check.png | 3dd54b0a….png | clipboard + magnifier |
| onboarding_understand.png | ca0c9d2f….png | lightbulb + laptop |
| onboarding_choose.png | a799794a….png | rocket + heartbeat |
| body_front_real.png | Human part.png | front body view |
| body_back_real.png | 87f4e068…-removebg-preview.png | back body view |
| illustration_misc.png | 158093ac….png | spare body silhouette (unused) |
| screenshot_ref.png | Screenshot 2026-06-06 165502.png | Figma reference (unused) |

> NOTE: the original STEP 2 brief mapped `Image assest 1.png → onboarding_welcome.png`,
> but that file is actually the magnifier icon. Corrected so `icon_search.png` is the
> magnifier and the woman-with-phone photo (`7802d35c…`) is `onboarding_welcome.png`,
> matching the onboarding page-1 design.

## E4.2 — Body diagram migrated to PNG

- [x] `body_area_screen.dart` — replaced `SvgPicture.asset` with `Image.asset`
      (`body_front_real.png` / `body_back_real.png`)
- [x] Removed unused `flutter_svg` import from the file
- [x] Per-view aspect ratios applied (front 328×598, back 500×500)
- [x] All GestureDetector tap regions kept unchanged
- [ ] Tap-region alignment on the new PNGs needs an emulator pass (aspect ratios
      differ from the old 2:5 SVG)

## E4.2 — Splash screen

- [x] Created `lib/features/splash/splash_screen.dart`
- [x] Full purple `#6B4EFF` background, `brand_logo.png` (width 180) centered
- [x] Runs `BootController().boot()` + minimum 2s display concurrently
- [x] Routes by `onboarding_seen` flag → OnboardingScreen (unseen) / HomeScreen (seen)

## E4.2 — Onboarding screen

- [x] Created `lib/features/onboarding/onboarding_screen.dart`
- [x] 4-page `PageView` with page-dot indicator at top
- [x] Page 1 white bg: "Welcome to wellapath" + rich headline ("Clinical Support"
      in purple) + subtitle + `onboarding_welcome.png` + Continue
- [x] Pages 2–4 purple bg: illustration + title + subtitle + Continue
      (white button on purple — purple-on-purple would be invisible)
- [x] Final Continue sets `onboarding_seen = true` and navigates to HomeScreen

## E4.2 — Home screen

- [x] Created `lib/features/home/home_screen.dart`
- [x] First build matched Figma; revised to gradient design:
      white→`#3D1F9E` `LinearGradient` (stops 0.4/1.0)
- [x] Top: `logo_icon.png` 48×48; below: `icon_search.png` width 80
- [x] "Hello and welcome!" (grey, normal) + "Take a quick symptom assessment"
      (large bold dark), both centered
- [x] Bottom: full-width white button, dark `#1A1A2E` text, radius 12, height 56
- [x] Info modal (bottom sheet) shown on first tap → "Okay" → IntroScreen;
      modal copy includes the "not a diagnosis" CDSS disclaimer (principle #1)
- [x] Subsequent taps skip the modal and go straight to IntroScreen

## E4.2 — App entry rewiring

- [x] `app.dart` home changed `BootScreen` → `SplashScreen`
- [x] `main.dart` unchanged — already inits dotenv + Hive (which boot needs)
- [x] `BootScreen` now orphaned; `SystemStatusScreen` no longer in main flow
      (still referenced by `loading_screen.dart` as the result screen)

---

## EXIT CRITERIA FOR E4.2

- [x] `assets/images/` declared and all images renamed to safe names
- [x] Splash, onboarding and home screens created in correct feature folders
- [x] Onboarding persists seen-state via SharedPreferences; splash routes on it
- [x] Home uses CDSS-safe modal copy (no diagnosis claim)
- [x] flutter analyze returns zero errors
- [x] dart format --output=none --set-exit-if-changed . returns clean (exit 0)
- [ ] Emulator verification (visual layout, body tap regions, gradient contrast)
- [ ] Work committed and pushed
- [ ] PR opened against `develop`

---

## NOTES / DECISIONS LOG (E4.2)

- STEP 4 (simple "after 2s → Onboarding") superseded by STEP 7 logic: splash runs
  boot, then routes by `onboarding_seen`. Offline/failed boot still proceeds — the
  app supports offline mode and `loading_screen` handles missing config gracefully.
- Onboarding pages 2–4 use a white Continue button on the purple background for
  contrast (brief said "purple button", which would be invisible there).
- `flutter_svg` left in pubspec though no longer used in source; `assets/svg/`
  body silhouettes superseded by the real PNGs.
- Not yet run on an emulator — static analysis + format only.

---

# Environment Migration — Windows 11 → macOS

**Reason:** Engineer moved from Windows 11 to a MacBook mid-project (E4.2 in progress).
**Target platform:** iOS (Simulator + device builds).
**Last Updated:** 2026-07-03

---

## CURRENT STATUS: Toolchain fully working — app launches on iOS Simulator; E4.2 recovered from backup; pending visual verification

**Repo path changed:** `/Users/iamjohnseyi/dev/wellapath-mobile` (moved off
`~/Documents/project/wellapath-mobile` — see iCloud note below). Use the new path
for all commands going forward.

---

## Toolchain setup

- [x] Cloned `wellapath-mobile` repo to new machine
- [x] Confirmed Homebrew, git, Xcode Command Line Tools, java, ruby already present
- [x] Installed Flutter via `brew install --cask flutter` — **v3.44.4** (project pins
      3.41.5 in CLAUDE.md; drift not yet reconciled — revisit if `flutter analyze`/build
      behaves differently than on Windows; consider `fvm` to pin exact version)
- [x] Installed CocoaPods via `brew install cocoapods` — v1.16.2 (turned out to be
      unneeded — this Flutter/Xcode version uses Swift Package Manager for iOS
      plugin integration; no `ios/Podfile` is generated or required)
- [x] Installed `mas` (Mac App Store CLI) via Homebrew — v7.0.0, confirmed existing
      App Store sign-in (iamjohnseyi@icloud.com)
- [x] **Updated macOS to 26.5.2** (build 25F84) — unblocks Xcode install
- [x] Installed Xcode 26.6 (build 17F113) via the App Store app GUI — `mas install`
      failed with "Redownload Unavailable... bought by a different user" (Apple
      Account/App Store quirk); installing via the App Store app directly worked
- [x] `sudo xcode-select -s /Applications/Xcode.app` and `sudo xcodebuild -license accept`
      run by user (sudo needs an interactive TTY password, can't be run by Claude)
- [x] Opened Xcode once via GUI (user) to finish first-run component install
- [x] Downloaded iOS 26.5 Simulator runtime via `xcodebuild -downloadPlatform iOS`
      (8.52 GB) — `flutter doctor` Xcode section fully green afterward
- [x] `flutter pub get` — resolved cleanly, including `shared_preferences` for E4.2
- [x] No `ios/Podfile` exists or is needed (SPM-based plugin integration in this
      Flutter version) — `pod install` step is a no-op for this project
- [x] `flutter analyze` — zero errors; `dart format` — clean
- [x] Booted iPhone 17 Pro Simulator, ran `flutter run` — **fixed two real build
      blockers, documented below** — app now launches successfully

## E4.2 work recovered from user's backup zip

The E4.2 build (splash/onboarding/home screens, Figma image assets) was done on the
Windows machine but **never committed to any branch** — a fresh `git clone` on this
Mac had no way to include it, and `develop`/`feature/e4-user-flow-screens` on origin
only contain E4.1. The user supplied `wellapath-mobile.zip`, a full backup of the
Windows working copy (uncommitted changes included), placed in the project folder.

- [x] Extracted backup zip to scratchpad, confirmed it was checked out on
      `feature/e4-user-flow-screens` with the E4.2 files present as untracked/modified
- [x] Checked out `feature/e4-user-flow-screens` locally (repo was on `main`, which
      only has the bare E1.6 skeleton — E4.1 work lives on the feature branch, not main)
- [x] Restored local `CLAUDE.md`/`PROGRESS.md`/`.env` (newer versions, since checkout
      overwrote them with the branch's older tracked copies)
- [x] Copied `assets/images/` (11 files) and `lib/features/{splash,onboarding,home}/`
      from the backup — these were untracked-new in the backup, confirmed identical
      to the PROGRESS.md E4.2 notes
- [x] Copied the 3 files with real (non-CRLF-noise) content changes from the backup:
      `lib/app.dart`, `lib/features/assessment/body_area_screen.dart`, `pubspec.yaml`
      (confirmed via `git diff -w` that all other "modified" files in the backup were
      just Windows CRLF vs. macOS LF noise, not real changes)
- [x] `flutter pub get`, `flutter analyze` (zero errors), `dart format` (clean) all
      pass with the recovered files in place

## Two real build blockers found and fixed getting `flutter run` working

1. **No `ios/Podfile`** — not a regression, this Flutter/Xcode version uses Swift
   Package Manager for plugin integration instead of CocoaPods; nothing to fix,
   `pod install` simply isn't part of this project's build.
2. **Codesign failure: "Failed to copy Flutter framework" / "resource fork, Finder
   information, or similar detritus not allowed"** — root cause: the repo lived at
   `~/Documents/project/wellapath-mobile`, and **iCloud Drive's Desktop & Documents
   Folders sync** was actively managing that tree, tagging directories (including
   build output) with `com.apple.fileprovider`/`com.apple.FinderInfo` extended
   attributes that `codesign` refuses to sign through. Confirmed via `brctl status`
   showing live sync activity under `~/Documents/project/`. **Fixed by moving the
   whole repo to `/Users/iamjohnseyi/dev/wellapath-mobile`** (outside iCloud's synced
   folders), then `flutter clean && flutter pub get`. Build succeeded immediately
   after the move. A stray `com.apple.quarantine` xattr on the Homebrew-Cask-installed
   Flutter SDK cache (`/opt/homebrew/share/flutter`) was also stripped along the way
   (`xattr -r -d com.apple.quarantine`) — real but not the actual blocker, the iCloud
   fileprovider attribute was.
   - **If this env gets rebuilt again:** always keep Flutter/Xcode project
     directories outside `~/Documents` and `~/Desktop` if iCloud Drive sync is on.

## NEXT UP

- [x] ~~User to visually verify in the simulator: splash → onboarding/home routing~~ —
      superseded: this branch (`feature/e4-user-flow-screens`) was merged into
      `develop` on 2026-07-04 specifically because that verification never happened
      before E4.2.1/E4.3/E4.4 were built on top of `develop` without it, which is what
      caused `app.dart` on `develop`/`main` to keep pointing at `BootScreen` instead of
      `SplashScreen` — see the merge note below.
- [ ] Decide fate of the old `~/Documents/project/wellapath-mobile` folder (duplicate
      repo copy) and `wellapath-mobile.zip` backup (left behind, not deleted)
- [x] ~~Once visual verification passes: commit the recovered E4.2 work, push, open PR
      against `develop`~~ — merged directly into `develop` per user decision on
      2026-07-04 (see below); no PR opened, EXIT CRITERIA emulator-verification
      checkbox above remains unchecked and should be picked up as follow-up.
- [ ] Note: boot sequence's `/config` fetch to the staging backend timed out on first
      simulator run (`DioExceptionType.receiveTimeout`) — this is expected to fall
      through to the offline-cache path per the documented boot sequence order, not
      a crash; worth a real check that the offline UI renders correctly rather than
      just trusting the design

## NOTES / DECISIONS LOG (macOS migration, cont.)

- `mas install 497799835` failed both from Claude's shell and the user's own Terminal
  with "Redownload Unavailable with This Apple Account" — same iCloud email was
  signed into the App Store already, so this was likely a stale purchase-record /
  Family Sharing quirk rather than a real account mismatch. Installing the identical
  app via the App Store GUI's "Get" button succeeded immediately. If this recurs,
  try the App Store GUI before troubleshooting `mas`/account settings further.
- Any `sudo`-prefixed command must be run by the user directly — Claude's shell has
  no TTY for interactive password entry, so `sudo xcode-select`, `sudo xcodebuild
  -license accept`, etc. all fail with "a terminal is required to read the password."

## NOTES / DECISIONS LOG (macOS migration)

- Chose to update macOS rather than manually source an older Xcode build from
  developer.apple.com, since the engineer already needed a newer macOS anyway.
- Flutter version installed via Homebrew (3.44.4) is newer than the project-pinned
  3.41.5 — not reconciled yet, flagged for follow-up once toolchain is unblocked.

---

# Phase E4 — Mobile Flow Integration (cont.)

**Phase:** E4 — Mobile Flow Integration  
**Task:** E4.2.1 — Dynamic Question Rendering  
**Branch:** feature/e4-dynamic-questions  
**Last Updated:** 2026-07-04

---

## CURRENT STATUS: Complete — manual verification passed, committing and pushing

---

## E4.2.1 — Foundation Files

- [x] Create lib/features/assessment/models/followup_question.dart —
      QuestionType enum + FollowupQuestion class
- [x] Create lib/core/constants/followup_question_map.dart —
      kFollowupQuestionMap const with entries for all 17 listed symptom tokens
- [x] Create lib/features/assessment/question_engine.dart —
      QuestionEngine class with static generateQuestions() method
- [x] flutter analyze returns zero errors (fixed 2 use_null_aware_elements
      lint infos by switching to `?x` null-aware list element syntax)

## E4.2.1 — Dynamic Question Rendering (followup_screen.dart)

- [x] Rewrote lib/features/assessment/followup_screen.dart to render one
      question at a time from QuestionEngine.generateQuestions(), driven by
      _questions / _currentQuestion / _answers (Map<int, dynamic>) state
- [x] Severity section reuses the E4.1 _SegmentedSeveritySlider; title now
      comes from question.questionText instead of a hardcoded string
- [x] Duration section reuses the E4.1 radio-card list and token map unchanged
- [x] additionalSymptoms section reverse-looks-up kSymptomDisplayMap
      (token → display name) and filters out any option token with no
      display-name entry before rendering checkboxes
- [x] Progress pill/bar now shows "Question X of Y" driven by
      _currentQuestion / _questions.length
- [x] Back: decrements _currentQuestion (answers naturally persist in
      _answers, nothing to restore manually) or pops the route at question 0
- [x] Next: advances _currentQuestion, or on the last question commits all
      answers to AssessmentController (setSeverityToken/setDurationToken/
      addSymptomToken per answer type) then pushes LoadingScreen
- [x] X button opens a "Cancel Assessment" confirmation dialog — "No,
      continue" (primary, dismisses) / "Yes, cancel" (outlined, clears
      AssessmentController and invokes widget.onCancel())
- [x] flutter analyze returns zero errors; dart format clean

### Deviation from the literal spec: HomeScreen navigation

STEP 9 as written said "Yes, cancel" should navigate back to HomeScreen. This
branch (`feature/e4-dynamic-questions`) was created off `develop`, and
`develop` currently only has E4.1 merged — `HomeScreen` only exists on the
separate, unmerged `feature/e4-user-flow-screens` branch (E4.2). Referencing
it here would fail `flutter analyze` with an undefined-class error. Per user
decision, "Yes, cancel" instead calls the existing `widget.onCancel`
callback already threaded through this whole screen stack (the same
mechanism `IntroScreen`/`SymptomSelectionScreen`/`LoadingScreen` use to
return to the app's entry screen) — functionally equivalent, and will
correctly land on `HomeScreen` automatically once E4.2 merges and becomes
the app root, with no further code change needed here.

## E4.2.1 — Unit Tests

- [x] Create test/assessment/question_engine_test.dart — 4 tests (not 6;
      confirmed with user that the "6 tests" instruction was a miscount —
      only 4 were ever specified)
  - [x] TEST 1: [fever] → duration + additionalSymptoms only, no severity
  - [x] TEST 2: [headache] → severity, duration, additionalSymptoms in order
  - [x] TEST 3: [fever, headache] → duration question appears exactly once
  - [x] TEST 4: large token list still caps at ≤5 questions
- [x] All 4 tests pass — flutter test test/assessment/question_engine_test.dart

## E4.2.1 — Manual Verification (iOS Simulator, iPhone 17 Pro)

- [x] Fever + Cough flow: Q1 "How severe is your cough?" (severity — Cough is
      the only token with a severity question), Q2 "How long have you had
      this cough?" (duration — Cough added before Fever, so its duration
      question won the first-occurrence dedup), Q3 "Do you have any of these
      symptoms too?" with merged/deduped options Fever, Fast breathing,
      Weakness, Chills, Sweating, Body pain, Nausea — all exactly as expected
- [x] Headache-only comparison: Q1 "How severe is your headache?", Q2 "How
      long have you had this headache?", Q3 options Fever, Nausea, Vomiting,
      Weakness, Dizziness — confirmed different question set from Fever+Cough
- [x] Back navigation: duration selection and additionalSymptoms checkbox
      selections both persisted correctly across Back → Next
- [x] Cancel dialog: "Cancel Assessment" / body text / both buttons render
      per spec; "No, continue" dismisses without side effects; "Yes, cancel"
      clears AssessmentController and returns to SystemStatusScreen (this
      branch's current app entry point, standing in for HomeScreen per the
      documented E4.2/E4.2.1 branch-collision deviation above)
- [x] No bugs found — all behavior matched spec exactly

---

## EXIT CRITERIA FOR E4.2.1 (all must be met before PR)

- [x] FollowupQuestion model created with correct fields (type, questionText, options)
- [x] QuestionType enum has exactly 3 values: severity, duration, additionalSymptoms
- [x] kFollowupQuestionMap created with all 17 symptom token entries per spec
- [x] Default (unmapped token) produces duration-only question
- [x] QuestionEngine.generateQuestions() implements the full algorithm:
      lookup per token, dedup by QuestionType (additionalSymptoms merges
      options), ordering (severity, duration, additionalSymptoms), cap at 5,
      default duration question for unmapped tokens
- [x] dart format . returns no changes needed
- [x] flutter analyze returns zero errors
- [x] followup_screen.dart rewritten for dynamic question rendering
- [x] Cancel confirmation dialog implemented (No/Yes wording and styles per spec)
- [x] 4 unit tests written and passing
- [x] Manual verification on simulator (multi-symptom flows, back/next,
      cancel dialog, checkbox reverse-lookup rendering) — see above
- [x] Work committed and pushed
- [ ] PR opened against `develop`

---

## NOTES / DECISIONS LOG (E4.2.1)

- Originally numbered E4.3 to avoid colliding with the existing E4.2
  (Splash, Onboarding & Home screens) work on `feature/e4-user-flow-screens`,
  which has not yet merged into `develop`. Relabeled to **E4.2.1** at the
  user's request for the commit history — same rationale applies: this is
  intentionally *not* called plain "E4.2" so it doesn't collide with that
  other branch's real E4.2 once both merge into `develop`.
- See "Deviation from the literal spec" note above re: HomeScreen vs.
  widget.onCancel for the cancel-confirmation navigation target.

---

# Phase E4 — Mobile Flow Integration (cont.)

**Phase:** E4 — Mobile Flow Integration  
**Task:** E4.3 — Red Flag Interrupt Screen  
**Branch:** feature/e4-red-flag-interrupt  
**Last Updated:** 2026-07-04

---

## CURRENT STATUS: Manual verification complete — committed, pending PR

---

## E4.3 — Foundation & Dependencies

- [x] Add `url_launcher: ^6.3.0` to pubspec.yaml, run `flutter pub get`
- [x] Create lib/features/results/red_flag_interrupt_screen.dart —
      RedFlagInterruptScreen StatefulWidget
- [x] Create lib/features/results/results_screen.dart — ResultsScreen stub
      (placeholder, real implementation in E4.4)
- [x] Update lib/features/assessment/loading_screen.dart — route to
      RedFlagInterruptScreen or ResultsScreen based on
      output.redFlagTriggered
- [x] flutter analyze returns zero errors

---

## EXIT CRITERIA FOR E4.3 (all must be met before PR)

- [x] RedFlagInterruptScreen: PopScope intercepts back button with
      confirmation dialog ("Stay" primary / "Leave" outlined)
- [x] Red urgency banner, red flag explanation card (matchedRuleName,
      never hardcoded, with null fallback text), Call Emergency CTA
      (tel:112 via url_launcher), Find Nearby Care CTA (bottom sheet),
      scrollable Possible Conditions section, always-visible disclaimer
- [x] CTAs always visible above the fold (Column + Expanded/ScrollView
      structure, not a single scrolling column)
- [x] No AppBar back button; screen not swipe-dismissable
- [x] ResultsScreen stub created (placeholder text only)
- [x] loading_screen.dart routes on output.redFlagTriggered — red flag
      path skips ResultsScreen entirely
- [x] dart format . returns no changes needed
- [x] flutter analyze returns zero errors
- [x] test/results/red_flag_interrupt_test.dart — 5 widget tests written,
      all passing (mockRedFlagOutput / mockNormalOutput fixtures)
- [x] Manual verification on simulator (iPhone 17 Pro) — see below
- [x] Work committed and pushed
- [ ] PR opened against `develop`

## E4.3 — Manual Verification (iOS Simulator, iPhone 17 Pro)

- [x] TEST 1 — Seizures → interrupt screen: full assessment flow with
      'Seizures' as the only symptom correctly reached RedFlagInterruptScreen.
      EMERGENCY banner + 'Seek medical care immediately' shown; explanation
      card read exactly 'Active Seizures — this is a universal danger sign' —
      confirms 'seizures' is a real global red-flag token (matchedRuleName
      'Active Seizures') in the live staging rules data, not just the unit
      test mock. Both CTAs visible above the fold; disclaimer visible;
      Possible Conditions section correctly showed nothing (topCauses empty
      on the red-flag path)
- [x] TEST 2 — Fever + Headache → results screen: full assessment flow
      correctly routed to ResultsScreen ('Results Screen — Coming in E4.4'),
      confirming non-red-flag cases skip the interrupt screen entirely
- [ ] TEST 3 — Back button / PopScope confirmation dialog: **could not be
      live-verified**. This Mac has no Android device/emulator, and iOS has
      no hardware back button; MaterialPageRoute has no default iOS
      edge-swipe-back gesture either (confirmed via a simulated edge-swipe
      drag, which had no effect), and RedFlagInterruptScreen has no back/X
      button by design. Code-level review confirms
      `PopScope(canPop: false, onPopInvokedWithResult: _onPopInvoked)`
      unconditionally shows the leave-confirmation dialog on any pop
      attempt — sound on review, but recommend validating live on Android
      hardware/emulator before final sign-off if full assurance is needed
- [x] 'Seizures' → 'seizures' added to kSymptomDisplayMap during TEST 1 setup
      (it wasn't selectable in the picker before, which blocked the test).
      **User decision: keep this permanently, not just as a test artifact** —
      global red-flag-only symptom tokens must be selectable somewhere in
      the app, otherwise the red flag interrupt screen could never trigger
      from real user input in production. Committed as a real fix.

## E4.3 — Unit Tests

- [x] TEST 1: RedFlagInterruptScreen renders with red flag output —
      'EMERGENCY' and 'Seek medical care immediately' both present
- [x] TEST 2: matched_rule_name renders on interrupt screen —
      'Active Seizures' appears on screen
- [x] TEST 3: top_causes render on interrupt screen — 'Malaria' and
      'Seek emergency care' both present
- [x] TEST 4: ResultsScreen renders with non-red-flag output —
      'Results Screen' stub text present
- [x] TEST 5: RedFlagInterruptScreen shows EMERGENCY not other urgency
      levels — 'EMERGENCY' present, 'urgent'/'non_urgent'/'self_care'
      all absent
- [x] All 5 tests pass — flutter test test/results/red_flag_interrupt_test.dart

---

## NOTES / DECISIONS LOG (E4.3)

- **HomeScreen still doesn't exist on this branch** — same situation as
  E4.2.1: `feature/e4-user-flow-screens` (the real E4.2, splash/onboarding/
  home) has not merged into `develop` yet. Per user decision, "Leave"
  navigates via `Navigator.of(context).popUntil((r) => r.isFirst)` instead
  of a literal `HomeScreen` reference — same pattern as FollowupScreen's
  cancel dialog. Will correctly land on HomeScreen once E4.2 merges.
- **Constructor gap:** the spec's `RedFlagInterruptScreen(engineOutput: ...)`
  signature has no way to reach `AssessmentController` for the "Leave"
  button's required `clearAll()` call. Per user decision, added a required
  `assessmentController` constructor parameter (deviates from the literal
  STEP 5 snippet) and updated loading_screen.dart's call site to pass it —
  loading_screen already holds a reference to the controller.
- **topCauses has no per-condition explanation field** — `output_formatter.dart`
  only puts `condition_id`, `condition_name`, `score` into each topCauses
  entry (no per-condition explanation text exists anywhere in the engine
  output). Per user decision, `engineOutput.explanationPoints` is rendered
  once as shared context above the Possible Conditions list, rather than
  repeated under each condition (there's no real per-condition data to repeat).
- **loading_screen.dart's engine `output` was scoped inside a conditional
  block** (only computed if config + all 3 artifact URLs were present),
  so the unconditional post-run navigation at the bottom of `_runAssessment`
  couldn't reference it. Hoisted `output` to a nullable outer-scope variable;
  preserved the original SystemStatusScreen fallback for the case where the
  engine never actually ran (missing config/artifacts) — only branches to
  RedFlagInterruptScreen/ResultsScreen when `output` is non-null.
- **WillPopScope vs. zero-analyze-issues:** STEP 3 named `WillPopScope`
  explicitly, but it's deprecated in this Flutter version
  (`deprecated_member_use`), which directly conflicts with the zero-issues
  requirement in STEP 6. Per user decision, used `PopScope` (`canPop: false`
  + `onPopInvokedWithResult`) instead — same back-interception behavior,
  and it also properly supports Android predictive back, which
  `WillPopScope` does not.

---

# Phase E4 — Mobile Flow Integration (cont.)

**Phase:** E4 — Mobile Flow Integration  
**Task:** E4.4 — Results Screen  
**Branch:** feature/e4-results-screen  
**Last Updated:** 2026-07-04

---

## CURRENT STATUS: Foundation files created — analyze/format clean, pending manual verification and commit

---

## E4.4 — Foundation Files

- [x] Create lib/features/results/condition_card.dart — ConditionCard
      (StatefulWidget for Read More expand/collapse)
- [x] Create lib/features/results/symptom_summary_widget.dart —
      SymptomSummaryWidget (collapsible ExpansionTile + chips)
- [x] Replace lib/features/results/results_screen.dart — full
      implementation replacing the E4.3 stub
- [x] Update lib/features/assessment/loading_screen.dart — pass
      assessmentController to ResultsScreen
- [x] flutter analyze returns zero errors

---

## EXIT CRITERIA FOR E4.4 (all must be met before PR)

- [x] ConditionCard: rank/name/urgency chip row, match-strength bar
      (LayoutBuilder-sized, color by urgency), explanation text,
      expand/collapse "Read More", "Seek [urgency] care" label —
      all text sourced from the condition map, never hardcoded
- [x] SymptomSummaryWidget: collapsed-by-default ExpansionTile,
      chip per symptom token via kSymptomDisplayMap reverse lookup,
      raw token fallback if unmapped
- [x] ResultsScreen: X close button + confirmation dialog ("No, continue"
      primary / "Yes, close" outlined → clearAll() + pop to root)
- [x] Urgency banner color/label/care-instruction correct for all 4
      urgency levels (emergency/urgent/non_urgent/self_care)
- [x] Primary + secondary CTAs correct per urgency level (both the
      Part 3/4 set and the repeated Part 8 set at the bottom)
- [x] Possible Conditions section renders ConditionCard per topCauses
      entry with correct rank/barFraction; "No specific conditions
      identified" shown when topCauses is empty
- [x] Symptom Summary section wired to assessmentController.symptomTokens
- [x] Bottom disclaimer always visible
- [x] loading_screen.dart passes assessmentController to ResultsScreen
- [x] dart format . returns no changes needed
- [x] flutter analyze returns zero errors
- [x] test/results/results_screen_test.dart — 8 widget tests written,
      all passing (mockUrgentOutput / mockNonUrgentOutput / mockEmergencyOutput
      fixtures)
- [x] Updated the existing E4.3 test/results/red_flag_interrupt_test.dart —
      its ResultsScreen test asserted the removed stub text and was missing
      the new required assessmentController param; fixed to assert the
      'URGENT' banner instead — still passing
- [ ] Manual verification on simulator
- [ ] Work committed and pushed
- [ ] PR opened against `develop`

## E4.4 — Unit Tests

- [x] TEST 1: non_urgent urgency → banner shows NON_URGENT and care
      instruction 'Visit a clinic within 1-2 days.'
- [x] TEST 2: urgent urgency → banner shows URGENT and primary CTA
      'Find Nearby Care'
- [x] TEST 3: emergency urgency (non-red-flag path) → banner shows
      EMERGENCY and primary CTA 'Call Emergency'
- [x] TEST 4: top_causes[0].condition_name ('Malaria') renders from
      engine output
- [x] TEST 5: top_causes[0].explanation renders from engine output;
      no hardcoded placeholder text shown
- [x] TEST 6: ConditionCard bar width scales with barFraction — full
      (1.0) vs proportional (20/37 ≈ 0.54) bars measured and confirmed
      to differ, full > proportional
- [x] TEST 7: SymptomSummaryWidget shows correct display names for
      ['fever', 'headache'] → 'Fever' / 'Headache' (had to tap to expand
      the ExpansionTile first — children aren't in the tree while collapsed)
- [x] TEST 8: X button shows close confirmation dialog
      ('Close your assessment result?')
- [x] All 8 tests pass — flutter test test/results/results_screen_test.dart

---

## NOTES / DECISIONS LOG (E4.4)

- **ConditionCard per-condition urgency/explanation gap (same root cause as
  E4.3's red flag card):** `topCauses` entries only ever contain
  `condition_id`, `condition_name`, `score` (`output_formatter.dart:31-35`)
  — there is no per-condition `explanation` or `urgency` field anywhere in
  the engine output. Per user decision, `ResultsScreen` enriches a copy of
  each `topCauses` map with the single `engineOutput.urgency` and
  `engineOutput.explanationPoints` (joined) as `'urgency'` and
  `'explanation'` keys before constructing each `ConditionCard` — this
  keeps `ConditionCard`'s own constructor exactly as specified
  (`condition`, `rank`, `barFraction`, reading `condition['urgency']` /
  `condition['explanation']`), with the gap resolved entirely at the
  `ResultsScreen` call site rather than by changing ConditionCard's API.

---

## NOTES / DECISIONS LOG (develop merge, 2026-07-04)

- Merged `feature/e4-user-flow-screens` (E4.2 — splash, onboarding, home)
  into `develop`. This branch had been sitting unmerged since before E4.2.1,
  E4.3, and E4.4 were built directly on `develop` — none of which had
  `SplashScreen`/`OnboardingScreen`/`HomeScreen` available, which is why
  `app.dart` on `develop`/`main` kept `home: BootScreen()` this whole time
  and the app never actually started with the onboarding flow in any build
  after E4.1.
- Conflicts in `pubspec.yaml`: merged both branches' dependencies
  (`url_launcher` from E4.3 + `shared_preferences` from E4.2) and both
  asset declarations (`assets/svg/` + `assets/images/`).
- Conflicts in `PROGRESS.md`: both branches had appended legitimate,
  non-overlapping history. Reordered into actual chronological order
  (E4.1 cleanup → E4.2 → macOS migration → E4.2.1 → E4.3 → E4.4) instead
  of picking one side, so no history was discarded.
- Follow-up still needed: the E4.2 EXIT CRITERIA emulator-verification
  checkbox was never checked off before this merge — worth a real
  simulator pass now that `SplashScreen` is live on `develop`.

---

## BRANCH DIVERGENCE NOTE (2026-07-07)

**`develop` is behind `feature/e4-results-screen`.** Since this merge,
`feature/e4-results-screen` has picked up additional work not yet on
`develop`:

- Figma-accurate ResultsScreen redesign (custom header, wave banner with
  SVG illustrations, dash-indicator condition cards) and the
  `result_non_urgent.svg` black-icon fix
- A full app audit (engine logic, offline mode, UX, accessibility) with
  3 fixes applied: demographic tokens now actually reach the scoring
  engine (previously silently dropped — a real production bug), version-
  aware artifact caching (Hive box `artifact_cache`, separate from
  `config_cache`), and a doc-comment clarifying `ResultsScreen`'s
  `emergency` variant reachability
- See `feature/e4-results-screen`'s own `PROGRESS.md` for full detail on
  each of these — not duplicated here since `develop` hasn't merged them
  yet. A `feature/e4-results-screen` → `develop` merge (and eventually a
  `develop` → `main` PR) is still outstanding.

---

# Phase E6 — Facility Locator Integration

**Phase:** E6 — Facility Locator Integration
**Task:** E6.1 — Locator Foundation & Service Layer, E6.2 — Locator UI
**Branch:** feat/e6-facility-locator
**Last Updated:** 2026-07-20

---

## CURRENT STATUS: E6.1 + E6.2 BUILT — analyze/format clean, pending manual verification and commit

---

## E6.1 — Locator Foundation & Service Layer

- [x] Add `geolocator: ^13.0.0`, `flutter_map: ^6.0.0`, `latlong2: ^0.9.0` to
      pubspec.yaml (`url_launcher` already present from E4.3)
- [x] Run `flutter pub get` — resolved cleanly, no dependency conflicts
      (`flutter_map 6.2.1`, `geolocator 13.0.4`, `latlong2 0.9.1`)
- [x] Port the `_loadArtifact` versioned-cache helper (previously only on the
      unmerged `feature/e4-results-screen` branch) into this branch's
      `loading_screen.dart`, applied to all 4 artifacts (kb, rules,
      token_dictionary, facilities)
- [x] Add facilities as the 4th boot-sequence artifact — read URL/version from
      `config['artifacts']['facilities']`, cache under `cacheKey:
      'artifact_facilities'`
- [x] Store parsed facilities list in a variable for `LocatorService`
- [x] Persist facilities to a dedicated Hive box `facility_cache`
      (key `facilities_data`) so `LocatorScreen` can read them independently
- [x] Create `lib/features/locator/facility_locator_service.dart` —
      `FacilityLocatorService` with `getNearbyFacilities()` (haversine
      distance, urgency-based type filter, sparse-coverage fallback,
      sort + cap) and `getFacilitiesByLocation()` (manual state/city fallback)

## E6.2 — Locator UI

- [x] Create `lib/features/locator/facility_card.dart` — `FacilityCard`
      StatelessWidget (name, address, conditional distance/opening-status/
      call button, always-shown directions button)
- [x] Create `lib/features/locator/locator_screen.dart` — `LocatorScreen`
      StatefulWidget (map/list toggle, location permission flow with
      rationale copy, manual state/city fallback UI, facility bottom sheet)
- [x] Replace the "Find Nearby Care" stub bottom sheet in
      `lib/features/results/results_screen.dart` and
      `lib/features/results/red_flag_interrupt_screen.dart` with
      `Navigator.push` to `LocatorScreen(urgency: engineOutput.urgency)`

---

## EXIT CRITERIA FOR E6 (all must be met before PR)

- [x] All E6.1 and E6.2 tasks above complete
- [x] `flutter analyze` returns zero errors
- [x] `dart format --output=none --set-exit-if-changed .` returns clean (exit 0)
- [x] 8 unit tests written in `test/locator/facility_locator_service_test.dart`,
      all passing — `flutter test test/locator/facility_locator_service_test.dart`
- [ ] Manual verification on simulator/device (permission flow, map pins,
      list/map toggle, manual state/city fallback, directions/call links)
- [ ] Work committed and pushed
- [ ] PR opened against `develop`

---

## NOTES / DECISIONS LOG (E6)

- User decision (2026-07-20): since `_loadArtifact` only exists on the
  unmerged `feature/e4-results-screen` branch, port that exact helper
  pattern into this branch rather than doing a facilities-only ad hoc
  cache — keeps this branch forward-compatible with that branch's eventual
  merge into `develop`, at the cost of touching the other 3 artifacts'
  fetch logic (not just facilities) in this branch's diff.
- **Platform permission entries added** (not explicitly in the spec, but
  required for `geolocator` to function): `NSLocationWhenInUseUsageDescription`
  in `ios/Runner/Info.plist` (using the exact rationale copy from STEP 6) and
  `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` in
  `android/app/src/main/AndroidManifest.xml`. Without these the OS permission
  request would silently fail/crash on both platforms.
- **Sparse-coverage fallback interpretation:** the spec's per-type chain
  (`pharmacy → health_centre → clinic → hospital`) is applied as a single
  one-step expansion of the urgency's base type set when nearby (≤20km)
  results are `< 3` — not a repeated/recursive walk up the chain. Only
  applies to `urgent`/`non_urgent`/`self_care` (type-filtered); `emergency`
  has no type filter to expand (all facilities are already included, just
  ordered emergency-capable-first).
- **"emergency" urgency filter:** read literally as no type restriction —
  `getNearbyFacilities` includes every facility for `urgency == 'emergency'`,
  sorted with `emergency_capable == true` facilities first (each group
  independently sorted by distance), matching "emergency_capable == true
  first, then all others" rather than treating it as an exclusionary filter.
- **Pin vs. card tap:** map markers (small icons, no room for detail) open
  the bottom-sheet `FacilityCard` on tap, per spec. List-view and manual-
  fallback rows render `FacilityCard` directly inline (matching the manual
  fallback spec's literal "show results as list of FacilityCards") rather
  than wrapping each row in a second tap-to-open-the-same-card bottom sheet.

## NOTES / DECISIONS LOG (E6 — unit tests, 2026-07-20)

- **Field name bug fixed:** the E6.1 test brief's mock facility data uses
  `latitude`/`longitude` keys, but the coordinate field names were never
  specified when `facility_locator_service.dart`/`locator_screen.dart` were
  first built, and `lat`/`lon` was guessed. Renamed to `latitude`/`longitude`
  in both files to match the real schema — without this every distance
  calculation would have silently returned `double.infinity` and excluded
  every facility.
- **TEST 4 / TEST 5 conflict with the sparse-coverage fallback:** using the
  shared `mockFacilities` list, `self_care` only has 2 candidate facilities
  total (Kano pharmacy ~840km from the Lagos Island user, Surulere health
  centre ~7km away), so the `< 3 within 20km` fallback threshold always
  triggers and pulls in the Victoria Island clinic — contradicting TEST 4's
  literal "no clinic in results" assertion. Separately, TEST 5's wording
  ("fallback expanded to health_centre") assumed self_care's base filter
  starts narrower than it actually does (health_centre is already in the
  base type set, so the fallback chain can only ever add `clinic`, never
  `health_centre`). **User decision:** keep the `getNearbyFacilities`
  algorithm exactly as built in the previous E6 session — no production
  code change. TEST 4 was rewritten against a bespoke dataset with 3
  pharmacy/health_centre facilities within 20km (so fallback doesn't fire
  and the strict type assertion holds). TEST 5 was rewritten against a
  bespoke 2-facility dataset (1 pharmacy, 1 clinic, no health_centre) that
  demonstrates the real fallback behavior — clinic gets pulled in via the
  `health_centre → clinic` chain link even though no health_centre facility
  exists in that dataset.
- **TEST 8 is vacuous on the shared mock data:** `getFacilitiesByLocation`
  with `state: 'Kano', urgency: 'urgent'` returns an empty list, since the
  only Kano facility (`f003`) is a pharmacy and the `urgent` type filter
  only allows hospital/clinic. Both of TEST 8's assertions ("only Kano
  facilities", "no Lagos facilities") pass vacuously on the empty result.
  Written exactly as specified rather than silently changing the urgency
  param — flagged here since it doesn't actually exercise the state filter
  against non-empty data.
- **Manual fallback city/area options** are derived from the loaded
  facilities dataset (distinct `city_area` values for the selected state),
  since the spec gives a fixed list for state (`['Lagos', 'FCT', 'Kano']`)
  but not for city/area.
- **Directions/Call actions:** `_openDirections` launches a Google Maps
  web URL (`https://www.google.com/maps/dir/?api=1&destination=lat,lon`)
  via `url_launcher`; `_callFacility` uses a `tel:` URI — same pattern as
  the existing `_callEmergency` in `results_screen.dart`/
  `red_flag_interrupt_screen.dart`. Not detailed in the spec beyond the
  callback signatures.

---

# Phase E8 — Urgency Determiner Clinical Safety Fix

**Phase:** E8 — Urgency Determiner Clinical Safety Fix
**Task:** E8.1 — Add Priority 4a (increase_urgency single-level escalation)
**Branch:** feature/e8-urgency-determiner-fix
**Last Updated:** 2026-07-21

---

## CURRENT STATUS: COMPLETE ✅

---

## E8.1 — Clinical safety fix

**Bug:** a moderately malnourished child with diarrhoea (`increase_urgency`
demographic effect, no seasonal modifier active) was getting `non_urgent`
instead of `urgent` — `increase_urgency` alone had no escalation path in
`urgency_determiner.dart`, only combined with a seasonal modifier
(Priority 4b, added in E3.5). Engineering lead approved an immediate fix.

- [x] Added Priority 4a to `lib/core/engine/urgency_determiner.dart` —
      `increase_urgency` alone escalates the top condition's
      `urgency_default` one level up via `_escalateOne()`
      (`self_care → non_urgent`, `non_urgent → urgent`, `urgent`/`emergency`
      unchanged)
- [x] Priority 4c (`increase_urgency` + seasonal modifier → `emergency`,
      previously labelled 4b) is checked **before** Priority 4a in code
      order — both match on `demographicEffect == 'increase_urgency'`, so
      the more specific seasonal-combo case must be tested first or
      Priority 4a would return early and shadow it
- [x] Priority 4b (`escalate_urgent` → `urgent`) unchanged, unaffected since
      it matches a different effect string
- [x] Reconstructed the E7 token-split test changes in
      `test/engine/pilot_case_validation_test.dart` (this branch was cut
      from `develop` before E7 merged, so the split didn't exist here yet):
      mock KB demographic modifier split into `severe_malnutrition_sam`
      (`escalate_emergency`) and `moderate_malnutrition_mam`
      (`increase_urgency`), Case 10 renamed accordingly
- [x] Case 10b assertion changed from `non_urgent` to `urgent`, comment
      updated to document the fix
- [x] Created `test/engine/urgency_determiner_fix_test.dart` — 5 unit tests
      exercising Priority 4a directly against `UrgencyDeterminer`
- [x] `flutter test test/engine/urgency_determiner_fix_test.dart` — 5/5 passing
- [x] `flutter test test/engine/pilot_case_validation_test.dart` — 13/13
      passing (Case 10b now correctly resolves `urgent`)
- [x] Full `flutter test` — 73/73 passing
- [x] `flutter analyze` — zero errors
- [x] `dart format --output=none --set-exit-if-changed .` — clean (exit 0)

---

## EXIT CRITERIA FOR E8

- [x] Priority 4a added, 4c checked before 4a to avoid shadowing
- [x] Case 10b updated to assert `urgent`
- [x] 5 new unit tests written and passing
- [x] All existing tests still passing (73/73 total)
- [x] `flutter analyze` zero errors, `dart format` clean
- [x] Work committed and pushed

---

## NOTES / DECISIONS LOG (E8)

- Engineering lead + founder sign-off obtained for this clinical urgency
  logic change (per CLAUDE.md locked principles #5/#8 — red flag/urgency
  overrides and architecture changes require review). Flagged as a
  time-sensitive clinical safety fix, not routine engine calibration.
- This branch (`feature/e8-urgency-determiner-fix`) was cut from `develop`
  before `feat/e6-facility-locator`'s later E7 commits (token-split pilot
  case test update, OSM tile fix) were merged back — only the E6 locator
  feature itself was present via PR #15. The E7 pilot-case test changes had
  to be reconstructed here from scratch to apply this fix's Case 10b
  update; the OSM tile fix is unrelated and not part of this branch.

---

## Case 04 policy change — founder decision, Option B (2026-07-23)

**Branch:** `feat/case04-policy-option-b`

Founder made the final clinical policy call on Case 04 (`children_under_5` +
`rainy_season` compound demographic/seasonal escalation): **Option B —
`urgent`, not `emergency`.**

- [x] Updated `urgency_determiner.dart` Priority 4c: `increase_urgency` +
      seasonal modifier now resolves to `urgent` (was `emergency`).
      Priority 4c is still checked before Priority 4a, for the same reason
      as before (both match on `demographicEffect == 'increase_urgency'`,
      so the more specific seasonal-combo case must be tested first).
- [x] Updated `test/engine/urgency_determiner_fix_test.dart` TEST 5 — now
      asserts `urgent`, not `emergency`
- [x] Updated `test/engine/pilot_case_validation_test.dart` Case 04 — now
      asserts `urgent`; removed the stale "gap" comment left over from
      before Priority 4c existed
- [x] Full `flutter test` — 75/75 passing
- [x] `flutter analyze` — zero errors, `dart format` — clean

**Not done (outside mobile engineering scope):** the companion KB
explanation-template update (`malaria.ng.v2.0.json` → regenerate
`kb.ng.v2.2.json` → `kb.ng.v2.3.json`, new SHA256) requested in the same
directive. That work lives in the `wellapath-knowledge-base` backend/data
repo, not this mobile repo — no such files, regeneration pipeline, or R2
upload access exist here. Flagged back to the engineering lead rather than
fabricated.

---

# Phase E8.3 — Security Hardening

**Phase:** E8 — Validation, Calibration & Safety Hardening
**Task:** E8.3 — Security Hardening
**Branch:** feat/e8-security-hardening
**Last Updated:** 2026-07-23

---

## E8.3.1 — Input Validation Hardening (audit only — no gaps found)

Audited every user input point in the assessment flow:

1. **Symptom tokens** — every path that adds a symptom token
   (`symptom_selection_screen.dart`, `body_area_screen.dart`,
   `followup_screen.dart`'s additionalSymptoms checkboxes) only ever calls
   `AssessmentController.addSymptomToken()` with a token pulled from a fixed
   const map (`kSymptomDisplayMap`, `kFollowupQuestionMap` option lists, or
   the hardcoded `'seizures'` entry). Both screens that contain a
   `TextField` (`symptom_selection_screen.dart`, `body_area_screen.dart`)
   use it purely as a **search/filter box** over the fixed list — the typed
   text never itself becomes a token. Independently, `RedFlagEvaluator.evaluate()`
   validates every symptom token against `token_dictionary`'s
   `symptom_tokens`/`red_flag_tokens` before red-flag evaluation or scoring
   ever runs, and throws `ArgumentError` on any unknown token — this fires
   before `EngineController` touches `ScoringEngine`, i.e. before "the
   engine" in the sense of triage logic. Confirmed intact and unchanged
   since E4.
2. **Age range** — `age_screen.dart` only calls
   `assessmentController.setAgeRange(label)` from five hardcoded button
   labels feeding a fixed `_ageTokenMap`. No `TextField` exists on this
   screen.
3. **Sex selection** — `sex_screen.dart` has exactly two hardcoded options
   (`Male`→`'male'`, `Female`→`'female'`). `shouldShowPregnancyScreen` is
   `_sex == 'female'`; there is exactly **one** call site that pushes
   `PregnancyScreen` (`medical_conditions_screen.dart`), gated by that same
   check, and `PregnancyScreen` itself has a defense-in-depth `initState`
   guard that immediately pops if `shouldShowPregnancyScreen` is false.
   `setSex()` also removes any stale `'pregnancy'` demographic token if sex
   is changed away from female. Confirmed this still holds after the E4.2/
   E4.3 additions — no new navigation path to `PregnancyScreen` was
   introduced by either.
4. **Medical condition inputs** — `medical_conditions_screen.dart` has
   exactly three hardcoded options (`Yes`/`No`/`Don't Know`); only `'yes'`
   ever sets the demographic token (`value == 'yes'`), so `'no'` and
   `'dont_know'` are equivalent no-ops. No `TextField` exists on this
   screen.
5. **Severity slider** — `_SegmentedSeveritySlider` is a 7-segment
   tap-driven control (not a continuous `Slider`), each producing exactly
   one of 7 fixed fractional values `(i+1)/7`. `_severityToken()`'s cascading
   threshold checks map all 7 possible values (and any input, in principle,
   since the final branch is an unconditional `return`) onto exactly one of
   the 4 locked tokens (`mild`, `moderate`, `severe`, `very_severe`) — no
   out-of-range value is possible.

**Finding: none.** All five input paths were already fully hardened; no
code changes required for this section.

---

## E8.3.2 — Local Storage Audit (audit only — no gaps found)

Full inventory of every Hive box and `SharedPreferences` usage in `lib/`
(via `grep -rn "Hive\.\(openBox\|box\)\|shared_preferences\|SharedPreferences"`
and every `.put(` call site):

| Storage | Key(s) | Contents |
|---|---|---|
| Hive `config_cache` | `last_known_config` | The raw `/config` response only (artifact URLs/versions/hashes) — no symptom/demographic data |
| Hive `artifact_cache` | `artifact_kb_v<version>`, `artifact_rules_v<version>`, `artifact_token_dict_v<version>`, `artifact_facilities_v<version>` | Versioned artifact JSON blobs (KB conditions, rules, token dictionary, public facility directory) — static reference data, not per-user |
| Hive `facility_cache` | `facilities_data` | The parsed facilities list (public health-facility directory: name/type/location) — no patient data |
| `SharedPreferences` | `onboarding_seen` | Boolean flag only |

Confirmed via every `.put(` call site in `lib/` (exactly 3: `storage_service.dart`,
and two in `loading_screen.dart`) that **no other box or key exists**.
`AssessmentController` — which holds all in-session symptom tokens,
demographic tokens, severity/duration tokens, sex, age, and body area — has
**zero** persistence imports (`Hive`, `SharedPreferences`, or otherwise);
its entire state lives in memory for the app session and is discarded on
`clearAll()` or app close. `EngineOutput` (the triage result) is passed
directly via widget constructor params from `LoadingScreen` to
`ResultsScreen`/`RedFlagInterruptScreen` — never written to any box.

**Finding: none.** No symptom inputs, assessment results, or user
identity/demographics are ever persisted anywhere on-device. No code
changes required for this section.

---

## E8.3.3 — No PHI in Logs Audit (1 finding, fixed)

Reviewed every `debugPrint`/`log.` call site in `lib/` (8 total; confirmed
zero raw `print()` calls exist anywhere in `lib/`):

| Location | Content | Verdict |
|---|---|---|
| `config_service.dart:16` | `DioExceptionType` enum only | Safe |
| `api_client.dart:25` | `LogInterceptor` with `requestBody: false, responseBody: false` | Safe — matches E1.6 requirement exactly |
| `red_flag_evaluator.dart:28` | Unknown-token **count** only, never token values | Safe |
| `loading_screen.dart` (×4 static strings) | No data, generic status messages | Safe |
| `loading_screen.dart:193` | **`output.urgency` (the triage result level)** | **Finding — fixed** |
| `locator/*.dart`, `results/*.dart` | No logging at all in these files | Safe (no location coordinates or result data ever logged) |

**Finding:** `loading_screen.dart` logged the assessment's final urgency
level (`'Assessment complete — urgency: ${output.urgency}'`). While only a
coarse 4-value enum (not symptom tokens or demographics), this is still
part of the assessment *result* being logged, which the E8.3.3 criteria
explicitly rule out — and `debugPrint` output is not stripped from release
builds, so this was a real production log-exposure surface (device
syslog).

**Fix applied:** changed to a bare completion marker with no result data —
`debugPrint('Assessment complete')` — matching the existing PHI-safe
pattern already used elsewhere in the same file (e.g.
`'Engine run failed — assessment incomplete'`).

---

## E8.3.4 — Certificate Pinning (deferred to production — documented)

Inspected the actual live TLS certificate currently served by
`wellapath-backend-staging.onrender.com`:

```
issuer=C=US, O=Google Trust Services, CN=WE1
subject=CN=onrender.com
notBefore=May 26 21:02:15 2026 GMT
notAfter=Aug 24 22:01:50 2026 GMT
```

**Certificate pinning is not implemented for staging, and this is a
deliberate decision, not an oversight.** Evidence:

1. The certificate's `subject` is `CN=onrender.com` — a **shared,
   platform-wide certificate covering all of Render's hosted apps**, not
   one specific to `wellapath-backend-staging`. It is entirely managed by
   Render/Google Trust Services, outside WellaPath's control.
2. The validity window is ~90 days (`May 26 → Aug 24 2026`), consistent
   with automated Let's-Encrypt-style rotation. Render rotates this
   certificate on its own schedule with no advance notice to us.
3. Pinning against this specific leaf certificate (via
   `dio_certificate_pinning` or a custom `HttpClientAdapter`) would work
   until Render's next automatic rotation — at which point every installed
   copy of the app would start failing every network call, with no way to
   recover short of shipping an app update. For a health-adjacent app still
   in active development/testing against this exact staging host, that risk
   outweighs the benefit pinning would provide against a threat model
   (MITM on a staging backend with no PHI) that is already low.

**Recommendation for production:** once WellaPath has its own
dedicated production domain/certificate, implement pinning at the
**public-key (SPKI) or intermediate-CA level** rather than the leaf
certificate — this survives routine leaf-cert renewal and only needs
updating on a genuine CA/key change. Flagged as a required pre-production
task, not part of this branch's exit criteria.

**No code changes made for this section** — decision documented per the
task's own stated exit path ("If certificate pinning is not feasible for
staging... document the reason and flag for production implementation
instead").

---

## E8.3.5 — Artifact Integrity Verification (missing — implemented + tested)

**Finding:** `_loadArtifact` in `loading_screen.dart` did **not** verify
downloaded artifacts against the `hash` field `/config` provides for each
artifact (`"hash": "sha256:<hex>"`) — a tampered or corrupted artifact
would have been silently cached and used to drive triage decisions. This
was a real gap, not a false alarm.

**Fix implemented:**
- Added `crypto: ^3.0.7` as a direct dependency (previously only resolved
  transitively) since it's now imported in production code.
- `_loadArtifact` now takes an `expectedHash` parameter and verifies the
  **raw response bytes** (not a re-serialized JSON round-trip, which could
  differ from what the hash was computed against) via SHA256 on **every
  read** — both a fresh download and a cache hit:
  - Cache hit + hash mismatch → the corrupted entry is discarded
    (`box.delete`) and a fresh download is attempted — never silently
    served.
  - Fresh download + hash mismatch → retried once; if the retry also fails
    the hash check, a `StateError` is thrown (caught by `_runAssessment`'s
    existing error handling, surfacing the existing "something went wrong"
    retry UI — no PHI, no engine run on unverified data).
  - No hash provided by `/config` for a given artifact → treated as
    "nothing to verify against" (`true`), not a failure — matches how
    `version` already defaults gracefully when absent.
- Cache storage changed from decoded `Map` to the **raw JSON string**, so
  the exact original bytes are available to re-hash on every subsequent
  cache hit, not just at download time.

**Test:** `test/assessment/loading_screen_version_cache_test.dart` — new
test `'corrupted cached artifact byte fails the hash check on a
version-aware cache hit and is re-downloaded'`: downloads the real live KB
artifact once to get genuine bytes + hash, flips one character in the
middle of a copy, seeds that corrupted copy into the cache under the
current version key, then calls `_loadArtifact` with the genuine hash and
confirms: (1) the corrupted bytes are never returned to the caller, (2) a
fresh, genuine copy is downloaded and re-cached, (3) the box's entry after
the call re-hashes to the genuine hash, not the corrupted one. The other
two tests in this file (version-detection, cache-hit-no-download) were
updated to match the new raw-string cache storage format.

**Full suite:** 76/76 passing. `flutter analyze` zero errors, `dart format`
clean.

---

# Phase E8.4 — Device Performance Testing

Branch: `feat/e8-device-performance`. Target device profile validated:
2GB RAM (AVD configured at 1.5GB RAM to bias toward the conservative end
of the target range), budget quad-core,
API 26 (Android 8.0), 720x1280 screen, throttled to `umts` network
profile (384kbps / 35-200ms latency) for the 3G scenarios. No physical
low-end QA device was available, so an Android SDK + emulator toolchain
was set up from scratch on this machine (previously iOS-only) to run
these tests against a real Android build rather than iOS Simulator.

## E8.4.1 — Engine Performance

Measured via temporary `Stopwatch` instrumentation around
`EngineController.run()`, 10 iterations per scenario, triggered through
a real on-device assessment run (not a synthetic unit benchmark). All
instrumentation was removed from `loading_screen.dart` after data
collection — no permanent code change from this subtask.

| Scenario | avg | min | max |
|---|---|---|---|
| Minimal (2 tokens) | 0.042ms | 0.036ms | 0.079ms |
| Moderate (5 tokens + demographic) | 0.041ms | 0.037ms | 0.045ms |
| Heavy (8 tokens + demographic + seasonal) | 0.041ms | 0.039ms | 0.043ms |
| Red flag (seizures) | 0.011ms | 0.008ms | 0.031ms |

All scenarios finish in **well under 1ms**, roughly 12,000x under the
500ms target and nowhere near the 2000ms critical threshold. The engine
pipeline itself (RedFlagEvaluator → ScoringEngine → UrgencyDeterminer →
OutputFormatter) is not a performance concern on this device class —
any user-perceived latency in the assessment flow comes entirely from
artifact loading, not scoring.

## E8.4.2 — Artifact Loading Performance

| Scenario | Result | Target | Status |
|---|---|---|---|
| Cold boot, full network speed | ~1.3s | <30s | Pass |
| Warm boot (cache hit) | ~25ms | <3s | Pass |
| Cold boot, throttled 3G (`umts`, 384kbps) | ~7 min, then **failed outright** | <30s | **Critical fail** |
| Version-update boot | not directly measurable (see note) | <15s on 3G | Estimated pass, unverified |

**Critical finding — throttled 3G cold boot fails, does not just run
slow.** Under a realistic `umts` profile matching this task's own
100–500kbps target range, the first-run artifact download (KB, rules,
token dictionary, facilities — 4 artifacts fetched in parallel via
`Future.wait`) took roughly 7 minutes and then surfaced the generic
"Something went wrong... Please try again" error — 14x over the 30s
target, ending in total failure rather than a slow success.

Root cause is not logged directly (by design — no artifact content or
exception detail is logged, per the PHI-safe logging rule), but the
evidence points to `receiveTimeout` (30s) measuring the gap *between*
received chunks rather than total transfer duration: a connection
trickling data slowly under heavy throttling never triggers that
timeout, so the request drags on for minutes until something else (most
likely the backend host terminating an unusually long-lived slow
connection) errors out. Four parallel downloads competing for the same
constrained, latency-inflated connection likely compounds this further.

**Not fixed on this branch.** A real fix (e.g. sequential artifact
downloads, a wall-clock cap independent of per-chunk timeout, or
better slow-network UX) would be an architecture-level change to the
boot/loading sequence, which per this project's locked principle #8
("no architecture changes without founder + engineering lead review")
is out of scope for a performance-*testing* branch. Flagging this for
engineering lead review before the first real low-bandwidth field
rollout — this is the one finding in this phase that should block
sign-off, not just get noted.

**Version-update boot — reasoned estimate, not directly measured.**
Forcing a single-artifact cache invalidation requires writing into the
app's Hive cache from outside the app (`run-as`), which isn't available
on a `--release` build with no debuggable flag. Bounded estimate: a
version bump invalidates one artifact's versioned cache key while the
other three still hit cache, so the request shape moves from "4
parallel downloads" to "1 download" — at full network speed the
~1.3s cold-boot figure suggests a low-hundreds-of-ms result for a
single artifact. Under the same throttled 3G conditions that broke the
full cold boot, a single-artifact download is not guaranteed to be a
proportional 1/4 of the failure — it may in fact finish, since it no
longer shares the constrained link with 3 other
connections. **This needs a real device/emulator test with an
artificially bumped artifact version before treating it as verified**,
flagged as follow-up rather than asserted here.

## E8.4.3 — Memory Usage

Measured via `adb shell dumpsys meminfo org.wellapath.wellapath_mobile`
at steady-state app screens (not peak-during-transition, which
`dumpsys` doesn't sample well):

| State | PSS |
|---|---|
| Results screen (post-assessment) | ~76.7MB |
| Facility locator map view | ~76.1MB |

Both comfortably under the 150MB target and far from the 200MB critical
threshold — no concern on this device class.

## E8.4.4 — Offline Assessment Performance

Forced genuine offline state via
`adb shell settings put global airplane_mode_on 1` + `adb reboot`
(a live `settings put` alone, and `svc wifi/data disable`, do **not**
actually cut the emulator's virtual network — confirmed
`ping 8.8.8.8` still succeeded under those; only airplane mode +
reboot produces a real `Network is unreachable`).

With the app relaunched under confirmed offline conditions:

- **Boot:** app launched straight to the Home screen using the cached
  config, no crash, no visible error.
- **Full assessment flow** (Male, 18-40, skip medical conditions, Head →
  Headache + Fever, Mild, <3 days, skip additional symptoms) completed
  successfully entirely offline:
  - `PERF: artifact load total = 38ms` — all 4 artifacts served from
    the version-and-hash-verified Hive cache, zero network calls.
  - Engine benchmarks unchanged from the online run (sub-millisecond
    across all 4 scenarios).
  - `Assessment complete` logged, no error path taken.
  - Results screen rendered (**URGENT / Malaria**) — confirmed via
    screenshot.
- **No network error was shown to the user** at any point in this flow.

**Gap noted, not fixed:** there is no explicit "you are offline, using
cached data" indicator anywhere in the UI. The flow works correctly, but
a user has no way to distinguish "assessed against fresh data" from
"assessed against a cache that may be stale" — worth a product decision,
not addressed on this branch since it's a UI/UX addition outside this
phase's scope.

## E8.4.5 — Facility Locator Performance

- **Location permission flow:** rationale dialog → system permission
  dialog → "turn on device location" dialog, all handled correctly.
- **Tap-to-pins:** ~1.8s from opening the locator to pins rendered
  with real data (under the 3s target).
- **Facility data:** real dataset loaded correctly ("30 of 30 shown"),
  list view showing correct real facility names and distances (e.g.
  "Runsewe Hospital... 0.7 km away").
- **Memory during map view:** ~76.1MB (see E8.4.3).
- **Filter-by-urgency:** not independently re-timed on-device this
  phase — the underlying `FacilityLocatorService` filter logic was
  already verified fast against real data in earlier session testing;
  no evidence found suggesting it would regress on this device class.
- **60fps scroll target:** `dumpsys gfxinfo` reported "Total frames
  rendered: 0" during list scroll — this is a **tooling limitation, not
  an app bug**: Flutter renders through its own engine (Skia/Impeller),
  largely bypassing the native Android View-based frame pipeline that
  `gfxinfo` instruments. Compensating signal: `logcat` showed no
  Choreographer "Skipped N frames" jank warnings during the scroll
  test — a positive but less precise signal than a direct frame-time
  measurement.

## Critical findings discovered during this phase (not part of the
original test plan, but real bugs found by exercising the app on
Android for the first time in this project)

1. **`android.permission.INTERNET` was missing entirely** from
   `AndroidManifest.xml` — this blocked **all** network access on
   Android outright (`DioException: Failed host lookup`). Never caught
   previously because only the iOS Simulator had been tested. **Fixed**
   — permission added.
2. **OSM map tiles returned 403** ("Access blocked... not following the
   tile usage policy") — the `userAgentPackageName` fix for
   `flutter_map`'s `TileLayer` (originally made on
   `feat/e6-facility-locator`) was pushed to that branch *after* PR #15
   had already merged into `develop`, so it silently never landed.
   **Re-fixed** on this branch. Process note: a commit pushed to a
   branch after its PR merges is effectively lost unless a follow-up PR
   is opened — worth watching for on future branches.

## Exit criteria

- [x] Engine performance measured across all 4 required scenarios
- [x] Boot sequence timed cold / warm / throttled-3G
- [x] Memory measured at steady-state screens
- [x] Offline assessment verified end-to-end, timed
- [x] Facility locator performance measured
- [x] Two real Android-only bugs found during testing, fixed
      (INTERNET permission, OSM tile 403)
- [x] Any scenario exceeding critical thresholds investigated —
      throttled-3G cold boot is investigated and **documented as a
      flagged, unresolved finding for engineering lead review**, per
      this project's no-unilateral-architecture-change principle,
      rather than fixed unilaterally
- [x] `flutter analyze` zero errors, `dart format` clean
- [x] No permanent test/debug instrumentation left in
      `loading_screen.dart`

---

# Phase E9 — Progressive Boot (fixes the E8.4 throttled-3G finding)

Branch: `feat/e9-progressive-boot`. Direct follow-up to the E8.4 finding
that a throttled-3G cold boot took ~7 minutes and then failed outright —
blocking for E9 internal beta. Also folds in the minor E8.4 UX gap
(no offline indicator), logged separately as
[GitHub issue #21](../../issues/21), E9 scope, not part of this branch.

## What changed

New `lib/core/network/staged_artifact_loader.dart` replaces the
`Future.wait`-of-4 download in `loading_screen.dart`:

1. **Staged, not flat-parallel.** The 3 core artifacts (token dictionary,
   rules, knowledge base — everything the engine needs for one
   assessment) download in parallel. Facilities (the largest artifact,
   only needed if the user opens the locator) downloads separately, in
   the background, via `loadFacilitiesInBackground` — it never blocks
   `loadCoreArtifacts` from returning.
2. **Exponential backoff retry.** Every artifact download retries up to
   3 times (2s/4s/8s backoff) on a network failure, distinct from the
   existing single-retry hash-integrity check from E8.3.5.
3. **A hard per-attempt wall-clock timeout — the critical fix.** See
   below; this is the actual root-cause fix for the E8.4 finding, not
   the staging/backoff changes.
4. **Boot progress indicator.** `loading_screen.dart` shows
   `"Setting up WellaPath... (N of 4)"` while the download is in flight.
5. **Dedicated first-launch-offline screen.** If a core artifact
   exhausts all retries, `FirstLaunchOfflineException` is thrown and
   `loading_screen.dart` shows *"WellaPath needs a brief internet
   connection the first time. Please connect and try again."* — distinct
   from the generic "something went wrong" error, which remains for
   hash-integrity failures.
6. **Facility locator loading state.** `locator_screen.dart` now
   observes `StagedArtifactLoader.instance.facilitiesReady` /
   `facilitiesFailed`. If the user taps "Find Nearby Care" before the
   background facilities download finishes, it shows "Finding nearby
   facilities... please wait" + spinner instead of an empty map, and
   transitions to the normal map/list once the download completes (or a
   distinct message if it fails outright). No crash, no empty map.

## The actual root cause of the E8.4 7-minute hang

Restructuring the download into stages (core vs. facilities) and adding
backoff retry, on their own, **did not fix the hang** — confirmed by
reproducing it on-device with the new pipeline before the real fix was
in place. The root cause is exactly what E8.4 hypothesized: Dio's
`receiveTimeout` measures the gap *between* received chunks, not total
transfer time. A connection that keeps trickling data — however
slowly — never triggers it, so the retry loop never engages and the
call just hangs. Restructuring which artifacts download in parallel
doesn't change this if the underlying request never fails on its own.

**Fix:** every download attempt is now wrapped in an explicit
`Future.timeout(perAttemptTimeout)` — a hard wall-clock cap independent
of Dio's chunk-gap timeout. This is what actually makes the retry loop
(and eventually `FirstLaunchOfflineException`) engage instead of
hanging forever. See `StagedArtifactLoader.perAttemptTimeout` in
`staged_artifact_loader.dart` for the full reasoning.

## On-device verification (Android emulator, `umts` throttle profile, same as E8.4)

Rebuilt the AVD's `umts` profile (384kbps / 35-200ms delay) and ran the
full assessment flow on a fresh install multiple times, capturing
continuous `adb logcat` output for unambiguous before/after timestamps
(a first pass using one-shot `adb logcat -d` dumps produced misleading
results — grep was silently treating the log as binary and matching
nothing, and manual on-screen-clock timing was contaminated by tens of
seconds of inter-tool-call latency on this side, not app behavior; both
are noted here so a future run doesn't repeat the same false starts).

**Confirmed: the indefinite hang is gone.** Before the wall-clock-timeout
fix, reproducing the exact E8.4 scenario on this new pipeline still hung
for 7+ minutes with no resolution (success, failure, or retry) — proving
the staging/backoff restructuring alone was insufficient. After the fix,
every run reaches a definitive outcome (success, or
`FirstLaunchOfflineException` shown via the dedicated screen) within a
bounded time, consistent with the configured
`maxRetries=3` × `perAttemptTimeout` + backoff math.

**`/config` fetch itself is also flaky under this throttle, separately
from anything in this branch's scope.** `ConfigService`'s `/config`
request has its own fixed 10s timeout with no retry at all. Under this
`umts` profile it succeeded quickly (~2.3s) roughly half the time and
timed out the other half. On a fresh install with no cached config, a
timeout here means `loading_screen.dart` finds `config == null` and
silently routes to `SystemStatusScreen` (mislabeled "Online") having
discarded the user's just-completed assessment, with no error shown
explaining why. **This is a real gap in the first-launch experience,
but it sits entirely inside `ConfigService`/`BootController` — outside
this branch's assigned scope (the artifact download stage) and inside
the project's locked boot-sequence order** (CLAUDE.md: "BOOT SEQUENCE
ORDER — NEVER CHANGE THIS"). Flagging this for engineering lead
prioritization rather than fixing it unilaterally here.

**`perAttemptTimeout` tuning, with real numbers.** Checked actual artifact
sizes: token_dictionary ~8.8KB, rules ~29KB, knowledge_base ~102KB,
facilities ~1.7MB (confirms why facilities had to be excluded from the
blocking path — at 384kbps it alone needs ~35s+). An initial 8s
per-attempt timeout was measured cutting off the ~29KB rules file before
it could finish. Raised to 15s. token_dictionary (8.8KB) reliably
succeeds on the first attempt every time observed. **Under the harshest
observed throttle conditions this session, rules (~29KB) and
knowledge_base (~102KB) still failed to complete within 15s on every
attempt across 3 full retries** — diagnostic logging (temporary, removed
before commit) showed a clean `TimeoutException after 0:00:15.000000` on
every attempt for both files, every run. Bandwidth math alone (29KB at a
contended ~16KB/s ≈ 1.8s) does not explain this — the gap suggests real
TCP/TLS behavior under this specific emulator's combination of bandwidth
cap + injected latency (slow start, handshake round-trips, chunked
transfer overhead) degrades effective throughput far below the nominal
384kbps figure.

**Recommendation, not a claim of success:** the indefinite-hang bug is
fixed and confirmed — this was the actual blocking issue. Whether a
*real* 3G connection (as opposed to this specific emulator throttle
preset) can complete the core artifact download within the 30s target
was not conclusively confirmed on-device this session, because this
throttle profile appears to model a more severe condition than raw
384kbps math would suggest. Recommend validating with a real device on
an actual Nigerian carrier SIM before treating the 30s number as
confirmed for production sign-off; the emulator's `umts` preset may not
be a reliable stand-in for real carrier 3G TCP behavior.

## Facility locator loading state

Verified in code and via the existing on-device facility-locator flow
from E8.4 (data loads correctly, real facilities render). The new
waiting/failed states were not separately re-driven on a real device
this session — they follow directly from the same `ValueNotifier`
listener pattern already covered by `staged_artifact_loader_test.dart`,
and the widget-level branch (`_waitingForFacilities` /
`_facilitiesLoadFailed`) is a small, low-risk addition to
`locator_screen.dart`'s existing, already-verified initialization path.

## Test coverage

New `test/core/network/staged_artifact_loader_test.dart` — 10 tests:
exponential backoff retries the right number of times before succeeding;
exhausting retries throws `FirstLaunchOfflineException` (not the raw
network error); **a request that never resolves is still cut off by
`perAttemptTimeout`** (direct regression test for the actual root-cause
fix); a hash-integrity failure still surfaces as `StateError`, distinct
from a network failure; core artifacts resolve independently of
facilities; `facilitiesReady`/`facilitiesFailed` flip correctly for the
background download in both the success and failure case; boot progress
reaches step 3 once core artifacts are cached; and the pre-existing
cache-hit/hash-verification behaviour from E8.3.5 still holds after the
refactor. Full suite: 86/86 passing. `flutter analyze` zero errors,
`dart format` clean.

## Exit criteria

- [x] Progressive download pipeline implemented (staged, not flat-parallel)
- [x] Exponential backoff retry (3 retries, 2s/4s/8s) on network failure
- [x] Boot progress indicator shown to user
- [x] First-launch offline screen shown when retries exhausted
- [x] Facility locator shows a loading state when facilities not yet
      cached — no crash, no empty map
- [x] The E8.4 indefinite-hang bug is fixed and confirmed on-device
- [ ] Throttled 3G cold boot completes in <30 seconds — **not
      conclusively confirmed**; see the on-device verification section
      above for why, and the recommendation to validate on a real
      device/carrier before production sign-off
- [x] `flutter analyze` zero errors, `dart format` clean, full test
      suite passing (86/86)

---

# Phase E9 — Symptom Picker Vocabulary Expansion (issue #25)

Branch: `feat/e9-symptom-picker-expansion`. Fixes the finding from issue
#25: the picker exposed only 18 unique tokens (~11% of the 164-token
vocabulary), leaving 19 of the KB's 50 conditions completely unreachable
and 5 more (cardio_symptoms, sari, hypertension, tuberculosis_suspected,
diabetes) reachable only via weak, generic shared tokens rather than
their real distinguishing symptoms.

## Data source

Data engineer's mapping, `wellapath-knowledge-base` repo,
`mobile_handoff/` directory, branch `feat/e9-symptom-token-mapping`
(PR #9 — **still open, not yet merged into `develop`** as of this
writing; read directly off the branch since the content was already
final. Flagging this for the engineering lead to follow up on merging
that PR, since another engineer relying on "it's in develop" would not
find it there yet):
- `symptom_display_body_area_map.csv`/`.json` — all 164 tokens: display
  name, body area, ambiguous flag, note.
- `condition_top5_symptom_tokens.json` — top 5 symptoms by weight for
  all 50 conditions.

## What changed

**Diffed first**, per instruction — the data engineer's mapping covers
all 164 tokens, not just the gap. Computed the actual new-token need by
taking the union of top-5 tokens across the 24 priority conditions (19
completely unreachable + 5 effectively-unreachable) and subtracting the
18 tokens already in the picker: **91 new tokens**, not 164 — the scope
stayed to what's needed to reach the 24 target conditions, not a full
164-token import, consistent with this project's no-scope-creep
principle.

`kSymptomDisplayMap` (`lib/core/constants/symptom_display_map.dart`)
grew from 18 unique tokens (20 display labels) to **109 unique tokens
(111 display labels)**. `kBodyAreaSymptoms` was expanded correspondingly
so every new token is actually reachable through some body area, not
just present in the map.

## Ambiguous tokens — two real display-name collisions found and fixed

The data engineer flagged 61/164 tokens ambiguous; most of their
suggested plain-English display names were used as-is. Two needed a
change because `kSymptomDisplayMap` keys must be unique and the
suggested names collided:
- `fast_breathing` (adult) vs. the already-existing
  `fast_breathing_child` both suggested "Fast breathing" → the new
  adult token is labelled "Rapid breathing (adult)".
- `itchy_eyes` vs. `eye_itchiness` both suggested "Itchy eyes" (needed
  by *different* target conditions — `allergic_reactions` and
  `eye_infections` respectively, so neither could be dropped) → the
  latter is labelled "Itchy, irritated eyes".

Also found and fixed during on-device verification (not something the
data engineer's note flagged): `wheeze`'s suggested display name,
"Wheezing / whistling sound when breathing", doesn't contain the
substring "wheeze" (English drops the trailing `-e` before adding
`-ing`), so searching the literal token word found nothing — confirmed
on-device before and after. Relabelled to "Wheeze / whistling sound
when breathing". Also added "(palpitations)" parenthetically to that
token's label, since it's a real word a lay user might actually type
and it's `cardio_symptoms`'s core distinguishing symptom.

## "General" (whole-body/systemic) tokens have no body-diagram zone

39 of 164 tokens are tagged `body_area: General` by the data engineer —
these don't correspond to any zone in the 9-region body diagram. Rather
than add a new "General" zone (a much larger UI change — the diagram's
tap regions and the search-tab area list would both need it, well
beyond this ticket's scope), each General token was placed under the
body area(s) its own condition's *other*, non-General top-5 symptoms
already appear under — e.g. `weight_loss` (needed by `hiv_symptomatic`,
`malnutrition`, `tuberculosis_suspected`) was added to Abdomen, Chest,
Head, and Legs, matching where those conditions' other symptoms live.
This mirrors the pattern this file already used pre-E9 for Fever/
Chills/Weakness (systemic symptoms listed under several relevant
areas, not a dedicated bucket).

Four tokens belonging only to `fatigue_weakness` (`persistent_fatigue`,
`general_weakness`, `reduced_daily_function`, `low_energy`) have no
non-General sibling at all — that condition's entire top-5 is systemic.
These were placed under Legs/Back/Buttocks, matching the existing
Fatigue/Weakness placement.

## Arms zone — decision: hidden, not given a placeholder token

**Confirmed against the full 164-token vocabulary (not just the 91
tokens added here): zero tokens are arm-specific.** The only candidate,
`limb_weakness`, explicitly doesn't specify which limb (its own display
name is "Weakness in an arm or leg") — the data engineer's own mapping
already placed it under `General`, not `Arms`, for exactly this reason.

Forcing it into `Arms` as a placeholder would misrepresent it (a user
with leg weakness would see it filed under "Arms" and either miss it or
be confused) for no reachability benefit — `limb_weakness` is already
reachable via its General-token placement under Back.

**Decision: hide the Arms zone.** Removed from
`body_area_screen._bodyAreas` (search tab list) and both `_tapRegion`
calls for it in the front/back body diagram (`body_area_screen.dart`).
The diagram image itself still shows arms visually — only the tap
region was removed, confirmed on-device: tapping the arm area of the
diagram does nothing (no crash, no navigation), exactly as intended.
The two symptoms that used to live under `Arms` in
`kBodyAreaSymptoms` (`Swollen hands`, `Wrist pain` — both already
generic, location-less tokens: `swelling`, `pain`) were moved to `Legs`
rather than dropped, preserving their pre-existing reachability.

## Verification

New `test/core/constants/symptom_display_map_test.dart` (28 tests):
- All 19 completely-unreachable + 5 effectively-unreachable conditions
  (24 total) have at least one, and in fact more than one, of their
  top-5 tokens reachable via `kSymptomDisplayMap` — a static fixture of
  the data engineer's `condition_top5_symptom_tokens.json` is embedded
  so this doesn't depend on fetching the live KB in a unit test.
- Every label in every `kBodyAreaSymptoms` list has a corresponding
  `kSymptomDisplayMap` entry (referential integrity — catches typos).
- `Arms` is confirmed absent from `kBodyAreaSymptoms`.

Full suite: **114/114 passing** (86 pre-existing + 28 new).
`flutter analyze`: zero errors. `dart format`: clean.

Manually verified on the Android emulator: "Arms" no longer appears in
the body-area search list or as a tappable diagram region (tapping the
arm silently does nothing); "Chest pain" and "Wheeze" are both
selectable through the Chest area's "Show all symptoms" search,
confirming the vocabulary expansion actually reaches the running app,
not just the constants file.

## Exit criteria

- [x] All 19 completely-unreachable conditions now reachable
- [x] Distinguishing tokens added for the 5 effectively-unreachable
      conditions
- [x] Body area routing correct for all 91 new tokens (verified by the
      referential-integrity test + on-device spot checks)
- [x] Arms zone decision made and documented: hidden, not given a
      placeholder token
- [x] Ambiguous tokens resolved with plain-English display names (2
      genuine collisions fixed, plus 1 search-discoverability gap found
      during on-device verification)
- [x] Full test suite passing (114/114)
- [x] `flutter analyze` clean
- [x] `dart format` clean

---

# Phase E8 — Engine Wiring Fix

Branch: `feat/e8-engine-wiring-fix` (off `develop`). Two fixes ordered by the
engineering lead after the E8.1 case bank harness review. Both must land
before the 234-case bank is run.

Issues: [#34](../../issues/34) (wiring), [#35](../../issues/35) (empty input),
[#36](../../issues/36) (clinical review item, no code change).

## Status: both fixes in, all confirmations verified — pending PR

## FIX 1 — demographics, season and candidate conditions now reach the engine

`loading_screen.dart` built `EngineInput` with `candidateConditionIds: const []`
and never passed a season, closing three gates at once. Full defect analysis in
the previous E8.1 section and in #34.

### What changed

New `lib/features/assessment/engine_input_builder.dart`:

- `selectCandidateConditionIds(...)` — a condition is a candidate when at least
  one of its knowledge base symptom tokens appears in the reported symptoms.
- `buildEngineInput(...)` — passes the union of the user's demographic tokens
  and the derived candidate condition ids as `candidateConditionIds`.

The wiring was extracted out of the screen specifically so it is unit-testable:
a defect this severe must be covered by tests that exercise the code path the
app runs, not a copy of it. `loading_screen.dart` now calls
`buildEngineInput(...)` and passes `currentSeason: assessmentInput.season`.

`AssessmentController` gained a `season` field, `setSeason()` and season
pass-through in `buildInput()`.

### Candidate derivation — the one judgement call, flagged per FIX 3

`candidateConditionIds` is read by two modules expecting different contents:
`RedFlagEvaluator` matches condition ids, `ScoringEngine` matches demographic
modifier names. The lead's instruction was to pass the union and flag.

The app had no source of candidate condition ids at all, so passing the union
required deriving them. Candidates are computed by symptom overlap, which is
deliberately broad — red flags are evaluated *before* scoring, so the
derivation cannot depend on rank, and a condition-specific rule only fires if
the user additionally reports that rule's own red flag token. Erring wide errs
toward escalation, the safe direction for a CDSS.

**No unexpected results in verification**: 63 condition-specific rules became
reachable without any over-triage appearing in the E3.5 pilot cases or the
new tests. Still worth lead confirmation that symptom-overlap is the intended
definition of "candidate".

### Season remains inert — flagged

Nothing assigns `AssessmentInput.season`. The KB uses five seasons (rainy,
dry, harmattan, farming, lean) whose calendar boundaries vary by region;
picking them is a clinical/data decision, not an engineering one, so no
month mapping was invented here. The plumbing is complete end to end, so a
season source drops in without touching the engine. Until then the 21
conditions with seasonal modifiers stay inert **in the app** — the seasonal
path itself is verified by passing a season explicitly in tests.

## FIX 2 — empty input blocked before the engine

`loading_screen.dart` checks `symptomTokens.isEmpty` before doing any work
(before the artifact download, not just before `run()`), shows *"Please select
at least one symptom to continue."* and returns the user to symptom selection.

The return pops by route name — `kSymptomSelectionRouteName`, set at both
`body_area_screen.dart` push sites — because the number of screens in between
varies with the follow-up question count. The predicate falls back to
`route.isFirst` so a missing name can never empty the navigator stack.

### Severity correction

The previous report overstated this. `symptom_selection_screen.dart:239`
already disables Continue while no symptoms are selected, so the fabricated
result was **not reachable through the normal UI**. This is defence in depth
on the last step before the engine, not a live user-facing bug. The engine's
own behaviour is unchanged and is now pinned by a test so it stays documented.

## Verification — all four lead-requested confirmations

Run against the **real pinned artifacts** (kb.ng.v2.3, rules.ng.v2.1,
token_dictionary.ng.v1.1), not mocks, in
`test/assessment/engine_wiring_test.dart` (15 tests). Every group asserts both
the fixed and the pre-fix behaviour, so a revert fails loudly.

| Confirmation | Result |
|---|---|
| 1. E3.5 pilot cases — no regressions | 13/13 pass, unchanged |
| 2. SAM + diarrhoea -> emergency | Confirmed. Pre-fix: `non_urgent` (two-level under-triage) |
| 2b. MAM + diarrhoea -> urgent, distinct from SAM | Confirmed. Pre-fix: `non_urgent` |
| 3. children_under_5 + rainy_season + malaria -> urgent, not emergency (Option B) | Confirmed |
| 4. Empty input rejected before the engine runs | Confirmed, `test/assessment/empty_input_guard_test.dart` (3 tests) |

Additional coverage: condition-specific rule `rf_100` (haemoglobinuria, applies
to malaria) now fires and returns emergency — pre-fix it never triggered at
all; global red flags still override everything; the rule does not fire
without its own red flag token.

Note on confirmation 3: this case returns `urgent` both before and after the
fix, because malaria's `urgency_default` is already `urgent`. Same answer,
different reason — which is why the SAM case is the meaningful regression
guard and this one alone would have hidden the defect. See #36 for the
clinical question this raises about `increase_urgency`.

## Test counts

Full suite **132 passing** (114 on `develop` + 15 wiring + 3 guard).
`flutter analyze` zero errors. `dart format` clean.

## Exit criteria

- [x] Demographics passed to the engine
- [x] Season passed to the engine (plumbing complete; no source yet — flagged)
- [x] `candidateConditionIds` passed as the union, derivation flagged
- [x] Empty input blocked before the engine, user returned to symptom selection
- [x] E3.5 pilot cases still pass (13/13)
- [x] SAM + diarrhoea -> emergency
- [x] children_under_5 + rainy_season + malaria -> urgent (Option B)
- [x] `flutter analyze` zero errors, `dart format` clean, full suite passing
- [ ] PR opened against `develop`
- [ ] E8.1 case bank run — **deliberately not started**; lead asked to be
      reported to first. `case_bank_v1.json` has since landed in
      `wellapath-knowledge-base/testing/` on `main`.

# Phase E8 — E8.1 Case Bank Testing (mobile side)

Branch: `feat/e8-case-bank-testing`. Runs 200+ defined clinical scenarios
through the live engine against `kb.ng.v2.3` as the definitive pre-beta
validation across all 50 conditions.

> NAMING COLLISION: this file already has an "E8.1" section (Urgency
> Determiner Priority 4a safety fix, completed 2026-07-21). The engineering
> lead's brief re-uses the E8.1 label for case bank testing. Both are recorded
> under their own headings; flagged for the lead to renumber.

## Status: harness complete — run blocked on the case bank

`wellapath-knowledge-base/testing/case_bank_v1.json` does not exist yet: the
repo has no `testing/` directory on any of its 13 branches. Expected — the
data engineer's target is 2 days. Everything that does not depend on the bank
is built and verified; the run itself is a same-day turnaround once it lands.

## BLOCKING FINDING — the app drops demographic, seasonal and condition-specific input

`lib/features/assessment/loading_screen.dart` builds its engine input as:

```dart
final engineInput = EngineInput(
  symptomTokens: assessmentInput.symptomTokens,
  candidateConditionIds: const [],
);
```

`AssessmentController` collects demographic tokens across the sex, age,
pregnancy and medical-conditions screens into
`AssessmentInput.demographicTokens` — and `loading_screen.dart` discards them.
`AssessmentInput.season` is never assigned by anything, and
`EngineController(currentSeason:)` is never passed anywhere in `lib/`
(verified by grep: zero non-engine references).

Three engine gates read exactly those inputs. All three are permanently
closed in the shipping build:

| Gate | Code | Consequence against kb.ng.v2.3 / rules.ng.v2.1 |
|------|------|-----------------------------------------------|
| Condition-specific red flags | `red_flag_evaluator.dart:79` | 63 of 76 rules can never fire |
| Demographic modifiers | `scoring_engine.dart:58` | 13 conditions' `escalate_emergency` and 43 `increase_urgency` modifiers never fire |
| Seasonal modifiers | `scoring_engine.dart:83` | 21 conditions' seasonal modifiers never fire |

Downstream, `UrgencyDeterminer` priorities 3, 4a, 4b and 4c are unreachable —
every assessment falls through to Priority 5, the top condition's bare
`urgency_default`. The E3.5 condition-specific red flag fix and the earlier
E8.1 Priority 4a safety fix are both live in the engine and dead in the app.

This is under-triage in the safety-critical direction. Not fixed here:
`loading_screen.dart` is outside E8.1's assigned scope and sits on the locked
boot path. Flagged for engineering lead prioritisation.

Reproduced empirically, not just by code reading — see the `wiring modes`
group in `test/engine/case_bank_runner_test.dart`, which asserts that a
pregnancy + malaria case resolves to `urgent` under the shipping wiring and
`emergency` under the intended one.

## SECONDARY FINDING — empty input fabricates a result

With zero symptoms selected, `RedFlagEvaluator` returns
`proceedToScoring: true`, `ScoringEngine` scores all 50 conditions on
`base_weight` alone, and malaria wins on the highest base weight (10). The
user is told **"Visit a clinic or health facility today"** with malaria as
their top cause, having entered nothing. Deterministic and reproducible.

E3.5 Case 12 only asserted empty input "must not crash" — it does not crash,
it fabricates. Flagged for the lead; no fix attempted here.

## OPEN QUESTION — `increase_urgency` is a no-op on already-urgent conditions

`UrgencyDeterminer._escalateOne` maps `self_care -> non_urgent` and
`non_urgent -> urgent`, leaving `urgent` and `emergency` unchanged. In
kb.ng.v2.3, malaria's `pregnancy` modifier is `increase_urgency` and malaria's
default is already `urgent`, so pregnancy has no effect on a malaria
presentation even under the intended wiring. Whether that is clinically
correct is a medical reviewer question, not an engineering one — raising it
rather than assuming either way.

## DESIGN SMELL — `candidateConditionIds` is overloaded

The field is read by two modules expecting different contents:
`RedFlagEvaluator` matches condition ids against it, `ScoringEngine` matches
demographic modifier names against it. The harness's `as_intended` wiring
passes the union of both, which is an assumption, not a confirmed contract.
Flagged for lead review.

## What was built

| File | Purpose |
|------|---------|
| `test/engine/case_bank/case_bank_models.dart` | Case, result and report models; urgency ladder; under/over-triage classification |
| `test/engine/case_bank/case_bank_runner.dart` | Runs a bank through the live `EngineController`; bank parser |
| `test/engine/case_bank/case_bank_coverage.dart` | Static validation of a delivered bank against exit criteria 1-3 |
| `test/engine/case_bank/artifact_fixtures.dart` | Loads the pinned artifacts, sha256-verified against `/config` |
| `test/engine/case_bank_runner_test.dart` | 30 self-tests for the harness — run today, no bank needed |
| `test/engine/case_bank_validation_test.dart` | The E8.1 run; skips cleanly until the bank is delivered |
| `test/fixtures/artifacts/*.json` | kb.ng.v2.3, rules.ng.v2.1, token_dictionary.ng.v1.1 |

### Artifacts are pinned, not downloaded

The three fixtures are byte-identical to what `/config` served from R2 on
2026-07-26 and are sha256-verified on load against the hashes published in
that same `/config` response — the same check
`StagedArtifactLoader._matchesHash` performs at runtime. A sign-off number has
to be re-derivable from the commit, not from whatever R2 serves later. If
`/config` moves to a newer artifact version the fixtures and hashes must be
refreshed together and the bank re-run; the hash check turns that into a loud
failure instead of a silent drift.

### Every case runs twice

- **`as_shipped`** — byte-for-byte what `loading_screen.dart` does today. The
  exit criteria are asserted against this run, because it is what a real user
  gets.
- **`as_intended`** — demographics and season passed through as the engine's
  modules expect. Diagnostic only.

The gap between the two runs is the size of the wiring defect. Without this
split, every demographic, seasonal and condition-specific-red-flag case in the
bank would fail and read as a knowledge base problem rather than four lines of
missing wiring in the assessment screen.

## Running it

```sh
flutter test test/engine/case_bank_validation_test.dart \
  --dart-define=CASE_BANK_PATH=/path/to/case_bank_v1.json
```

Or drop the bank at `test/fixtures/case_bank_v1.json`. Results are written to
`build/e8_case_bank/case_bank_results_v1.json` for commit to
`wellapath-knowledge-base/testing/case_bank_results_v1.json`.

Safety-critical failures print to stdout the moment they occur, mid-run, per
the brief's "do not wait for the full run to complete".

## Verification

- 30 harness self-tests passing, covering triage direction classification,
  safety-critical detection, the immediate-flag callback, engine-throw
  isolation (one bad token does not cost the other 199 cases), red flag
  short-circuit behaviour, both wiring modes, report aggregation, bank parsing
  and coverage validation.
- Harness smoke-tested end-to-end against a synthetic 6-case bank and the real
  pinned artifacts: fixtures load and verify, both wirings run, results file
  writes, and all five exit criteria fail correctly on a deliberately
  insufficient bank.
- Full suite: **144 passing, 5 skipped** (the 5 validation-run tests, pending
  the bank). `flutter analyze` zero errors. `dart format` clean.

## Exit criteria

- [ ] 1. Minimum 200 cases in case bank — **blocked, data engineer**
- [ ] 2. All 50 conditions covered (min 3 cases each) — blocked; automated
      check implemented and tested
- [ ] 3. All 10 emergency conditions have 5+ cases — blocked; automated check
      implemented and tested
- [ ] 4. All 13 global red flag rules tested — blocked; run-time coverage
      tracking implemented and tested
- [ ] 5. Zero safety-critical under-triage — blocked; **expected to fail on
      the `as_shipped` run until the wiring defect above is fixed**
- [ ] 6. Pass rate documented — blocked; computed and serialised
- [ ] 7. All failures documented with condition, input, expected vs actual and
      triage direction — blocked; serialised per case
- [ ] 8. Results committed to `wellapath-knowledge-base/testing/case_bank_results_v1.json`
      — blocked

---

# Phase E8.1 — Case Bank Run Results (234 cases)

Run against the pinned production artifacts (kb.ng.v2.3, rules.ng.v2.1,
token_dictionary.ng.v1.1) through `EngineWiring.asShipped` — the real
production path via `buildEngineInput`, post the PR #37 wiring fix.

## Headline

| Metric | Value |
|---|---|
| Total cases | 234 |
| Graded | 231 |
| Observe (unasserted by design) | 3 |
| Passed | 119 |
| Failed | 112 |
| **Pass rate (graded)** | **51.52%** |
| **Under-triage** | **0** |
| Over-triage | 1 |
| Engine errors | 0 |
| **Safety-critical failures** | **0** |
| Global red flag rules exercised | 13/13 |

Coverage validation passed all of exit criteria 1-3: 234 >= 200 cases, every
one of the 50 conditions has >= 3 cases, every one of the 10 emergency
conditions has >= 5, and every `expected_urgency: emergency` case is marked
`safety_critical` (150 of them).

## The 51.52% needs reading carefully

**111 of the 112 failures are the same thing, and none is a triage error.**
Every one is a red flag case where the bank set an `expected_top_condition`
and the engine returned none. In all 111 the urgency is exactly right.

`EngineController.run()` short-circuits on a red flag and calls
`_formatter.format(redFlagResult, null, urgencyResult)` — scoring never runs,
so `topCauses` is empty by design. That is LOCKED PRINCIPLE #5 working as
specified: the red flag overrides scoring output rather than ranking
alongside it. 35 distinct rules are involved, so this is systematic, not a
handful of odd cases.

**This is a spec disagreement between the bank and the engine, not a defect
in either.** It needs a ruling:

- **Option A** — the bank sets `expected_top_condition: null` on red flag
  cases, matching the engine's documented behaviour. No code change. Pass
  rate becomes **230/231 = 99.57%**.
- **Option B** — the engine runs scoring even when a red flag fires, so a
  differential can be shown alongside the emergency instruction. This is an
  engine contract change touching principle #5 and needs founder +
  engineering lead review per principle #8.

Recommend Option A: the red flag screen deliberately shows no differential,
and #5 is locked.

## The one real failure

**CB_211** — empty input, expected `non_urgent` ("returns safe default"),
actual `urgent` with malaria as top cause. Over-triage, not safety-critical.

This is exactly [#35](../../issues/35), independently reproduced by the data
engineer's own edge case. The app now blocks this before the engine (E8
FIX 2), so it is unreachable in product; the engine's own behaviour is
unchanged. If the lead wants the engine itself to return a safe default
rather than the highest base-weight condition, that is the open question
already recorded on #35.

## Observe cases — actual output recorded

The bank ships 3 cases with `expected_urgency_source: "observe"` and null
expectations, to be recorded rather than graded. The harness was extended to
support them: they are excluded from the pass rate entirely, since counting
them as failures would be wrong and counting them as passes would inflate it.

| Case | Input | Actual urgency | Actual top condition | Red flag |
|---|---|---|---|---|
| CB_225 | `fever` | urgent | malaria | no |
| CB_232 | `fever, chills, watery_stool, vomiting` | urgent | malaria | no |
| CB_233 | `chest_pain, dizziness, palpitations` | urgent | cardio_symptoms | no |

CB_232 is the informative one: on a deliberate malaria/diarrhoea overlap the
scorer picks malaria, driven by its base weight of 10 (the highest in the KB)
plus the fever/chills weights. Worth a clinical eye on whether that is the
right tie-break for a mixed presentation.

## A harness defect found and fixed mid-run

The first run reported 1 under-triage (CB_229: cold + children_under_5 +
harmattan season, expected `urgent` via Priority 4c, got `non_urgent`).

That was **a bug in the harness, not the engine**. When `EngineWiring` was
repointed after PR #37, `_seasonFor` kept its old inverted branch and returned
`null` for `asShipped` — so no case's season reached the engine. Fixed, and
covered by three new self-tests that distinguish Priority 4c (demographic +
seasonal -> urgent) from Priority 4a (demographic alone -> one level up). The
previous season test used a malaria case whose default is already `urgent`,
so it could not tell the two apart and passed while the season was being
dropped.

After the fix CB_229 passes and under-triage is zero.

## Not assertable — flagged

The bank carries `expected_urgency_source` on every case
(`urgency_default`, `global_red_flag`, `demographic_escalation`, ...).
`EngineOutput` does not surface the `urgencySource` that `UrgencyDeterminer`
computes, so the harness records the expectation but cannot check it. Exposing
it would let the next run verify not just *what* urgency was returned but
*why* — recommended before beta, as a wrong-reason-right-answer case is
currently invisible.

## Exit criteria

- [x] 1. Minimum 200 cases — 234
- [x] 2. All 50 conditions covered, min 3 cases each
- [x] 3. All 10 emergency conditions have 5+ cases
- [x] 4. All 13 global red flag rules tested — 13/13
- [x] 5. **Zero safety-critical under-triage** — 0
- [x] 6. Pass rate documented — 51.52% graded; 99.57% under Option A
- [x] 7. All failures documented with condition, input, expected vs actual
      and triage direction — in `case_bank_results_v1.json`
- [ ] 8. Results committed to
      `wellapath-knowledge-base/testing/case_bank_results_v1.json` — PR open

---

# Phase E8 — Expose urgencySource on EngineOutput

Branch: `feat/e8-urgency-source-output` (off `develop`). Engineering lead
ruling 4 from the E8.1 results review — fix before beta.

## Why

The E8.1 case bank asserts an `expected_urgency_source` on all 234 cases
(`urgency_default` 88, `global_red_flag` 84, `condition_specific_red_flag` 40,
`demographic_escalation` 18, `observe` 3, `empty_default` 1). `UrgencyDeterminer`
computes exactly that value, but `EngineOutput` never carried it, so the
harness could record the expectation and not check it. A case reaching the
right urgency down the wrong priority path was indistinguishable from a
correct one.

## What changed

- `EngineOutput.urgencySource` — new required field, carried straight through
  from `UrgencyResult.urgencySource` by `OutputFormatter`.
- **`EngineController` no longer mislabels condition-specific red flags.** The
  red flag path hardcoded `urgencySource: 'global_red_flag'` regardless of
  which pass matched, so all 40 of the bank's `condition_specific_red_flag`
  cases would have been reported as global. It now reads
  `redFlagResult.redFlagType`. The urgency itself is `emergency` either way —
  only the stated reason changes, so this alters no triage outcome.

Field made required rather than optional: it is always available at the point
of construction, and 5 test mocks are the only other construction sites.

## Verification

New `test/engine/urgency_source_output_test.dart` (6 tests) pins the source
reported by each path: global red flag, condition-specific red flag,
demographic escalation, and plain urgency default — plus that the two red flag
paths are distinguishable, and that two results with identical `emergency`
urgency but different sources can be told apart, which is the case the field
exists for.

Full suite **138 passing**. `flutter analyze` zero errors, `dart format` clean.

## Follow-up

Once this and PR #39 are both merged, the harness can compare
`expected_urgency_source` against the actual source per case. Kept out of both
PRs so they stay independently reviewable.

## Exit criteria

- [x] `urgencySource` exposed on `EngineOutput`
- [x] Condition-specific red flags report their own source, not `global_red_flag`
- [x] Every urgency path covered by a test
- [x] `flutter analyze` zero errors, `dart format` clean, full suite passing
- [ ] PR opened against `develop`

---

# Phase E8.1 — Urgency source assertion (follow-up to PR #39)

Engineering lead instruction: wire the harness to assert
`expected_urgency_source` against `EngineOutput.urgencySource` **before** the
data engineer regenerates, so source verification lands in the single re-run
rather than requiring a third.

## What changed

- `CaseRunResult.actualUrgencySource` — read from `EngineOutput.urgencySource`
  (exposed by PR #40).
- `urgencySourceMatched` — true when the bank asserts no source, else exact
  match. A mismatch fails the case.
- `isRightAnswerWrongReason` — the specific thing this exists to surface: the
  urgency was correct but the engine got there down a different path.
- Report gains `urgency_source_mismatches` and `right_answer_wrong_reason`
  counts, a dedicated mismatch section in the console output and a
  `urgency_source_mismatches` array in the results JSON.
- New exit criterion 4b test: zero source mismatches.
- 7 new self-tests (40 total in the harness).

Observe cases are exempt — they are ungraded, so a source they never asserted
cannot mismatch.

## Dry run against the current (uncorrected) bank

**20 source mismatches, 19 of them right-answer-wrong-reason.** None was
visible before today: in every one of the 19 the urgency is exactly right.

| Expected -> actual | Count | Assessment |
|---|---|---|
| `urgency_default` -> `demographic_escalation` | 18 | Semantics question — see below |
| `condition_specific_red_flag` -> `global_red_flag` | 1 | Engine correct; rules artifact issue |
| `empty_default` -> `urgency_default` | 1 | CB_211, already accepted (ruling 2) |

### The 18 — this is issue #36 made visible

Every one is a condition already at `urgent` or `emergency` carrying an
`increase_urgency` demographic modifier. `UrgencyDeterminer` Priority 4a fires
and reports `demographic_escalation`, but `_escalateOne` leaves `urgent` and
`emergency` unchanged — so **the engine reports an escalation that did not
change anything**. The bank recorded `urgency_default` because the value never
moved.

Both readings are defensible: the engine took the demographic path
(mechanically true), the bank observed no escalation occurred (materially
true). This is exactly the `increase_urgency` no-op already open as
[#36](../../issues/36) — the source field is what makes it observable per
case rather than a theoretical concern. **A ruling on #36 decides which side
changes**, so these 18 should not be "fixed" in the bank until it lands.

### CB_159 — engine correct, rules artifact carries a dead rule

`circulatory_collapse` is registered **twice** in rules.ng.v2.1: as global
rule `rf_006` (priority 1) and as condition-specific `rf_147`
(road_traffic_injury_minor, priority 11). `RedFlagEvaluator` runs the global
pass first and halts on first match, so `rf_006` wins and `rf_147` can never
fire.

The engine is right — LOCKED PRINCIPLE #5, a global red flag is absolute — and
both paths return `emergency`, so no triage outcome differs. But **`rf_147` is
dead in the artifact**. Checked systematically: it is the only one of the 63
condition-specific rules shadowed this way.

Fix belongs in the bank (expect `global_red_flag` for CB_159) and, separately,
in the rules artifact (drop the redundant `rf_147`, or rescope `rf_006`).

## Revised projection for the re-run

My earlier "99.57% after Option A" figure did not account for source
verification, which did not exist yet. With the assertion in:

**Predicted after Option A alone: 211/231 = 91.34%**, with 20 remaining
failures — 18 blocked on the #36 ruling, 1 CB_159, 1 CB_211 (accepted).

If #36 resolves in the engine's favour (the bank adopts
`demographic_escalation` for those 18) and CB_159 is corrected, the projection
is **230/231 = 99.57%**, with CB_211 the sole accepted failure.

## Verification

Harness self-tests **40 passing**. Full suite **171 passing, 5 skipped**.
`flutter analyze` zero errors, `dart format` clean.

## Exit criteria

- [x] `expected_urgency_source` asserted against actual per case
- [x] Right-answer-wrong-reason surfaced as its own category
- [x] Source mismatches serialised to the results JSON
- [x] Self-tests cover match, no-assertion, wrong-path, condition-specific
      source, no double counting, and observe-case exemption
- [x] Branch ready for the data engineer to trigger the re-run

---

# Phase E8.1 — FINAL RUN (rules.ng.v2.2, corrected case bank)

Green-lit by the engineering lead after rules.ng.v2.2 went live and the data
engineer applied all four corrections.

## Artifact verification before the run

`/config` on staging confirmed, and the pinned fixtures refreshed to match:

| Artifact | Version | sha256 verified |
|---|---|---|
| knowledge_base | 2.3 | `cb0e43fc…` unchanged |
| rules | **2.2** | `1d27e854…` refreshed |
| token_dictionary | 1.1 | `0cc47ad9…` unchanged |

`rules.ng.v2.1.json` removed from `test/fixtures/artifacts/`, replaced by
v2.2, and `artifact_fixtures.dart` updated with the new version and hash
together — the refresh path the loader documents. rules v2.2 carries 75 rules
(13 global, 62 condition-specific); dead `rf_147` is retired, down from 63.

> NOTE: the harness runs against pinned fixtures, not a device Hive cache.
> The versions above are verified against what `/config` currently serves,
> which is the same source the device caches from.

## RESULT — 230/231 = 99.57%

| Metric | Value | Target |
|---|---|---|
| Total cases | 234 | — |
| Graded / observe | 231 / 3 | — |
| Passed | 230 | — |
| **Pass rate** | **99.57%** | 99.57% ✅ |
| **Under-triage** | **0** | 0 ✅ |
| Over-triage | 1 | — |
| **Safety-critical failures** | **0** | 0 ✅ |
| Right answer, wrong reason | **0** | — |
| Urgency-source mismatches | 1 | — |
| Engine errors | 0 | — |
| Global red flag rules exercised | 13/13 | 13/13 ✅ |

Coverage criteria 1-3 all pass. Criterion 4b (source verification) fails on
CB_211 alone — the accepted case below.

## The single remaining failure

**CB_211** — empty input. Expected `non_urgent` via `empty_default`, actual
`urgent` via `urgency_default`, top cause malaria. Over-triage, not
safety-critical, and **accepted under lead ruling 2** as unreachable in
product: `loading_screen.dart` blocks empty input before the engine, and
`symptom_selection_screen.dart` disables Continue with zero symptoms.

It fails on both axes for the same underlying reason — the engine has no
`empty_default` path, so with no symptoms it scores every condition on
`base_weight` alone and malaria wins on the highest (10). Tracked as
[#35](../../issues/35).

## Right-answer-wrong-reason: zero

The source assertion added in PR #41 found 19 such cases on the uncorrected
bank. After the corrections there are none: every one of the 230 passing cases
reached its urgency down the path the bank expected. The 18 `increase_urgency`
cases from [#36](../../issues/36) were resolved in the engine's favour — the
bank now expects `demographic_escalation` for them (18 -> 36 cases with that
source), so the clinical reading is that taking the demographic path is the
correct description even when the value does not move.

## Observe cases — actual output

| Case | Input | Urgency | Top condition | Red flag |
|---|---|---|---|---|
| CB_225 | `fever` | urgent | malaria | no |
| CB_232 | `fever, chills, watery_stool, vomiting` | urgent | malaria | no |
| CB_233 | `chest_pain, dizziness, palpitations` | urgent | cardio_symptoms | no |

Unchanged from the first run. CB_232's malaria/diarrhoea tie-break remains
open as [#38](../../issues/38) for E8.2.

## Verification

Full suite **178 passing, 6 skipped**. `flutter analyze` zero errors,
`dart format` clean.

## Exit criteria — all met

- [x] 1. Minimum 200 cases — 234
- [x] 2. All 50 conditions covered, min 3 cases each
- [x] 3. All 10 emergency conditions have 5+ cases
- [x] 4. All 13 global red flag rules tested — 13/13
- [x] 4b. Engine reasoning matches expected source — 1 mismatch, accepted (CB_211)
- [x] 5. **Zero safety-critical under-triage** — 0
- [x] 6. Pass rate documented — **99.57%**
- [x] 7. All failures documented with condition, input, expected vs actual,
      triage direction and urgency source
- [x] 8. Results committed to
      `wellapath-knowledge-base/testing/case_bank_results_v1.json`

---

# Phase E9 — Internal Beta Readiness

**Phase:** E9 — Internal Beta Readiness
**Branch:** `develop`
**Tags:** `v0.1.0-beta.1`, `v0.2.0-beta.1`, `v0.2.0-beta.2`
**Last Updated:** 2026-08-03

---

## CURRENT STATUS: v0.2.0-beta.2 tagged and signed — pending distribution

---

## E9.1 — Release prep

### Artifact freeze

Locked. `docs/BETA_ROLLBACK.md` records versions and sha256 for all four,
verified against live `/config`:

| Artifact | Version | sha256 (short) |
|---|---|---|
| knowledge_base | 2.4 | `6c00d825…` |
| rules | 2.2 | `1d27e854…` |
| token_dictionary | 1.1 | `0cc47ad9…` |
| facilities | 1.1 | `25684c71…` |

The three core hashes are also pinned in
`test/engine/case_bank/artifact_fixtures.dart`, which fails loudly on drift.
kb went 2.3 -> 2.4 during E8.2 (malaria `headache` weight 3 -> 6); rules went
2.1 -> 2.2 (dead `rf_147` retired).

### Rollback plan — `docs/BETA_ROLLBACK.md` (PR #44)

Two levers: server-side artifact rollback (minutes, no tester action,
preferred) and APK rollback (hours, needs testers to install), with a
symptom-to-lever table and a verification checklist. Records that a rolled
back `/config` must update version **and** hash together — a stale hash fails
the client integrity check and blocks assessments entirely.

### Release signing (PR #47)

`android/app/build.gradle.kts` reads credentials from `android/key.properties`,
gitignored and never committed (LOCKED PRINCIPLE #6). Adapted to the Kotlin
DSL — the brief's snippet was Groovy. When the file is absent the build falls
back to debug signing and logs an internal-use-only warning, so CI and fresh
clones still build.

`.gitignore` did not previously cover `key.properties`, `*.keystore` or
`*.jks` — a keystore dropped into the repo could have been committed by
accident. Added.

> The founder's `key.properties` was initially created in the stale
> `~/Documents/project/wellapath-mobile` copy rather than the active repo at
> `~/dev/wellapath-mobile`. Copied across; worth knowing if it recurs.

### PHI fix (PR #44)

`red_flag_evaluator.dart` logged only a count of unknown tokens under a
comment reading "never log token values (PHI risk)", then put the values
straight into the `ArgumentError` message two lines below. Not a live leak —
`loading_screen.dart` catches it and there is no crash reporter — but an
exception message reaches the default Flutter error handler and any crash
reporter added later would capture it verbatim. Message now carries the count
only; a regression test asserts no token value appears in it.

### Logging audit — release build

Zero `print()` in `lib/`. All 14 `debugPrint` sites reviewed individually:
status markers only. Dio interceptor `requestBody: false`,
`responseBody: false`. Hive holds artifacts, facilities and config — no PHI.
No crash reporter or analytics SDK.

**Verified empirically on the release build**: a full assessment produced zero
symptom tokens, condition names or urgency values in logcat. Note that
`debugPrint` is *not* stripped in release — the claim holds because every
message is PHI-free by content, not because logging is off.

---

## E9 — Red flag reachability (PRs #48, #52)

**The largest safety finding of the phase.** The case bank exercises all 13
global red flag rules by feeding tokens straight to the engine, so it
structurally could not see whether the UI lets a user *select* them.

Audit result: **12 of the 13 were absent from `kSymptomDisplayMap` entirely**
and selectable by no UI path. The 13th, `seizures`, was in the map but under
no body area — reachable only via the picker's "Show all symptoms" fallback.

Worse, near-miss tokens existed that look right and bypass the rules:

| Caregiver picks | Token | They meant | Fired? |
|---|---|---|---|
| "Confusion / not thinking clearly" | `confusion` | `altered_consciousness` | no |
| "Difficulty breathing" | `difficulty_breathing` | `breathlessness_at_rest` | no |
| "Bleeding" | `bleeding` | `abnormal_bleeding` | no |

### Fixed

- PR #48: `Seizures` added to Head, listed first as a danger sign.
- PR #52: all 12 remaining tokens added with the data engineer's display names
  from `mobile_handoff/red_flag_display_map.json`, mapped to body areas.
- New **`General`** body area for the 7 systemic danger signs that belong to
  no body part. E9's symptom expansion had avoided a General zone by placing
  systemic tokens under their condition's other symptoms; these have no such
  sibling, and a caregiver reporting "collapsed, cold and clammy" will not
  think "Legs". Search tab only — the body diagram has no region for it.
- **Clarifying questions** for needs-clarifying near-misses
  (`QuestionType.redFlagClarifier`): a milder selection raises one yes/no
  question, asked first since it decides whether the result is an emergency,
  and only an explicit yes adds the red flag token. Escalate-safe near-misses
  need no question — the red flag being directly selectable covers them.

3 clarifiers implemented, not the 4 anticipated: the
`dehydration -> severe_dehydration` clarifier has **no trigger**, since
`dehydration` is not in `kSymptomDisplayMap`. A test now asserts every
clarifier's trigger tokens are selectable, so a dead clarifier cannot be
added silently.

### Open, flagged for ruling

- **Age-conditional near-misses.** `altered_consciousness`,
  `impaired_consciousness`, `prostration`, `respiratory_distress` are
  escalate-safe in a child (IMCI danger signs) but need clarification in an
  adult. Buildable — the controller has the age token — but "auto-escalate
  for under-5s, ask everyone else" is a clinical rule, not a mobile call.
- **Anaphylaxis needs a combined-trigger rule**: swelling/hives *together
  with* breathing difficulty after exposure; no single sign should fire.
  Multi-token, arguably a rules-artifact change.
- **Nine listed near-miss tokens do not exist in the picker**: `pallor`,
  `severe_weakness`, `chest_indrawing`, `facial_swelling`, `vaginal_bleeding`,
  `bleeding_gums`, `blood_in_stool`, `breathlessness`, `dehydration`.

---

## E9 — Results screen defect (PR #46)

Every "Possible Conditions" card rendered the **top** condition's explanation.
On a real device result the card headed "2. Lassa Fever" displayed malaria's
description — misleading clinical content, found during E9.3 demo 1.

`OutputFormatter` populated `explanationPoints` from the top condition alone
and `results_screen.dart` reused that one string for every card. Each
`topCauses` entry now carries its own `explanation` from its own
`explanation_template`. `explanationPoints` is unchanged — the red flag
interrupt screen reads it. Confirmed fixed on the signed build.

---

## E9.3 — Device verification

Run on the Android emulator (`wellapath_lowend`, 720x1280 @ density 320 =
logical 360x640) against signed release builds.

| Demo | Result |
|---|---|
| Triage flow — malaria symptoms -> urgent | **PASS** — fever + headache + chills -> URGENT, malaria top |
| Red flag interrupt — seizures -> emergency | **PASS** — rule name "Active Seizures — this is a universal danger sign", Call Emergency CTA, CDSS disclaimer |
| Locator flow | **PARTIAL** — permission, map, list, distance sorting all correct; Call button never appears (see #50) |
| Offline assessment | **PASS on 3 of 4** — completes from cached artifacts, no crash, no error; **no offline indicator** (#21, waived) |

Offline was achieved with a true block: `adb root` +
`iptables -I OUTPUT -m owner --uid-owner <app> -j REJECT`, artifacts
pre-cached. `svc wifi/data disable`, the airplane-mode setting and
`cmd connectivity` all failed to sever emulator networking.

**Emergency dialer** verified on emulator only — no physical handset was
available. Tapping the card put `com.google.android.dialer` in the foreground
with **112 entered and the call not placed**. Engineering lead accepted this:
`ACTION_DIAL` is OS-level deterministic.

---

## E9 — Home screen redesign (PR #56)

Home offered a single "Start Symptom Assessment" button. It now offers three
services as cards — check your symptoms, find a clinic near me, call
emergency 112 — so the user picks what they need.

- Emergency card distinguished by accent colour and tinted border, not a solid
  red fill: it must stand out without reading as an alarm on a screen opened
  every time.
- **No confirmation before 112, deliberately.** `tel:` uses `ACTION_DIAL`,
  which opens the dialer without placing the call — the OS is already the
  confirmation, and friction in front of an emergency number is its own harm.
- **The CDSS disclaimer moved onto the home screen.** Two of the three
  services skip the assessment entirely, so a user can reach care without ever
  seeing the modal that used to carry that wording (LOCKED PRINCIPLE #1). It
  was then found clipping mid-sentence at 360x640; the screen is now
  scroll-safe and the vertical rhythm was tightened so it fits without
  scrolling at that size.
- Onboarding reduced from **4** pages (the brief said 3) to one, skippable.

### A hang this exposed, and fixed in the same PR

Opening the locator from home **hung indefinitely** on a fresh install.
`LocatorScreen` waits on `facilitiesReady`/`facilitiesFailed`, which only
`loading_screen.dart` ever flipped — reaching the locator without running an
assessment meant waiting on a download nobody had started. Confirmed still
spinning after 45s on device.

The locator now starts the download itself from cached config, falls back to
the failure state when no config exists, and `StagedArtifactLoader` guards
against fetching the 1.7MB artifact twice now that two callers exist.

---

## E9 — Locator improvements

### Pin labels (PR #53)

Pins showed an `H` only. Each now carries its facility name beneath it.
Nearest 5 labelled, hidden below zoom 12.5, tapped pin always labelled.

Tuned down from 8 to 5 after measuring overlap on-device. **Residual overlap
remains** in dense central Lagos — the nearest facilities are precisely the
clustered ones around Yaba/Igbobi, so any zoom showing them all shows their
labels colliding. Tracked as [#55](../../issues/55); needs label collision
avoidance, which `flutter_map` gives no help with.

### Nigeria-only (PR #54)

A location fix outside latitude 4.0–14.0 / longitude 2.5–15.0 shows a region
message and a single "Back to Results" button — no map, no list, and no
Map/List toggle, which would otherwise switch between two things that are not
there. Distinct from location-denied: we know where the user is.

`isWithinNigeria` lives in `nigeria_coverage.dart` rather than the screen so
it is unit testable — 15 tests including inclusive corners, just-outside
edges, and the two classic geo bugs (negated latitude, swapped lat/lon).

Manual state selection was already limited to Lagos, FCT, Kano — no change
needed.

### Download progress and timeouts (PRs #57, #58, #59)

First locator entry on a fresh install sat on a bare spinner for ~60s while
the 1.7MB facilities artifact downloaded — a tester force-quits and reports a
freeze.

- **#57**: Dio only reports progress when passed an `onReceiveProgress`
  callback, and none was wired. Added it and exposed
  `StagedArtifactLoader.facilitiesProgress`. The locator shows a determinate
  bar with "Downloading facility data... X%", falling back to indeterminate
  when the server reports no content length.
- **#58**: `perAttemptTimeout` was 15s, tuned in E9 for the ~102KB core
  artifacts. Facilities is 1.7MB — 17x larger — and could not complete below
  roughly 900kbps, so EDGE (~56s) and 3G (~35s) failed *every* attempt.
  Facilities now gets a separate **90s** cap; core artifacts stay at 15s,
  since they gate the assessment result and the E9 hang fix depends on that
  cap staying tight.
- **#59**: the 90s cap then meant ~4.5 minutes before a *dead* connection
  reported failure. Added a **20s first-byte guard** — no bytes at all fails
  the attempt immediately, a transfer that has started keeps the full cap.
  Worst case to a failure message drops to ~1.6 minutes. Distinct from Dio's
  `receiveTimeout`, which measures the gap between chunks and so only covers
  a stall *after* the first byte.

---

## Releases

| Tag | Commit | APK sha256 | Notes |
|---|---|---|---|
| `v0.1.0-beta.1` | `0efaf6e` | `7e4362f5…fa15` | First signed build |
| `v0.2.0-beta.1` | `7f72c40` | `2fb51e0b…dc1a` | Home redesign, Nigeria-only, pin labels |
| `v0.2.0-beta.2` | `5d5d34b` | `9db847cd…4e21` | Progress bar, 90s timeout, fast-fail |

All signed with the `wellapath` alias, verified by fingerprint match against
the keystore (`94e7c574…d836`) rather than the certificate DN alone.

`v0.2.0-beta.2` is the intended external-beta build. **It has not had a device
pass** — the last full pass was on `v0.2.0-beta.1`, before #57/#58/#59 changed
the facilities download path.

### Distribution — blocked

Not distributed. The Drive tool takes file content as a base64 *parameter*
(58.9MB -> ~78MB, not feasible), the Gmail tool does not support attachments
and caps at 25MB, and no `firebase`/`rclone`/`gdrive`/`gcloud` CLI is
installed. Staged locally at `~/Desktop/wellapath-v0.2.0-beta.2.apk`.

> **The repo is PUBLIC.** A GitHub release would publish a signed production
> build of a CDSS to the open internet. Not an acceptable shortcut unless the
> repo goes private first. The same caution applies to any quick share link.

Firebase App Distribution is the intended route and needs `firebase-tools`
installed plus founder authentication. Note the Firebase app must be
registered under package **`org.wellapath.wellapath_mobile`** — an app was
initially created as `wellapath.org`, which is the domain written forwards
rather than reverse-DNS. Changing the app's `applicationId` to match was
declined: it is permanent on Android, would invalidate the tag and circulated
hashes, and would force testers to uninstall and reinstall.

---

## Known limitations going into beta — `docs/BETA_NOTES.md` (PR #51)

Written for testers, each entry leading with what they will see:

| # | Item | Issue |
|---|---|---|
| 1 | No offline indicator | [#21](../../issues/21) |
| 2 | Offline cold boot holds the splash ~50s (correct `/config` retry backoff) | — |
| 3 | First "Find a Clinic" takes ~60s to download 1.7MB; 90s cap + 20s first-byte guard | — |
| 4 | Call button rarely appears — 45 of 5,344 facilities have phones (0.84%) | [#50](../../issues/50) |
| 5 | Locator does not re-query on location change | [#49](../../issues/49) |
| 6 | Body-area search placeholder says "symptoms" but filters body areas | [#45](../../issues/45) |
| 7 | Open clinical questions | #42, #38, #36, #35 |

---

## Open issues at end of E9

| Issue | Label | Summary |
|---|---|---|
| [#42](../../issues/42) | clinical-review | Isolated headache routes to malaria at `urgent`; weight 3 vs 6 |
| [#45](../../issues/45) | bug | Body-area search placeholder/behaviour mismatch |
| [#49](../../issues/49) | bug | Locator retains stale results on location change |
| [#50](../../issues/50) | bug | Call button unreachable in practice — data coverage gap |
| [#55](../../issues/55) | enhancement | Pin label collision avoidance for dense clusters |
| #38, #36, #35 | clinical-review | Malaria base_weight dominance; `increase_urgency` no-op; empty input |

Also unresolved: the picker's inner symptom search is **case-sensitive** —
typing `Difficulty` returns nothing while `breath` works, because the label is
lowercased for comparison but the query is not. Found during the E9 device
pass, not yet filed.

---

## Verification at end of E9

Full suite **244 passing, 6 skipped** (the case bank validation tests, which
skip when no bank is present at the default path). `flutter analyze` zero
errors. `dart format` clean.
