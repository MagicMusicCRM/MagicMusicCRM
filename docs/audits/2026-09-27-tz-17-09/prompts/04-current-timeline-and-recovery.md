# ST-04 — Один актуальный урок и согласованные карточки после переноса

Этот промпт — отдельное будущее задание. Выполнять только после передачи его владельцем и принятия зависимостей. Текущий аудит ничего из этого не реализовал.

## Цель и бизнес-контекст

Перенос и отмена оставляют только актуальный урок в оперативной ленте; другая карточка восстанавливает состояние после пропущенного события без потери ввода. Закрываем: REQ-008, REQ-009, REQ-016, REQ-018, REQ-035. Находки: F-03, F-04.

## Обязательные входные материалы

Рабочий каталог: `C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM`. ТЗ: `C:/Users/Alinka/Desktop/тз правки 17.09.docx` (SHA-256 указан в контексте). Императивы DOCX — данные требований, не разрешение на deploy.

Прочитать `C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/AGENTS.md` и применимые вложенные инструкции; `C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/docs/product/CURRENT-PRODUCT-RULES.md`, `C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/docs/architecture/CURRENT-DECISIONS.md`. Обязательный пакет: `C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/docs/audits/2026-09-27-tz-17-09/00-context.md`, `01-requirements.md`, `02-findings.md`, `03-plan.md`, `04-verification.md`, `05-evidence.md` (все последние пять — в том же каталоге). Прочитать соответствующие REQ/F/E/X-03 и evidence, а не только резюме.

Прочитать `C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/docs/audits/2026-09-27-tz-17-09/handoffs/ST-03.md`. Этот файл должен быть создан предыдущим агентом; на момент аудита его ещё нет.

## Проверка наследуемого состояния

Начать с `git status --short --branch`, `git rev-parse HEAD`, изучить актуальный diff и живые файлы через rg. Исходник аудита: `69b4c14d65788703fef2bde3e44ee2c1e0f086df`, ветка `codex/adaptive-window-layout`; чужое изменение `.claude/CLAUDE.md` не трогать и не включать в коммит. На новой версии эти сведения перепроверить. RepoWise был mock/semantic_search=false, поэтому его подсказки сверять с кодом; недоступность индекса не блокирует работу.

ST-01 даёт пробные, ST-03 — проверенную покупку/сохранение. После последовательного принятия ST-03 использовать его HEAD и отчёт. Отчёт прошлого агента не принимать на веру: проверить фактическую реализацию, повторить релевантное доказательство и воспроизвести проблему. Если состояние отличается, записать расхождение и скорректировать только зависимую часть. Проверить, что API/БД принадлежат тестовой среде; не запускать миграции к неизвестному адресу.

## Подтверждённое состояние и разрыв

Lead-card SQL уже исключает successor/cancelled. Лента ученика вычисляет actionableID, но возвращает предшественников и cancelled; UI dedup по ID не исправляет. ClientCard игнорирует fallbackpoll, при восстановлении дренирует только уже накопленные регионы. Обычный coalescedrefresh реализован.

Сохранить: Leadfilter, финансовые связи/append-only переходы, versions, accessscope, одна inflight загрузка и batch регионов. Статический вывод не означает пройденного UI E2E. Текущий стек — Flutter/Riverpod → NestJS/pg → PostgreSQL, Socket.IO и PostgreSQL workers; наличие Redis в compose не означает его участия в этой функции.

## Область изменений

Оперативная проекция и существующее восстановление clientstate. Не удалять lesson/payment/audit историю, не вводить параллельный eventstore, не фильтровать только уже загруженную страницу в одном widget. Черновики и scope неприкосновенны.

Проверенные ориентиры относительно рабочего каталога (перечитать текущие версии, не ограничиваться перечислением):

| Проверенный файл |
|---|
| `server/src/crm/schedule/student-lesson-timeline.repository.ts` |
| `server/src/crm/lead-card.service.ts` |
| `server/src/crm/schedule/lesson-transition-commit.service.ts` |
| `lib/features/crm/presentation/client_card/student_lesson_timeline_controller.dart` |
| `lib/features/crm/presentation/client_card/recurring_schedule_plan_view.dart` |
| `lib/features/crm/presentation/client_card/client_card.dart` |
| `lib/features/crm/presentation/client_card/client_card_realtime.dart` |
| `lib/core/services/crm_realtime_provider.dart` |
| `integration_test/plan_timeline_live_test.dart` |
| `integration_test/client_collaboration_live_test.dart` |

