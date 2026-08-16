# Production hotfix раздела абонементов `1.5.17+197`

Дата: `2026-08-16` (МСК)

Результат: **PASS**

## Кандидат и изменение

- Release commit: `54deba80`.
- Исправление: `cab0e641`.
- Tag и GitHub Release: `v1.5.17`.
- После отмены абонемента историческая ссылка больше не блокирует раздел.
- Отменённая запись не возвращается в список активных, а кнопка
  «Добавить абонемент» остаётся доступной.
- Сервер, база данных и миграции не менялись.

## Проверки кандидата

- Регрессионный тест воспроизвёл исчезновение кнопки до исправления и прошёл
  после него.
- Flutter: `829/829`; release history и cancel flow `6/6`;
  `flutter analyze --no-pub` без замечаний.
- RepoWise: обычный риск, percentile `34.1`, review priority `moderate`.
- Gitleaks: два release-коммита, утечек нет.
- Windows portable: embedded version `1.5.17+197`, запуск PASS.
- Setup: Inno Setup `6.7.3`, ProductVersion `1.5.17.197`.
- APK: `versionName=1.5.17`, `versionCode=197`, Signature Scheme v2 PASS,
  certificate SHA-256
  `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
- AAB JAR integrity PASS.

## Backup и rollback

- До публикации создан encrypted backup
  `magicmusiccrm-staging-20260816T193043Z.tgz.enc`, `153 344` bytes,
  SHA-256
  `79b5132c016d526997599300ce245ebd02c48e2363e89c9e4627ec6e97e0a2b9`.
- Off-host копия имеет тот же SHA-256. Изолированное восстановление в
  PostgreSQL `16.4` вернуло migration
  `0140_repair_legacy_subscription_finance`, `12` пользователей и `2`
  сохраняемые учётные записи.
- Manifest build `196` и прежняя release history сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260816T223144-pre-197`.
- Откат клиента выполняется атомарным возвратом этих manifest; серверный
  runtime и данные при таком откате не изменяются.

## Production verification

- `latest.json` и `latest-v2.json` идентичны: `1.5.17+197`, build `197`,
  точный Windows ZIP URL и SHA-256.
- Public release history содержит `37` выпусков и начинается с build `197`.
- Все четыре public URL вернули HTTP `200`; Windows ZIP повторно скачан с
  production-домена, SHA-256 совпал.
- GitHub Release не является draft или prerelease; размеры и digests всех
  четырёх assets совпадают с локальными и production-артефактами.
- Production API сохранил image
  `magicmusiccrm-server:1.5.16-196-29428568`, health `healthy`, restart `0`.
- V7 reconciliation дважды вернула `issues=[]`; outbox pending/dead `0/0`;
  readiness `ok`.

## Артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 570 543` | `22C5E10A9E3752B83836211264E2B46D004A87CC30F0B726E3E40DD48A721B45` |
| Windows Setup | `15 405 147` | `E92CC5B36B4DC0F6E2FF4F839C9D4E55E7E17F25F01E6B33E8E8701C04EA17AE` |
| Android APK | `86 580 560` | `85172A5B2035494288717E535EAA4B1FF2E5052EDB847950A53FABE480D99AB6` |
| Android AAB | `60 687 556` | `AC87BE95016006DFFFB747FF20AF05E78A1FA0F66E9561EF099BDCCDFB918382` |

Клиенты build `<197` получают золотую точку у версии и предложение обновиться
при запуске, возврате в приложение или следующей фоновой проверке.
