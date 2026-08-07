# V7 — финальная перепроверка 26 пунктов ТЗ

**Дата:** 2026-08-07
**Кандидат:** `1.5.1+157`
**Источник:** `pasted-text.txt`, пункты 1–26
**Решение:** **ENGINEERING PASS 26/26; PRODUCTION ACCEPTANCE BLOCKED**

## Итог без приукрашивания

Все 26 пунктов имеют production UI или, где требование чисто серверное, авторитетный backend-contract. Изменения карточки, расписания, финансов, задач, конфигурации и ролей подтверждены реальными рендерами Windows/Android. Пять production-аккаунтов и повторный вход проходят.

Но текущий развёрнутый API отстаёт от кандидата. На реальном директоре 2026-08-07 подтверждены `404` для:

- `GET /crm/clients/student/:id/internal-note`;
- `GET /crm/clients/student/:id/operational-history`;
- `GET /crm/schedule-plans?clientType=student&clientId=:id`.

Эти endpoints есть и проходят tests в текущем `server/`, но отсутствуют на `api.magicmusiccrm.ru`. Поэтому приложение **нельзя честно назвать окончательно готовым production-кандидатом до синхронного deployment backend/migrations**. Визуальные симптомы сохранены в [Windows LIVE](v7-26-point-ui-evidence/windows/01-live-release-window.png) и [Android Lessons LIVE](v7-26-point-ui-evidence/android/15-client-lessons-live.png).

## Матрица 1–26

| # | Требование | Фактическое подтверждение | Статус |
|---:|---|---|---|
| 1 | Вкладки, per-tab history, связанные сущности, горизонтальный scroll | [LIVE desktop shell](v7-26-point-ui-evidence/windows/01-live-release-window.png), real-account role screenshots; compact direct-link regression | **PASS** |
| 2 | Конструктор CRM, обязательные ФИ/телефон/источник, CRUD options | [Lead form LIVE](v7-26-point-ui-evidence/android/16-lead-create-required-fields-live.png), [fields/options](v7-26-point-ui-evidence/windows/configuration-fields-option-sets.png) | **PASS** |
| 3 | Полная карточка ученика как центр CRM | [desktop long canvas](v7-26-point-ui-evidence/windows/windows-client-workspace-overview.png), [compact LIVE](v7-26-point-ui-evidence/android/06b-student-card-overview-live.png) | **PASS локально / BLOCKED prod API** |
| 4 | Каталог/выдача/замена/отмена абонемента и остаток | [mobile purchase LIVE](v7-26-point-ui-evidence/android/13-subscription-purchase-expanded-live.png), [replace](v7-26-point-ui-evidence/windows/subscription-replace-financial-impact.png), [cancel](v7-26-point-ui-evidence/windows/subscription-cancel-financial-impact.png) | **PASS** |
| 5 | Скидка, способ оплаты, рассрочка и история | [purchase LIVE](v7-26-point-ui-evidence/android/12-subscription-purchase-form-live.png), [payments LIVE](v7-26-point-ui-evidence/android/14-client-payments-default-collapsed-live.png), [status/reversal](v7-26-point-ui-evidence/windows/compact-client-payments.png) | **PASS** |
| 6 | Создать расписание из карточки ученика | [card Lessons LIVE](v7-26-point-ui-evidence/android/15-client-lessons-live.png), [plan editor](v7-26-point-ui-evidence/windows/recurring-plan-editor-required-fields.png) | **PASS локально / BLOCKED prod API** |
| 7 | Постоянные расписания, строки, недели, active/ended, tray | [active tray](v7-26-point-ui-evidence/windows/recurring-plan-active-tray.png), [end impact](v7-26-point-ui-evidence/windows/recurring-plan-end-impact.png) | **PASS локально / BLOCKED prod API** |
| 8 | Обязательные поля занятия и server validation | [required plan/lesson fields](v7-26-point-ui-evidence/windows/recurring-plan-editor-required-fields.png), backend constraint suites | **PASS** |
| 9 | Разделить Lead и Student lesson/create semantics | Отдельные [Lead](v7-26-point-ui-evidence/android/16-lead-create-required-fields-live.png) и [Student](v7-26-point-ui-evidence/android/17-student-create-fields-live.png) flows; typed `ClientRef` contracts | **PASS** |
| 10 | Рабочее время/недоступность преподавателя | [schedule settings](v7-26-point-ui-evidence/windows/settings-teacher-branch-availability.png) + backend availability constraints | **PASS** |
| 11 | Привязка преподавателя к филиалам | Тот же [settings render](v7-26-point-ui-evidence/windows/settings-teacher-branch-availability.png) + branch constraint tests | **PASS** |
| 12 | Collision Engine: student/teacher/room/branch/interval/concurrency | [Day calendar LIVE](v7-26-point-ui-evidence/android/08-schedule-day-live.png), conflict counters and backend concurrency suites | **PASS** |
| 13 | Отдельное расписание преподавателя Day/Week, read-only scope | [real Teacher account](v7-26-point-ui-evidence/windows/real-role-2-teacher-schedule.png), [Day calendar LIVE](v7-26-point-ui-evidence/android/08-schedule-day-live.png) | **PASS** |
| 14 | Общий календарь, фильтры, free slots, links, move | [Month LIVE](v7-26-point-ui-evidence/android/07-schedule-live.png), [Day LIVE](v7-26-point-ui-evidence/android/08-schedule-day-live.png), [move preview](v7-26-point-ui-evidence/windows/lesson-reschedule-reason-preview.png) | **PASS** |
| 15 | Задачи all-day и временное окно у Lead/Student | [audience/deadline preview](v7-26-point-ui-evidence/windows/task-audience-preview.png) | **PASS** |
| 16 | Исполнитель: человек/филиал/вся школа | [exact recipients preview](v7-26-point-ui-evidence/windows/task-audience-preview.png) | **PASS** |
| 17 | Persistent overdue reminder до закрытия | [overdue/close render](v7-26-point-ui-evidence/windows/task-overdue-explicit-close.png), [LIVE notification center](v7-26-point-ui-evidence/android/21-notification-center-live.png) | **PASS** |
| 18 | Явное закрытие задачи | [close action](v7-26-point-ui-evidence/windows/task-overdue-explicit-close.png) + one-close-fact API tests | **PASS** |
| 19 | Уведомлять о внешней заявке, не о ручном Lead | [notification UI LIVE](v7-26-point-ui-evidence/android/21-notification-center-live.png); inbound/manual event separation backend tests | **PASS** |
| 20 | Статусы учеников, counts и drilldown для руководства | [Students board LIVE](v7-26-point-ui-evidence/android/03-clients-students-live.png), [dashboard LIVE](v7-26-point-ui-evidence/android/19-director-dashboard-export-live.png) | **PASS** |
| 21 | Директор отключает capability Управляющего | [capability editor](v7-26-point-ui-evidence/windows/settings-manager-capability-access.png), Actor Matrix | **PASS** |
| 22 | Только директор архивирует; impact и finance block/preservation | [archive impact preview](v7-26-point-ui-evidence/windows/client-archive-impact-preview.png) + archive PostgreSQL/RBAC suites | **PASS** |
| 23 | Стабильная связь Lead→Student и видимый переход | [badge «Лид→Ученик»](v7-26-point-ui-evidence/windows/client-lead-student-link.png) + conversion-link tests | **PASS** |
| 24 | Автоматическое завершение занятия без ручной команды | [quick view без «Завершить»](v7-26-point-ui-evidence/windows/lesson-quick-view.png) + completion worker replay/poison tests | **PASS** |
| 25 | Валидный XLSX | [XLSX actions](v7-26-point-ui-evidence/windows/director-dashboard-xlsx-export.png) + OOXML workbook validation tests | **PASS** |
| 26 | Перестроенный раздел «Занятия» и карточка без разрозненных дублей | [desktop card](v7-26-point-ui-evidence/windows/windows-client-workspace-overview.png), [compact tabs LIVE](v7-26-point-ui-evidence/android/15-client-lessons-live.png), [active tray](v7-26-point-ui-evidence/windows/recurring-plan-active-tray.png) | **PASS локально / BLOCKED prod API** |