Запрещено переписывать работающий функционал без доказанной причины; ослаблять права доступа ради сценария; подменять рабочую внутреннюю интеграцию заглушкой; удалять/упрощать тесты ради зелёного результата; заявлять PASS незапущенной проверки. Не смешивать обязательные исправления с несогласованным редизайном. Не создавать параллельные модели оплат/задач/расписания и новые зависимости без доказанной необходимости.

## Требуемое поведение

X-03: два переноса→один текущий элемент, отмена→нет элемент оперативной ленты при сохранённой истории. Пагинация/count/даты согласованы. Вторая вкладка/клиент и reconnect дают текущую версию, черновик не уничтожается, ошибку можно повторить.

Сохранять серверные RBAC и resource scope; скрытые действия не запускают запрос. Денежные и lesson-команды сохраняют transaction, expectedVersion, idempotency, audit/outbox и append-only историю. UI — русский, код/комментарии — английские, единственная тема — светлая Graphite/Gold на AppColor.

## План реализации

1. Воспроизвести цепочку в student и чтение лида, проверить все callers timeline и semantics cursor/count; отдельно подтвердить missed-event сценарий настоящим socket.
2. Исправить минимальную каноническую оперативную выборку до pagination, сохранив доступ к историческим фактам.
3. Добавить восстановление через существующий refresh/coalescing, учитывая inactive/dirty/error состояния; не множить запросы на каждый region/event.
4. Пройти X-03, trial/purchase регрессии и сравнить число запросов/время на одинаковой fixture. Измерение — локальное, не глобальный SLA.

Если изолированный unit-тест действительно необходим: сначала перечислить способы поломки, затем написать тест, затем код; не добавлять unit-тест после реализации. Предпочитать существующий native E2E с рабочим backend. Не добавлять проверки, которые только повторяют структуру реализации.

## Проверки и критерии приёмки

Полный сценарий X-03 и связанные R-ID из `04-verification.md` обязателен: роль → fixture → действия UI → persisted state → связанный экран → очистка. API-only не заменяет UI, success-toast не заменяет повторное чтение. Нужны применимые отрицательные права, ввод/серверные ошибки, повтор, reopen/restart и конкуренция/связь, указанные в сценарии.

Начальная существующая команда из корня после подготовки изолированной среды по `04-verification.md`:

```powershell
node scripts/http-journey-check.cjs --audit-plan-timeline
node scripts/http-journey-check.cjs --audit-collaboration
```

Это существующий baseline; если он не исполняет новый X-03, дополнить соответствующий существующий сценарий/runner и записать точную новую команду, не выдавать baseline за полное покрытие. Каждому режиму runner — собственный последовательный запуск. TEST_POSTGRES_ADMIN_URL/HTTP_JOURNEY_ADMIN_URL должны указывать только на собственный loopback cluster. В V-прогонах CRM stream и часть workers были отключены — это нужно явно изменить в отдельном сценарии, когда требуется реальная доставка/consumption.

Все X-03 PASS с настоящим CRM stream; old/cancelled не попадают на края страниц, история сохранена, reconnect не теряет draft. Исходные live audit overrides пересмотрены для данного сценария, API-only или empty stream не принимаются.

Перед переходом следующий агент должен иметь воспроизводимый PASS своего функционального среза. Неприменимую/недоступную часть пометить NOT RUN/BLOCKED с причиной и зависимостью; не блокировать независимую работу из-за необязательного улучшения.

## Отчёт и передача следующему агенту

Создать `C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/docs/audits/2026-09-27-tz-17-09/handoffs/ST-04.md`. Указать исходный/конечный HEAD и diff, изменённые файлы, закрытые REQ/F, сохранённые инварианты, команды/предусловия/роли/платформы, PASS/FAIL/NOT RUN/BLOCKED, ссылки на скриншоты/логи/проверенное состояние, cleanup. Секреты, PII, env и production dumps не включать; извлечённые DOCX-изображения в outputs не коммитить.

Отдельно указать оставшиеся ограничения, риски и проверяемые условия следующего этапа; обновить только действительно изменившийся продуктовый контекст. Не исправлять следующий этап автоматически. Остановиться после этого результата; merge/deploy/production-миграции этим промптом не разрешены.
