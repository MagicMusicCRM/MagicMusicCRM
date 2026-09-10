# Тесты: запуск, изоляция и границы покрытия

Полный серверный gate из корня репозитория:

```powershell
npm --prefix server run test:full
```

Он проверяет сам test harness, затем запускает все `server/src/**/*.spec.ts`.
Успех требует ненулевого числа тестов, полного совпадения с найденным набором,
отсутствия skipped/pending/todo, неизменности проверяемых исходников за время
прогона и успешной очистки временных БД. `test.only` приводит к пропускам и не
проходит gate. `--full` не принимает выбор файлов, фильтр имени, замену Jest
config/environment, sharding, watch или `--passWithNoTests`.

## Команды для повседневной работы

| Задача | Команда из корня |
| --- | --- |
| Полный серверный набор и его coverage | `npm --prefix server run test:full -- --coverage` |
| Отдельные серверные файлы с изоляцией БД | `npm --prefix server test -- --runTestsByPath src/auth/session-postgres.integration.spec.ts` |
| Явная выборка без PostgreSQL | `npm --prefix server test -- --no-database --runTestsByPath src/contracts/expense-contract.spec.ts` |
| Все обычные клиентские тесты | `flutter test --no-pub --coverage` |
| Сквозной Windows/HTTP/PostgreSQL/restore сценарий | `node scripts/http-journey-check.cjs --release-journeys` |

`npm test` без аргументов также запускает весь серверный набор с изоляцией;
`test:full` дополнительно проверяет harness. Именованные команды
`test:actor-matrix:v4`, `test:schedule-v4`, `test:commerce-v4`, `test:tasks-v4`
и `test:export-v4` используют тот же runner, но остаются частичными выборками.
Прежний `test:watch`, обходивший изоляцию, удалён. Для быстрого повторного
запуска используется выбор файла; текущий gate не поддерживает watch.

В `--no-database` требуется явный список файлов. Известные PostgreSQL suites
отклоняются до запуска, а `pg.Pool`/`pg.Client` не могут открыть соединение
или выполнить запрос. Это проверка wire/unit-поведения, а не полный PASS.
PGlite и локальный HTTP-сервер contract harness могут использоваться этим
режимом: «без PostgreSQL» означает отсутствие внешней БД, а не запрет всех
локальных сетевых соединений или embedded SQL.

API-контракты запускаются через `scripts/check-api-contracts.ps1`.
Ключ `-Offline` сохраняет явный режим без БД; без ключа скрипт использует
ту же автоматическую изоляцию. Подробности: [API-CONTRACTS.md](API-CONTRACTS.md).

## Подготовка PostgreSQL

Нужен локальный PostgreSQL 17 и роль, которой разрешено создавать тестовые
БД и применять текущие миграции. Для стандартного локального окружения:

```powershell
docker compose -f server/docker-compose.test.yml up -d --wait
```

Если на localhost:54329 уже запущен проектный PostgreSQL, второй экземпляр
поднимать не нужно. По умолчанию runner подключается к служебной БД `postgres`
на этом порту с тестовой ролью из `docker-compose.test.yml`.

Другой **локальный** экземпляр задаётся только через `TEST_POSTGRES_ADMIN_URL`.
URL должен иметь loopback host, путь `/postgres`, без query-параметров и
fragment. `DATABASE_URL`, `MIGRATION_DATABASE_URL`,
`V4_PLATFORM_TEST_DATABASE_URL` и стандартные PG-переменные приложения не
выбирают базу для штатного runner. `.env` автоматически не загружается.

Механизм перенесён из проверенного release runner, а не реализует вторую
модель миграций: создаётся новая БД-шаблон, выполняются `MigrationRunner.up`
и существующий v4 backfill, затем отдельный клон на каждый Jest suite.
Каждая DB-suite получает адрес своего клона **до загрузки тестового файла**.
Изоляция действует между файлами; внутри файла порядок fixtures по-прежнему
должен контролировать сам тест. Чистая БД не отменяет необходимость проверять
транзакции, конфликт версий и конкуренцию в бизнес-сценариях.

Все имена содержат случайный идентификатор запуска. Очистка проверяет точную
принадлежность имени этому запуску. Никакая существующая пользовательская БД
не удаляется. После обычной ошибки, SIGINT/SIGTERM или неудачного teardown
runner пытается очистить оставшиеся клоны. Ошибка очистки даёт ненулевой код.
При принудительном завершении всего процесса/потере питания `finally` может
не выполниться; оставшиеся базы требуют отдельной проверки, а не удаления
всех баз с похожим именем.