## Что дополнительно нашла эта перепроверка

1. **Исправлено:** compact direct route в карточку клиента перетирался восстановленным состоянием доски. Теперь входящий canonical link применяется после restore; добавлен regression test.
2. **Исправлено:** desktop-форма замены абонемента падала с `BoxConstraints forces an infinite height`. Убран `stretch` у строки сравнения пакетов; Windows integration test повторно зелёный.
3. **Исправлено в acceptance test:** analytics device-test ждал удалённую вкладку `Каталог`; теперь проверяет фактическую единую IA `Обзор / Журналы` и XLSX actions.

## Gates

- `flutter analyze` — PASS.
- `flutter test` — **645/645 PASS**.
- Backend `npm run typecheck` — PASS.
- Backend `npm run build` — PASS.
- Backend full Jest — **155/155 suites, 1237/1237 tests PASS**.
- Generated inventories — v6 routes `22`, reachable `261`, unowned `0`; v7 finance sites `255`, lesson writes `7`, unowned `0` — PASS.
- Real production accounts `magic1..5` — **5/5 roles PASS** on Windows runner.
- Secure restart/logout/switch/same-account login — PASS.
- Android release update-over-install — session preserved; compact direct link opens after fix.
- Final signed APK `1.5.1+157` installed with `adb install -r` — PASS; authenticated session remained active ([final device capture](v7-26-point-ui-evidence/android/22-final-apk-session-live.png)).
- Production API health — `200`; three required v7 routes above — `404`.

## Release artifacts

- Android APK: `build/app/outputs/flutter-apk/app-release.apk`, 84,606,473 bytes, SHA-256 `C0DC2C0DC5BEE953F67F06E05BF9A8F2A5F81ECD8528ECC190CBFD66370D3115`.
- APK signature: v2 verified, RSA 2048, certificate `CN=Magic Music CRM, OU=Release, O=Nazarova Natalia IP, L=Moscow, C=RU`.
- Windows EXE: `build/windows/x64/runner/Release/magic_music_crm.exe`, 757,760 bytes, SHA-256 `6D3A505358815CB625929E88DD857F25D3E03BEA0C795A56C0788810C64801E3`.

## Release decision

**Не выпускать публичное обновление только фронтенда.** Сначала развернуть соответствующую текущему commit версию backend и migrations, затем повторить LIVE rows 3/6/7/26 на Windows и Android. Локальная инженерная реализация 26 пунктов подтверждена; интеграционная production-приёмка пока заблокирована объективным version skew.
