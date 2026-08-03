# System Design - v3 Security Gates

> [!IMPORTANT]
> Это наследованный security baseline v3. Актуальная для v4 матрица из шести ролей и hard invariants определена в `access_control.md`; перечисленная ниже старая actor matrix не расширяет права v4.

**System IDs**: SYS-SEC, SYS-API, SYS-AUTH, SYS-DATA, SYS-FILES, SYS-OPS
**Status**: Implementation-ready
**Related ADR**: ADR-006

## 1. Gate Groups

| Group | Checks |
|---|---|
| Secrets | No exposed DB credentials, public `.env`, hardcoded API keys, frontend secrets, build-log leaks. |
| Auth/session | Strong authentication, reset safety, refresh rotation, JWT secret hygiene, secure cookies/tokens. |
| Authorization | No client-side-only checks, no IDOR, no user-controlled roles/IDs, protected admin routes. |
| Data isolation | Actor matrix for anon/client/teacher/manager/admin and tenant/user isolation. |
| API security | DTO validation, SQL injection, XSS, CSRF where applicable, SSRF, path traversal. |
| File security | MIME/size allowlists, private storage, signed downloads, no public web root. |
| Infra | Private DB, firewall, no public dashboards, dependency/container scans, monitoring, alerting. |
| Operations | Audit logs, PII redaction, backups, restore drill, incident runbooks. |
| Integrations | SMTP fallback, OAuth state/redirect validation, webhook signatures, optional Firebase. |

## 2. Actor Matrix

| Actor | Must not access |
|---|---|
| anon | Any private CRM, chat, file, profile, admin or legal records. |
| client A | client B profile, payments, chats, files, deletion status or notifications. |
| teacher | unrelated students, finance/admin routes, staff role management. |
| manager | security/admin-only routes unless explicitly granted. |
| admin | allowed privileged actions with audit logs. |

## 3. Release Evidence

Every production cutover candidate must include:

- CI scan output.
- Dependency and container scan output.
- Actor matrix test report.
- Migration integrity report.
- Backup restore report.
- Production smoke report.
- Completed 50-point checklist.

## 4. Blocking Rules

- Any Critical/High finding blocks cutover.
- Missing backup restore evidence blocks cutover.
- Missing actor matrix evidence blocks cutover.
- Any public secret or frontend privileged credential blocks merge and requires rotation.
