# Release 1.5.45+225 — 2026-09-22

Status: **CLIENT RELEASE DEPLOYED AND PUBLICATION VERIFIED**. Владелец прямо
разрешил выпуск в production для ручного тестирования.

## Точная идентичность и объём

- Source commit/tag: `d8bd74ba54f48b8a3a4f1a11b60dd12df2454fd1` /
  `v1.5.45`.
- Frozen source: 2193 файла, fingerprint
  `8884c953bd3f374c2ec25758c00ce3c99dc0c6ed86246369f4ae3715bd8badb7`.
- Между `v1.5.44` и кандидатом нет изменений в `server/`. Поэтому это
  client-only выпуск: API намеренно не пересобирался и не переключался.
- Production API остался на `magicmusiccrm-server:1.5.44-224-final`, image
  `sha256:8954adc55c080e3398cb94f4caf6768bc9f437271c755dabd7fc090094b960a0`,
  schema `0160_requeue_lead_create_outbox`.
- Локальное release evidence: `dist/release225/`.

В клиент вошли плотная Holli Hop-подобная карточка клиента, полноценные
секционные карточки Staff/Teacher, несколько рабочих интервалов и датированные
периоды недоступности преподавателя, а также явный чекбокс перед ручным
изменением ставки или компенсации. Используются только реальные функции и
существующие права MagicMusicCRM.

## Проверки кандидата

До версионирования полный Flutter gate дал 1853 PASS, 4 штатных skip и 0 FAIL;
целевой analyzer завершился без замечаний. Windows device-сценарии проверили
desktop/compact/RBAC карточки, связанные переходы, график преподавателя и
защиту ставки. Версионирование изменило только release metadata; после него
release-history и release-config tests дали 10 PASS, updater audit — PASS.

Артефакты собраны из отдельного clean worktree точного commit. Локальный gate
проверил 31/31 файл Windows ZIP, содержимое встроенной истории APK/AAB, Android
подписи и неизменность frozen source. Android certificate SHA-256 совпадает с
production:
`0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
Windows Setup остаётся unsigned, как и предыдущие выпуски.

## Backup и rollback

Перед публикацией создана свежая encrypted backup
`magicmusiccrm-staging-20260922T140929Z.tgz.enc`, SHA-256
`a06b51eb821b0a3d57edd961b61e1b09d6df3afa95721f1fd5eb0c7acd02e400`.
Она скопирована вне production-хоста, сверена с sidecar и удалённым хешем и
восстановлена в изолированной Docker-сети на точных production и recovery
images — PASS. Живая база восстановлением не заменялась.

Server rollback не менялся:
`magicmusiccrm-server:223-recovery-0160-e4e14b6ae809`, image
`sha256:3a605547374559233590643fc68a7808a8382c68eea77e01455c6351f49bcd4e`.
Сохранены публичные `latest.json`, `latest-v2.json` и release history build 224.
Их возврат остановит новые автообновления, но не понизит уже установленный
build 225. Предпочтителен forward fix; БД и финансовую/учебную/audit-историю
не откатывать.

## Production-проверки

Оба update-канала и публичная история выдают build 225 / `1.5.45+225`.
Все четыре файла повторно скачаны через публичный HTTPS endpoint: размеры и
SHA-256 совпали с локальными артефактами. При публикации первое SSH-соединение
закрылось на последнем atomic rename `latest-v2.json`; канал оставался на 224,
пока повторный keepalive-сеанс не завершил rename. Финальная полная проверка
обоих каналов выполнена после исправления смешанного состояния.

| Артефакт | SHA-256 |
| --- | --- |
| Windows Setup | `94bdd896a119a2aaecd036c3911aaa95bde7c454e3a029c32b988d6a03a02195` |
| Windows ZIP | `f5c9104b7b87b6cb1c02ea2dcfb37e4114277d6287c6d45d91d66bbf21f15c7d` |
| Android APK | `e633f0781e223c16b182f17d5590d052b348141082ce1d7298b7f6fcd02742f8` |
| Android AAB | `64241985e89b673efca2a1b9771044098f389e2d24108e00916ce043666a2ea6` |

После публикации readiness вернул `status=ok`, schema 0160, outbox
pending/dead-letter `0/0`. Точный runtime image остался build 224;
reconciliation завершился с `issues=[]`. Синтетические production-клиенты,
задачи, занятия или платежи не создавались.

[GitHub Release v1.5.45](https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.45)
опубликован не как draft/prerelease. Digest и размер всех четырёх assets совпали
с локальными артефактами; tag указывает на точный source commit. Ручной
authenticated UAT визуального сходства и рабочих сценариев выполняет владелец;
автоматические проверки его не подменяют.
