# Production rollout `1.5.2+182`

Дата: `2026-08-12`

Результат: **PASS**

Owner mega-UAT: **IN PROGRESS**, этим rollout не закрыта

## Зафиксированный кандидат

- Production server source revision:
  `52b272087f81a99384bdee9243c0cc79808162ee`.
- Client/release revision после installer-only правки:
  `e9514bb51084b32c11964a3a6727d71dd6079f98`.
- Production image:
  `sha256:698db9b42d75bc09936861e7c61022e2132f3085879c4d946ad27bd52e2debfe`.
- OCI version/revision/user: `1.5.2+182`, `52b272087…`, `magiccrm`.
- Предыдущий production image:
  `sha256:6e8fc8870c54287e9b33eeaee9436cb8d45233f6382120bf6a1eaa9e6d4829f1`.
- Rollback tag:
  `magicmusiccrm-server:rollback-pre-1.5.2-182-20260812T1900Z`.
- GitHub Release: `v1.5.2`, target `e9514bb51084b32c11964a3a6727d71dd6079f98`.

Server revision и client revision различаются только двумя декларативными
строками Inno Setup: default admin-upgrade mode сохранён, а `/CURRENTUSER`
разрешён для неинтерактивного smoke. Runtime-код приложения и сервера между
этими revision не менялся.

## Полные gates до production

- Flutter: `786/786`, analyze PASS.
- Backend: `175/175` suites, `1401/1401` tests, typecheck/build PASS.
- Update-manifest tests: `31/31`.
- Clean prod-like migration ledger: `0001..0131`; readiness и reconciliation
  `issues=[]`.
- Production dependency audit: `0 vulnerabilities`; Gitleaks: `0`.
- Exact image runtime: invalid-config fail-closed, live/ready, healthcheck и
  degraded `503` PASS.
- Trivy: `0` High, `0` Critical, `0` secrets.

Локальный image gate использовал отдельно собранный из того же commit image
`sha256:c26790efe2bb5f7a1dbd0f1da2c4dc7a44c3f3f1d30f6d1559479a379e67e2e4`.
Production image был воспроизводимо пересобран на сервере из exact Git commit;
различие image ID вызвано build metadata, OCI revision/version и runtime gate
проверены повторно на production image.

## Backup, restore-check и cutover

- Перед изменением создан encrypted backup
  `magicmusiccrm-staging-20260812T184708Z.tgz.enc`, размер `33 940 832` bytes.
- SHA-256 production и off-host копии:
  `3B0D81A4AEFF909BD352A5C139050288CD172884B83C71EAF898DBCC0DF98E32`.
- Isolated restore полностью восстановил backup, применил миграции
  `0119..0131`, повторил aggregate counts и вернул reconciliation `issues=[]`.
- Ключевые counts до/после: users `1097`, leads `1996`, students `1047`,
  lessons `33845`, payments `3252`, audit `26162`, outbox `7`.
- Старый production image успешно стартовал на additive schema `0131`; rollback
  совместимость доказана до cutover.
- Worker и outbox были остановлены только на фазе candidate readiness, затем
  включены штатно. Automatic rollback был вооружён, но не запускался.

Cutover завершился `CUTOVER_PASS`; migration
`0131_installment_payment_reminders`, paused/final reconciliation и два
дополнительных post-deploy reconciliation вернули `issues=[]`.

## Client artifacts и device smoke

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 499 928` | `5E7440B9839BFF384D1C42C8ED4C3D24826077527C19AAEDEC39EE2AE6F3D74B` |
| Windows Setup | `15 361 482` | `F9BAED3EC652D6A8292396D62B48E14628463B60C7AEAC8D5C148DE0536A5CBB` |
| Android APK | `86 033 613` | `3BDDA9F4C31D355C881FCEED871397C249B2A285FE6F7EC1051BCE053C15F509` |
| Android AAB | `60 530 077` | `A0D8193B7685370E5AE5DDD940D16ED44F20B638D72E1C91C780722254F03084` |

- Windows portable executable и установленный executable имеют
  FileVersion/ProductVersion `1.5.2+182`.
- Portable launch `15 s` PASS. Setup `/CURRENTUSER` install → launch `15 s` →
  uninstall PASS. Обычный Setup сохраняет admin-mode для обновления предыдущей
  установки в `Program Files`; unsigned distribution остаётся ранее явно
  принятым owner-риском.
- APK подписан одним release signer, package `magic.crm`, versionName `1.5.2`,
  versionCode `182`, minSdk `24`, targetSdk `36`.
- Android 15/API 35: `adb install -r` PASS, `MainActivity` foreground, process
  жив после повторного запуска; FATAL/ANR/`E/flutter` = `0`. Тёмный login screen
  визуально отрисован. Credential-based five-role повтор в этом rollout не
  выполнялся и остаётся частью owner-UAT.
- AAB собран release Gradle и имеет upload-keystore JAR signature; сертификат
  действителен до `2053-10-15`. Строгий JDK trust check ожидаемо считает
  приватный self-signed upload certificate недоверенным.

## Публикация обновления

- Старые `latest.json` и `latest-v2.json` build `181` сохранены в
  `/opt/magicmusiccrm/downloads/rollback/manifests-20260812T192011Z-pre-182`.
- Versioned artifacts опубликованы сначала и проверены по SHA-256 на сервере.
- GitHub Release `v1.5.2` содержит те же четыре файла и те же GitHub-computed
  SHA-256.
- Оба манифеста атомарно переключены на `version=1.5.2+182`,
  `buildNumber=182`, Windows ZIP URL и его точный SHA-256.
- Публичный HTTPS HEAD всех четырёх файлов: `200`, размеры совпали.
- Windows ZIP полностью скачан по URL из публичного `latest-v2.json`; SHA-256
  совпал. Клиенты ниже build `182` получают предложение обновиться при штатной
  проверке манифеста.

## Post-deploy состояние

- Internal/public live и ready: `ok`; migration `0131`.
- API image healthy, non-root, restart count `0`, OOM/failing streak `0`.
- Worker due/claimed/retry/poison: `0/0/0/0`; один due Lesson штатно завершён
  после включения worker.
- Outbox pending/dead-letter: `0/0`.
- Access/schedule effective path: `v4/v4`, kill switches `false`.
- Reconciliation после cutover дважды: `issues=[]`.
- Invalid indexes: `0`; три `NOT VALID` constraint — ожидаемые ограничения
  migration `0125` для исторических messenger rows:
  `message_payload_check`, `messages_attachment_file_fk`,
  `messages_voice_duration_check`. Новые/изменяемые rows ими защищены.
- API fatal/runtime markers: `0`; API restarts: `0`.
- Caddy 5xx в чистом post-cutover окне `20 min`: `0`. В более широком окне
  `45 min` было `8` ожидаемых ответов во время контролируемого пересоздания API.
- Пять public readiness samples: `5/5`, average `0.0665 s`, max `0.2164 s`.

## Решение и остаток

Production server и update channels `1.5.2+182` технически выпущены и healthy.
Это переводит `UAT-134` в PASS и обновляет evidence `UAT-000`, `UAT-001`,
`UAT-002`, `UAT-135`, но не заменяет owner-проходы предметных сценариев и
five-role UI/API/DB evidence. Финальная owner-приёмка остаётся открытой.
