# MagicMusicCRM `1.5.27+207` — production release evidence

Дата выпуска: 2026-08-31

Final commit: `f8bafa9a62b2afa0608fd5e89bdbc836200ea616`

Rollback commit: `e5503e511c9cbe9871e9f8dd644550c391cba716`

## Выпущенный контур

- История карточки клиента и журнал Аналитики используют один общий
  человекочитаемый presenter вместо отдельных технических представлений.
- Каждая краткая карточка называет действие, сотрудника и связанную сущность;
  подробности раскрываются по запросу и дают переход к доступному объекту.
- Изменения выводятся безопасными значениями «было → стало» для всего
  поддерживаемого audit payload, а не только для заранее выбранных примеров.
- Внутренние event codes, aggregate versions, UUID, токены, полные заметки и
  другие чувствительные значения не показываются пользователю.
- В карточке клиента сначала отображаются 10 последних событий; остальные
  подгружаются без полной перезагрузки карточки.

## Test, security и package gates

- Flutter full: `1481/1481`; analyze: PASS.
- Backend full: `274/274` suites, `3482/3482` tests; typecheck/build: PASS.
- Deploy, DB, behavior и backup compatibility contract gates: PASS.
- Production-like gate: migration `0145_student_contact_email`, reconciliation
  `issues=[]`; exact-image invalid-config, healthy и degraded readiness: PASS.
- Application security gate: `11 PASS / 0 WARN / 0 FAIL`; Gitleaks: `0`;
  Semgrep OWASP: `0`; Trivy: `0` High/Critical и `0` secrets.
- Windows portable: `1.5.27+207`; Setup: `1.5.27.207`; launch smoke: PASS.
- Android: package `magic.crm`, `versionCode=207`, `versionName=1.5.27`,
  min SDK `24`, target SDK `36`; APK v2 signature и AAB `jar verified`: PASS.

## Production rollout

- Rollback image: `magicmusiccrm-server:1.5.26-206-e5503e511c9c`.
- Final image: `magicmusiccrm-server:1.5.27-207-f8bafa9a62b2`, image
  `sha256:ac33cd552b658c83868afc5b5e931538a74b67906a345a8d68ca32581c46834e`.
- Guarded cutover: `DEPLOY_API_RELEASE|PASS`; migration осталась
  `0145_student_contact_email`.
- Final runtime: user `magiccrm`, healthy, restart `0`, OOM `false`.
- Public live/ready и V7 reconciliation проверены дважды;
  `{"backfill":null,"issues":[]}` в обоих проходах.
- Fresh exhausted email / stale invitation после readiness: `0/0`.
- Production monitor после окна наблюдения: PASS; свежие API ошибки и Caddy
  HTTP 5xx: `0/0`.

## Backup и rollback evidence

- Pre-cutover encrypted backup:
  `magicmusiccrm-staging-20260831T104114Z.tgz.enc`, `208096` bytes, SHA-256
  `b767ddf187a4ec039c46aa54283f5384f5502cfaa556c43df7a6bacd0c3476ad`.
- Post-deploy encrypted backup:
  `magicmusiccrm-staging-20260831T104524Z.tgz.enc`, `208112` bytes, SHA-256
  `c8397e3a7c693e254bb2a47134f99947153d268dec9f4b863baa783c68adcdc2`.
- Оба backup и sidecar скопированы off-host в
  `C:\Users\Alinka\Documents\MagicMusicCRM Backups\2026-08-31`.
- Оба backup прошли isolated candidate/rollback restore для `1.5.27+207` и
  `1.5.26+206`; rollback сохранил forward migration `0145` и clean reconcile.
- Client manifest rollback snapshot:
  `/opt/magicmusiccrm/releases/client-manifest-rollback-206-20260831T104841Z`.

## Опубликованные artifacts

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `MagicMusicCRM-1.5.27-207-windows-x64.zip` | 19789437 | `b737d5994bbd469776ed856b63822d3fef655ca278a4d2a228d86b0e3cfbd160` |
| `MagicMusicCRM-1.5.27-207-Setup.exe` | 15562242 | `5599ee7b0b5ee8786dd1350615f96f47ac2f152e45e0c7735b0189208e6823fd` |
| `MagicMusicCRM-1.5.27-207.apk` | 87680640 | `04151570ddcac8bb86a1069c83e5ab3df712848244171d869d6a5c5e097aaa89` |
| `MagicMusicCRM-1.5.27-207.aab` | 61267200 | `235907605db6ab9a4406046e6eb8430ad2b357a39501a9282429c9ced0bfe4cc` |

Оба public manifest показывают `1.5.27+207`; release history начинается с
build `207`. Все четыре artifacts полностью повторно прочитаны через HTTPS и
совпали с локальными по длине и SHA-256. GitHub Release:
`https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.27`.
