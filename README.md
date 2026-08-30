# WellaPath Mobile

Offline-first Flutter application for WellaPath — a clinical decision support system (CDSS) that helps frontline health workers in Nigeria assess symptoms and triage patients safely, even without a network connection.

WellaPath is built around versioned clinical knowledge artifacts (a knowledge base, red-flag rules, and a symptom token dictionary maintained in [wellapath-knowledge-base](https://github.com/Wellapath-org/wellapath-knowledge-base)). This app runs the entire decision engine on the device: symptoms are captured through a guided assessment flow, scored locally against the knowledge base, and presented with an urgency level — no patient data needs to leave the phone for an assessment to complete.

## What's inside

- **On-device CDSS engine** (`lib/core/engine/`) — a four-stage pipeline orchestrated by `EngineController`:
  - `RedFlagEvaluator` checks input tokens against global and condition-specific red-flag rules; a global red flag short-circuits scoring entirely and returns an emergency result.
  - `ScoringEngine` scores candidate conditions by matching symptom tokens against per-condition weighted symptom lists, with base weights and seasonal context.
  - `UrgencyDeterminer` resolves the final urgency tier and records its source (red flag, demographic modifier, or condition default).
  - `OutputFormatter` shapes the result for the UI using artifact metadata.
- **Boot sequence with offline fallback** (`lib/features/boot/`) — on launch the app tries to fetch fresh configuration from the backend's `/config` endpoint, caches it in Hive on success, and falls back to the last known good cached config when offline. Only when neither is available does boot fail.
- **Guided assessment flow** (`lib/features/assessment/`) — stepwise screens for age, sex, pregnancy status, existing medical conditions, body area, and symptom selection, plus a `QuestionEngine` that drives condition-aware follow-up questions.
- **Results and safety UI** (`lib/features/results/`) — ranked condition cards, a symptom summary, and a dedicated red-flag interrupt screen that takes over when an emergency sign is detected.
- **Supporting screens** — splash, onboarding, home, and a system status screen.
- **Test suite** (`test/`) — unit tests for every engine stage (red-flag evaluation, scoring, urgency determination, output formatting), the follow-up question engine, results and red-flag-interrupt widgets, and a pilot case validation suite.
- **CI** (`.github/workflows/`) — Flutter analyze/build checks on pushes and pull requests, plus a manually dispatched internal-beta validation build with deliberately conservative secret handling (documented inline in the workflow).

## Tech stack

- **Flutter / Dart** (SDK `^3.11.3`), Material Design
- **Dio** — HTTP client with request logging
- **Hive** (`hive_flutter`) — local cache for offline-first config storage
- **flutter_dotenv** — environment-based configuration
- **flutter_svg** — SVG assets (front/back body maps for body-area selection)
- **url_launcher**, **shared_preferences**
- **flutter_lints** + `flutter analyze` in CI

## Architecture notes

- **Offline-first by design.** The network is treated as an enhancement, not a requirement: configuration is fetched when available and cached in Hive; assessments run entirely against local data through the on-device engine.
- **Engine and artifacts are decoupled.** The engine consumes the knowledge base, rules, and token dictionary as plain JSON structures, so clinical content can be versioned and updated independently of app code.
- **Safety rules override scoring.** Red-flag evaluation runs before scoring and cannot be outvoted by symptom weights — a triggered global red flag produces an emergency result immediately.

## Getting started

Prerequisites: Flutter SDK (stable channel) with Dart `^3.11.3`.

```bash
git clone https://github.com/Wellapath-org/wellapath-mobile.git
cd wellapath-mobile
flutter pub get

# Configure the environment (API base URL, artifact CDN, timeouts).
# A .env is bundled as a Flutter asset; see .env.example for the expected keys.

flutter run
```

Run the checks:

```bash
flutter analyze
flutter test
```

## Project structure

```
lib/
├── main.dart               # Entry point: dotenv + Hive init
├── app.dart                # Root widget
├── core/
│   ├── config/             # ConfigService (/config fetch)
│   ├── constants/          # Symptom display and follow-up question maps
│   ├── engine/             # EngineController, RedFlagEvaluator, ScoringEngine,
│   │                       # UrgencyDeterminer, OutputFormatter, engine models
│   ├── network/            # ApiClient (Dio)
│   └── storage/            # StorageService (Hive config cache)
├── features/
│   ├── boot/               # BootController + boot screen (offline fallback)
│   ├── onboarding/         # Onboarding flow
│   ├── home/               # Home screen
│   ├── assessment/         # Age, sex, pregnancy, conditions, body area,
│   │                       # symptom selection, follow-up question engine
│   ├── results/            # Results screen, condition cards, red-flag interrupt
│   ├── splash/             # Splash screen
│   └── status/             # System status screen
└── shared/                 # Shared models and widgets
test/                       # Engine, assessment, and results tests
assets/                     # Body-map SVGs, onboarding and brand images
```
