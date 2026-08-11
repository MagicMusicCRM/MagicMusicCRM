# Magic Music CRM

Magic Music CRM — private production CRM для сети музыкальных школ. Клиент
написан на Flutter, backend — NestJS/PostgreSQL; Redis и Socket.IO обеспечивают
worker/realtime-контур. Интерфейс русский, production-тема только тёмная.

## Текущее состояние

Обновлено: 2026-08-11.

- Production client: `1.5.1+181`.
- Production API: `https://api.magicmusiccrm.ru/api`.
- Server revision: hotfix `b04f177`, exact image `sha256:6e8fc887…`.
- Production migration: `0118`.
- Последний полный baseline: Flutter `667/667`; backend `158/158` suites,
  `1259/1259` tests; backend build PASS.
- Owner mega-UAT не завершён: `10 PASS`, `29 PARTIAL`, `61 PENDING`.
- Обнаружен незавершённый organizational lifecycle: филиалы и группы можно
  создавать, но нельзя штатно закрыть; room delete не проверяет активные связи;
  offboarding Staff/Teacher не атомарно отзывает доступ.

Подробный актуальный статус:
`docs/architecture/NEXT-AGENT-HANDOFF.md`.

## Архитектура

```text
Flutter / Riverpod / GoRouter
        |
        v
NestJS API / backend RBAC / Socket.IO
        |
        +--> PostgreSQL (canonical state and append-only facts)
        +--> Redis (worker/realtime coordination)
        +--> private file storage
```

Supabase сохранён только для legacy export/import tooling и не является runtime
зависимостью Flutter. HolliHop используется как backend-only источник импорта.

Основные решения: `docs/architecture/CURRENT-DECISIONS.md`.
Продуктовые инварианты: `docs/product/CURRENT-PRODUCT-RULES.md`.

## Структура репозитория

```text
lib/                 Flutter application
test/                Flutter unit/widget tests
integration_test/    Flutter integration smoke
server/              NestJS API, workers, migrations and tests
infra/               Docker, Caddy, backup and deployment tooling
scripts/             Release, inventory and smoke helpers
docs/                Current rules, runbooks, audits and release evidence
```

## Локальный запуск

Требуются Flutter stable, Node.js/npm, PostgreSQL и Redis. Реальные env-файлы
ignored и не должны попадать в Git.

```powershell
flutter pub get
npm --prefix server ci
npm --prefix server run start:dev
flutter run --dart-define=MAGIC_API_BASE_URL=http://localhost:3000/api
```

Перед локальным запуском backend подготовьте ignored `server/.env` по
актуальному deployment/runbook-контексту. Не копируйте production secrets в
документацию или shell output.

## Проверка

Для обычной правки запускайте только затронутый тест. Полный baseline:

```powershell
flutter analyze
flutter test
npm --prefix server run typecheck
npm --prefix server test
npm --prefix server run build
```

Release и production используют отдельные scripts/runbooks, backup, rollback и
reconciliation. Наличие успешных unit-тестов само по себе не закрывает owner
UAT.

## RepoWise

RepoWise — единственный активный code-intelligence слой проекта. Локальный
индекс не коммитится.

Для новой машины:

```powershell
repowise init --no-prose --no-agents --no-claude-md --codex --no-editor-setup
```

После структурных изменений:

```powershell
repowise update --index-only
```

Правила использования без лишней церемонии:
`docs/engineering/REPOWISE-WORKFLOW.md`.

## Актуальные документы

- `AGENTS.md` — короткие правила для агентов.
- `docs/architecture/NEXT-AGENT-HANDOFF.md` — production/UAT и ближайшие
  продуктовые пробелы.
- `docs/product/CURRENT-PRODUCT-RULES.md` — предметная модель и RBAC.
- `docs/architecture/CURRENT-DECISIONS.md` — действующие архитектурные решения.
- `docs/audits/2026-08-11-repowise-application-audit.md` — полный аудит
  приложения и незавершённых lifecycle.
- `docs/audits/v7-owner-production-mega-uat-result.md` — единственный текущий
  статус 100 UAT-сценариев.
- `docs/audits/v7-owner-mega-uat-evidence/README.md` — индекс доказательств.
- `docs/runbooks/` — операционные runbooks.
