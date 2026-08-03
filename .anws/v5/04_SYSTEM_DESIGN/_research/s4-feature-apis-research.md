# Research - S4 Feature APIs

**Systems**: SYS-DATA, SYS-MSG, SYS-FILES, SYS-LEGAL, SYS-NOTIFY
**Date**: 2026-06-11
**Purpose**: Provide implementation constraints for S4 feature APIs before coding.

## Sources Reviewed

- NestJS Validation: https://docs.nestjs.com/techniques/validation
- NestJS Guards: https://docs.nestjs.com/guards
- NestJS WebSocket Gateways: https://docs.nestjs.com/websockets/gateways
- OWASP REST Security Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html
- OWASP Authorization Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html
- OWASP File Upload Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html
- PostgreSQL Indexes: https://www.postgresql.org/docs/current/indexes.html
- PostgreSQL Partial Indexes: https://www.postgresql.org/docs/current/indexes-partial.html

## Findings

1. **Module-per-domain fits NestJS**: S4 should keep one NestJS module per bounded domain. Controllers own DTO validation, services own business rules, repositories own SQL, guards own authentication and role/ownership boundaries.
2. **Authorization must be explicit at every operation**: OWASP authorization guidance aligns with v3 PRD: role, actor id and ownership must come from the JWT actor context, never from request bodies.
3. **REST writes, WebSocket events after commit**: Messenger writes should be REST transactions first. WebSocket only broadcasts committed, already-authorized events. This prevents realtime from bypassing validation and audit.
4. **Private file storage needs layered validation**: File uploads require size limit, extension normalization, MIME allowlist, random storage names, storage outside web root, metadata authorization and short-lived download tokens.
5. **Partial indexes are useful for active records**: PostgreSQL partial indexes should support common active queries such as non-deleted profiles, open deletion requests, unread messages and pending notifications without indexing historical rows unnecessarily.
6. **Read models are acceptable**: For Flutter migration speed, API DTOs may expose stable read models that replace Supabase joined selects/views, while writes stay normalized and audited.

## Design Constraints Adopted

- Use DTO validation for every public REST input.
- Use `JwtAuthGuard` plus role/ownership guards for every private endpoint.
- Use scoped repositories and SQL parameters only.
- Return `403` for authenticated actors lacking permission and `404` when hiding object existence is safer.
- Audit privileged writes, account deletion, legal consent, file access denial and admin actions.
- No public file URLs; file download is always backend authorized.
- WebSocket room join must call the same authorization policy as REST reads.
