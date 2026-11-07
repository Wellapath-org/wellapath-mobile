# Community feature flag — spec v0.1 (DRAFT)

| | |
|---|---|
| Status | **DRAFT v0.1.** Internal development only |
| Date | 2026-11-07 |
| Endpoint | `GET /v1/features` (new; the hash-locked `/config` is **not** changed) |
| Mobile implementation | `lib/features/community/gate/` |
| Related | [`API_CONTRACT.md`](API_CONTRACT.md) §3, ADR-001 §4.7 |

## 1. Two keys, both must turn

Community is reachable on a device only when **both** are true:

1. **Compile-time:** the build was made with
   `--dart-define=COMMUNITY_SCAFFOLD_ENABLED=true`. The default is `false`.
   In a default build the Community entry point is not in the widget tree at
   all, and the app never calls `/v1/features`.
2. **Server-time:** `GET /v1/features` says Community is available to *this*
   account (§3).

Neither key alone is enough. A compile-time `true` with a server that says
`disabled` (or that cannot be reached) shows nothing. A server `public` with a
compile-time `false` shows nothing. There is no third override (no
preference, no debug menu, no cached "last known good" allow).

## 2. Server-evaluated states

The server holds one setting, `COMMUNITY_MODE`, default **`disabled`**:

| `community` | Who may enter | Server behaviour |
|---|---|---|
| `disabled` (default) | Nobody | Community plugin registers **no routes**; `/v1/community/*` and `/v1/auth/*` return 404 |
| `internal` | Accounts on the internal allowlist (staff) | Routes registered; non-allowlisted accounts get 403 `community_not_allowed` everywhere |
| `closed_beta` | Accounts on the beta allowlist (internal ∪ beta testers) | As `internal`, wider allowlist |
| `public` | Any signed-in account | Not permitted until the PUBLIC gate in `COMMUNITY_BUILD_STATUS.md` §5 is met |

An unset, empty or unrecognised `COMMUNITY_MODE` is treated as `disabled` by
the server, and an unrecognised `community` value is treated as `disabled`
by the client.

## 3. Response

```http
GET /v1/features
Authorization: Bearer <access_token>   (optional)
```

```json
{ "community": "internal", "community_allowed": true }
```

| Field | Type | Rule |
|---|---|---|
| `community` | string enum | One of the four states above |
| `community_allowed` | boolean | `true` only if this request's account may enter in the current state. Always `false` when `community == "disabled"` or when no valid token was sent in `internal`/`closed_beta`. In `public`, `true` for any valid signed-in account and `false` anonymously |

* Allowlists are lists of **account ids** held server-side (env or table).
  They are never sent to clients.
* `Cache-Control: no-store`. The response contains no PII.
* The endpoint exists in every mode (it is how `disabled` is announced), never
  touches the Community DB in `disabled`, and must not 5xx because the
  Community DB is down — it returns `{ "community": "disabled", "community_allowed": false }`
  instead.

### Anonymous discovery

Before sign-in the client calls without a token. In `internal`/`closed_beta`
the answer is `community_allowed: false`, so an anonymous device sees nothing.
For the internal scaffold the sign-in screen itself is reached only by
testers who already know to look (out of scope for this PR; see §7).

## 4. Client evaluation (mobile)

```
allowed = COMMUNITY_SCAFFOLD_ENABLED
       && fetch succeeded
       && response parsed strictly
       && community ∈ {internal, closed_beta, public}
       && community_allowed == true
```

**Fail closed.** Every one of these yields *hidden*:

* compile flag false (no request is made);
* network error, timeout (5 s), non-200 status, non-JSON body;
* missing `community` or `community_allowed`, wrong types, unknown enum value;
* `community == "disabled"` regardless of `community_allowed`;
* `community_allowed != true`.

## 5. Client caching rules

* **Memory only.** The decision is never written to disk (Hive,
  shared_preferences or otherwise). A cold start always re-asks.
* **Only an allow is cached, for at most 5 minutes.** A deny is not cached
  (cheap to re-ask, and it means a later enable is seen quickly).
* **An error never extends a cached allow.** If a refresh fails, the cached
  allow is discarded and the result is *hidden*. There is no stale-while-error.
* **Entering Community always re-fetches** (bypasses the cache). Tapping the
  More-tab row runs a fresh evaluation and navigates only on a fresh allow.
* Any Community API response of 404 on a `/v1/community/*` route or 403
  `community_not_allowed` clears the cache and closes Community (pops to the
  More tab).

## 6. Kill switch

To switch Community off for everyone, immediately:

1. Set `COMMUNITY_MODE=disabled` on the backend (Render env) and redeploy /
   restart. The plugin registers no routes.
2. Effect on devices: the next evaluation (cold start, return to More, tapping
   the row, or any Community API call) returns hidden. Worst case an already
   open Community screen survives until its next request (which 404s and
   closes it) — at most one cache window (5 min) for the More-tab row.
3. No app release is needed. A store build with
   `COMMUNITY_SCAFFOLD_ENABLED=false` (every build today) is unaffected by any
   server setting.

To remove one tester: delete their account id from the allowlist (and
optionally revoke their sessions). Effect is the same as above for that account.

## 7. Not in this spec / later

* Remote flags for anything other than Community.
* Sign-in UI and token storage (`flutter_secure_storage`) — the scaffold uses
  in-memory mock repositories; the remote flag client sends no token yet, so
  until sign-in lands, a compile-flag-on build against a real server always
  evaluates to hidden in `internal`/`closed_beta`.
* Percent rollouts, per-space flags.

## 8. Changelog

| Version | Date | Change |
|---|---|---|
| 0.1 | 2026-11-07 | First draft |
