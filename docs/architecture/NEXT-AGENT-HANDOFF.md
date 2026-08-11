# MagicMusicCRM — актуальная передача

> Обновлено: 2026-08-11
> Production: client `1.5.1+181`, server `b04f177`,
> image `sha256:6e8fc887…`, migration `0118`
> Рабочая ветка: `codex/v7-production-readiness`
> Статус: production rollout PASS; owner mega-UAT не завершён

## Быстрый старт

1. Прочитать `AGENTS.md` и проверить `git status --short --branch`.
2. Использовать RepoWise для ответа на конкретный вопрос по коду. При
   low-confidence/mock результате подтвердить ответ живым исходником.
3. Если задача касается приёмки, открыть:
   - `docs/audits/v7-owner-production-mega-uat-result.md`;
   - `docs/audits/v7-owner-mega-uat-evidence/README.md`.
4. Если задача касается найденных пробелов продукта, открыть
   `docs/audits/2026-08-11-repowise-application-audit.md`.

Не нужно читать глобальный backlog, проходить фазовый workflow или создавать
служебный отчёт до начала обычной правки.

## Честный production-статус

| Проверка | Результат |
|---|---:|
| Flutter | 667/667 |
| Backend | 158/158 suites, 1259/1259 tests |
| Backend build | PASS |
| Exact image runtime/security gate | PASS, Trivy 0 High/Critical/secret |
| Windows ZIP launch | PASS |
| Android 15/API 35 install/launch | PASS |
| UAT PASS | 10 |
| UAT PARTIAL | 29 |
| UAT PENDING | 61 |

`PARTIAL` не равен `PASS`. Приложение нельзя объявлять окончательно принятым,
пока обязательные строки не имеют итоговый статус и требуемые UI/API/DB
доказательства.

Production rollout build 181 прошёл encrypted off-host backup, isolated restore,
worker pause/resume, reconciliation и automatic rollback gate. Первый кандидат
server hotfix был отклонён runtime smoke и откатан; исправленный `b04f177`
прошёл повторный gate.

Evidence:

- `docs/audits/v7-production-rollout-181.md`;
- `docs/audits/v7-production-rollout-server-hotfix-b04f177.md`;
- `docs/audits/v7-teacher-compensation-181.md`.

## Главный незавершённый продуктовый блок

Организационный контур create-centric:

| Сущность | Сейчас | Не хватает |
|---|---|---|
| Branch | list/create/update | close preview, blockers, archive, history, restore |
| Room | list/create/update/soft-delete | usage preview, active-link guards, restore |
| Group | list/create/update/members | end/archive с обработкой plans/future lessons |
| Teacher | create/update | status UI и атомарный offboarding |
| Staff | create/update/status | отзыв account/sessions/access вместе со статусом |
| Branch discipline | add/restore/reorder | unassign/archive action |
| Discipline/loss reason | list/create | rename/archive/restore и usage guard |

Физический cascade delete филиала недопустим: схема смешивает `CASCADE`,
`SET NULL` и restrict/default references, а финансовая, учебная и audit-история
должна оставаться неизменяемой. Нужен canonical
`preview → remediation/blockers → commit` с состояниями
`active → closing → archived` и tombstone-записью Branch.

## Следующая работа

1. Реализовать organization decommission flow, начиная с Branch preview/close.
2. Сделать Room delete usage-aware и добавить restore.
3. Реализовать Group end/archive.
4. Объединить Staff/Teacher status, branch assignments, будущую работу и отзыв
   sessions/access в один offboarding flow.
5. Добавить новые owner-UAT строки для lifecycle, затем продолжить оставшиеся
   `PENDING/PARTIAL` сценарии.
6. Перед следующим release проверить, что `origin/main` воспроизводит
   production-reachable код.

## Стоп-условия

Остановить mutation/release при финансовом drift, утечке прав, дубле эффекта,
необъяснённом 5xx или невозможности восстановить backup. Не исправлять такие
состояния ручной очисткой production-истории.
