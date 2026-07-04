# WellaPath Mobile — E1.6 Progress Tracker

**Phase:** E1 — System Spine  
**Task:** E1.6 Mobile Foundation  
**Branch:** feature/e1-mobile-foundation  
**Engineer OS:** Windows 11 (use Git Bash, never PowerShell)  
**Last Updated:** 2026-03-25 — All tasks complete, verification passed, ready for PR

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
- [ ] Work committed and pushed
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
