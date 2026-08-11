# T1.4.1 — Workspace/navigation device suite

**Статус:** PASS

**Дата:** 2026-08-01

**Исходная ветка:** legacy v4 delivery branch (удалена после governance cleanup)

**Машинный результат:** `docs/audits/v4-workspace-device-result.json`

## Контур

- Windows 10 x64, Flutter desktop, Visual Studio Build Tools 2026 + ATL.
- Android 15 / API 35 x86_64, AVD `MagicMusicCRM_API35`, AEHD 2.2.
- Один integration harness: `integration_test/v4_workspace_device_test.dart`.
- Команда: `pwsh -File scripts/v4_workspace_e2e.ps1 -Windows -Android`.

## Результат

| Gate | Результат | Время |
|---|---:|---:|
| Workspace widget/navigation regression | 24/24 | 18.988 s |
| Windows workspace device E2E | 2/2 | 83.091 s |
| Android context-stack device E2E | 2/2 | 81.637 s |

Проверены лимит 10 вкладок, tab-local state, конфликт двух вкладок,
restart/account isolation, global logout, mobile four-level context stack,
authenticated link и system Back. Итоговые показатели:

- context loss: `0`;
- silent overwrite: `0`;
- cross-account leak: `0`;
- logout latency gate: `≤2 s`.

## Совместимость Windows toolchain

Закреплённые Windows-плагины используют legacy MSVC `/await`. Для сборки с
MSVC 14.51 добавлено явное
`_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`; версии pub-зависимостей
и runtime-контракты не менялись. ATL установлен как компонент локального
Build Tools.