## Что означает каждый уровень проверки

| Уровень | Что подтверждает | Что не подтверждает сам по себе |
| --- | --- | --- |
| Unit / таблица параметров | Правило для конкретных входов и отказов | Реальную транзакцию и пользовательский маршрут |
| Widget/device с fake API | UI-состояния, форму запросов, доступность элементов | Backend RBAC, актуальную схему и сохранение в БД |
| Embedded SQL / PGlite | Исполнение SQL и конкретную миграцию на заданной схеме | Все production constraints и межсоединительную конкуренцию |
| Мигрированный PostgreSQL / HTTP contract | Реальные SQL, ограничения, факты и wire-поведение выбранного harness | Все меню, роли, доставку push и установленный release-клиент |
| Real device journey | Выбранные UI-действия через HTTP и сохранённые результаты | Все остальные сценарии продукта и платформы |

Папка `integration_test` и слово `postgres` в имени не являются классификацией.
Перед использованием результата нужно прочитать fixtures и точки подмены.
Историческая схема в migration-тесте может быть намеренным входом; удалять
такой тест по возрасту нельзя. Границы employee journey зафиксированы в
[RELEASE-JOURNEYS.md](RELEASE-JOURNEYS.md).

## Минимальная карта критичных инвариантов

Это опорные тесты для изменений денег и занятий, а не полный перечень покрытия.
Пути в таблице даны относительно репозитория.

| Инвариант | Опорная проверка | Дополнительный уровень |
| --- | --- | --- |
| Повтор оплаты сохраняет один эффект и согласованный текущий ответ | `server/src/contracts/payment-http-postgres.integration.spec.ts` | `test/core/api/payment_contract_test.dart`, `integration_test/employee_journey_live_test.dart` |
| Неопределённый сетевой результат не повторяет произвольную запись автоматически | `test/core/api/magic_api_retry_test.dart` | Потеря ответа после commit в employee journey |
| Недостаточное финансирование не создаёт списание и начисление преподавателю | `server/src/crm/schedule/completion-worker-postgres.integration.spec.ts` | Состояние pending, audit/outbox, два завершения на одном счёте |
| Замена абонемента сохраняет израсходованную стоимость, долг и историю | `server/src/crm/commerce/subscription-full-volume-replacement.spec.ts` | `server/src/crm/commerce/subscription-replace-postgres.integration.spec.ts` |
| Текущая серверная роль и scope ограничивают доступ даже со старой identity | `server/src/access-control/actor-matrix-postgres.integration.spec.ts` | revoked-role HTTP checks и `server/src/crm/schedule/student-lesson-membership-postgres.integration.spec.ts` |

При изменении правила нужны assertions для наблюдаемого результата и отказа,
а для денежных команд — повтора, конфликта/конкуренции и сохранённой истории.
Число вариантов данных не заменяет эту карту: в текущем наборе один preview
codec даёт больше тысячи случаев, но остаётся проверкой одного семейства
протоколов. Удаление дублей допустимо только после сравнения входов, результата
и дефекта, который способен обнаружить каждый тест.

## Результаты и coverage

Каждый серверный запуск создаёт отдельный каталог
`server/coverage/test-runs/<runId>/`. В нём:

- `summary.json`: режим full/selection/offline, источник SHA-256, число случаев,
  причины отказа, самые большие suites и результат очистки;
- `jest-results.json`: исходный результат Jest с конкретными assertions;
- `suite-results.json`: случаи и длительность по файлам, без смешивания их
  с числом бизнес-сценариев;
- `jest-config.json`: конфигурация этого запуска;
- `coverage/`: свежий coverage, только если передан `--coverage`.

Каталог игнорируется Git; его сохранённый PASS относится только к данному
источнику и окружению. Source hash учитывает server source/tests, миграции,
инструменты, manifests/lock-файл и общие contracts. Отдельные coverage-отчёты
разных запусков не следует складывать без проверки идентичности источников.
Старые `coverage/lcov.info` не являются сегодняшним baseline.

Для проверки точности guard используются отрицательные примеры. Тест
`test/architecture/icon_tooltip_guard_test.dart` проверяет чужую подпись,
вложенный tooltip, комментарии, именованные/const/new конструкторы и
пустые/null подписи. Production inventory проверяет собственный аргумент
кнопки через AST; вычисляемые подписи всё ещё требуют widget semantics checks.
`visual_baseline_test.dart` проверяет layout/tokens/reduced motion, а не
пиксельное сравнение с golden. Screenshots без comparator не считаются
автоматическим контролем визуальной регрессии.
