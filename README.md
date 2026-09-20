# Magic Music CRM

Закрытая CRM для сети музыкальных школ: клиенты и лиды, расписание занятий,
абонементы и оплаты, задачи, мессенджер и отчётность. Клиент написан на Flutter,
backend — NestJS/PostgreSQL. Интерфейс — на русском языке; единая светлая тема —
Quiet Graphite & Sophisticated Gold.

## Версии и статус

README актуализирован 20 сентября 2026 года по исходникам и документации репозитория.

| Область | Зафиксированное состояние |
| --- | --- |
| Версия клиента в исходниках | `1.5.43+223`, см. [pubspec.yaml](pubspec.yaml) |
| Последний документированный production-выпуск | `1.5.42+222` от 16 сентября 2026 года, tag `v1.5.42` |
| Схема этого production-выпуска | `0156_trial_lesson_catalog` |
| Приёмка выпуска 222 | Windows clean-install/upgrade UAT пропущен по решению владельца; Android проверен на локальной Debug-сборке, проверка подписанного релиза на физическом устройстве не заявляется |

Версия в исходниках не подтверждает публикацию. Текущая передача, ограничения
и сведения о восстановлении находятся в
[NEXT-AGENT-HANDOFF.md](docs/architecture/NEXT-AGENT-HANDOFF.md),
доказательства выпуска — в [аудите 222](docs/audits/release-222-production.md).
Указанный статус взят из этих документов; обновление README не включает live-проверку production.

## Архитектура

```text
Flutter / Riverpod / GoRouter
        |
        v
NestJS API / backend RBAC / Socket.IO
        |
        +--> PostgreSQL (состояние, история, audit/outbox)
        +--> private file storage
```

Redis также описан в инфраструктурном Docker Compose. Для приведённого ниже
локального запуска API используется PostgreSQL. Supabase сохранён для legacy
export/import tooling и не является runtime-зависимостью Flutter; HolliHop
используется как backend-only источник импорта.

- UI обращается к существующим services/providers; shared state — Riverpod.
- Backend проверяет права и область доступа к ресурсам.
- Денежные команды и операции с занятиями сохраняют транзакции, контроль версии,
  идемпотентность, audit/outbox и неизменяемую историю фактов.
- Организационные сущности с историческими связями закрываются через
  preview/blockers/commit и архивирование.

Подробности: [архитектурные решения](docs/architecture/CURRENT-DECISIONS.md)
и [продуктовые правила](docs/product/CURRENT-PRODUCT-RULES.md).

## Структура репозитория

| Путь | Назначение |
| --- | --- |
| `lib/` | Flutter-приложение: общие компоненты, API, providers и функциональные разделы |
| `test/`, `integration_test/` | Клиентские unit/widget и интеграционные проверки |
| `server/src/`, `server/db/` | NestJS API, фоновые обработчики, тесты и SQL-миграции |
| `infra/`, `scripts/` | Инфраструктура, backup, сборка, release и smoke-инструменты |
| `docs/` | Продуктовые правила, архитектура, тестирование, runbooks и release evidence |

Точки входа: [lib/main.dart](lib/main.dart) и [server/src/main.ts](server/src/main.ts).

## Локальный запуск на Windows

Нужны Flutter с Dart, совместимым с `^3.11.1`, Node.js 24/npm и PostgreSQL 17.
Команды ниже используют Docker Compose для локальной БД. Для Flutter Windows
должны быть установлены инструменты desktop-сборки; готовность проверяет `flutter doctor`.
Все команды выполняются из корня репозитория в PowerShell.

1. Установите зависимости и создайте локальный конфигурационный файл, если его ещё нет:

   ```powershell
   flutter pub get
   npm --prefix server ci
   if (-not (Test-Path server/.env)) {
     Copy-Item server/.env.example server/.env
   }
   ```

   Проверьте `server/.env` по [шаблону](server/.env.example): `DATABASE_URL` и
   `MIGRATION_DATABASE_URL` должны указывать на локальную БД. Реальные env-файлы,
   секреты и персональные данные не коммитятся. Email/push и внешние интеграции
   требуют отдельной настройки провайдеров; шаблон не содержит их ключей.

