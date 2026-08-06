# Этап 9 — реальные аккаунты, release-сборки и граница выпуска

**Дата:** 2026-08-06
**Кандидат backend release:** `1.2.2+151`
**Актуальный клиент для OWNER UAT:** `1.2.2+155`
**Ветка / базовый commit:** `codex/v5-configurable-crm` / `532bf1eb8e500dfcd5e55a510a470e5e4545fc46`
**Итог:** ENGINEERING RELEASE PASS для backend, сборок и ролевого shell;
OWNER UAT PASS не присвоен

## Реальные аккаунты и production baseline

Production health вернул `200` / `status=ok`. Парольный вход дал сессию всем
пяти предоставленным аккаунтам и подтвердил последовательность ролей:

| Аккаунт | Роль | Проверенные безопасные GET-сценарии | Граница |
|---|---|---|---|
| `magic1` | Client | profile, self summary, self commerce — `200` | общий список учеников — `403` |
| `magic2` | Teacher | profile, назначенные lessons/clients, shared tasks — `200` | shell без management-разделов |
| `magic3` | Admin | profile, branches, lessons, clients — `200` | shared tasks — `403` |
| `magic4` | Manager | profile, shared tasks, status analytics, Lead/Student pipelines — `200` | school finance — `403` |
| `magic5` | Director | profile, CRM config, shared tasks, status/school-finance analytics, Lead/Student pipelines — `200` | capability/resource deny остаётся fail-closed |

После backend release повторная матрица дала `27/27 PASS` на пяти аккаунтах.
`/crm/client-pipelines?clientType=lead|student` теперь возвращает `200` для
Manager и Director; прежний production gap закрыт.

## Production release и rollback evidence

- Перед миграциями создан custom-format PostgreSQL backup размером
  `29,843,331` bytes; `pg_restore --list` прошёл, SHA-256
  `e8f82f097e7dd88b933096fe450ba6b411edc0ba609d715a18df8bed3a6b53c8`
  совпал у server- и off-host-копии.
- На отдельной восстановленной БД выполнен полный drill:
  restore `0098` → up `0099..0101` → down до `0098` → повторный up →
  idempotent up (`none`). Временная БД после проверки удалена.
- Production API переключён на image
  `sha256:cbc33d9993c2f700791f74910c9ed242f430e8b04ab25ee98fc72b0653f6ee2a`;
  latest schema — `0101_canonical_shared_tasks`.
- Старый image `sha256:114730c57b95a79a1dc293a6c720dd6a5db23258c55bb9a02781b63a2e8aac52`
  и исходники сохранены для быстрого rollback; backup не удалён.
- На первом переключении защитный rollback сработал из-за ошибки только в
  финальной verification-команде (неверное имя БД). Старый healthy API был
  восстановлен автоматически; после исправления проверки повторное
  переключение прошло полностью. Восстановление production-данных не
  потребовалось.
- Итог: container `healthy`, restart count `0`, public health `200`, burst
  health `30/30`, role/API matrix `27/27`.

## Windows и Android

Device-check расширен вторым сценарием
[`stage9_real_account_device_test.dart`](../../integration_test/stage9_real_account_device_test.dart),
который на настоящем production API входит каждым аккаунтом, сверяет фактическую
роль и монтирует разрешённую ролевую навигацию, а затем проверяет холодный старт,
выход и переключение Client → Director → Client через platform secure storage.

- Windows x64: 5/5 аккаунтов + secure relogin, `2/2 PASS`.
- Android 15 / API 35 (`emulator-5554`): 5/5 аккаунтов + secure relogin,
  `2/2 PASS`.
- После backend release оба device-check повторены: Windows `1/1 PASS`,
  Android `1/1 PASS`. Первый Windows запуск встретил единичный transport EOF;
  proxy не зафиксировал ошибок, health burst прошёл `30/30`, повторный полный
  прогон прошёл.
- Финальный Windows EXE: процесс жив после 5 секунд — PASS.
- Финальный APK: установлен на API 35, `magic.crm` жив после 5 секунд,
  `versionName=1.2.2`, `versionCode=155` — PASS.

Windows Computer Use не смог захватить Flutter-окно из-за ошибки Windows UIA
`SetIsBorderRequired ... 0x80004002`. Поэтому owner screenshots и ручной
mouse-only сценарий этим инструментом не подменялись; device integration
проверяет shell, но не является подписью владельца.

## Найденное и исправленное расхождение

Реальный Windows-прогон показал фоновый `403`: Teacher Chat запрашивал
привилегированный `/admin/profiles`. Общий messenger bootstrap теперь загружает
этот каталог только для Admin/Manager/Director/system_admin. Минимальный тест
фиксирует отсутствие запроса у Teacher.

Перед OWNER UAT дополнительно закрыты регрессии повторного входа, стабильного
поиска Lead/Student и постоянной подсветки расписания в Month/Week/Day. Аналитика
освобождена от дублирующего каталога, а технические «Справочники» переименованы в
понятные «Варианты для полей». Полный отчёт:
[`v6-pre-owner-regression-check.md`](v6-pre-owner-regression-check.md).

## Проверки

```text
flutter analyze: PASS, 0 issues
targeted messenger: 5/5 PASS
flutter test: 601/601 PASS
backend typecheck/build: PASS
backend test: 151/151 suites, 1155/1155 tests PASS
backup restore/up/down/up drill: PASS
production migrations: 0099, 0100, 0101 PASS
post-release HTTP/RBAC matrix: 27/27 PASS
Windows real-account device test: 2/2 PASS (5 roles + secure relogin)
Android real-account device test: 2/2 PASS (5 roles + secure relogin)
Windows release build: PASS
Android release APK build: PASS
APK signature: v2 verified, 1 signer
git diff --check: PASS
```

## Артефакты

| Артефакт | Размер | SHA-256 |
|---|---:|---|
| [Windows x64 ZIP](../../outputs/stage9-release-20260806/MagicMusicCRM-1.2.2-155-windows-x64.zip) | 19,156,774 bytes | `E2D622E0E507B93C469EFFB2DE911D6EE37EB7F77D29BFB5A3FCBB7DF76D332C` |
| [Android APK](../../outputs/stage9-release-20260806/MagicMusicCRM-1.2.2-155.apk) | 83,491,645 bytes | `505E1F49A29C3A01BAE983B36006ADBB786B92CCE8D04ACBF5621FAE17CE216B` |

## Незакрытые границы

- **PENDING:** 26-point owner UAT, реальные мутации Lead/Student/Lesson/Payment,
  reconciliation, webhook/recipient/worker evidence и подпись владельца.
- Windows ZIP и APK `+155` проверены и готовы к OWNER UAT, но update
  manifest/публичная раздача в рамках backend-разрешения не менялись.
- ENGINEERING RELEASE PASS не подменяет OWNER UAT PASS.

PRODUCT-ESSENCE-MAP не изменён: нового бизнес-решения не обнаружено; подтверждён
production parity и исправлен лишний frontend-запрос.
