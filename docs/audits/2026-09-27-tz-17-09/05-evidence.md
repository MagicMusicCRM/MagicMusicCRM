# Реестр источников и активных цепочек

Все пути ниже относительно `C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM`; номера строк относятся к HEAD `69b4c14d65788703fef2bde3e44ee2c1e0f086df`. Символы и строки — ориентиры, следующий агент обязан перечитать актуальный код. E-ID связывает сценарий с цепочкой, но не заменяет V-ID фактического запуска.

## E-01 — Входящий и ручной лид, уведомления

`lib/main.dart:215` → `lib/core/services/lead_notification_listener.dart:22`: app-level listener подключён в реально используемом приложении, desktop only. Условие lead/created, роли admin/manager/director, sound-policy по активному разделу. Поля события в `lib/core/services/crm_realtime_provider.dart:8` не различают ручной/внешний источник.

Ручное действие: форма → `lib/core/services/magic_crm_service_leads.dart` → `server/src/crm/lead-command.service.ts:110` → изменение/audit/outbox → немедленный lead/created:115 → listener. Update публикует updated; именно ручной create доказывает F-01. Внешний вход: `server/src/crm/clients/inbound-lead.service.ts:39` создаёт inbound.lead.created → `server/src/platform/platform-outbox.worker.ts:132` вызывает notifyInboundLead, затем публикует CRM-событие. В том же worker:299/308 универсальная классификация entity/action не является фильтром происхождения.

V-03: `inbound-lead-postgres.integration.spec.ts` подтверждает доменный вход/дедупликацию на PostgreSQL. Реальная доставка toast/push/звук, workers и полное приложение здесь NOT RUN. Task-created listener в том же Dart-файле:55 — отдельный канал, AMB-01.

## E-02 — Пробные, перенос и оперативная лента

Доступ к лиду/карточке проверяется capability и серверным scope. В `lib/features/crm/presentation/client_card/client_card_desktop_dashboard.dart:262` _bookClientTrial открывает CreateLessonDialog с текущим лидом и initialIsTrial. `client_card_student.dart:199` редактирует урок; :234 создаёт пробный; :974 читает trials из серверной lead-card. Это активные части общего ClientCard, не автономные демо-виджеты.

UI → `lib/core/services/magic_crm_service_schedule.dart` → `server/src/crm/schedule/lesson-write-command.service.ts` / команды переходов → server policy + constraint engine + versioned mutation → lessons/переходы/audit/outbox → ответ и refresh client-card. Отмена сохраняет историю, не физически удаляет lesson.

Чтение lead: `server/src/crm/lead-card.service.ts:286` (фильтры successor/cancelled:307–308). Чтение student: `server/src/crm/schedule/student-lesson-timeline.repository.ts:132` вычисляет successor, :197–198 возвращает исходный и actionable ID, :291 не исключает предшественников/cancelled. UI `lib/features/crm/presentation/client_card/student_lesson_timeline_controller.dart:100` dedup по ID; `recurring_schedule_plan_view.dart:760` фильтр по типу и :1053 ссылка на successor. `server/src/crm/schedule/lesson-transition-commit.service.ts:384` сохраняет переход; это не архивирование.

V-02: native CreateLessonDialog defaults/manual-pay/drag/filter/search PASS; lead OPEN PASS, CREATE FAIL предпосылки, EDIT/CANCEL BLOCKED. Отсутствие дубля в student timeline и полноценный multi-tab перенос не проверены UI.

## E-03 — Режимы расписания, доступность и ограничения

`lib/features/admin/presentation/widgets/schedule_widget_toolbar.dart` содержит переключение режимов; активные `schedule_widget_week_view.dart` и `schedule_widget_actions.dart` загружают недельный контекст. Недоступность отображается из тех же canonical references, но есть F-05. Поиск преподавателя в `lesson_editor/lesson_participant_section.dart:22` использует только active/assignedBranch; :249 сообщает о поздней проверке — F-06.

Карточка/редактор графика → `server/src/crm/schedule/availability.controller.ts` → `availability.service.ts` → `availability.rules.ts:90` + `availability.repository.ts:227` → teacher availability/assignment с версией. Несколько recurring-интервалов в день и отрицательные датированные правила уже поддержаны. endsAt=null разрешён для отрицательного правила; `constraint-engine.rules.ts:90` считает конец бесконечным. UI week:153 такой интервал пропускает.

Команды урока и плана используют `constraint-engine.service.ts` и PostgreSQL-конфликты: доступность, филиал, существующие уроки, смежность интервалов. Серверный guard необходим независимо от фильтра выбора. V-03 проверяет один содержательный интеграционный сценарий overlaps/adjacency/excludeLessonId/cross-branch; это не все call-sites. V-05 через настоящий UI director подтверждает 11 шагов редактора, сохранение/повторное открытие/stale conflict. Персонал→карточка→график этим прогоном не подтверждён.

## E-04 — Задачи, badge, результат и напоминания

