# Журнал изменений - .anws v3

> Этот файл фиксирует изменения архитектурной версии v3.

## 2026-06-10 - Инициализация

- [ADD] Создана версия `.anws/v3` для перехода на собственный backend.
- [ADD] Зафиксирована стратегия big-bang cutover с обязательной репетицией миграции и rollback reference.
- [ADD] Добавлены security gates и Linear-ready task blueprint.

## 2026-06-16 - Desktop UX/UI audit backlog

- [ADD] Зафиксирован Windows manager UX/UI audit в `docs/audits/windows-ux-ui-2026-06-16/report.md`.
- [ADD] В `.anws/v3/05_TASKS.md` добавлен `S8 - Desktop UX/UI Stabilization` с задачами `T8.1`-`T8.4` и acceptance gate `INT-S8`.
- [ADD] Audit backlog синхронизирован с текущим stabilization stream в Linear (`Magic Music CRM` / parent `KVA-117`).

## 2026-06-17 - S6 closure and S7 launch start

- [UPDATE] `INT-S6` закрыт по user acceptance staged Android/Windows v3 smoke evidence; S6 отмечен завершенным этапом.
- [UPDATE] S7 переведен в активную launch-closure волну; `T7.3` started, `T7.4`/`INT-S7` остаются открытыми до production cutover evidence.
- [UPDATE] S7 scope clarified: HolliHop was one-time data extraction only, credential rotation and API domain migration are not planned now, and `api.phantom-net.ru` remains the current public v3 API endpoint.
- [NOTE] S7 preflight: `security:gate` fixed for ignored local env files and now passes `7/4/0`; HTTPS health passes with HTTP/1.1/TLS1.2 and from staging host/container.
- [DONE] `T7.3`, `T7.4` and `INT-S7` closed after final health, auth/realtime, private file, email-provider and restart rollback smokes on `api.phantom-net.ru`.

## 2026-07-18 - Four-role Android demo workflow

- [ADD] По прямому запросу владельца добавлен `S9` с задачами `T9.1`-`T9.4` и acceptance gate `INT-S9` для взаимосвязанного демо ролей Ученик, Преподаватель, Администратор и Управляющий на четырёх Android-эмуляторах.
- [RULE] Зафиксирована бизнес-последовательность владельца: пробное занятие, ДЗ и сбор обратной связи выполняются, пока клиент остаётся лидом; конверсия в ученика происходит только при выдаче абонемента, после чего назначается обычное постоянное расписание.
- [ADD] В scope включены безопасный точечный reset `magic1@gmail.com`, немедленный PUSH о пробном при свёрнутом приложении, пятисекундные визуальные паузы, строгая привязка ролей к именам AVD и возобновляемый Appium-runner без сохранения паролей.
- [NOTE] Изменение классифицировано как controlled expansion: системные границы, ADR и публичная v3-топология не меняются; задачи уточняют уже существующие CRM, schedule, homework, notification и Android smoke contracts.
