# Production OTP login hotfix `5f7bce2b`

Дата: `2026-08-13`

Результат: **PASS**

## Инцидент

Production audit подтвердил последовательность для `system_admin`:
`auth.login_password -> auth.login_email_otp_required -> auth.otp_verified`,
после которой пользователь снова попадал на пустой экран входа.

`login()` принудительно требовал OTP для привилегированных ролей даже при
`email_otp_2fa_enabled=false`, но `verifyOtp()` выдавал session только по
персональному флагу. Поэтому валидный одноразовый код потреблялся, а access и
refresh tokens не создавались.

## Исправление

- `verifyOtp()` использует то же правило завершения, что и `login()`:
  персональный флаг **или** привилегированная роль.
- OTP UI не покидает экран подтверждения, если backend не вернул session.
- Добавлены backend regression для forced OTP `system_admin` и Flutter widget
  regression для fail-closed ответа без session.

## Gates

- Backend auth: `32/32`; полный backend: `180/180` suites,
  `1425/1425` tests.
- Backend typecheck/build: PASS; production npm audit: `0` vulnerabilities.
- Flutter auth: `16/16`; targeted analyze: PASS.
- Exact image: production flags fail-closed, live/ready/healthcheck и
  ожидаемый degraded readiness HTTP `503` PASS.
- Trivy High/Critical: `0`; secrets: `0`; Gitleaks: no leaks.
- RepoWise change risk: typical change, percentile `52.5`, moderate review
  priority; покрывающий backend test найден.

## Production rollout

- Revision: `5f7bce2bede8227aca56b0be9b5110fb8aa92fd8`.
- Image: `magicmusiccrm-server:1.5.7-187-5f7bce2b`.
- Image ID:
  `sha256:f6c4440502d678dacc00fca9e2ae5c5b70a76bd4304b9bb5669ebcdc9572c12a`.
- OCI version/user: `1.5.7+187`, `magiccrm`.
- Migration осталась `0135_requeue_organization_outbox`.
- Перед cutover создан и скопирован off-host encrypted backup
  `magicmusiccrm-staging-20260813T203930Z.tgz.enc`, `114 256` bytes,
  SHA-256
  `8BFA4C4BE71B5029DF289399ECEC16138C88361B831A82830582A6D204BDCC86`.
- Rollback image `0e7411e6` сохранён отдельным tag и был вооружён скриптом.
- Post-cutover readiness `5/5`, reconciliation `issues=[]`, outbox `0/0`,
  restart count `0`; свежий log scan чистый.
- Клиентские manifests и четыре GitHub assets не менялись: актуальный build
  остаётся `1.5.7+187`. Server fix совместим с уже установленными клиентами.

Ранее потреблённые OTP нельзя использовать повторно; после hotfix требуется
новая password-login попытка и новый код из нового письма.
