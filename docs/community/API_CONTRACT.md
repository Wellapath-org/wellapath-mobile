# WellaPath Community API contract — v0.1 (DRAFT)

| | |
|---|---|
| Status | **DRAFT v0.1.** Internal development only. Community is OFF by default and is not publicly released |
| Date | 2026-11-07 |
| Governing decision | `WELLAPATH_ENGINEERING/ADR_COMMUNITY_AUTH_AND_DATA.md` (ADR-001, PROPOSED) |
| Consumers | `wellapath-mobile` `lib/features/community/**` (mock repositories today) |
| Implementer | `wellapath-backend` Community PoC (branch `poc/community-auth`) |
| Feature flag | [`FEATURE_FLAG_SPEC.md`](FEATURE_FLAG_SPEC.md) |

This document is the only coordination point between the mobile scaffold and
the backend PoC. If either side needs a change, change this file first (bump
the minor version, add a changelog row) and then the code.

## 0. Hard rules (non-negotiable, both sides)

1. **No assessment data, ever.** No endpoint accepts or returns symptoms,
   answers, triage results, urgency, red flags or assessment history. The
   mobile Community module cannot import the engine or assessment code (a test
   enforces this). Nothing here may be added to `/config`.
2. **Accountable pseudonymity.** Every post and comment is stored with its
   author's account id (`NOT NULL`). `display_mode` only changes what other
   members see.
3. **Member-facing payloads never contain an author account id** — not for
   pseudonymous content, and not for named content either. The member DTO has
   no `author_account_id`, `author_id`, `account_id` or `user_id` field at all.
   The server tells the viewer whether they wrote something via the boolean
   `viewer_is_author`. The mobile client **rejects** a member payload that
   carries any of those keys as a contract violation. Only moderator endpoints
   (§10) return the accountable identity, and every such read is audited.
4. **Verification is admin-only.** A member can *claim* a profession; the
   result is `pending`. Only an admin action sets `verified`. A badge is
   rendered only when `status == "verified"`.
5. **Every moderation action requires a reason**, and the server records the
   actor and a server timestamp in an append-only log. Clients never send a
   timestamp or an actor id.
6. **Out of scope for v0.1** (no endpoint may exist): private consultations,
   doctor chat, prescriptions, dosing, payments, booking, image or file
   uploads, nested threads (comment-on-comment), AI-generated replies,
   automatic diagnosis from posts, push notifications.

## 1. Conventions

* Base path: `/v1`. JSON, UTF-8. Field names are `snake_case`.
* Timestamps: RFC 3339 UTC strings set by the server (`2026-11-07T10:15:00Z`).
* IDs: opaque strings (UUIDv7 recommended). Clients must not parse them.
* Auth: `Authorization: Bearer <access_token>` on every endpoint except
  `/v1/auth/*` and `GET /v1/features` (which accepts an optional token).
* All Community routes (`/v1/community/*`, `/v1/auth/*`) **do not exist**
  when the server flag is `disabled` (the plugin registers no routes → 404).
* Versioning: breaking changes go to `/v2`. Additive fields are allowed in
  v0.x; clients ignore unknown fields (except the forbidden identity keys in
  rule 3).

### 1.1 Error model

Every non-2xx response has this body:

```json
{
  "error": {
    "code": "validation_failed",
    "message": "Human-readable, safe to log, never contains PII",
    "details": { "field": "body", "rule": "min_length" },
    "request_id": "req_01J..."
  }
}
```

| HTTP | `code` | Meaning |
|---|---|---|
| 400 | `validation_failed` | Body/query failed validation (`details.field`, `details.rule`) |
| 401 | `unauthenticated` | Missing/expired/revoked token |
| 403 | `forbidden` | Authenticated but role lacks the capability |
| 403 | `community_not_allowed` | Flag is `internal`/`closed_beta` and this account is not allowlisted |
| 403 | `account_restricted` | Account is restricted (read-only) or suspended |
| 404 | `not_found` | Missing, or hidden from this viewer (do not distinguish) |
| 409 | `conflict` | E.g. duplicate report by the same account on the same target |
| 410 | `content_removed` | Target was removed/deleted (posts and comments) |
| 422 | `invalid_state` | E.g. verifying a claim that is not `pending` |
| 429 | `rate_limited` | See §1.3; `Retry-After` header set |
| 503 | `community_unavailable` | Community DB down. `/config` must be unaffected |

