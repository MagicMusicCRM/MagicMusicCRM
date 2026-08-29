# Production evidence — subscription payment hotfix 68a63527

Date: 2026-08-29

Release commit: `68a635270fbfb49365a0ecd7d3cde60e738c4d2a`

Server image: `magicmusiccrm-server:1.5.22-202-68a63527`

Image ID: `sha256:393021628865cc1cec7a31708676ad4ad72ac288d1f1a8a60148c0fc3753061a`

Migration: `0143_payment_record_link_permission`

## Root cause and behavior

- Production rejected the final subscription purchase transaction with
  `permission denied for table payments` while linking the new canonical
  payment to its payment record.
- Migration `0143` grants `magiccrm_app` only
  `UPDATE (payment_record_id)` on `app.payments`. Table-level `UPDATE` and
  `DELETE` remain denied.
- The subscription sheet exposes one action, `Оплатить`. The signed preview is
  still enforced, but it is obtained and committed inside the same user action;
  no separate `Проверить` or `Подтвердить покупку` button remains.

## Verification before cutover

- Flutter full suite: `1453/1453`; analyze PASS.
- Backend full suite: `268/268` suites, `3382/3382` tests; typecheck and Nest
  build PASS.
- Exact PostgreSQL regression proves column update `true`, table update `false`.
- Encrypted pre-cutover backup
  `magicmusiccrm-staging-20260829T195328Z.tgz.enc`, `192288` bytes, SHA-256
  `8ab7f9e75b20a2926abfcd5495583bc93c2a2bc0d5c3f78129ffa2ca81292714`
  was copied off-host and passed isolated candidate/rollback restore.

## Production verification

- `DEPLOY_API_RELEASE|PASS` selected exact revision `68a63527` and migration
  `0143_payment_record_link_permission`.
- Public live/ready returned OK; API is healthy, restart `0`, OOM `false`.
- Privilege matrix for `payment_record_id update / table update / table delete`
  is `true / false / false`.
- V7 reconciliation twice returned `issues=[]`; platform outbox pending/dead is
  `0/0`; recent API permission/internal/fatal errors and Caddy 5xx are `0`.
- Post-deploy backup
  `magicmusiccrm-staging-20260829T195921Z.tgz.enc`, `192448` bytes, SHA-256
  `16afd62843fd4da45179b70c34f9adaf41f7013107bc6927f4559a99184235dd`
  was copied off-host and passed the isolated candidate/rollback restore drill.

## Client UAT boundary

Windows Release was built and launched from exact commit `68a63527` at
`C:\mr2\build\windows\x64\runner\Release\magic_music_crm.exe`; SHA-256 is
`ffa75894a53d723769a5eef2d5a40778f8ff5eb418171f498cf7f7cede85443b`.
No real customer purchase was created during deployment. Owner UAT must use an
explicitly selected client so financial and lesson history is not mutated by an
automated smoke test.
