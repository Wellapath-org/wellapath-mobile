# Support contact and privacy policy — requirements (both stores)

**Status: neither exists yet. Both are HARD BLOCKERS for the store
declarations** (Play Data Safety + Health Apps declaration; App Store
Connect app record). Neither can be invented by engineering — they need a
real, monitored contact and a founder-approved published policy.

## Support contact — required

| Store | Requirement |
|---|---|
| Play Console | support email address on the store listing (public) |
| App Store Connect | support URL required; marketing URL optional |

**Action (founder):** designate a monitored mailbox, e.g.
`support@wellapath.org` (the org controls wellapath.org — verified: live
site, registrar-managed DNS), and a support page on wellapath.org. Do not
use a personal address.

## Privacy policy — required

Play requires a privacy-policy URL for **all** apps, and doubly so under
the Health Apps declaration. Apple requires a privacy-policy URL on the app
record before TestFlight external testing / review (internal TestFlight
testers can technically precede the listing, but the field is part of the
app record — prepare it now).

The policy must be publicly reachable (suggested:
`https://wellapath.org/privacy`), non-editable by the app, and must
truthfully cover at minimum:

1. **What the app is** — a Clinical Decision Support System, not a
   diagnosis service and not a substitute for professional care.
2. **Health data:** symptom selections and assessment results are processed
   **on the device only** and are never transmitted to or stored by
   WellaPath's servers.
3. **Location:** used on-device to sort facilities and centre the map;
   precise location is never sent to WellaPath. Viewing the map sends the
   viewed map-area tile coordinates to the map tile provider (CARTO) to
   render the map.
4. **Telemetry (internal builds only, when enabled):** anonymised usage
   events (screen funnel, state-level region code, app version); no user
   identifier exists; retention on staging infrastructure.
5. **Crash reporting (when enabled):** redacted crash reports via Sentry
   (EU region); no personal data attached; 30-day retention on the current
   Sentry plan.
6. **No accounts, no advertising, no sale or sharing of personal data, no
   tracking.**
7. **Contact** for privacy questions (the support mailbox above).
8. Governing law / data-controller identity as counsel advises (Nigeria
   NDPR applies to the audience; not an engineering call).

**Approval chain:** founder (+ counsel if available) must approve the text
before the URL goes into either console. Engineering must not author the
final legal text.

## Where the URLs get entered (once they exist)

- Play Console → Store presence → Store listing → contact details +
  privacy policy.
- Play Console → App content → Data safety + Health apps declarations.
- App Store Connect → App Information → Support URL, Privacy Policy URL;
  App Privacy section (labels per `PLAY_DATA_SAFETY.md` ground truth —
  same answers translated to Apple's taxonomy, matching
  `ios/Runner/PrivacyInfo.xcprivacy`).
