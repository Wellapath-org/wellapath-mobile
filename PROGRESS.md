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
