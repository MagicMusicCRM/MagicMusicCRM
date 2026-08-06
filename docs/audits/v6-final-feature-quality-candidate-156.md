# Финальный feature-quality кандидат `1.2.3+156`

Дата: 2026-08-06  
Ветка: `codex/v5-configurable-crm`  
Fix commits: `6f5bffb`, `a0d1a31`; финальное evidence-hardening — текущая ревизия.

## Итог

- Канонический реестр: [`MagicMusicCRM-Canonical-Feature-Register.xlsx`](../../outputs/feature-quality/MagicMusicCRM-Canonical-Feature-Register.xlsx).
- Описано и повторно проверено: **256 / 256 user stories** в 11 системах.
- Исторический ручной/device baseline: 55 runs; точный post-fix regression: 256 / 256 stories (265 named-test evidence rows); адресные retest: 14 runs.
- Найдено ошибок: 11; статус после исправлений: **11 / 11 RETEST PASS**.
- Открытых ошибок / blocked stories: **0 / 0**.
- Общие итоги suites не использованы как story acceptance: каждая история сопоставлена с конкретным прошедшим тестом в листе `Evidence Audit`.

## Release gate

| Проверка | Результат |
|---|---:|
| `flutter analyze` | PASS, 0 issues |
| Flutter full | PASS, 615 / 615 |
| Backend full | PASS, 152 / 152 suites, 1159 / 1159 tests |
| Backend typecheck / build | PASS / PASS |
| Android release build/install | PASS, versionName `1.2.3`, versionCode `156` |
| Android update with retained session | PASS; staff workspace restored, PID alive, fatal exceptions `0` |
| Windows x64 release build/launch | PASS; release process remained alive during smoke |

## Артефакты

| Артефакт | Размер | SHA-256 |
|---|---:|---|
| [`MagicMusicCRM-1.2.3-156.apk`](../../outputs/stage9-release-20260806/MagicMusicCRM-1.2.3-156.apk) | 83,589,949 bytes | `36BE9B929C17D4E4E232667B9537F214272FF1B8F78BECBA8884ED17FC4EEE7A` |
| [`MagicMusicCRM-1.2.3-156-windows-x64.zip`](../../outputs/stage9-release-20260806/MagicMusicCRM-1.2.3-156-windows-x64.zip) | 19,166,038 bytes | `14D8E76916621176EAD7B7B2E32C73EE836103AF73EEBE1D56D8488E4A23E86C` |

Машинные отчёты: `outputs/feature-quality/evidence/flutter-test-machine-final-156.ndjson`, `outputs/feature-quality/evidence/server-test-json-final-156.json`; story-level verdicts: `outputs/feature-quality/story-evidence-audit.json`.

## Развёртывание

Кандидат включает изменения Flutter и backend. Для полного RBAC/data результата нужно разворачивать оба слоя из одной ревизии: клиент уже fail-closed скрывает school-finance у Manager и legacy migration-email, а обновлённый backend дополнительно не выполняет запрещённые finance queries и возвращает фактические счётчики групп.
