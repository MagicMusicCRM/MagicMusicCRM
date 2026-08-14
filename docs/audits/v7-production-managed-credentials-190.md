# Production managed credentials rollout `1.5.10+190`

Дата: `2026-08-14` (МСК)

Результат: **PASS**

## Зафиксированный кандидат

- Feature commit: `11c13244`.
- Release revision и tag `v1.5.10`:
  `765a10a9591b302ac490100c25f225ae98dfe107`.
- Image: `magicmusiccrm-server:1.5.10-190-765a10a9`.
- Image ID: `sha256:5590b6c5551b67d891d8de6dd3c3cbb1d5760c34e3c8fced1a26272d0d356287`.
- Transport archive: `82 771 968` bytes, SHA-256
  `BAD2B25F3E5F34B3AE8058FBE8CB3BBAFA78A9D82B8660044FE00635E681F1B2`.

## Изменение

- Обычная аутентификация продолжает использовать односторонний `scrypt`.
- Для управляемого Staff/Teacher password добавлен отдельный AES-256-GCM
  envelope с production-only ключом `MANAGED_PASSWORD_ENCRYPTION_KEY`.
- Admin provision, self-service change и reset синхронно обновляют envelope.
- Read endpoints доступны только Director/system_admin, проверяют иерархию,
  отвечают с `no-store` и фиксируют reveal в audit без самого секрета.
- Обычные Teacher/Staff DTO и поиск не раскрывают login email/password metadata
  прочим ролям.
- Старые `scrypt`-хэши необратимы: пароль появляется после следующей смены или
  переустановки.

## Release gates

- Flutter: `803/803`, `flutter analyze` PASS.
- Backend: `182/182` suites, `1447/1447` tests; typecheck/build PASS.
- Production-like gate: migration `0136`, live/ready и reconciliation PASS.
- Exact image: invalid config fail-closed, healthy readiness и degraded `503`
  PASS.
- Strict security preflight: `11 PASS / 0 WARN / 0 FAIL`; npm audit `0`.
- Semgrep по `33` изменённым файлам: `244` rules, `0` findings.
- Gitleaks по трём release commits: `0` leaks.
- Trivy exact image: `0` High/Critical vulnerabilities, `0` secrets.
- Windows portable и Setup install/launch/uninstall PASS.
- APK: `versionName=1.5.10`, `versionCode=190`, Signature Scheme v2 PASS,
  certificate SHA-256
  `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
- AAB signature PASS.

## Backup и rollback

- До mutation создан encrypted backup
  `magicmusiccrm-staging-20260814T153506Z.tgz.enc`, `130 896` bytes,
  SHA-256
  `63EFA9077F5EFEF7A9BF82DA881B11144AA613B9D500418D46C27545F0A28271`.
- После rollout создан backup с новой схемой и зашифрованным env:
  `magicmusiccrm-staging-20260814T160037Z.tgz.enc`, `131 536` bytes,
  SHA-256
  `B71E546D10291A8B7319DEDBF09358D122389C16A5B228B6DE813D1D80D1C2B9`.
- Оба backup расшифрованы, внутренние SHA-256 и `pg_restore -l` проверены,
  off-host копии совпали.
- Предыдущий image сохранён как
  `magicmusiccrm-server:rollback-pre-managed-credentials-20260814T1558Z`.
- Старые manifests сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260814T160037Z-pre-190`.
- `0136` additive; предыдущий server image совместим с новой nullable колонкой.

## Production verification

- Runtime revision/version: `765a10a9` / `1.5.10+190`.
- Migration head: `0136_managed_password_recovery`.
- API health `healthy`, restart count `0`, свежие fatal/unhandled/500 `0`.
- Reconciliation: `issues=[]`.
- Queues `pending outbox / dead outbox / exports / lesson poison / task poison /
  installment poison`: `0|0|0|0|0|0`.
- Оба update manifests идентичны и указывают build `190` с точным Windows ZIP
  SHA-256.
- Все четыре public download URL вернули точные размеры; Windows ZIP повторно
  скачан и совпал по SHA-256.
- GitHub Release `v1.5.10` опубликован как ready release; GitHub-computed
  digests и размеры всех четырёх assets совпали с локальными.

## Клиентские артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 534 155` | `CF9073FDB0EED13519A2D7943CE3F9095CD5DC707E7024C3DA25EE5123A97A94` |
| Windows Setup | `15 382 245` | `674F51CEF292C4E45294CE8E55F1BF9EF7AF06B2E2F5C9B044EB222489E03869` |
| Android APK | `86 246 793` | `084FA63A6188F2F32FD4255B93A90C87B6B825BCB91929D1A018DFFC89B4B4D8` |
| Android AAB | `60 612 608` | `D4C8E016E0EDDF09A95C9DA74166B5FBAC11635946422A12A917FF42A4F90064` |

Технический rollout завершён. Предметная owner-UAT на реальной карточке
Staff/Teacher остаётся отдельной проверкой; для аккаунтов со старым хэшем нужно
один раз сменить или переустановить пароль.