Clients must treat `community_not_allowed` and a 404 on any Community route as
the **kill switch**: close Community and re-evaluate the flag.

### 1.2 Pagination

Cursor based. Request: `?limit=20&cursor=<opaque>` (`limit` 1–50, default 20).
Response envelope:

```json
{ "items": [ ... ], "next_cursor": "opaque-or-null" }
```

Lists are ordered newest first unless stated otherwise. `next_cursor: null`
means the end.

### 1.3 Rate limits (per account unless stated)

| Action | Limit |
|---|---|
| `POST /v1/auth/otp/request` | 3 / 15 min per email **and** 10 / hour per IP |
| `POST /v1/auth/otp/verify` | 5 attempts per issued code, then the code is burned |
| Create post | 5 / hour, 20 / day |
| Create comment | 30 / hour |
| Create report | 20 / day |
| Professional claim | 3 / day |
| Moderator reveal identity | 30 / hour per moderator (each read audited) |
| Everything else | 120 / min |

Responses carry `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`.

## 2. Auth — email OTP (ADR-001 §4.3)

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/v1/auth/otp/request` | `{ "email": "a@b.ng" }` | `202 {}` — always 202, even for unknown emails (no account enumeration) |
| POST | `/v1/auth/otp/verify` | `{ "email": "...", "code": "123456" }` | `200 { "access_token", "refresh_token", "expires_in": 900, "account": AccountSelf }` |
| POST | `/v1/auth/refresh` | `{ "refresh_token" }` | `200` same shape; refresh tokens rotate, reuse revokes the family |
| POST | `/v1/auth/logout` | — | `204` revokes the session |

`AccountSelf` (only ever returned to the account itself):

```json
{ "account_id": "acc_...", "role": "member", "status": "active", "created_at": "..." }
```

`role` ∈ `member | moderator | admin`. `status` ∈ `active | restricted | suspended`.
Suspension revokes all sessions. Moderator/admin sign-in requires TOTP (second
step; contract TBD with the PoC — `POST /v1/auth/totp/verify`). Mobile stores
tokens in `flutter_secure_storage` (new dependency, not added in the scaffold).

## 3. Feature flag — `GET /v1/features`

Specified fully in [`FEATURE_FLAG_SPEC.md`](FEATURE_FLAG_SPEC.md). Summary:

```json
{ "community": "disabled", "community_allowed": false }
```

This endpoint is registered **even when** Community is disabled (it is the
thing that says so). It must not read the Community DB in `disabled` or
`public` mode, and must never 5xx because of it.

## 4. Spaces

| Method | Path | Response |
|---|---|---|
| GET | `/v1/community/spaces` | `200 { "items": [Space] }` — exactly the two seeded spaces |

```json
{ "id": "general_health", "name": "General Health", "description": "..." }
{ "id": "pregnancy_maternal", "name": "Pregnancy / Maternal Health", "description": "..." }
```

`id` ∈ `general_health | pregnancy_maternal`. No create/update/delete endpoint.
A client receiving any other id ignores it.

## 5. Profile

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/v1/community/me/profile` | — | `200 Profile` (404 `not_found` until created) |
| PUT | `/v1/community/me/profile` | `{ "display_name": "SunnyMum" }` | `200 Profile` |

`display_name`: 3–30 characters, letters, digits, space, `_`, `-`, `.`;
trimmed; unique case-insensitively (409 `conflict`). It must not be an email
address or phone number (400). A profile is required before posting.

```json
{ "display_name": "SunnyMum", "professional": ProfessionalVerification|null }
```

## 6. Posts (text only)

| Method | Path | Body / query | Response |
|---|---|---|---|
| GET | `/v1/community/spaces/{space_id}/posts` | `limit`, `cursor` | `200 Page<Post>` |
| POST | `/v1/community/spaces/{space_id}/posts` | `PostCreate` | `201 Post` |
| GET | `/v1/community/posts/{post_id}` | — | `200 Post` |
| DELETE | `/v1/community/posts/{post_id}` | — | `204` — own post only (403 otherwise); sets `deleted_by_author` |

`PostCreate`:

```json
{ "body": "text, 1–2000 chars after trim", "display_mode": "pseudonymous" }
```