2. Запустите локальный PostgreSQL и примените миграции:

   ```powershell
   docker compose -f server/docker-compose.test.yml up -d --wait
   $env:MIGRATION_DATABASE_URL = 'postgresql://magiccrm_owner:magiccrm_owner@localhost:54329/magiccrm'
   npm --prefix server run db:migrate
   Remove-Item Env:MIGRATION_DATABASE_URL
   ```

   Адрес соответствует проектному [Compose-файлу](server/docker-compose.test.yml)
   и предназначен только для локальной разработки. Если проектная БД уже работает
   на порту `54329`, повторно поднимать её не нужно. Мигратор читает переменные
   процесса и самостоятельно не загружает `server/.env`; для другого локального
   экземпляра замените адрес и согласуйте его с настройками API.

3. Запустите API и оставьте терминал открытым:

   ```powershell
   npm --prefix server run start:dev
   ```

4. Во втором терминале проверьте API и запустите клиент:

   ```powershell
   Invoke-RestMethod http://localhost:3000/api/health
   flutter run -d windows --dart-define=MAGIC_API_BASE_URL=http://localhost:3000/api --dart-define=MAGIC_PROFILE=local
   ```

   `MAGIC_API_BASE_URL` явно выбирает локальный backend: без него клиент по умолчанию
   использует production API. `MAGIC_PROFILE=local` отделяет локальную сессию от
   обычного профиля. Для проверки готовности БД и фоновых обработчиков доступен
   `/api/health/ready`. Запуск API не заменяет подготовку локальных учётных записей
   и данных для пользовательских сценариев.

## Проверка изменений

Для обычной правки запускайте затронутые тесты. Примеры из корня репозитория:

```powershell
flutter test test/core/api/payment_contract_test.dart
npm --prefix server test -- --runTestsByPath src/auth/session-postgres.integration.spec.ts
```

Полный набор проверок кода:

```powershell
flutter analyze
flutter test
npm --prefix server run typecheck
npm --prefix server run test:full
npm --prefix server run build
```

Серверным тестам нужен локальный PostgreSQL из инструкции выше. Runner создаёт
мигрированный шаблон и отдельную БД на каждый suite; полный gate отклоняет
skipped/pending/todo и неполный набор. Настройки изоляции, режим без внешней БД
и coverage описаны в [TESTING.md](docs/engineering/TESTING.md).

Полный набор тестов не заменяет release gate и пользовательскую приёмку.
Сквозные сценарии описаны в [RELEASE-JOURNEYS.md](docs/engineering/RELEASE-JOURNEYS.md).
Исторические результаты проверок относятся только к проверенному кандидату.

## Работа с репозиторием

Начните с [AGENTS.md](AGENTS.md). RepoWise — основной инструмент навигации по
коду и оценки риска; локальный индекс не коммитится.

Настройка на новой машине:

```powershell
repowise init --no-prose --no-agents --no-claude-md --codex --no-editor-setup
repowise doctor
```

После серии структурных изменений:

```powershell
repowise update --index-only
```

Если индекс использует `mock`, отключён семантический поиск или уверенность
низкая, вывод сверяется с живым исходником. Процесс описан в
[REPOWISE-WORKFLOW.md](docs/engineering/REPOWISE-WORKFLOW.md).

## Эксплуатация и документация

Production и deploy изменяются только по прямой команде владельца, со свежим
backup, проверяемым планом восстановления и post-deploy reconciliation.
Финансовая, учебная и audit-история сохраняется.

- [Текущая передача и production/UAT](docs/architecture/NEXT-AGENT-HANDOFF.md).
- [Продуктовые правила и RBAC](docs/product/CURRENT-PRODUCT-RULES.md).
- [Архитектурные решения](docs/architecture/CURRENT-DECISIONS.md).
- [Инфраструктура и развёртывание](infra/staging/README.md).
- [Операционные runbooks](docs/runbooks/).
