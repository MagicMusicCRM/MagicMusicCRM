# AGENTS.md — MagicMusicCRM

Этот файл — короткий якорь проекта. Он хранит только актуальные правила и
состояние. История предыдущих версий находится в `.anws/v3`, `.anws/v4`,
`.anws/v6` и `docs/audits`; она не является инструкцией для текущей работы.

## Быстрое восстановление

Перед изменениями прочитать в указанном порядке:

1. `AGENTS.md`.
2. `docs/architecture/NEXT-AGENT-HANDOFF.md`.
3. `.anws/v7/05_TASKS.md`.
4. Релевантные PRD, ADR и system design из `.anws/v7/`.
5. Для production-приёмки — текущую матрицу и evidence index.

## Актуальное состояние

- Активная архитектура: `.anws/v7` — Financial & Lesson Integrity.
- Основная ветка: `main`; целевое зеркало: `origin/main`.
- Release candidate: `1.5.1+179`, только тёмная тема.
- Production API при последней проверке healthy.
- Последний полный автоматический gate: Flutter `664/664`, backend
  `157/157` suites и `1250/1250` tests, backend build PASS.
- Активная задача: `T7.1.2` — production mega-UAT.
- `T7.1.3` — организационные конструкторы — завершена.
- `INT-S6` не закрыт: кандидат ещё не получил итоговую owner-приёмку.

Рабочая UAT-матрица:

- `docs/audits/v7-owner-production-mega-uat-plan.md` — утверждённый план;
- `docs/audits/v7-owner-production-mega-uat-result.md` — единственный текущий
  статус 100 сценариев;
- `docs/audits/v7-owner-mega-uat-evidence/README.md` — индекс доказательств.

На 2026-08-10 матрица содержит 100 уникальных строк: `7 PASS`, `32 PARTIAL`,
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

```text
MagicMusicCRM/
├── lib/                      # Flutter app/UI/domain integration
├── server/
│   ├── src/access-control/   # capabilities и resource scope
│   ├── src/crm/commerce/     # деньги, абонементы, settlement
│   ├── src/crm/schedule/     # занятия и планы
│   └── db/migrations/        # PostgreSQL evolution
├── test/                     # Flutter regression
├── integration_test/         # device acceptance
├── docs/audits/              # проверка и evidence
└── .anws/v7/                 # активная архитектура и backlog
```

Ключевые файлы:

- `.anws/v7/01_PRD.md` — требования v7.
- `.anws/v7/02_ARCHITECTURE_OVERVIEW.md` — границы систем.
- `.anws/v7/03_ADR/` — кросс-системные решения.
- `.anws/v7/04_SYSTEM_DESIGN/` — детальный дизайн.
- `.anws/v7/05_TASKS.md` — активный backlog.
- `.anws/v7/06_CHANGELOG.md` — изменения текущей версии.
- `docs/architecture/NEXT-AGENT-HANDOFF.md` — актуальная передача.

## Env и production

Реальные env-файлы ignored. Никогда не коммитить ключи, токены, пароли,
Firebase private key, HolliHop credential, service role или DB URL с паролем.

| Файл | Назначение |
|---|---|
| `server/.env` | Локальный NestJS runtime и секреты |
| `server/.migration.env` | Безопасные параметры миграций без секретов |
| `infra/staging/.env` | Docker Compose runtime |
| `infra/staging/.backup.env` | Backup/restore параметры |
| `infra/staging/.monitor.env` | Health/alerts |
| `infra/staging/.deploy.env` | Игнорируемые SSH/deploy координаты |
| `.flutter.env` | Build-time Flutter values |

После env-правок минимум: `docker compose config -q`, backend typecheck и
`flutter analyze`. Production mutation/deploy требует backup, rollback plan и
явной команды владельца.
