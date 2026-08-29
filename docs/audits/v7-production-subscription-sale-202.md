# Production evidence — subscription sale 1.5.22+202

Date: 2026-08-29

Release commit: `289309100fba6f49522621d672f84f6115da499b`

Tag: `v1.5.22`

Server image: `magicmusiccrm-server:1.5.22-202-28930910`

Image ID: `sha256:a4671dace80348b1b4070ffb2ff87e89563589e61cef674a0ef55e5f8560c143`

Migration: `0142_schedule_plan_series_subscription_snapshot`

## Released behavior

- The existing subscription assignment sheet now records the actual payment in
  the same preview/commit flow: amount, cash/cashless method, date and comment.
  Zero, partial, full and overpayment are supported; zero does not create a fake
  payment.
- Start and inclusive end dates are part of the same signed preview. Start may
  be backdated. The default end is one clamped calendar month after start; an
  expired subscription is excluded from active balance regardless of remaining
  lessons.
- Student and Lead purchases use one canonical transactional writer. The build
  201 Lead route remains only as a compatibility adapter over it until telemetry
  proves builds `<=201` have left the supported client window.
- Backend capability, Student/Lead branch scope and external payer scope are
  checked on first execution and idempotent replay. Only Director and
  `system_admin` bypass branch scope.

## Verification before cutover

- Flutter: `1418/1418` tests; `flutter analyze` clean; Windows release, Setup,
  APK and AAB builds PASS. APK v2 and AAB JAR signatures verified.
- Backend: targeted release matrix `54/54`; full Jest matrix `268/268` suites,
  `3372/3372` tests; typecheck and Nest build PASS.
- Independent release review: P0/P1/P2 `0`. Codex Security diff coverage
  `40/40`, findings `0`. Application security gate `11/11`, npm audit `0`,
  Gitleaks `0`, Trivy High/Critical/Secrets `0`.
- Exact-image gate: invalid production configuration failed closed; live,
  ready and Docker health PASS; degraded readiness returned `503`.
- Offline image tar SHA-256:
  `fb0ec44b6863fc246753b07d530684a6d19819f5b13724f2c751073fd472d1cb`.

## Backup and rollback

- Pre-cutover encrypted backup:
  `magicmusiccrm-staging-20260829T125458Z.tgz.enc`, `187952` bytes,
  SHA-256 `430de6e2115197589cb2e0ea9cb8c97de22f08d6c445f796a57ab4d21bd57477`.
- Post-deploy encrypted backup:
  `magicmusiccrm-staging-20260829T130201Z.tgz.enc`, `187952` bytes,
  SHA-256 `8f262f89a7b737459f07daee3c8cfba288281fef8bedd9d95a0ae37a5474d011`.
- Both archives were copied off-host with matching hashes. Each passed an
  isolated restore, candidate reconciliation and rollback-image compatibility
  drill without touching the production database.
- Immediate API rollback image is
  `magicmusiccrm-server:1.5.21-201-f09cef3a` at revision
  `f09cef3a82e96904dc0422c0a03ab590f8dadb54`. Migration `0142` is retained.
- Client rollback manifests are stored in
  `/opt/magicmusiccrm/releases/client-manifest-rollback-201-20260829T125937Z`.

## Production verification

`DEPLOY_API_RELEASE|PASS` selected the exact image and revision. API is
`running/healthy`, restart count `0`, OOM `false`, non-root user `magiccrm`.
Public live/ready returned `200/200` twice with database, migration and workers
healthy. All six required workers are enabled. V7 reconciliation returned
`issues=[]` twice; outbox pending/dead is `0/0`; recent API error/fatal lines
and Caddy 5xx are `0`.

Unauthenticated Student and Lead purchase-preview requests returned `401`.
No current Manager/Director production token was available and no account or
token was created for the release, so the authenticated sale scenario is
proven by the exact-image PostgreSQL/unit matrices rather than a live mutation
of customer data.

## Client publication

Both `latest.json` and `latest-v2.json` point to build `202`, version
`1.5.22+202`, with ZIP SHA-256
`7127e0829685e4741ac703d7ffdbfd5759b24fe840d6b379b626b89789f455a4`.
Release history starts with build `202` and contains `42` entries. All four
public artifacts returned HTTP `200` with the expected sizes and hashes:

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Windows ZIP | 19780043 | `7127e0829685e4741ac703d7ffdbfd5759b24fe840d6b379b626b89789f455a4` |
| Windows Setup | 15554822 | `c233b1d03339a908ab26be826cf6401aa18269c90496356fa8d6e4a510f95150` |
| Android APK | 87745140 | `40f54e29968822068e11f889c0eb8712c7f43b532fb5db559c94e5dd2d5d6714` |
| Android AAB | 61242245 | `28d8cf0af2546c2b958729e4fb68bcba7d9448b01be8ebcd3cfca627546ce78f` |

GitHub Release: `https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.22`.
