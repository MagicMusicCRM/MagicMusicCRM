# Production rollout контроля оплат и абонементов `1.5.16+196`

Дата: `2026-08-16` (МСК)

Результат: **PASS**

## Зафиксированный кандидат

- Release commit: `29428568`.
- Tag и GitHub Release: `v1.5.16`.
- Server image: `magicmusiccrm-server:1.5.16-196-29428568`.
- Image ID: `sha256:08fdc30a8d995e949dd8291010077649d0d0eb581cc7ba153c889639619488f7`.
- Image labels: revision `294285683c68ed34dfee379ebb19cb4cf92de44e`,
  version `1.5.16+196`.
- Transport archive: `82 497 532` bytes, SHA-256
  `126FDBC9929DF3E5D9C9C1A65346BAAECCD2EEB5B536781571C8D62D6F246573`.

## Изменение

- Отменённый абонемент сразу исключается из списка выданных и не предлагается
  для новой оплаты.
- Оплату, связанную с отменённым абонементом, можно исправить или сторнировать;
  append-only финансовая история сохраняется.
- Legacy-выдача абонемента теперь создаёт исходный debit и точную двустороннюю
  связь с оплатой.
- Миграция `0140_repair_legacy_subscription_finance` безопасно восстанавливает
  старые связи и отсутствующий debit только для однозначно сопоставленных
  записей; повторный запуск идемпотентен.
- В истории используется понятная подпись «Возврат по абонементу». Из окна
  обновления удалена кнопка «Скачать вручную».

## Release gates

- Flutter: `829/829`; `flutter analyze --no-pub` PASS.
- Backend: `186/186` suites, `1457/1457` tests; typecheck и NestJS build PASS.
  Commerce PostgreSQL suite: `8/8` suites, `65/65` tests. Полный suite запущен
  на новой production-shaped базе `0140` с корректной системной CRM-связью.
- Exact image: invalid production flags fail-closed, healthy readiness PASS,
  degraded readiness `503` PASS, migration `0140`.
- Trivy exact image: `0` High/Critical vulnerabilities, `0` secrets.
  Gitleaks release commit: `0` leaks.
- RepoWise: `Elevated`, percentile `79.6`, review priority `high`; причина в
  новой финансовой миграции и `859` добавленных строках. Изменение покрыто
  точечными, полными Flutter и commerce PostgreSQL тестами.
- Windows portable: embedded version `1.5.16+196`, launch PASS. Setup собран
  Inno Setup `6.7.3` с ProductVersion `1.5.16.196`.
- APK: `versionName=1.5.16`, `versionCode=196`, Signature Scheme v2 PASS,
  certificate SHA-256
  `0d0c576061e04a920a550d478ab3f4b85fb9e3b4acfe91c5238280c0ecef4b97`.
  AAB JAR integrity PASS; self-signed release certificate действует до
  `2053-10-15`.

## Backup и rollback

- До mutation создан encrypted backup
  `magicmusiccrm-staging-20260816T183922Z.tgz.enc`, `151 056` bytes,
  SHA-256
  `E1E1F4C7C4B32B07CA2FA6A9F09025A6783157829A528FB6554E9BC484F8DBC5`.
  Off-host hash совпал; изолированное восстановление вернуло migration `0139`
  и counts `12/1/1/1`.
- После rollout создан encrypted backup
  `magicmusiccrm-staging-20260816T184412Z.tgz.enc`, `152 768` bytes,
  SHA-256
  `1917E799397A7D7B7D12C402147D8FAFB4813582E1A616B2FB6094AA6BA8EF56`.
  Off-host hash совпал; изолированное восстановление вернуло migration `0140`
  и counts `12/1/1/1/1`.
- Предыдущий image сохранён как
  `magicmusiccrm-server:rollback-pre-subscription-finance-20260816T1843Z`.
- Manifest build `195` и прежняя release history сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260816T185200Z-pre-196`.
- При откате runtime используется предыдущий image без down migration:
  `0140` содержит применённые append-only repair facts и защищает их от
  удаления.

## Production verification

- Runtime image/revision/version: exact candidate / `29428568` /
  `1.5.16+196`; restart count `0`, health `healthy`.
- Migration head: `0140_repair_legacy_subscription_finance`.
- Одна однозначная legacy-запись восстановлена: обе связи оплаты указывают на
  абонемент, исходный debit существует, repair ledger содержит одну строку.
- Личный счёт исправлен с `4 800 000` до `2 400 000` minor units, то есть с
  `48 000 ₽` до `24 000 ₽`; оплату и возврат не удаляли и не переписывали.
- V4 reconciliation: `17/17`, status `clean`, unexplained diff `0`. V7
  reconciliation дважды и финально вернула `issues=[]`.
- Public live/ready: `200/200`; все readiness checks `ok`; outbox pending и
  dead-letter `0/0`; свежие fatal, unhandled и Internal Server Error отсутствуют.
- `latest.json` и `latest-v2.json` идентичны: `1.5.16+196`, build `196`, точный
  Windows ZIP URL/SHA-256. Public release history содержит `36` выпусков.
- Все четыре public URL вернули HTTP `200` и точные размеры. Windows ZIP
  повторно скачан с production-домена; SHA-256 совпал с manifest.
- GitHub-computed digests и размеры четырёх assets совпали с локальными и
  production-артефактами.

## Клиентские артефакты

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 570 480` | `1398B49BBD03F15AAB44A7D6DFDBF5521F59AF4A6FA85CB362106E7BFA615168` |
| Windows Setup | `15 406 536` | `FBAD9D4E4330C1B370455BE184E3873F8AE8B882F7621D9C9044B113E9D31BB2` |
| Android APK | `86 580 376` | `C506BBFB6A50B1FE0674774393611C163434897CB8C36A36E4F35C28229AAFB7` |
| Android AAB | `60 687 279` | `97F55ECEA3F0E33143BA1EC33E51A7273435336AB6072AEED881E398B98D90D6` |

Клиенты build `<196` получают золотую точку у версии и предложение обновиться
при запуске, возврате в приложение или следующей фоновой проверке.
