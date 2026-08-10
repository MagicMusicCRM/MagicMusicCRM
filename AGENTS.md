# AGENTS.md — MagicMusicCRM

Этот файл хранит только актуальные правила и состояние. Исторические документы
не загружать без прямой связи с текущей задачей.

## Быстрое восстановление

Перед изменениями прочитать в указанном порядке:

1. Прочитать `AGENTS.md` и `docs/architecture/NEXT-AGENT-HANDOFF.md`.
2. Прочитать короткий `.nexus-map/INDEX.md`; большие JSON открывать только
   точечным запросом по нужному экрану, виджету, функции или endpoint.
3. В `.anws/v7/05_TASKS.md` открыть только определения активных
   `T7.1.2`/`INT-S6`, не весь завершённый backlog.
4. PRD, ADR, system design и исторические аудиты открывать только по затронутому
   домену.

## Актуальное состояние

- Активная архитектура: `.anws/v7` — Financial & Lesson Integrity.
- Основная ветка: `main`; целевое зеркало: `origin/main`.
- Production release candidate: `1.5.1+180`, только тёмная тема; exact server
  image `sha256:a07c39ff…` развёрнут 2026-08-10.
- Локальный unreleased candidate: `1.5.1+181`, commit `17ce254`, Teacher
  compensation refinement; production и update manifests не изменялись.
- Production API при последней проверке healthy на migration `0118`; worker
  активен, worker/outbox/reconcile drift `0`.
- Последний полный автоматический gate: Flutter `667/667`, backend
  `158/158` suites и `1258/1258` tests, backend build PASS. Exact production
  server image прошёл migration/live/ready/503 runtime gate и Trivy=0
  High/Critical/secret.
- Exact local `+181` image `sha256:5fbd5a29…` прошёл migration/fail-closed/
  live/ready/503 и Trivy=0; Windows ZIP и Android API 35 launch smoke PASS.
- Активная задача: `T7.1.2` — production mega-UAT.
- `T7.1.3` — организационные конструкторы — завершена.
- `INT-S6` не закрыт: кандидат ещё не получил итоговую owner-приёмку.
- Владелец 2026-08-10 принял unsigned Windows distribution и явно разрешил
  production backup/rollout. Rollout, новый encrypted off-host backup,
  isolated restore-check и автоматические rollback gates прошли.

Рабочая UAT-матрица:

- `docs/audits/v7-owner-production-mega-uat-plan.md` — утверждённый план;
- `docs/audits/v7-owner-production-mega-uat-result.md` — единственный текущий
  статус 100 сценариев;
- `docs/audits/v7-owner-mega-uat-evidence/README.md` — индекс доказательств.
- `docs/audits/v7-teacher-compensation-181.md` — технический audit локального
  кандидата `+181`, не заменяющий production owner-UAT.

На 2026-08-10 матрица содержит 100 уникальных строк: `10 PASS`, `29 PARTIAL`,
`61 PENDING`, `0 FAIL`, `0 BLOCKED`. Нельзя объявлять приложение окончательно
принятым, пока каждая обязательная строка не имеет итоговый статус и требуемые
UI/API/DB-доказательства.

## Реализованная предметная модель

- Один Flutter/NestJS/PostgreSQL runtime без второго ledger или event store.
- Append-only оплаты, сторно, возвраты, exclusions и техническая история.
- Три статуса оплаты: `Не оплачен`, `Проведён, ожидает подтверждения`,
  `Оплачен`.
- Покупка абонемента со своего или чужого личного счёта, скидка, доплата,
  рассрочка, полный резерв обязательства и отмена с корректным возвратом.
- Семь настраиваемых типов списания и пять независимых правил оплаты
  преподавателю; исторические snapshots неизменяемы.
- Единый reason + preview + commit flow для переноса, отмены и расчёта занятия.
- Именованные индивидуальные и групповые постоянные планы, conflict preview,
  обязательные преподаватель и аудитория, active/ended history и bounded tray.
- Каноническая карточка Lead/Student, staff note, комментарии, задачи,
  коммерция, расписание и entity-text navigation.
