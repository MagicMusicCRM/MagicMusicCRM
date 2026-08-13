# Release candidate `1.5.5+185`

Дата подготовки: `2026-08-13`

Статус: **READY FOR CONTROLLED ROLLOUT, NOT DEPLOYED**

Owner mega-UAT: **IN PROGRESS**, этим кандидатом не закрыта

## Зафиксированный runtime

- Source revision: `93d66a849022b0a85c99e2ac7f2fc692df89246d`.
- Версия клиента и OCI label: `1.5.5+185`.
- Последняя migration: `0134_canonical_clients`.
- Локальный exact image:
  `sha256:c1ea0eada8ebd06f1112a0fa67882b7f0dacc4cbdf819a283597f7877e17cd49`.
- Image user: `magiccrm`; revision label совпадает с source revision.
- Production на момент preflight не изменён: client `1.5.4+184`, migration
  `0132_app_registration_source`, image `sha256:eee82d6c…`.

## Состав кандидата

- Одно определение CRM-поля с общей Lead/Student видимостью и одним набором
  вариантов вместо двух расходящихся определений.
- Один стабильный `app.clients.id` для Lead/Student lifecycle-проекций.
- Сохранение порядка вариантов при legacy merge.
- `ALWAYS` cleanup triggers пересобирают Client из оставшейся проекции или
  удаляют последнюю identity вместе с custom values без сирот.

## Release gates

- RepoWise change risk для `b67f62c9..93d66a84`: `Elevated`, 91-й
  percentile из-за объёма и рассеянности schema/client изменений. Coverage map
  в индексе отсутствует, поэтому выполнен рекомендованный полный suite.
- Flutter analyze: PASS.
- Flutter: `793/793` PASS.
- Backend typecheck/build: PASS.
- Backend: `178/178` suites, `1418/1418` tests PASS.
- Production-like runtime: migration `0134`, fail-closed, live/ready,
  reconciliation `issues=[]` PASS.
- Migration roundtrip на отдельной БД:
  `0134 -> 0132 -> 0134` PASS; Client/custom-value orphans `0`.
- Exact image: invalid production flags fail-closed, migration/live/ready/
  healthcheck PASS, degraded readiness HTTP `503` PASS.
- Trivy vulnerability + secret scan: `0` High/Critical, secrets `0`.
- Server image tar load/readback: PASS.
- Reset safety contract и `git diff --check`: PASS.

## Client artifacts

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 520 281` | `6A807320A9AE42ABB52957333761A628F5722A463776286096F85A42FD0E14AD` |
| Windows Setup | `15 372 952` | `85A5DB2C015003989AFD6DEFF64F4F4EF0D85718560E4B4350238CC7D7DD4F52` |
| Android APK | `86 230 409` | `9B07CCF4961C25878F296A1DD30FC974B6DDC96D1E41ABDD74B563411BCD95E3` |
| Android AAB | `60 578 493` | `B737BBB8534281E6A219E0D08A1AF28E6FA9CA6BA1B6AB9F2619841F29B20A97` |
| Server image tar | `82 767 360` | `8248CFB62AE009884AE90A5C4216D9C1445473E1A7B7996B6310A1D5CA737B2A` |

- Windows EXE FileVersion/ProductVersion: `1.5.5+185`.
- Windows portable launch PASS; Setup `/CURRENTUSER` install, version readback,
  launch и uninstall PASS. Distribution остаётся unsigned в рамках ранее
  принятого owner-риска.
- APK: package `magic.crm`, versionName `1.5.5`, versionCode `185`, minSdk `24`,
  targetSdk `36`; APK Signature Scheme v2 PASS.
- APK signer SHA-256 совпадает с опубликованным build `184`.
- Android 15/API 35: update install `184 -> 185`, cold launch, resumed
  `MainActivity`, UI tree и тёмный login screen PASS; crash buffer,
  `AndroidRuntime FATAL`, `E/flutter` и `FlutterError` пусты.
- AAB JAR signature verification PASS.
- Локальные `latest.json` и `latest-v2.json` идентичны, содержат build `185`,
  Windows ZIP URL и exact SHA-256. Публичные manifests не переключались.
- Sentry остаётся отключённым: ignored `.flutter.env` не содержит DSN; проект
  явно поддерживает этот режим. Production API URL встроен через HTTPS.

## Production read-only preflight

- Public ready: `status=ok`, migration `0132`; database, migrations, lesson
  completion worker, platform outbox и v4 rollout `ok`.
- Серверные containers healthy; API работает от exact image build `184`.
- Свободно около `29.8 GB`; canonical backup script читается.
- Clean-start guards PASS: system accounts, `10` system fields, `40` custom
  fields, protected source и announcements сохранены.
- Текущее состояние: users `3`, staff `2`, clients/leads/students, branches,
  rooms, lessons и commerce facts `0`.
- Reconciliation: `issues=[]`; outbox pending/published/dead-letter `0/0/0`.
- Оба public update channel идентичны и остаются на `1.5.4+184`.
- Последний существующий encrypted backup от rollout `184` доступен, но перед
  новым cutover обязателен новый backup, off-host hash и isolated restore.

## Обязательный controlled rollout

1. Сохранить оба текущих manifest и точные build `184` artifacts/image как
   rollback target.
2. Создать новый encrypted production backup, скопировать off-host, сверить
   SHA-256 и выполнить isolated restore-check.
3. Загрузить exact server tar и четыре client artifacts, не переключая public
   manifests.
4. Вооружить automatic rollback; остановить workers/writers по runbook.
5. Запустить candidate image, применить `0133/0134`, проверить ready/reconcile
   сначала без workers, затем с workers.
6. Только после server PASS атомарно опубликовать четыре client artifacts и оба
   manifest build `185`; проверить HTTP size/hash и update `184 -> 185`.
7. Откатить rollout при drift, утечке прав, необъяснённом 5xx, дубле эффекта,
   failed restore или невозможности вернуть build `184`.

Кандидат технически готов к controlled rollout. Production mutation,
публикация manifests/artifacts, GitHub Release и owner mega-UAT этим документом
не выполнялись.
