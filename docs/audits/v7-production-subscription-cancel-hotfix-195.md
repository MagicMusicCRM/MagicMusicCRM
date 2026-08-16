# Production hotfix отмены абонемента `1.5.15+195`

Дата: `2026-08-16` (МСК)

Результат: **PASS**

## Зафиксированный кандидат

- Release commit: `95dc8465`.
- Tag и GitHub Release: `v1.5.15`.
- Выпуск клиентский. Production server остался на image
  `magicmusiccrm-server:1.5.14-194-be9b19e0`, migration head
  `0138_payment_record_corrections`.

## Причина и исправление

- Backend cancel DTO требует обязательный `refundMinor`, но Flutter-команда
  отмены его не отправляла. Запрос отклонялся валидацией до бизнес-логики, а UI
  показывал общий текст «Не удалось отменить абонемент».
- Flutter теперь читает `recommendedRefundMinor` из серверного preview,
  показывает сумму как «Возврат на личный счёт» и передаёт её в cancel-команду.
- Клиент не пересчитывает деньги самостоятельно. Сервер остаётся источником
  истины, а оплаты, списания и занятия сохраняются в истории.

## Release gates

- TDD: тест сначала подтвердил отсутствие `refundMinor` и суммы возврата, затем
  прошёл после исправления.
- Точечные тесты: `6/6`, полный Flutter suite: `827/827`.
- `flutter analyze --no-pub`: PASS, замечаний нет.
- RepoWise change risk: `Below typical`, percentile `32.5`, review priority
  `low`; изменённые строки Flutter покрыты двумя тестами.
- Windows portable: embedded version `1.5.15+195`, launch PASS.
- Windows Setup: ProductVersion `1.5.15.195`, сборка PASS.
- APK: `versionName=1.5.15`, `versionCode=195`, Signature Scheme v2 PASS.
- AAB JAR signature integrity PASS; сертификат действителен до `2053-10-15`.

## Backup и rollback

- До публикации создан encrypted backup
  `magicmusiccrm-staging-20260816T164031Z.tgz.enc`, `148 128` bytes,
  SHA-256
  `EA289D8C8AB9C83CB781FA71093E6387ECB488455F7BE708C7DA0697A0E38B07`.
- Backup скопирован off-host; локальный и remote SHA-256 совпали. Архив
  расшифрован и восстановлен в изолированный PostgreSQL: migration `0138`,
  users `12`, students `1`, subscriptions `1`.
- Manifest build `194` и прежняя release history сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260816T164400Z-pre-195`.
- Rollback клиента: атомарно вернуть оба сохранённых manifest и прежнюю
  release history. Backend rollback не требуется.

## Production verification

- `latest.json` и `latest-v2.json` идентичны: `version=1.5.15+195`, build
  `195`, exact Windows ZIP URL/SHA-256.
- Public release history содержит `35` выпусков и начинается с `1.5.15+195`.
- Все четыре public URL вернули HTTP `200` и точные размеры. Windows ZIP
  полностью скачан с production-домена; SHA-256 совпал с manifest.
- GitHub Release опубликован как latest; GitHub-computed digests и размеры
  четырёх assets совпали с локальными и production-артефактами.
- Public live/ready: `200/200`; API container healthy, restart `0`, server
  revision `be9b19e0` не менялась.
- Две независимые reconciliation вернули `issues=[]` / `issues=[]`; platform
  outbox pending/dead-letter `0/0`; свежие API fatal и Caddy 5xx отсутствуют.

## Клиентские артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 570 826` | `559EED1E8524B2D26E823D2ED3A0EEDCC348B6428787B0B45CE1D6E020985826` |
| Windows Setup | `15 407 599` | `F5BD022E481D62C9AF1174A389936867DFC71E8022591C5C0DAE743B3E29EA9F` |
| Android APK | `86 580 160` | `7576E3558FCD5706490AECBDE164ABAF2E469383CFD0C888A7BAEED7153442BB` |
| Android AAB | `60 686 461` | `B90EDE969850B9E0B4C1398AF53585A032DD3A19306177E027D01D6D00D87650` |

Клиенты build `<195` получают золотую точку у версии и предложение обновиться
при запуске, возврате в приложение или следующей фоновой проверке.
