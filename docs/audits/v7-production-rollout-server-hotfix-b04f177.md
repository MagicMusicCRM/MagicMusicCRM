# Production server hotfix `b04f177`

Дата: `2026-08-11`

Результат: **PASS**

Client release: `1.5.1+181` без изменений

Owner mega-UAT: **IN PROGRESS**, этим rollout не закрыта

## Назначение

- Ускорить серверную загрузку раздела задач без изменения task-модели и
  видимости.
- Переиспользовать настроенные CRM-значения уровней обучения и категорий в
  формах создания и редактирования преподавателя.
- Не публиковать новый Windows/Android клиент: обе правки совместимы с уже
  выпущенным API-контрактом build `181`.

## Неизменяемый кандидат

- Source revision: `b04f1771af52a76a058be610ee45080cb2029219`.
- Предыдущий production image:
  `sha256:5fbd5a299bb43bb32f5269e446102c6014aac94f803d950b4cfafe217f7ba09f`.
- Развёрнутый exact image:
  `sha256:6e8fc8870c54287e9b33eeaee9436cb8d45233f6382120bf6a1eaa9e6d4829f1`.
- OCI version/revision и runtime user: `1.5.1+181`, `b04f177…`, `magiccrm`.
- Rollback image:
  `magicmusiccrm-server:rollback-pre-b04f177-20260811T1030Z`.

До production mutation кандидат прошёл:

- backend `158/158` suites и `1259/1259` tests;
- профильные tests `16/16`, typecheck и build;
- Gitleaks `0`, production dependency audit `0`;
- exact-image migration/fail-closed/live/ready/degraded-503 gate;
- Trivy `0` High/Critical и `0` secrets.

## Backup и restore-check

Непосредственно перед итоговым cutover создан новый encrypted backup:

- `magicmusiccrm-staging-20260811T103139Z.tgz.enc`;
- размер `33 815 680` bytes;
- SHA-256
  `A6DDAB4CD7533C62495892A8A08460F1EDD84C53E58A95958FE3D93E1EC5FC2D`;
- production и off-host SHA совпали.

В отдельной временной БД проверены расшифровка, внутренние checksums,
`pg_restore --list`, полный restore, candidate migration `0118` и
reconciliation `issues=[]`. Plaintext, временная БД и restore-каталог удалены.

Кандидат дополнительно запускался на восстановленной production-копии. Runtime
smoke вернул:

- уровни преподавателя: `Без опыта`, `Начальный`, `Средний`;
- категории преподавателя: `Взрослые`, `Дети`;
- на `12 487` задачах admin-visible counters/list projections заняли
  `64/67 ms`;
- reconciliation: `issues=[]`.

## Контролируемый rollback первой попытки

Первый кандидат `f6a3a58` прошёл технические gates, но post-cutover runtime
smoke обнаружил пустые teacher options. API был немедленно возвращён на exact
image `5fbd5a29…`; readiness и reconciliation после rollback прошли.

Корневая причина: production legacy-поля `teachers.levels` и
`teachers.categories` имеют тип `text`, а первоначальный тест моделировал
`select`. Адаптер добавлял options, но legacy-нормализатор удалял их у текстовых
полей. Revision `b04f177` преобразует только эти два совместимых поля в
`select` и содержит регрессионный тест на фактическую production-схему.

## Итоговый cutover

- Completion worker выключен на первое пересоздание API и восстановлен перед
  финальной проверкой.
- Автоматический rollback оставался вооружён до compiled runtime smoke,
  двойной reconciliation и публичного readiness.
- Rollback не потребовался для итогового кандидата.

Post-rollout:

- защищённый `GET /api/settings/crm-custom-fields`: HTTP `200`, оба teacher
  select заполнены ожидаемыми CRM-значениями;
- live task smoke: counters `86 ms`, list + audience/reminder projections
  `98 ms` для `366` видимых открытых задач;
- `/health/ready`: `ok`, migration `0118_lesson_participant_exclusions`;
- worker due/claimed/retry/poison: `0/0/0/0`;
- outbox pending/dead-letter: `0/0`;
- access/schedule effective path: `v4/v4`;
- reconciliation дважды: `issues=[]`;
- пять public readiness samples: average `0.0939 s`, max `0.1362 s`;
- API restarts/runtime errors/Caddy 5xx: `0/0/0`;
- остаточных restore DB/directories: `0/0`.

## Граница приёмки

Технический server rollout завершён. Client build и update manifests остаются
`1.5.1+181`. Матрица owner mega-UAT и `INT-S6` остаются открытыми до реальной
пользовательской приёмки всех обязательных сценариев.
