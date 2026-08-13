# Production teacher options hotfix `2d1c6255`

Дата: `2026-08-14` (МСК)

Результат: **PASS**

## Инцидент и исправление

Настройки CRM содержали актуальные варианты `level` и `category`, но карточка
и форма создания преподавателя не показывали их. Production snapshot после
унификации полей использует общий shape без legacy `entityType`, а clean-start
удалил отдельные persisted definitions `teachers.levels` и
`teachers.categories`.

`SettingsService.getCrmCustomFields()` теперь:

- принимает unified level/category fields без устаревшего `entityType`;
- продолжает поддерживать legacy entity-specific snapshot;
- формирует только в read-response отсутствующие teacher projections из тех же
  option sets, не создавая второй редактируемый справочник и не изменяя данные.

## Release gates

- Revision: `2d1c625535c1cadd82371adcd7ae7e7bbb30538e`.
- Backend: `180/180` suites, `1426/1426` tests; typecheck/build PASS.
- Targeted Flutter teacher fields: `2/2` PASS.
- Exact image: invalid production flags fail-closed, live/ready/healthcheck и
  degraded readiness HTTP `503` PASS.
- Trivy: `0` High/Critical, secrets `0`; npm audit: `0` vulnerabilities.
- Gitleaks нового коммита: no leaks. Historical full-repository scan содержит
  legacy findings и не использовался как доказательство текущего diff.

## Backup и rollback

- Перед cutover создан encrypted backup
  `magicmusiccrm-staging-20260813T210647Z.tgz.enc`, `118 576` bytes,
  SHA-256
  `48F7F3F9A251F6AF33D593E71CB11407DBD9E24C4F3E01168191011A4E42A6E9`.
- Off-host-копия на рабочей машине совпала по SHA-256. Backup расшифрован,
  внутренние SHA-256 DB/globals/env/storage проверены, `pg_restore -l` PASS.
- Предыдущий production image `5f7bce2b` сохранён как immutable rollback target
  `magicmusiccrm-server:rollback-pre-teacher-options-20260813T211019Z`.
- Automatic rollback был вооружён, но не запускался.

## Production rollout

- Image: `magicmusiccrm-server:1.5.7-187-2d1c6255`.
- Image ID:
  `sha256:4967c3d704f89d64d73f33e1e1171f94133f8f3b7934683b98fa2189a96980a9`.
- OCI version/user: `1.5.7+187`, `magiccrm`.
- Transport archive: `82 768 384` bytes, SHA-256
  `1C772E00D6668510F288E65DB07421C0D34FD3341F46F0FA7F0BE18C3A421607`.
- Migration осталась `0135_requeue_organization_outbox`; schema и persisted CRM
  settings не менялись.
- Предметный production readback: levels
  `Без опыта / Начальный / Средний`, categories `Взрослые / Дети`.
- Initial и delayed public readiness `5/5 + 5/5`; internal readiness PASS,
  reconciliation `issues=[]`, outbox `0 pending / 0 dead`, restart count `0`,
  свежий log scan чистый.

Клиентские manifests и GitHub Release assets не менялись: уже установленный
build `1.5.7+187` получает исправленный справочник с сервера.
