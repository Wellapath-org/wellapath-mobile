# iOS privacy-manifest audit — 0.3.0+210

Audit backing `ios/Runner/PrivacyInfo.xcprivacy` (closes the manifest half
of `RC-BLK-009`). Performed 2026-09-11 against the working tree and the
built `build/ios/iphoneos/Runner.app`.

## Dependency audit — every package with native iOS code or network reach

| Package | Native iOS? | Collects/transmits | Required-reason APIs | Own manifest in the built app |
|---|---|---|---|---|
| shared_preferences (foundation) | yes (SPM, static) | nothing off device — NSUserDefaults storage | UserDefaults CA92.1 | ✅ `shared_preferences_foundation_….bundle/PrivacyInfo.xcprivacy` |
| path_provider (foundation) | yes (static, no bundle needed) | nothing | none declared by plugin | covered by plugin package (no resource bundle emitted) |
| url_launcher (ios) | yes | nothing — opens tel:/https: externally | none | ✅ own bundle manifest |
| geolocator (apple) | yes | reads device location **on request**; plugin sends nothing anywhere | none | ✅ own bundle manifest |
| sentry_flutter / Sentry cocoa | yes (framework) | crash events **only when a DSN + both gates are supplied**; none bundled in this artifact | declared by Sentry itself | ✅ `Sentry.framework/PrivacyInfo.xcprivacy` |
| package_info_plus (transitive) | yes | nothing — reads own bundle version | none | ✅ own bundle manifest |
| Flutter engine | yes | nothing | declares its own (UserDefaults etc.) | ✅ `Flutter.framework/PrivacyInfo.xcprivacy` |
| dio, hive/hive_flutter, flutter_dotenv, flutter_svg, flutter_map, latlong2, crypto, unorm_dart | pure Dart | see app-level flows below | none (no native code) | n/a — covered by the app manifest |

**Validated in the built Runner.app:** 7 `PrivacyInfo.xcprivacy` files
present — the app-target manifest at the bundle root (`plutil -lint` OK)
plus Flutter.framework, Sentry.framework, and the shared_preferences /
url_launcher / geolocator / package_info_plus resource bundles.

## App-level data flows (what the app itself does)

| Flow | Declared as | Rationale |
|---|---|---|
| Crash reports (Sentry EU; off by default, no DSN bundled; redacted, no PII, no breadcrumbs, `tracesSampleRate=null`) | CrashData · not linked · no tracking · AppFunctionality | The SDK ships in the binary and internal builds may enable it — declaring "uncollected" would be false |
| Telemetry contract v1.0 (off by default; funnel events, random per-assessment session id, app version/build, platform; `os_version` deliberately omitted) | ProductInteraction · not linked · no tracking · Analytics | same reasoning |
| `admin_area_code` in facility_search telemetry (state-level: Lagos/Kano/FCT) | CoarseLocation · not linked · no tracking · Analytics | state-level region is location-derived data; coarsest honest bucket |
| Precise location (facility sorting, map centring) | **not** collected | read on device, never transmitted to WellaPath; guarded by the purpose string "Your location never leaves your device" |
| Map tiles (basemaps.cartocdn.com) | not a collected-data type | viewport tile indices go to the CDN as ephemeral servicing of the map render; nothing retained or used by WellaPath. Disclosed in the privacy-policy requirements instead |
| Symptom answers, scoring, results | **not** collected — never leaves the device | LOCKED PRINCIPLES #2/#3; enforced by the telemetry privacy guard and interceptor config |
| Identifiers | none exist — no user/device/install ID anywhere in the contract | verified: the only id is a random per-assessment session id |

## Required-reason APIs in first-party usage

- **UserDefaults (CA92.1)** — `onboarding_seen` via shared_preferences; the
  app's own data only.
- File timestamps / system boot time / disk space / active keyboard APIs:
  no first-party usage found (`lib/` is pure Dart; the Runner target's
  Swift is the stock AppDelegate/SceneDelegate). Plugin usage is covered by
  plugin manifests.

## Tracking

None. `NSPrivacyTracking=false`, no tracking domains, no ad SDK, no
fingerprinting. No `NSUserTrackingUsageDescription` and no ATT prompt.

## Guards

`test/release/permissions_and_privacy_test.dart` pins the manifest's
presence, its Xcode registration, the no-tracking/no-linked flags, the
three declared data types, CA92.1, and the absence of precise-location /
health-data declarations.
