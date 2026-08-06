# Финальный инженерный кандидат `1.2.2+155`

**Дата:** 2026-08-06
**Статус:** ENGINEERING PASS; OWNER UAT ещё не подписан

## Закрытый разрыв

- Формы создания сотрудника, преподавателя и группы смонтированы в реальном
  workspace настроек и используют существующие service/API-контракты.
- Ролевые ограничения выбора сотрудника сохранены: Управляющий не назначает
  равную или более высокую роль.
- Удалены дубли канонических экранов Клиентов/Расписания, заменённые аналитика и
  каталог, а также тестовый cache/conflict-контур, который не был подключён к
  production events. Реальные экраны продолжают использовать существующие
  realtime providers и version-conflict handlers.

## Gate

```text
flutter analyze: PASS, 0 issues
flutter test: 601/601 PASS
settings production create-flow: 6/6 PASS
v6 inventory: routes=22, reachable=253/254, unowned=0 PASS
backend typecheck/build: PASS
backend: 151/151 suites, 1155/1155 tests PASS
Windows production accounts/relogin: 2/2 PASS
Android production accounts/relogin: 2/2 PASS
Windows release launch: PASS
Android release install/launch: PASS, versionCode=155
APK signature: v2 PASS, 1 signer
git diff --check: PASS
```

`253/254` — ожидаемый результат: `runtime_env_io.dart` подключается условным
`dart.library.io` import, который простой import-graph генератора не раскрывает.

## Артефакты

| Артефакт | Размер | SHA-256 |
|---|---:|---|
| [Windows x64 ZIP](../../outputs/stage9-release-20260806/MagicMusicCRM-1.2.2-155-windows-x64.zip) | 19,156,774 bytes | `E2D622E0E507B93C469EFFB2DE911D6EE37EB7F77D29BFB5A3FCBB7DF76D332C` |
| [Android APK](../../outputs/stage9-release-20260806/MagicMusicCRM-1.2.2-155.apk) | 83,491,645 bytes | `505E1F49A29C3A01BAE983B36006ADBB786B92CCE8D04ACBF5621FAE17CE216B` |

Публичный update manifest не изменён. Следующий шаг — ручной 26-point OWNER UAT
на `+155`; только после него кандидат можно публиковать.
