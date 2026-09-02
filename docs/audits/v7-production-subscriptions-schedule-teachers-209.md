# MagicMusicCRM `1.5.29+209` — production release evidence

Дата выпуска: 2026-09-02. Прямая команда владельца: выпускать в production,
если готовность подтверждена.

Release commit: `229b8a6fd725e486f92947004987cebe6021350c`.
Rollback commit: `6f5c146bc250e7f0f1f52e944d46b88b845128f6` (`1.5.28+208`).

## Выпущенные изменения

- Бессрочный абонемент выбран по умолчанию; срок показывается после снятия
  флажка, бессрочная покупка сохраняет `expiresAt=null`.
- Постоянное расписание материализуется на весь заданный диапазон независимо
  от остатка абонемента. Покрытие распределяется по датам, покрытые занятия
  выделяются зелёным. Проверен диапазон пятниц 01.09–01.12.2026: 13 занятий,
  первые 12 покрыты абонементом на 12 посещений.
- Занятие из ленты загружается по точному ID с учеником и версией. Преподаватель,
  филиал, кабинет и тип списания редактируются через существующие signed
  preview/commit команды, включая прошедшие занятия. Корректировки сохраняют
  append-only историю; новая ставка берётся из справочника на дату занятия.
- По умолчанию используется стандартная ставка преподавателя. Отдельное окно
  преподавателей в Аналитике показывает проведённые занятия, типы начислений
  и суммы за выбранный период, включая пресеты недели, месяца и года.
- Каноническое направление обучения корректно восстанавливается в карточке
  клиента после сохранения и повторного открытия.

## Проверки кандидата

- Flutter full: `1492/1492`; analyze: PASS.
- Backend full: `277/277` suites, `3657/3657` tests; typecheck/build: PASS.
  Полный прогон выполнен на отдельной локальной PostgreSQL test DB с лимитом
  Node heap 8 GiB. Первоначальный незавершённый прогон в итог не включён.
- Deploy/DB/behavior и backup/restore compatibility contract gates: PASS.
- Production-like и exact-image gates: invalid configuration fail-closed,
  healthy live/ready, degraded readiness HTTP 503, migration `0145`,
  reconciliation `issues=[]`: PASS.
- RepoWise change risk: high из-за объёма и распределения изменений. Вывод
  проверен по исходникам; выполнены полные тесты и интеграционные проверки
  транзакций, RBAC, версий, идемпотентности и финансовых корректировок.
- Security gate: `11 PASS / 0 WARN / 0 FAIL`; npm audit: `0` vulnerabilities.
  Обновлены совместимые транзитивные зависимости. Semgrep OWASP: `77` rules,
  `1217` files, `0` findings. Trivy exact image: `0` High/Critical, `0` secrets.
- Gitleaks release diff: `0`. Текущий tracked snapshot: 6 ложных совпадений
  (идентификатор commit, имя прежнего образа, тестовые idempotency keys и
  искусственный невалидный токен). Full history: 173 исторических совпадения;
  ранее принятое владельцем исключение из `v7-final-candidate.md` сохраняется.
  Allowlist не расширялся, история не переписывалась.
- Windows portable/Setup: `1.5.29+209` / `1.5.29.209`; launch smoke PASS.
  APK: `magic.crm`, versionCode `209`, versionName `1.5.29`, SDK 24/36,
  signature v2 PASS; AAB: `jar verified`. Подключённого Android-устройства
  не было; новый device smoke не заявляется. Старый Android depfile со
  ссылками на отсутствующий диск удалён, APK/AAB собраны заново.

## Production и откат

Candidate image: `magicmusiccrm-server:1.5.29-209-229b8a6fd725`, ID
`sha256:aee7deaf574eed311c26356fdb712fff07320249346ae5f9c5df5c68e77f9e1f`.
Rollback image: `magicmusiccrm-server:1.5.28-208-6f5c146bc250`.

Guarded cutover: `DEPLOY_API_RELEASE|PASS`. Новых миграций нет, migration head
остаётся `0145_student_contact_email`. Образ и OCI revision/version совпали
локально и на сервере. Runtime: `magiccrm`, healthy, restart `0`, OOM `false`.
Live/ready и reconciliation повторно проверены после выпуска; `issues=[]`.
Due/poison lessons, unpublished/dead-letter events, due/fresh exhausted emails:
все `0`. Production monitor PASS после окна наблюдения и публикации клиентов.

Точного активного production-примера с `valid_from=2026-09-01`,
`valid_until=2026-12-01`, weekday=5 нет. Проверка 13/12 выше относится к
интеграционному сценарию, а не к ручному изменению клиентских данных.

Pre/post encrypted backup и sidecar сохранены off-host в
`C:\Users\Alinka\Documents\MagicMusicCRM Backups\2026-09-02`.
Оба прошли isolated candidate/rollback restore с чистой reconciliation;
production volumes и финансовая история при проверке не изменялись.

| Backup | Bytes | SHA-256 |
|---|---:|---|
| `magicmusiccrm-staging-20260902T193259Z.tgz.enc` | 233264 | `6e2a246e4b51553f9afd064168d607a7520bbfd2e43b424045baf55db227c749` |
| `magicmusiccrm-staging-20260902T193645Z.tgz.enc` | 234320 | `1208e55bbc860143bbdb3f5cb64aabc208f9798330a0f11e42bcc3afdaba946b` |

Rollback использует сохранённый образ `208` и не выполняет down migration.
Release/rollback overrides и guarded script находятся в
`/opt/magicmusiccrm/releases/1.5.29-209-229b8a6fd725/`.
Снимок прежних client manifests и release history:
`/opt/magicmusiccrm/releases/client-manifest-rollback-208-20260902T193644Z`.

## Публикация клиентов

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `MagicMusicCRM-1.5.29-209-windows-x64.zip` | 19792131 | `93d0d58003d7108105764d0232ad5bf099da6d747d6962ea3e759bca38dac6b7` |
| `MagicMusicCRM-1.5.29-209-Setup.exe` | 15565466 | `dc0da53adf42219336f34caa91866ad38931b853801eb8466b37628cf5a0c23f` |
| `MagicMusicCRM-1.5.29-209.apk` | 87681312 | `1590a35a739bf28d3b53f4a687f689d465b6a7fc70c9a76ab4b0d933ee8998a8` |
| `MagicMusicCRM-1.5.29-209.aab` | 61288589 | `82b729ef988dbd56ea374393e659881deaefbdf2e4e0da6a096d486ef85ab638` |

`latest.json` и `latest-v2.json` показывают `1.5.29+209`, release history
начинается с build `209`. Все четыре public artifacts повторно прочитаны
через HTTPS; длина и SHA-256 совпали. GitHub assets проверены по size/digest.
Git tag `v1.5.29` указывает на release commit. Release опубликован:
https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.29.

Локальные журналы проверок: ignored `dist/release209/`.
