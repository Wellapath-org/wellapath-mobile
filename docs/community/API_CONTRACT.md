# Community API contract — pointer (mobile v0.1 is superseded)

The mobile v0.1 contract that used to live here is **superseded** by the
canonical contract (status: CANONICAL v1.0-draft, waiting for founder
sign-off):

| | |
|---|---|
| Canonical (markdown wins) | `WELLAPATH_ENGINEERING/COMMUNITY_API_CONTRACT.md` v1.0-draft, dated 2026-11-07, with P6 adopted and every Appendix P item approved by the founder on 2026-11-08 and applied (SHA-256 `4add68c478293db91783c974c3478b0b817ec0f56f76fb496adbcde01b062d38`) |
| Machine-readable | `WELLAPATH_ENGINEERING/community_api_v1.openapi.yaml` (OpenAPI 3.1, `1.0.0-draft`) |
| Mobile copy of the OpenAPI file | [`community_api_v1.openapi.yaml`](community_api_v1.openapi.yaml), copied verbatim on 2026-11-08 (after the remaining Appendix P approvals: P2–P5, P7, P9, P10, C2, C5, then the pre-validation security fixes and the display-name trimming decision) |
| SHA-256 of the copy | `312a1b9e0e89cd0c1fc36f20553da28f895218cd2e70588b01ecbbc098f7a11a` |
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

- **2026-11-08 founder decisions (Appendix P).** P1: export for every
  role, self-deletion for members only (422 `privileged_account` is shown
  as "hand over the role first"). P8: sign-out keeps the install's
  `device_id`; account deletion erases it (`forgetDevice`). C6: any bad
  refresh token is 401 `refresh_invalid`, which clears the session. D-019:
  on 409 `refresh_race` the client retries once only if storage changed.
  C3 and C7(d) are mirrored by the in-memory backend (a repeated
  restrict/suspend is 422 `already_in_state` with no audit row;
  `comment_reply` goes only to earlier commenters with a visible comment
  and an active account).

## Mobile-only notes (not contract changes)

- `COMMUNITY_API_BASE_URL` (dart-define, default empty) is where the client
  sends requests. Empty means Community is hidden.
- `COMMUNITY_DATA_SOURCE=in_memory` (dart-define) keeps posts on the device
  for local development. The gate (compile flag + base URL + server flag
  + sign-in) is identical either way.