`display_mode` ∈ `named | pseudonymous`. No title, no attachments, no links
preview, no images. Unknown fields → 400.

`Post` (member DTO):

```json
{
  "id": "pst_...",
  "space_id": "general_health",
  "body": "…",
  "author": PublicAuthor,
  "viewer_is_author": false,
  "status": "visible",
  "comment_count": 3,
  "created_at": "2026-11-07T10:15:00Z"
}
```

`PublicAuthor`:

```json
{ "display_mode": "named", "display_name": "SunnyMum", "badge": ProfessionalBadge|null }
{ "display_mode": "pseudonymous", "display_name": null, "badge": null }
```

* Pseudonymous: `display_name` and `badge` are `null`; the client renders
  "Community member". No stable per-author handle is exposed (so posts cannot
  be linked to each other).
* `badge` is non-null only when the author's verification is `verified`:
  `{ "profession": "Midwife", "specialty": "Antenatal care" }`.
* `status` ∈ `visible | hidden | removed | deleted_by_author`. Members only
  ever receive `visible` items in lists; a direct GET of a non-visible post
  returns 410 `content_removed` (body only `{error}`; never the original text).

## 7. Comments (single level)

| Method | Path | Body / query | Response |
|---|---|---|---|
| GET | `/v1/community/posts/{post_id}/comments` | `limit`, `cursor` (oldest first) | `200 Page<Comment>` |
| POST | `/v1/community/posts/{post_id}/comments` | `{ "body", "display_mode" }` | `201 Comment` |
| DELETE | `/v1/community/comments/{comment_id}` | — | `204` own only |

`Comment`: `{ id, post_id, body, author: PublicAuthor, viewer_is_author, status, created_at }`.
Body 1–1000 chars after trim. **There is no `parent_comment_id`**; a request
carrying one → 400. The mobile client rejects a Comment payload carrying it.

