# Community API contract — pointer (mobile v0.1 is superseded)

The mobile v0.1 contract that used to live here is **superseded** by the
canonical contract (status: CANONICAL v1.0-draft, waiting for founder
sign-off):

| | |
|---|---|
| Canonical (markdown wins) | `WELLAPATH_ENGINEERING/COMMUNITY_API_CONTRACT.md` v1.0-draft, dated 2026-11-07 (SHA-256 `46cf4e05bf55358d836945290001c7042f29b594a79e4284593f6cb115391f26`) |
| Machine-readable | `WELLAPATH_ENGINEERING/community_api_v1.openapi.yaml` (OpenAPI 3.1, `1.0.0-draft`) |
| Mobile copy of the OpenAPI file | [`community_api_v1.openapi.yaml`](community_api_v1.openapi.yaml), copied verbatim on 2026-11-07 |
| SHA-256 of the copy | `68992e18004a1cd4977e6eed5f4f63c720a8135714319a42c97ec34a22b852f5` |
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

## Mobile-only notes (not contract changes)

- `COMMUNITY_API_BASE_URL` (dart-define, default empty) is where the client
  sends requests. Empty means Community is hidden.
- `COMMUNITY_DATA_SOURCE=in_memory` (dart-define) keeps posts on the device
  for local development. The gate (compile flag + base URL + server flag
  + sign-in) is identical either way.
