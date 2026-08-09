# V7 — каталог визуальных доказательств 26 пунктов ТЗ

Дата съёмки: **2026-08-07 — 2026-08-09**. Актуальная проверенная
сборка: **1.5.1+167**; ранние файлы каталога сохраняют исторические
состояния предыдущих сборок.

## Уровни доказательств

- `LIVE` — установленное приложение работает с `https://api.magicmusiccrm.ru/api` и реальным аккаунтом директора.
- `REAL ACCOUNT` — полный `MagicMusicApp` запущен на Windows с реальными аккаунтами `magic1..5@gmail.com`; API настоящий, сборка тестовая.
- `DEVICE RENDER` — production-виджеты приложения реально отрисованы Windows integration runner; данные детерминированы, чтобы показать редкие состояния без изменения production-данных.

Скриншоты не являются макетами и не сняты из HTML-прототипа.

## Windows

| Файл | Уровень | Что подтверждает |
|---|---|---|
| `01-live-release-window.png` | LIVE, исторический blocker | rail, вкладки, Back/Forward, breadcrumb и прежний 404 до синхронизации backend |
| `02-postdeploy-client-lessons-live.png` | LIVE post-deploy | production-раздел «Занятия», корректный empty state, без 404 |
| `03-postdeploy-client-overview-live.png` | LIVE post-deploy | production-карточка, заметка, rail, вкладки и breadcrumb без 404 |
| `lead-status-menu-compact-live.png` | LIVE, Admin | список статусов ограничен пятью видимыми строками и имеет собственную прокрутку |
| `lead-board-status-refreshed-live.png` | LIVE, Admin | карточка лида сразу перемещена в колонку «Успешный» после сохранения без устаревшего кэша |
| `lead-card-system-fields-live.png` | LIVE, Admin | реальные филиал, рекламный источник и ответственный находятся в основной карточке |
| `lead-blacklist-reason-dialog-live.png` | LIVE, Admin | причина вводится до добавления клиента в чёрный список |
| `lead-blacklisted-state-live.png` | LIVE, Admin | активное ограничение и точная причина видны в карточке |
| `lead-blacklist-removed-live.png` | LIVE, Admin | ограничение снято, UI подтверждает действие |
| `lead-operational-history-live.png` | LIVE, Admin, `1.5.1+167` | после снятия ограничения история сохраняет действие, точную причину, автора и время; отсутствие причины показано без технических маркеров |
| `lead-status-history-live.png` | LIVE, Admin, `1.5.1+167` | все реальные переходы статуса лида и их автор видны в длинной карточке |
| `real-role-1-client.png` … `real-role-5-director.png` | REAL ACCOUNT | пять реальных ролей и capability-проекция оболочки |
| `real-role-2-teacher-schedule.png` | REAL ACCOUNT | отдельный read-only маршрут расписания преподавателя |
| `windows-client-workspace-overview.png` | DEVICE RENDER | длинная desktop-карточка, заметка, секционные действия, история с причиной |
| `compact-client-payments.png` | DEVICE RENDER | три статуса оплаты, личный счёт и техническая история в compact UI |
| `client-calendar-hide-others-default.png` | DEVICE RENDER | чекбокс «Скрывать чужие занятия» включён по умолчанию |
| `client-calendar-show-others-highlight.png` | DEVICE RENDER | занятие клиента зелёное, чужое нейтральное |
| `recurring-plan-active-tray.png` | DEVICE RENDER | активные/завершённые постоянные расписания и tray занятий |
| `recurring-plan-editor-required-fields.png` | DEVICE RENDER | обязательные преподаватель, аудитория, решение списания и оплаты |
| `recurring-plan-end-impact.png` | DEVICE RENDER | завершение расписания с причиной и impact preview |
| `lesson-quick-view.png` | DEVICE RENDER | quick view занятия и связанные сущности |
| `lesson-reschedule-reason-preview.png` | DEVICE RENDER | перенос с обязательной причиной и финансовым preview |
| `subscription-active-card-actions.png` | DEVICE RENDER | действия абонемента находятся в профильном разделе |
| `subscription-cancel-financial-impact.png` | DEVICE RENDER | отмена с финансовым результатом, причиной и подтверждением |
| `subscription-replace-financial-impact.png` | DEVICE RENDER | атомарная замена пакета и расчёт долга |
| `task-audience-preview.png` | DEVICE RENDER | исполнитель: человек/филиал/школа и точный preview получателей |
| `task-overdue-explicit-close.png` | DEVICE RENDER | непропускаемая просрочка и явное закрытие задачи |
| `settings-teacher-branch-availability.png` | DEVICE RENDER | рабочие часы, филиал и назначение преподавателя |
| `settings-manager-capability-access.png` | DEVICE RENDER | директор меняет capability Управляющего с кодом причины |
| `configuration-fields-option-sets.png` | DEVICE RENDER | конструктор CRM и единые «Варианты для полей» |
| `configuration-lesson-payment-catalogs.png` | DEVICE RENDER | независимые типы списания и оплаты преподавателю |
| `client-archive-impact-preview.png` | DEVICE RENDER | проверка зависимостей и сохранение финансовых фактов перед архивом |
| `client-lead-student-link.png` | DEVICE RENDER | стабильная связь и видимый badge «Лид→Ученик» |
| `director-dashboard-xlsx-export.png` | DEVICE RENDER | единая аналитика и явные XLSX/Finance XLSX actions |

