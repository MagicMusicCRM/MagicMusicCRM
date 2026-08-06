# Финальный feature-quality кандидат `1.2.3+156`

Дата: 2026-08-06  
Ветка: `codex/v5-configurable-crm`  
Fix commits: `6f5bffb`, `a0d1a31`

## Итог

- Канонический реестр: [`MagicMusicCRM-Canonical-Feature-Register.xlsx`](../../outputs/feature-quality/MagicMusicCRM-Canonical-Feature-Register.xlsx).
- Описано и повторно проверено: **256 / 256 user stories** в 11 системах.
- Baseline: 256 runs; post-fix regression: 256 runs; адресные retest: 14 runs.
- Найдено ошибок: 11; статус после исправлений: **11 / 11 RETEST PASS**.
- Открытых ошибок / blocked stories: **0 / 0**.

## Release gate

| Проверка | Результат |
|---|---:|
| `flutter analyze` | PASS, 0 issues |
| Flutter full | PASS, 605 / 605 |
| Backend full | PASS, 151 / 151 suites, 1157 / 1157 tests |
| Backend typecheck / build | PASS / PASS |
| Android release build/install | PASS, versionName `1.2.3`, versionCode `156` |
| Android update with retained session | PASS |
| Windows x64 release build/launch | PASS |

## Артефакты

| Артефакт | Размер | SHA-256 |
|---|---:|---|
| [`MagicMusicCRM-1.2.3-156.apk`](../../outputs/stage9-release-20260806/MagicMusicCRM-1.2.3-156.apk) | 83,589,949 bytes | `BCDBC45EBFFE949D3E6CD96BCB5C4C6909EF5EE6846A0CC462131EF7D1F69801` |
| [`MagicMusicCRM-1.2.3-156-windows-x64.zip`](../../outputs/stage9-release-20260806/MagicMusicCRM-1.2.3-156-windows-x64.zip) | 19,166,342 bytes | `DC19C129BC312F4051CE054D8CD432463EFAD93B6EC2A8DF36F9A078A92C6D66` |

## Развёртывание

Кандидат включает изменения Flutter и backend. Для полного RBAC/data результата нужно разворачивать оба слоя из одной ревизии: клиент уже fail-closed скрывает school-finance у Manager и legacy migration-email, а обновлённый backend дополнительно не выполняет запрещённые finance queries и возвращает фактические счётчики групп.
