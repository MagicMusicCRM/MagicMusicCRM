# V7 — финальная перепроверка 26 пунктов ТЗ

**Дата:** 2026-08-08
**Кандидат:** `1.5.1+158`
**Источник:** `pasted-text.txt`, пункты 1–26
**Решение:** **PRODUCTION PASS 26/26**

> **Актуализация evidence от 2026-08-08.** Старый набор иллюстраций ниже
> остаётся историей инженерной приёмки, но не используется как owner-demo:
> часть кадров была снята из debug-сборки. Исправленный owner-документ
> [MagicMusicCRM_26_правок_реальное_приложение_1.5.1.docx](../../outputs/MagicMusicCRM_26_правок_реальное_приложение_1.5.1.docx)
> содержит только Windows/Android Release, единственную тёмную тему и реальные
> production-данные. Все 24 страницы документа отрендерены и просмотрены.

## Итог без приукрашивания

Все 26 пунктов имеют production UI или, где требование чисто серверное,
авторитетный backend-contract. Найденный deployment-разрыв устранён: production
переведён с ревизии `0488e19` на `54759e0`, миграции `0102..0113` применены,
API healthy и проблемные v7 endpoints возвращают `200`. Полный deployment,
backup и rollback evidence: [v7-production-backend-sync.md](v7-production-backend-sync.md).

Повторные LIVE-кадры Windows и Android подтверждают, что карточка, заметка,
история и постоянные расписания больше не падают с `404`. Рабочие данные ради
демонстрации не изменялись: в production сейчас нет постоянных расписаний,
поэтому LIVE показан честный empty state, а active/ended/tray подтверждены
device renders и backend lifecycle tests.

## Матрица 1–26

| # | Требование | Фактическое подтверждение | Статус |
|---:|---|---|---|
| 1 | Вкладки, per-tab history, связанные сущности, горизонтальный scroll | [LIVE desktop shell](v7-26-point-ui-evidence/windows/03-postdeploy-client-overview-live.png), real-account role screenshots; compact direct-link regression | **PASS** |
| 2 | Конструктор CRM, обязательные ФИ/телефон/источник, CRUD options | [Lead form LIVE](v7-26-point-ui-evidence/android/16-lead-create-required-fields-live.png), [fields/options](v7-26-point-ui-evidence/windows/configuration-fields-option-sets.png) | **PASS** |
| 3 | Полная карточка ученика как центр CRM | [desktop LIVE post-deploy](v7-26-point-ui-evidence/windows/03-postdeploy-client-overview-live.png), [Android LIVE post-deploy](v7-26-point-ui-evidence/android/23-postdeploy-student-overview-live.png), [long canvas](v7-26-point-ui-evidence/windows/windows-client-workspace-overview.png) | **PASS** |
| 4 | Каталог/выдача/замена/отмена абонемента и остаток | [mobile purchase LIVE](v7-26-point-ui-evidence/android/13-subscription-purchase-expanded-live.png), [replace](v7-26-point-ui-evidence/windows/subscription-replace-financial-impact.png), [cancel](v7-26-point-ui-evidence/windows/subscription-cancel-financial-impact.png) | **PASS** |
| 5 | Скидка, способ оплаты, рассрочка и история | [purchase LIVE](v7-26-point-ui-evidence/android/12-subscription-purchase-form-live.png), [payments LIVE](v7-26-point-ui-evidence/android/14-client-payments-default-collapsed-live.png), [status/reversal](v7-26-point-ui-evidence/windows/compact-client-payments.png) | **PASS** |
| 6 | Создать расписание из карточки ученика | [Windows LIVE post-deploy](v7-26-point-ui-evidence/windows/02-postdeploy-client-lessons-live.png), [Android LIVE post-deploy](v7-26-point-ui-evidence/android/24-postdeploy-client-lessons-live.png), [plan editor](v7-26-point-ui-evidence/windows/recurring-plan-editor-required-fields.png) | **PASS** |
| 7 | Постоянные расписания, строки, недели, active/ended, tray | [LIVE empty state](v7-26-point-ui-evidence/android/24-postdeploy-client-lessons-live.png), [active tray](v7-26-point-ui-evidence/windows/recurring-plan-active-tray.png), [end impact](v7-26-point-ui-evidence/windows/recurring-plan-end-impact.png) | **PASS** |
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
| 26 | Перестроенный раздел «Занятия» и карточка без разрозненных дублей | [desktop LIVE](v7-26-point-ui-evidence/windows/02-postdeploy-client-lessons-live.png), [compact LIVE](v7-26-point-ui-evidence/android/24-postdeploy-client-lessons-live.png), [active tray](v7-26-point-ui-evidence/windows/recurring-plan-active-tray.png) | **PASS** |

## Что дополнительно нашла эта перепроверка

1. **Исправлено:** compact direct route в карточку клиента перетирался восстановленным состоянием доски. Теперь входящий canonical link применяется после restore; добавлен regression test.
2. **Исправлено:** desktop-форма замены абонемента падала с `BoxConstraints forces an infinite height`. Убран `stretch` у строки сравнения пакетов; Windows integration test повторно зелёный.
3. **Исправлено в acceptance test:** analytics device-test ждал удалённую вкладку `Каталог`; теперь проверяет фактическую единую IA `Обзор / Журналы` и XLSX actions.

## Gates

- `flutter analyze` — PASS.
- `flutter test` — **646/646 PASS**.
- Backend `npm run typecheck` — PASS.
- Backend `npm run build` — PASS.
- Backend full Jest — **155/155 suites, 1238/1238 tests PASS**.
- Generated inventories — v6 routes `22`, reachable `261`, unowned `0`; v7 finance sites `255`, lesson writes `7`, unowned `0` — PASS.
- Real production accounts `magic1..5` — **5/5 roles PASS** on Windows runner.
- Secure restart/logout/switch/same-account login — PASS.
- Android release update-over-install — session preserved; compact direct link opens after fix.
- Final signed APK `1.5.1+158` installed with `adb install -r` — PASS; authenticated session remained active.
- Production revision — `54759e0`; migrations — `114/114`, latest `0113`.
- Production API health — `200`; internal note, operational history,
  schedule plans/series и commerce — **5/5 `200`**.
- Production role matrix — **5/5**; Client → Director → Client relogin — PASS.
- Production reconciliation twice — identical digest, `issues=[]`.
- Post-deploy Windows/Android LIVE rows 3/6/7/26 — PASS; Android runtime error scan — `0`.

## Release artifacts

- Android APK: `build/app/outputs/flutter-apk/app-release.apk`, 84,606,277 bytes, SHA-256 `9F2114214689131BC19B57F89C8072A6973D654063E6B3834DCC7673B0725812`.
- APK signature: v2 verified, RSA 2048, certificate `CN=Magic Music CRM, OU=Release, O=Nazarova Natalia IP, L=Moscow, C=RU`.
- Windows EXE: `build/windows/x64/runner/Release/magic_music_crm.exe`, 757,760 bytes, SHA-256 `12CA092970EE14C1357954179A9EB05777AD8D07305159DB074E7C38641E91EC`.
- Owner DOCX: `outputs/MagicMusicCRM_26_правок_реальное_приложение_1.5.1.docx`, 3,279,685 bytes, SHA-256 `D37AD3C29B18D4538902A77149FB41921005E0244850D20E16D534F5F607F3A1`.

## Release decision

Backend и migrations синхронизированы, version skew устранён. Повторная LIVE
проверка rows 3/6/7/26 на Windows и Android прошла; backend больше не блокирует
кандидат `1.5.1+158`. Публичный update manifest в рамках этой серверной операции
не изменялся.
