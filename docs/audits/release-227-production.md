# Release 1.5.47+227 — 24.09.2026 (Europe/Moscow)

Статус: **production-выпуск завершён; полная приёмка ТЗ не заявлена**. Владелец
прямо поручил выпустить кандидат в production. Функция «Добавить лид» исключена
из критериев приёмки по более раннему прямому решению владельца.

## Идентичность и объём

- Source commit/tag: `19de8f4017a75885e2b1bca6dce2c03b41c8752f` / `v1.5.47`.
- Замороженный tracked source: 2195 файлов, SHA-256
  `76c93c0e16cd3a0f8a1724e5ce6ba65c99f3fda3fea31933f50ff071170f9b85`.
- API image: `magicmusiccrm-server:1.5.47-227-final`, ID
  `sha256:6a5762ba9f16f1cf844dab2dbef3594ebdfd3431e7bf7baaf085e968511a381f`.
- Schema: `0160_requeue_lead_create_outbox` (без новой миграции).
- GitHub Release: https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.47.
- Локальные evidence и пакеты: `dist/release227/`; production release directory:
  `/opt/magicmusiccrm/releases/1.5.47-227-19de8f40`.

Выпуск переносит два исправления кандидата `ddc15e77a`: после покупки из лида
открытая карточка сохраняет имя и ученическую часть; частичная оплата с уже
внесённым первым платежом создаёт указанное число частей без лишней будущей
записи. Это факты реализации и локальных сценарных проверок, а не результат
ручной приёмки в production. Исходная матрица проверки:
`C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/outputs/application-audit-2026-09-23/VERIFY-ddc15e77a.md`.

## Проверки точного кандидата

1. Backend: **323/323 suites, 4158/4158 tests PASS, 0 skips**; typecheck и build
   PASS. `server/coverage/test-runs/e119ce1bd1644be0/jest-results.json`.
2. Flutter: **1862 PASS, 4 штатных skip, 0 FAIL**; `coverage/lcov.info`.
3. Production-like Windows UI/HTTP/PostgreSQL/restore: **24 PASS, 0 FAIL**,
   43 HTTP, 0 server errors. `dist/http-journeys/697154de544b4812b89f955ae383d524/result.json`.
4. Updater audit: 4/4 PASS, включая rollback, неверный hash и отсутствующий
   payload. Windows Release и подписанный Android APK запустились; это launch
   smoke, не authenticated UAT. `dist/release227/windows-smoke.json`,
   `dist/release227/android-smoke.json`.
5. Release source остался чистым при сборке; все четыре собранных файла,
   Windows ZIP (31 файл), подпись Android и встроенная история проверены.
   `dist/release227/artifact-manifest.json`.

| Публичный пакет | SHA-256 |
| --- | --- |
| Windows Setup | `a6125cb3250568149a32b3ae9f5a21507ee353cfc578fe5284733ac41cfbc4c6` |
| Windows ZIP | `d7a6333131c0cbd8b6ee78989f999d07e4730e010a7c26b8a666d973a5e8b141` |
| Android APK | `1b5e9dce7264160bc69f7ae82d5d6a870d2964c273805171be91734593fecb01` |
| Android AAB | `4577d9fd8d9087a2142da835845cc2b0c3c01d9cd15bb058c3d8b042fc74e560` |

GitHub Release опубликован (`draft=false`, `prerelease=false`). Все четыре
публичных HTTPS-файла повторно скачаны и сверены по размеру и SHA-256; оба
update-канала показывают `1.5.47+227`, публичные history и readiness прочитаны:
`dist/release227/public-verification.json`, итог `PASS`. APK/AAB опубликованы
как пакеты выпуска; публикация в Google Play не выполнялась. Windows Setup
остаётся без подписи, как в прежних выпусках.

## Production, backup и rollback

До переключения создана зашифрованная копия
`magicmusiccrm-staging-20260923T215858Z.tgz.enc`, SHA-256
`17e3ab3e0cd13959cc7d2685fb718808c97282b87fb819e4f83b241ab579380f`.
Она скопирована вне production-хоста, сверена по hash и восстановлена в
изолированном Docker с точными candidate/rollback images — PASS:
`dist/release227/backup-drill-pre-retry/result.json`.

API переключён версионированным `deploy-api-release.sh`; cutover подтвердил
image/revision/schema, DB contract, readiness и reconciliation до открытия
публичного proxy. Затем опубликованы два update-manifest build 227; прежние
manifest build 226 сохранены. После переключения readiness `status=ok`, миграция
`0160_requeue_lead_create_outbox`, outbox `pending=0`, `deadLetter=0`, повторная
reconciliation `issues=[]`. Evidence на сервере: `cutover.log`,
`post-reconciliation.json` в указанном release directory.

После выпуска создана новая зашифрованная копия
`magicmusiccrm-staging-20260923T233923Z.tgz.enc`, SHA-256
`b8a40b7a7b9098f8991fe8006969fef5756571053761814d7bd4583ed31b32fd`.
Она скопирована вне сервера; изолированное восстановление с candidate и
rollback images — **PASS** (`dist/release227/backup-drill-post/result.json`).
Проверка не писала в живую БД.

Совместимый резерв API:
`magicmusiccrm-server:1.5.44-224-final`, image
`sha256:8954adc55c080e3398cb94f4caf6768bc9f437271c755dabd7fc090094b960a0`.
Rollback клиентских manifest — сохранённые build 226; rollback API — только
переключение image после сверки. Исторические финансовые, учебные и audit-факты
не удалять и не откатывать.

## Граница приёмки

На прошлом локальном кандидате полностью принятых в установленной Release-сборке
требований было **0/20**: 16 проверены частично, 4 не проверены. Этот выпуск
устранил препятствие «кандидат не установлен в production» и подтвердил доставку,
запуск, API и базовые контракты. Он не заменяет authenticated UAT под рабочими
ролями на реальных экранах с перечитыванием сохранённых данных. Поэтому 20
требований не помечены полностью выполненными по одному факту публикации.
Приёмка должна отдельно охватить покупку из лида, точную частичную оплату,
расписание, роли, уведомления, синхронизацию двух окон и регрессии, перечисленные
в `VERIFY-ddc15e77a.md`.