## Android 15 / API 35

Все файлы в `android/` — `LIVE`, сняты с установленного приложения и реального директора.

- `01-director-shell-live.png` — мобильная capability-проекция.
- `02-clients-leads-live.png`, `03-clients-students-live.png` — одинаковый UI Лидов/Учеников, поиск, фильтры, колонки и FAB.
- `05-post-update-session-live.png` — сессия пережила установку новой APK поверх старой.
- `06b-student-card-overview-live.png` — compact-карточка и тематические вкладки.
- `07-schedule-live.png`, `08-schedule-day-live.png` — Месяц/Неделя/День, фильтры, аудитории, свободно/занято/конфликты.
- `10-subscriptions-live.png` … `13-subscription-purchase-expanded-live.png` — каталог, покупка, другой плательщик, личный счёт/рассрочка, скидка и доплата.
- `14-client-payments-default-collapsed-live.png` — суммы и финансовые блоки, свёрнутые по умолчанию.
- `15-client-lessons-live.png` — адаптивный раздел занятий; также фиксирует deployment-разрыв расписаний.
- `16-lead-create-required-fields-live.png`, `17-student-create-fields-live.png` — отдельные формы и обязательные системные поля.
- `18-director-dashboard-export-live.png`, `19-director-dashboard-export-live.png` — реальная мобильная аналитика, статусы и drilldown.
- `21-notification-center-live.png` — центр уведомлений и просроченные задачи.
- `22-final-apk-session-live.png` — финальный подписанный APK установлен поверх прежней версии; директорская сессия и production-данные сохранены.
- `23-postdeploy-student-overview-live.png` — production-карточка после backend sync; заметка и основные поля загружены без 404.
- `24-postdeploy-client-lessons-live.png` — production-раздел занятий после backend sync; корректный empty state постоянных расписаний без 404.
- `25-teacher-session-preserved-167.png` — подписанный APK `1.5.1+167`: реальный вход `magic2`, затем холодный перезапуск; Teacher-сессия, «Расписание» и «Ученики» сохранены, fatal/ANR/`E/flutter` = 0.

## Проверки кандидата 1.5.1+167

- Flutter: `flutter analyze` — PASS; `flutter test` — **656/656**.
- Backend: typecheck/build — PASS; Jest — **157/157 suites, 1248/1248 tests**.
- Production: backup `pre-client-history-20260809T175624Z.sql.gz`, deploy без миграций, `/api/health` — `ok`.
- Android: `versionCode=167`, `versionName=1.5.1`, APK Signature Scheme v2 — PASS, SHA-256 `497AD124E471CFC494853189AE920E96EE7715259038B5A024FC3F54EED8FCA0`.