## 8. Reports

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/v1/community/reports` | `ReportCreate` | `201 { "id", "status": "open", "created_at" }` |

```json
{ "target_type": "post", "target_id": "pst_...", "reason": "unsafe_medical_advice", "note": "optional, ≤500 chars" }
```

`target_type` ∈ `post | comment`. `reason` ∈
`spam | harassment | misinformation | unsafe_medical_advice | self_harm_or_emergency | personal_information | other`.
`note` is optional (≤500 chars after trim). The server records the reporter
account and `created_at`. The reporter's identity is never shown to the
reported author. Duplicate open report by the same account on the same
target → 409.

## 9. Notifications (in-app centre, polling; push deferred)

| Method | Path | Response |
|---|---|---|
| GET | `/v1/community/notifications` | `200 Page<Notification>`, plus `"unread_count": n` |
| POST | `/v1/community/notifications/{id}/read` | `204` |
| POST | `/v1/community/notifications/read-all` | `204` |

```json
{ "id": "ntf_...", "type": "reply_to_post", "post_id": "pst_...", "comment_id": "cmt_...", "created_at": "...", "read_at": null }
```

`type` ∈ `reply_to_post` (someone commented on your post) | `comment_reply`
(someone commented on a post you commented on) | `moderation_notice` (your
content was hidden/removed or your account was restricted; carries
`"notice": "content_hidden" | "content_removed" | "account_restricted" | "account_suspended" | "verification_updated"`).
Notifications never contain the actor's account id or another member's
content body; the client fetches the post if it needs text.

## 10. Professional verification

| Method | Path | Body | Response | Role |
|---|---|---|---|---|
| POST | `/v1/community/me/professional-claim` | `{ "profession", "specialty"? }` | `201 ProfessionalVerification` with `status: "pending"` | member |
| DELETE | `/v1/community/me/professional-claim` | — | `204` withdraws (→ `unverified`) | member |
| POST | `/v1/community/mod/verifications/{account_id}/verify` | `{ "reason", "evidence_ref" }` | `200` | **admin only** |
| POST | `/v1/community/mod/verifications/{account_id}/revoke` | `{ "reason" }` | `200` | **admin only** |
| GET | `/v1/community/mod/verifications?status=pending` | — | `200 Page<VerificationQueueItem>` | admin |

```json
{ "profession": "Midwife", "specialty": "Antenatal care", "status": "pending", "verified_at": null }
```

`status` ∈ `unverified | pending | verified | revoked`. The claim body has no
`status` field; a claim request carrying one → 400. `verified_at` is
non-null iff `status == "verified"`. Every verify/revoke writes a
`moderation_actions` row (`verify_professional` / `revoke_professional`).
Evidence documents are handled out of band in v0.1 (no uploads); only an
opaque `evidence_ref` is stored.

## 11. Moderation (`/v1/community/mod/*`, moderator or admin)

Every mutating request **requires** `"reason"` (10–500 chars after trim);
missing → 400. The server writes an append-only `moderation_actions` row with
`actor_account_id`, `action`, `target_type`, `target_id`, `reason`,
`created_at` (server clock). Clients never send actor or time.

| Method | Path | Body | Notes |
|---|---|---|---|
| GET | `/mod/reports?status=open` | `limit`, `cursor` (oldest first) | `Page<ReportQueueItem>` |
| POST | `/mod/reports/{report_id}/dismiss` | `{ reason }` | action `dismiss_report` |
| POST | `/mod/identity/reveal` | `{ target_type, target_id, reason }` | returns `AccountableIdentity`; action `reveal_identity` (a **read** that is audited) |
| POST | `/mod/posts/{id}/hide` · `/mod/comments/{id}/hide` | `{ reason }` | `hide_content` (reversible) |
| POST | `/mod/posts/{id}/restore` · `/mod/comments/{id}/restore` | `{ reason }` | `restore_content` |
| POST | `/mod/posts/{id}/remove` · `/mod/comments/{id}/remove` | `{ reason }` | `remove_content` (terminal for members; evidence retained) |
| POST | `/mod/accounts/{account_id}/restrict` | `{ reason, until? }` | `restrict_account` (read-only) |
| POST | `/mod/accounts/{account_id}/suspend` | `{ reason, until? }` | `suspend_account`; revokes sessions. **admin only** |
| POST | `/mod/accounts/{account_id}/reinstate` | `{ reason }` | `reinstate_account`. **admin only** |
| POST | `/mod/accounts/{account_id}/role` | `{ role, reason }` | `change_role`. **admin only** |
| GET | `/mod/actions` | `target_type?`, `target_id?`, `actor?` | `Page<ModerationAction>` (audit log, read-only) |

`ReportQueueItem`: `{ id, target_type, target_id, reason, note, status, created_at, target_preview }`
where `target_preview` is the content body (moderators may see hidden content)
and **no** identities; identity requires an explicit reveal.

`AccountableIdentity` (moderator DTO only):

```json
{ "account_id": "acc_...", "display_name": "SunnyMum", "status": "active", "created_at": "...", "prior_actions": 2 }
```

Email is **not** returned by reveal in v0.1 (admin-only support tooling, TBD).

`ModerationAction`:

```json
{ "id": "mod_...", "actor_account_id": "acc_...", "action": "hide_content", "target_type": "post", "target_id": "pst_...", "reason": "…", "created_at": "..." }
```

`action` ∈ `dismiss_report | reveal_identity | hide_content | restore_content | remove_content | restrict_account | suspend_account | reinstate_account | change_role | verify_professional | revoke_professional`.

### 11.1 Role capability matrix (server enforces; mobile mirrors it in `community_permissions.dart`)

| Capability | member | moderator | admin |
|---|:-:|:-:|:-:|
| read spaces / posts / comments | ✓ | ✓ | ✓ |
| create post / comment, delete own | ✓ | ✓ | ✓ |
| report content | ✓ | ✓ | ✓ |
| claim profession | ✓ | ✓ | ✓ |
| view reports queue | | ✓ | ✓ |
| reveal accountable identity | | ✓ | ✓ |
| hide / restore content | | ✓ | ✓ |
| remove content | | ✓ | ✓ |
| restrict account | | ✓ | ✓ |
| view moderation audit log | | ✓ | ✓ |
| suspend / reinstate account | | | ✓ |
| verify / revoke professional | | | ✓ |
| change roles | | | ✓ |

Restricted accounts keep read capabilities only. Suspended accounts have none
(sessions revoked). A moderator cannot act on their own content or account.

## 12. Changelog

| Version | Date | Change |
|---|---|---|
| 0.1 | 2026-11-07 | First draft (mobile scaffold, PR to `wellapath-mobile` develop) |