- Staff/Teacher создаются вместе с app user; старым сущностям доступ выдаётся
  атомарно; аудитории управляются внутри филиала.
- Одна task-модель. Teacher не является получателем staff-задач. Admin видит
  branch-scoped задачи и по умолчанию `Мои задачи + Сегодня`.

## RBAC

Иерархия: `client < teacher < admin < manager < director < system_admin`.

- Client видит только собственную область.
- Teacher видит назначенных учеников и своё расписание без staff-финансов.
- Admin: чат, расписание, клиенты и branch-scoped задачи read/close.
- Manager: операционный workspace назначенных филиалов, но без общешкольных
  финансов и финансовой аналитики.
- Director/system_admin: общешкольные финансы, конфигурация и управление
  доступами.
- Финансы конкретной карточки клиента доступны Admin/Manager/Director через
  узкие client-finance capabilities.
- Права проверяет backend capability/resource scope. Скрытый или запрещённый
  UI не должен запускать запрос.

## Источники истины

При конфликте использовать такой приоритет:

1. Последнее прямое решение владельца.
2. `.anws/v7/01_PRD.md`, ADR и system design v7.
3. Наблюдаемое поведение актуальной Release-сборки и production API/DB.
4. Текущий production-reachable код.
5. Исторические аудиты — только как доказательство прошлого состояния.

Старый PASS не подтверждает новый кандидат. Наличие endpoint, widget или теста
не доказывает, что пользовательский сценарий доступен через UI.

## Рабочие процессы

Если задача соответствует процессу, сначала прочитать файл из
`.agents/workflows/` и соблюдать его контрольные точки.

| Процесс | Назначение |
|---|---|
| `/quickstart` | Выбрать подходящий процесс |
| `/genesis` | Новая версия или изменение архитектурного базиса |
| `/probe` | Диагностика перед изменениями/приёмкой |
| `/design-system` | Детальный технический дизайн |
| `/blueprint` | Декомпозиция задач |
| `/change` | Локальное уточнение текущей версии |
| `/challenge` | Критика важного решения |
| `/forge` | Реализация и проверка |
| `/upgrade` | Миграция после обновления anws |

## Инженерные правила

1. Исправлять корневую причину в общей точке, сохраняя один канонический путь.
2. Не создавать параллельные модели оплат, задач, расписания или навигации.
3. Flutter UI работает через существующие services/providers; прямой доступ к
   БД или Supabase из widget запрещён.
4. Riverpod — основной state management для разделяемого состояния.
5. UI-текст — русский; код и комментарии — английские.
6. Единственная тема — Deep Charcoal & Sophisticated Gold; светлая тема,
   glow, яркие градиенты и legacy-стили не возвращаются.
7. Секреты, env, production dumps, backups и PII не коммитятся.
8. Денежные и lesson-команды сохраняют transaction, expected version,
   idempotency, audit/outbox и append-only факты.
9. Изменения проверяются минимальным релевантным тестом; release — полными
   gate, Windows/Android smoke и owner UAT.
10. Не удалять исторические финансовые факты и не чистить production вручную,
    чтобы скрыть дефект.

## Карта проекта

- `.anws/v7/01_PRD.md` — требования v7.
- `.anws/v7/02_ARCHITECTURE_OVERVIEW.md` — границы систем.
- `.anws/v7/03_ADR/` — кросс-системные решения.
- `.anws/v7/04_SYSTEM_DESIGN/` — детальный дизайн.
- `.anws/v7/05_TASKS.md` — активный backlog.
- `.anws/v7/06_CHANGELOG.md` — изменения текущей версии.
- `docs/architecture/NEXT-AGENT-HANDOFF.md` — актуальная передача.
- `.nexus-map/INDEX.md` — актуальная карта client/server кода.

## Env и production

Все реальные env-файлы ignored. Не коммитить секреты, PII, production dumps и
backups. После env-правок проверить Docker config, backend typecheck и Flutter
analyze. Production mutation/deploy требует backup, rollback plan и явной
команды владельца.
