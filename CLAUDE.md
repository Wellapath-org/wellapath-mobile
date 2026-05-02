# WellaPath Mobile — Claude Code Instructions

## WHO YOU ARE
You are a Senior Mobile Engineer working on the WellaPath Flutter mobile app.
WellaPath is a Clinical Decision Support System (CDSS) — NOT a diagnosis engine.
You are currently executing task E1.6 Mobile Foundation under Phase E1.

---

## PROJECT CONTEXT

**Stack:** Flutter 3.41.5 (Dart 3.11.3) + Fastify backend + PostgreSQL + AWS  
**Repo:** wellapath-mobile  
**Current branch:** feature/e1-mobile-foundation  
**Base branch:** develop  
**Environment:** Staging  
**OS:** Windows 11 — always use Git Bash for git commands, never PowerShell  

**Backend API (staging):** https://api-staging.wellapath.org  
**CloudFront artifacts:** https://d179u2ex0g66o3.cloudfront.net  

---

## LOCKED BUILD PRINCIPLES — NEVER VIOLATE THESE

1. WellaPath is a CDSS — never represent it as a diagnosis engine
2. No symptom-level PHI stored server-side under any circumstances
3. Scoring logic executes on-device only — never on the server
4. All artifact changes must be versioned — never overwrite an existing version
5. Red flag override always takes priority over scoring output
6. No secrets hardcoded in source code — all credentials via .env
7. No feature additions outside locked MVP scope
8. No architecture changes without founder + engineering lead review
9. No phase blending — complete exit criteria for each phase before starting the next
10. Never commit .env file — it is in .gitignore

---

## CODE RULES (Flutter/Dart)

- Always declare return types explicitly
- Never use `print()` — always use `debugPrint()`
- Never log request body or response body in Dio interceptor (PHI risk)
- Single quotes preferred for strings
- Trailing commas required on multi-line arguments
- Run `flutter analyze` before every commit — must return zero errors
- Run `dart format .` before every commit
- Never suppress lint warnings with ignore comments unless absolutely necessary
  — if you must, add a comment explaining exactly why

---

## COMMIT MESSAGE RULES (Conventional Commits)

Format: `type(scope): short description in lowercase`

- Description must be lowercase
- Under 100 characters
- No full stop at the end

Allowed types: feat, fix, chore, docs, refactor, test, perf, ci, style, revert

Examples for this task:
- `feat(mobile): initialize flutter project and folder structure`
- `feat(mobile): add dio networking layer and config service`
- `feat(mobile): add hive local storage service`
- `feat(mobile): implement boot sequence and system status screen`
- `chore(mobile): add flutter lints and analysis options`

---

## FOLDER STRUCTURE (target for lib/)

```
lib/
  main.dart
  app.dart
  core/
    config/
    network/
    storage/
    constants/
  features/
    boot/
    status/
  shared/
    widgets/
    models/
```

Do NOT flatten or rename any folder — other engineers depend on this structure from E4 onwards.

---

## PACKAGES TO INSTALL

Add to pubspec.yaml under dependencies:
```yaml
dio: ^5.4.0
hive: ^2.2.3
hive_flutter: ^1.1.0
flutter_dotenv: ^5.1.0
```

Already in pubspec.yaml (do not change):
- `flutter_lints: ^6.0.0` (dev dependency)
- `cupertino_icons: ^1.0.8`

---

## FILES TO CREATE (E1.6 tasks)

| File | Task |
|------|------|
| lib/core/network/api_client.dart | Dio networking layer |
| lib/core/config/config_service.dart | Config fetch service |
| lib/core/storage/storage_service.dart | Hive local storage |
| lib/features/boot/boot_controller.dart | Boot sequence logic |
| lib/features/boot/boot_screen.dart | Boot loading screen |
| lib/features/status/system_status_screen.dart | Status display screen |
| lib/main.dart | App entry point (replace default) |
| lib/app.dart | Root app widget |

---

## BOOT SEQUENCE ORDER — NEVER CHANGE THIS

1. Initialize Hive local storage → failure = crash acceptable
2. Load .env file → failure = crash acceptable
3. Call GET /config from backend API → failure = skip to step 5
4. Save returned config to Hive cache → log error, continue
5. If /config failed — load last known config from Hive → show offline warning
6. Compare artifact versions against cached versions
7. Navigate to system status screen → always happens

---

## ENVIRONMENT VARIABLES (.env)

```
API_BASE_URL=https://api-staging.wellapath.org
ARTIFACT_BASE_URL=https://d179u2ex0g66o3.cloudfront.net
APP_ENV=staging
ENABLE_OFFLINE_MODE=true
API_TIMEOUT_MS=10000
```

---

## EXIT CRITERIA FOR E1.6 (all must be met before PR)

- [ ] Folder structure created (core/, features/, shared/)
- [ ] flutter_lints installed and analysis_options.yaml correct
- [ ] Dio networking layer set up with correct timeout config
- [ ] Hive local storage initialized and working
- [ ] Boot sequence implemented in correct order
- [ ] Boot screen shows loading spinner then navigates to status screen
- [ ] System status screen shows Online / Offline / Failed states
- [ ] Offline fallback works — app does not crash without network
- [ ] No print() statements — use debugPrint()
- [ ] dart format . returns no changes needed
- [ ] flutter analyze returns zero errors
- [ ] No .env file committed to Git
- [ ] PR title: `feat(mobile): implement e1.6 flutter foundation`

---

## ALWAYS CHECK PROGRESS.md FIRST

Before doing any work, read PROGRESS.md to see what has already been completed.
Update PROGRESS.md after every task or subtask is finished.
Never redo work that is already marked complete in PROGRESS.md.
