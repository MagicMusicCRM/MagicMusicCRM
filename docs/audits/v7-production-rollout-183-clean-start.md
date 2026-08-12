# Production rollout и clean start `1.5.3+183`

Дата: `2026-08-13`

Результат: **PASS**

Owner mega-UAT: **IN PROGRESS**, этим rollout не закрыта

## Зафиксированный кандидат

- Runtime source revision: `c5ad77455738916fe39f422cc2097c7b1aae99e3`.
- Последующие ops-only исправления reset-runbook: `ffeae150`, `18334bea`,
  `94a57de4`; runtime Flutter/NestJS между ними не менялся.
- GitHub Release `v1.5.3` target: `94a57de49581d7a0aac13f71de09c2454cf1ff41`.
- Production image:
  `sha256:62473bb4bf53c6cab51aa22baf5db3e0d018dfe41486f7da11e499ed6d864748`.
- OCI version/revision/user: `1.5.3+183`, `c5ad7745…`, `magiccrm`.
- Migration: `0132_app_registration_source`.
- Предыдущий image `1.5.2+182` сохранён и доказан как совместимый rollback на
  additive-схеме `0132`.

## Полные gates

- Flutter: `789/789`, analyze PASS.
- Backend: `177/177` suites, `1415/1415` tests, typecheck/build PASS.
- Новые точечные проверки: backend `66/66`, Flutter `31/31`, reset contract
  PASS, diff-check PASS.
- Clean production-like migration `0001..0132`, live/ready и reconciliation
  `issues=[]`.
- Exact image: invalid configuration fail-closed, live/ready, healthcheck и
  degraded HTTP `503` PASS.
- Production dependency audit: `0 vulnerabilities`.
- Trivy exact image: `0 High`, `0 Critical`, `0 secrets`.
- Новые server/migration/reset paths: Gitleaks `0`; четыре совпадения полного
  Flutter-tree относятся только к неизменённому Firebase client config.

RepoWise оценил общий commit как `94-й percentile` риска из-за размера и
рассеянности (`50` файлов), поэтому сокращённый gate не использовался.

## Client artifacts

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Windows ZIP | `19 503 589` | `B35300EE65946213975907A6981C09C5F61AEC75227409B6B14AC57BF9B0B044` |
| Windows Setup | `15 365 501` | `965E9060B1455B4D47F5F3659F2315415CBC24F15C30B6D0FBF827F9155C3B67` |
| Android APK | `86 197 641` | `6A37E8A1251361A1199405CFF9052201522A9B3D34D8A0E81A8A43A98B89CC7E` |
| Android AAB | `60 560 016` | `2A86A44F1F61FF8F4AADFEC76575D08D2989118EE2E1AB4DF0F261026072C799` |

- Windows portable launch PASS; Setup `/CURRENTUSER` install → version
  `1.5.3+183` → launch → uninstall PASS. Distribution остаётся unsigned в
  рамках ранее принятого owner-риска.
- APK: package `magic.crm`, `versionName=1.5.3`, `versionCode=183`, minSdk `24`,
  targetSdk `36`, один release signer.
- Android 15/API 35: `adb install -r`, cold launch, foreground Activity и
  визуальный тёмный login screen PASS; `FATAL/ANR/E/flutter=0`.
- AAB release signature PASS; self-signed upload certificate и отсутствие
  timestamp являются ожидаемыми свойствами приватного upload key.

## Server rollout

- Перед deploy создан encrypted backup
  `magicmusiccrm-staging-20260812T230138Z.tgz.enc`, `34 011 024` bytes,
  SHA-256
  `F01BECBD7776929B5E7FF4F7F71C2321DE77CD90BFD37E8168A62DF09ABBBE12`;
  off-host копия совпала.
- Isolated restore восстановил migration `0131`, `1098` users и оба
  сохраняемых аккаунта.
- Migration `0132` сначала применена при работающем старом API; старый image
  остался healthy. Candidate затем прошёл readiness/reconciliation с
  выключенными workers и повторно после их включения.
- Automatic rollback был вооружён, но не запускался.

## Prelaunch reset

Сохранены:

- один `system_admin` и директор Назарова Наталия;
- их `users/profiles/staff_members`, неизменённые password hashes и отключённый
  email OTP директора;
- системный чат `Объявления`;
- системный источник `Приложение`;
- `10` системных и `40` полезных пользовательских полей;
- capability/role/legal registry и минимальные Lead/Student CRM-конструкторы.

Удалены клиенты, остальные пользователи/сотрудники/преподаватели, филиалы,
аудитории, расписание, занятия, планы, задачи, сообщения, абонементы, оплаты,
финансовые факты, uploads и все определения `hollihopId`.

- Reset backup:
  `magicmusiccrm-staging-20260812T231419Z.tgz.enc`, `34 011 488` bytes,
  SHA-256
  `297729F512B07F4D621693459A327BB692AB8CDB9E3905C2EDCCFA465EDB9DA3`.
- Remote SHA, off-host SHA и isolated restore `0132 / 1098 / retained=2` PASS.
- SQL reset был одной repeatable-read transaction и завершился
  `RESET|OK|2|2|10|40|1|1`.
- После commit обычный host `mv` storage получил permission denied. Wrapper
  вернул exact API/Caddy через `finally`; затем 7 файлов были recoverable
  скопированы в versioned quarantine, сверены по каждому SHA-256, рабочее
  storage очищено, Redis `FLUSHALL`, exact containers запущены повторно.
- Финальный DB gate:
  `POST_RESET_DB|PASS|2|2|2|10|40|1|1|1`.
- Итог: `0` Leads/Students/Teachers/Branches/Rooms/Lessons/Payments/
  Subscriptions/Messages/File objects, `0` HolliHop fields, один reset audit
  fact.

## Публикация и post-release

- Оба прежних manifest build `182` сохранены в
  `downloads/rollback/manifests-20260812T232217Z-pre-183`.
- `latest.json` и `latest-v2.json` атомарно переключены на
  `version=1.5.3+183`, `buildNumber=183` и exact Windows ZIP SHA-256.
- Все четыре public URL: HTTP `200`, размеры совпадают; Windows ZIP скачан
  полностью из public manifest, SHA-256 совпал.
- GitHub Release `v1.5.3` содержит те же четыре файла; GitHub digests совпали.
- Post-release: public readiness `5/5`, avg `0.068 s`, max `0.2232 s`;
  reconciliation `issues=[]`, API restart `0`, новых fatal/5xx `0`, storage
  files `0`, Redis keys `0`, OTP-bypass директора присутствует.

Production server, update channels и разрешённый clean start технически
завершены. Предметная owner-UAT на новых реальных данных остаётся отдельной
работой.
