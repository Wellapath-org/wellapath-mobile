# UI review assets (PR #86)

Screenshots and a screen recording of the home/onboarding redesign, so the
work can be reviewed without building the app.

Captured on the `wellapath_lowend` emulator (360x640 logical — a small
Android screen) from the branch's debug build, `APP_BUILD=ui-preview`.

The video and GIF that were here have been removed: they added ~2.2MB to a
23MB repository for review material with a short life. Recordings are
attached to the pull request instead. Still images stay, because they are
small and are referenced from both PR descriptions.

| File | Screen |
| --- | --- |
| `onboard1_welcome.png` | Meet Wella |
| `onboard2_intent.png` | What brings you here? (navigation-only choices) |
| `onboard3_journey.png` | Three simple steps |
| `onboard4_trust.png` | What WellaPath is — limits stated plainly |
| `onboard5_begin.png` | You're all set |
| `home.png` | Home: greeting, primary action, emergency, pinned disclaimer |
| `learn.png` | Learn: card of the day and How WellaPath works |
| `more.png` | More: about, your information, replay |

**These files are review documentation, not app assets.** They are not
declared under `flutter > assets` in `pubspec.yaml`, so they are never
bundled into an APK or IPA and add nothing to the download size.
