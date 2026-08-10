> generated_by: nexus-mapper v2 + project exhaustive inventories
> verified_at: 2026-08-10T14:11:29.427591+00:00
> source_revision: 13a9734356eca27f3d7b60dec00c639f1d85264b
> source_digest_sha256: cc6c200f55daa66889d4cd3a5de0176abe3d95eaf450576addb0db652f42a15f
> provenance: untruncated AST, Dart analyzer, route/DTO/policy/schema inventories and Git forensics

# Test and evidence coverage

- Test/spec modules mapped: 296.
- Inventory validation: routes/screens/wire/backend/commerce generators must pass `-Check`.
- Structural AST: parse errors=0, truncated=false.
- Production owner UAT remains governed by `docs/audits/v7-owner-production-mega-uat-result.md`; static coverage is not owner acceptance.

## Explicit gaps

- Dart analyzer records declarations and callsites, not the runtime widget tree produced by conditional builders.
- `unresolved` wire rows can be computed paths, download URLs, public/server-only or realtime contracts; inspect before treating as a defect.
- Five tables in `integrity_schema` are the guarded finance/schedule/access core, not a claim that PostgreSQL has only five tables.
