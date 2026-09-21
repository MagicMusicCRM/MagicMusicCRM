# Release 1.5.44+224 — 2026-09-21

Status: **DEPLOYED AND PUBLICATION VERIFIED**. Владелец прямо разрешил выпуск
на production для пользовательского тестирования.

## Точная идентичность

- Source commit/tag: `e4e14b6ae80921b8f94a305c2fe85184d35ea9e7` / `v1.5.44`.
- Server: `magicmusiccrm-server:1.5.44-224-final`, image
  `sha256:8954adc55c080e3398cb94f4caf6768bc9f437271c755dabd7fc090094b960a0`.
- Schema: `0160_requeue_lead_create_outbox`; до выпуска — build 223/schema 0157.
- Frozen source: 2191 файл, SHA-256
  `3112b357195d27884dee9c8ad8be769696c67b7facfebe54590ebfed9d69fcc2`.
- Remote release: `/opt/magicmusiccrm/releases/1.5.44-224-e4e14b6a`;
  локальное evidence: `dist/release224/`.

Полный Flutter gate: 1849 PASS, 4 штатных skip, 0 FAIL. Полный backend gate:
323 suites / 4158 tests, 0 skip, PASS. TypeScript typecheck/build, security gate
(11 PASS, npm audit 0 vulnerabilities), целевые миграционные и UI-тесты прошли.
Scoped Flutter analyzer завершился с exit 0; 40 прежних info lint не объявляются
новыми ошибками. Полный analyzer затрагивал посторонние untracked Dart-фрагменты
в `outputs/`, поэтому release-critical файлы отдельно проверены без замечаний.

## Backup и rollback

Обе зашифрованные копии скопированы вне сервера, сверены по SHA-256 и успешно
восстановлены в изолированной Docker-сети на точных candidate и recovery images.
Живая база и история восстановлением не заменялись.

| Backup | SHA-256 |
| --- | --- |
| `magicmusiccrm-staging-20260921T160417Z.tgz.enc` (pre) | `7315290862b0eca0396b363417e2bbdbea1de18d98d6d41303a8679b1429fef2` |
| `magicmusiccrm-staging-20260921T161342Z.tgz.enc` (post) | `fcff0211fb323a7355f46e0c0a20d438a69e10adeba9b726a9e6d3c11ec9cdd7` |

Совместимый резерв:
`magicmusiccrm-server:223-recovery-0160-e4e14b6ae809`, image
`sha256:3a605547374559233590643fc68a7808a8382c68eea77e01455c6351f49bcd4e`.
Это точный production build 223 с 38 хешированными файлами совместимости для
схемы 0160. Общие backport-файлы не являются независимым резервом от дефекта в
них; при непроверенном rollback трафик должен оставаться закрытым. Миграции и
живую финансовую/учебную/audit-историю не откатывать.

## Production-проверки

`cutover.log`: `DEPLOY_API_RELEASE|PASS`. После cutover точные image/revision,
schema 0160 и `status=ok` подтверждены; reconciliation вернул `issues=[]`.
Два прежних `crm.lead.create.committed` dead-letter события были единственными
деградировавшими событиями, имели завершённые idempotency-записи и были
переотправлены миграцией без изменения identity/payload. Оба опубликованы,
dead-letter/pending равны нулю, добавлены ровно две append-only audit-записи
`platform.outbox.requeued`.

На cutoff `2026-09-21T16:09:39.185Z` до/после совпали:

- `lesson_client_charge_facts`: 13 строк, SHA-256
  `b2e44aab0b1bc74faad53f00a653d1b30f58d395c283f7d2e679a447a7093e78`;
- `lesson_teacher_compensation_facts`: 33 строки, SHA-256
  `44efc7d7af86307e8359f997fb4d3dbfc16291e624fdf81b03bc0e57f75636f7`.

Новые task-results, sales/finance/utilization analytics и notification-delivery
routes доступны и без сессии отвечают 401, не раскрывая данные. Синтетические
клиенты, задачи, занятия или платежи в production не создавались.

## Публикация клиентов

Оба update-канала выдают build 224 / `1.5.44+224`; публичная история начинается
с build 224. Все публичные размеры и SHA-256 совпали с локальными артефактами.

| Артефакт | SHA-256 |
| --- | --- |
| Windows Setup | `03eeb2fb968ce8300e0fbfeeb282ddf8643c464dfdc572d46a84de89e836ad52` |
| Windows ZIP | `36922b99296bab33ba45f7c869433c67fb3e8fe72a6b4fb71012ecbf81b8d05e` |
| Android APK | `2f5655779e918996fc517160fe9b4fb7efae7a405a6330a1021b28fb0043c312` |
| Android AAB | `a969c5522c267878ec12f82d1ef902b36e8c1c8f62b285f0ced0ab8d05af22b5` |

Android certificate SHA-256 совпадает с production:
`0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
Windows Setup остаётся unsigned, как и предыдущие выпуски. Автоматические
проверки не заменяют ручной authenticated UAT новых экранов на production — его
выполняет владелец этим выпуском.

[GitHub Release v1.5.44](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.44)
опубликован не как draft/prerelease; размеры и SHA-256 всех четырёх assets
совпали с локальными артефактами. Tag указывает на точный production source
commit `e4e14b6ae80921b8f94a305c2fe85184d35ea9e7`.