`lib/core/workspace/production_workspace_host.dart:162` читает sectionUnseenProvider. `server/src/crm/section-views.service.ts:112` считает open canonical_tasks на текущий московский день, :121 ограничивает адресатом shared_task_recipients. Пометка раздела просмотренным не используется как критерий задач.

Активный экран `lib/features/manager/presentation/tasks/shared_tasks_view.dart` → shared_tasks_controller/data_source → `server/src/crm/shared-task.controller.ts` → `server/src/crm/tasks/shared-task.service.ts` и repository. Закрытие через `shared_task_close_dialog.dart`: обязательный result, Other-comment, disabled submit, ошибки не стирают диалог. Service:365–480 проводит versioned mutation/locking, завершает напоминания, пишет result/closedBy/closedAt/audit/outbox; :765 валидирует результат. Results-метод:267 и кнопка `shared_tasks_view.dart:163` ведут к `shared_task_results_panel.dart`, а не заглушке. Worker `shared-task-reminder.worker.ts` использует сохранённые reminders и устойчивые ключи доставки.

V-03:10 тестов, включая результат/Other и конкурентное закрытие. V-06: manager/director создают/редактируют/закрывают через shell, admin не может создать/редактировать, но читает и закрывает назначенную задачу. Badge20→15, журнал, UI-Other, доставка и midnight NOT RUN. Скриншот admin после закрытия показывает неправильную подсказку создать задачу при отсутствии права — F-09.

## E-05 — Покупка, платежи, покрытие и сроки

`lib/features/crm/presentation/client_card/client_card_student.dart:745` после успешной покупки перечитывает lead/student и меняет связанный mode, не закрывая карточку. `subscription_issue_controller.dart` → preview/commit через `lib/core/services/magic_crm_service_finance.dart` → `server/src/crm/subscription-commerce.controller.ts` → `subscription-purchase-command.service.ts` (текущие права/scope, версии/idempotency) → `subscription-purchase-persistence.service.ts:56`: subscription, отдельный ActualPayment, installments/obligations; `subscription-coverage.persistence.ts` поддерживает покрытие. Транзакционная граница принадлежит серверу.

`subscription_issue_pricing.dart:185` считает будущие платежи как count−1 при initial payment. `subscription_issue_form_sections.dart:98` передаёт future-only список; `subscription_issue_components.dart:374` рисует его — F-02. `server/src/crm/commerce/commerce-projection.repository.ts` возвращает future installments и dueKind forecast/actual/fixed; initial payment — отдельный факт, не «потерянная строка БД».

`server/src/crm/commerce/payment-lifecycle.repository.ts:157` материализует consumption due по paid coverage и `lesson_client_charge_facts_effective`, с защитой повтора. Расход считается по реальным фактам списания, не просто календарной дате. Worker запускает это отдельно; в HTTP-UI прогонах INSTALLMENT_DUE_WORKER выключен. Legacy-календарный режим не следует переписывать массово.

V-03:22 проверки финансового suite, среди них direct payment без wallet, due, immutable discount, права, rollback всех фактов, key mismatch/повтор/конкуренция. Тест consumption:1386 вставляет charge facts SQL, не проводит два урока UI. V-04: admin/manager/director × lead/student, cancel/purchase/reopen, сохранение 2000 на 7700 и частичное покрытие. Не доказывает точный пример 14400/7200/4, due-worker или третье занятие.

`client_card_display.dart:238` вычисляет отрицательное paid−price как долг — F-08. `client_card_student_tabs.dart:253` показывает actualPaymentsMinor счёта, что не равно всей оплате всех абонементов.

## E-06 — CRM stream и клиентское восстановление

`lib/core/services/crm_realtime_provider.dart:68` создаёт Socket.IO stream, :40 определяет fallback poll; staff poll30 секунд, client 5 минут. `lib/features/crm/presentation/client_card/client_card.dart:797` подписывает реальную карточку, :803 игнорирует poll.

`client_card_realtime.dart:15` определяет затронутые регионы; lesson/group обновляют карточку и контекст, scope ограничен текущим клиентом. Пакетирование, один inflight и dirty/TickerMode-защита сохраняют ввод. `client_card.dart:536` при возврате вкладки дренирует уже накопленные регионы, не восстанавливает пропущенные события — F-03.

`integration_test/live_audit_harness.dart:84` выполняет API-login, :102 использует InMemoryWorkspaceKeyValueStore, :106 подменяет CRM stream на empty. Поэтому HTTP и widgets реальные, но realtime, durable session и app-restart не проверены. Прямой API вызов для вторичного assert допустим, как замена основного пользовательского действия — нет.

## E-07 — Персонал и настройки

`lib/features/crm/presentation/staff_workspace_secondary_destination.dart:18` подключает PersonnelWorkspace по capability. `lib/features/admin/presentation/widgets/manage_entities_widget.dart:164` содержит master/detail преподавателей/сотрудников с существующими entities, :508 — сгруппированные настройки/поиск/visited IndexedStack, разрешённые вкладки зависят от прав.

