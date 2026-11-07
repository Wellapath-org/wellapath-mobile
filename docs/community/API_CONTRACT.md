# Community API contract — pointer (mobile v0.1 is superseded)

The mobile v0.1 contract that used to live here is **superseded** by the
canonical contract (status: CANONICAL v1.0-draft, waiting for founder
sign-off):

| | |
|---|---|
| Canonical (markdown wins) | `WELLAPATH_ENGINEERING/COMMUNITY_API_CONTRACT.md` v1.0-draft, dated 2026-11-07, with P6 adopted (SHA-256 `7ee44c30f223b78cde448f940bf77068943bab2e6e93c5a372e3bdac0e490166`) |
| Machine-readable | `WELLAPATH_ENGINEERING/community_api_v1.openapi.yaml` (OpenAPI 3.1, `1.0.0-draft`) |
| Mobile copy of the OpenAPI file | [`community_api_v1.openapi.yaml`](community_api_v1.openapi.yaml), copied verbatim on 2026-11-08 (after the P6 follow-up) |
| SHA-256 of the copy | `b88749cf946edeea40031ea502d025beebd8656999eb75f7f15b150b5fcbb533` |
| Governing decision | `WELLAPATH_ENGINEERING/ADR_COMMUNITY_AUTH_AND_DATA.md` (ADR-001) incl. amendments A1–A4 |

The v0.1 text is in git history (`d46d822`). Do not edit the copied YAML in
this repo: change the canonical files by PR in `WELLAPATH_ENGINEERING`, then
re-copy the YAML here and update the hash above. The contract test
(`test/community/community_contract_test.dart`) fails if the copy and this
hash disagree.

## What the mobile client enforces from the contract

- **Requests.** Every request the client builds is checked against an
  operation (method + path template) in the copied spec, and its body, query
  parameters and required headers are validated against the spec's schemas
  (`test/community/community_contract_test.dart`).
- **Responses.** Strict parsers in `lib/features/community/domain/**` decode
  fixtures generated from the spec's own schemas, rich and minimal.
- **Member payloads.** Rejected if any key at any depth is `author_id`,
  `author_account_id`, `account_id`, `user_id`, `accountable_identity`,
  `author_email`, `email` or `reporter_id`; a pseudonymous author with a
  name or badge, a `parent_comment_id`, or a non-`visible` status is
  rejected. The check is **not** applied to the self DTOs (`Me`,
  `TokenPair`, the export).
- **Prohibited keys (§5).** The HTTP client refuses, before sending, any
  body (any depth) or query carrying a key that matches the §5 pattern.
- **Scope.** Only member-facing operations are implemented. The
  `/v1/community/mod/*`, `/v1/community/admin/*` and `/v1/auth/totp/*`
  operations are not: moderation and verification live in the website
  admin.

- **Sign-out (A4, P6 adopted 2026-11-07).** The client signs out with the
  stored refresh token alone: `POST /v1/auth/logout` `{refresh_token}`, no
  `Authorization` header, nothing refreshed first. Any 2xx (the server's
  neutral `204`) is success; local tokens are cleared whatever the answer.
  Only when no refresh token is stored does it send the in-memory bearer.

## Mobile-only notes (not contract changes)

- `COMMUNITY_API_BASE_URL` (dart-define, default empty) is where the client
  sends requests. Empty means Community is hidden.
- `COMMUNITY_DATA_SOURCE=in_memory` (dart-define) keeps posts on the device
  for local development. The gate (compile flag + base URL + server flag
  + sign-in) is identical either way.