`teacher_detail_content.dart:168` размещает график в карточке; `ScheduleReferenceSettings(initialTeacherId:...)` переиспользует существующий редактор, без второго хранилища занятости. Учительские и кадровые команды сохраняют текущие services/providers, версии и серверные права; административное управление доступом не следует из права читать базовые данные.

V-05 доказал standalone Settings→teacher availability для director на высоком viewport. Это не UI-приёмка полноценного Personnel пути, всех полей Staff/Teacher или работы при 1366×768.

## E-08 — Карточка клиента и создание лида

`lib/features/crm/presentation/client_card/client_card_desktop_dashboard.dart` — активная непрерывная desktop-композиция с action sidebar; данные поступают из lead/student card services, финансовое чтение отдельно по capability. Предыдущая секционная композиция 225 отменена решением владельца; восстановление её не требуется.

`lib/features/crm/presentation/client_forms/client_create_dialogs.dart` использует primary predicate required||category и секцию дополнительной информации. Дополнительные значения сохраняются в draft, валидационная ошибка раскрывает секцию. Форма идёт через существующий MagicCrmService/LeadCommandService, не локальную имитацию.

V-04 визуально подтверждает открытую карточку после покупки на 1440×1100: левую колонку действий, заметку, основной контент/абонемент/финансы. Это не доказательство «всё видно без скролла» на любом устройстве. Маленькая высота, масштаб 125%, keyboard/focus/ошибка autosave, все карточки и новый lead NOT RUN.

## E-09 — Единая визуальная семантика урока

`lib/core/widgets/lesson_settlement_corner.dart` сохраняет legacy-имя, но строит полную decoration, backgroundFor:54 использует типовые семантические AppColor; это не старый уголок. Живые вызовы в `lib/features/admin/presentation/widgets/`: `schedule_day_canvas_widgets.dart:153`, `schedule_month_view.dart:367`, `schedule_teacher_timeline.dart:691`; также `lib/features/crm/presentation/client_card/recurring_schedule_plan_view.dart:1092`. Перед изменением повторно найти все вызовы `rg -n 'LessonSettlementCorner|backgroundFor' lib`.

`lesson_state_palette.dart` задаёт lifecycle-значок и предупреждение покрытия, не новую заливку completed. D-01 имеет приоритет над буквальным P050. V-02 показывает день/drag только admin; вся комбинация тип×состояние×экран не была визуально проверена. Название класса само по себе не свидетельствует об остаточном corner.

## E-10 — Автооплата преподавателя и явное ручное редактирование

`lib/features/admin/presentation/widgets/lesson_editor/lesson_financial_section.dart:382` использует compensationTouched/checkbox, блокирует поля до opt-in; `lesson_financial_autofill.dart` вычисляет default при изменении типа. Повторяющийся план имеет аналогичный guard в `preferred_schedule_editor_view.dart:492`, решение по уроку — `lesson_decision_sections.dart:406`; настройки ставок используют requireRateConfirmation.

Данные идут через существующие lesson/plan commands и persist rules, не только состояние checkbox. V-02 DEFAULT/MANUAL/DRAG подтверждают default, включение override и сохранение ручного значения после drag для одиночного trial admin. Полный спектр recurring/edit/type-switch и запрет неуполномоченному пользователю не запускался.

## Сохранённые артефакты

[verification-results.json](evidence/verification-results.json) содержит выбранные поля настоящих result.json и native steps без токенов/fixture payload. [source-artifact-manifest.json](evidence/source-artifact-manifest.json) связывает их с исходными файлами запуска и SHA-256. Это извлечение, а не новый результат теста. Полные логи локально в `outputs/tz-audit-2026-09-27`, исходные runner-артефакты в `dist/http-journeys/<runId>`; при переносе checkout их может не быть, команды приведены отдельно.

| Скриншот | Что наблюдалось |
|---|---|
| [Пробный, отказ филиала](evidence/lead-trial-admin-CREATE.png) |22:00+60 минут за пределами работы; F-07 |
| [Расписание после drag](evidence/customer-revisions-admin-DRAG.png) |Настоящая поверхность расписания Windows, V-02 |
| [Покупка и повторное открытие](evidence/partial-purchase-admin-lead-REOPEN.png) |Оплата 2000, остаток 5700 назван долгом; F-08 |
| [Сохранённая занятость](evidence/teacher-availability-director-INTERVAL-SAVE.png) |Настройки director, конечный запрет 09–18, высокий viewport |
| [Задача admin после закрытия](evidence/tasks-admin-TASKS-ADMIN-CLOSE.png) |Shell и success; недоступное предложение «Создайте задачу», F-09 |

Все пять скриншотов сохранены с синтетическими данными изолированного runner и визуально просмотрены. Скриншоты DOCX с исходными персональными данными в этот каталог не копировались.
