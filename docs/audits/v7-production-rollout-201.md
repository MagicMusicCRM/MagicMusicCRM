# Production rollout 1.5.21+201

Дата: 2026-08-29
Git/tag: `63f0021ae7fd357876cd632138130fea8f2ba50e`, `v1.5.21`
Server image: `magicmusiccrm-server:1.5.21-201-63f0021a`
Image ID: `sha256:1d85b615c419d0508795108452fc371fdc97c35af6a733eca60d82ee340e1328`
Final server hotfix: `f09cef3a82e96904dc0422c0a03ab590f8dadb54`
Final image: `magicmusiccrm-server:1.5.21-201-f09cef3a`,
`sha256:3704043308e86615ee7e9eeccb5b98091baab5f873cb2bf0e8c218b5234607f1`
Migration: `0142_schedule_plan_series_subscription_snapshot`

## Выпущенное правило

- Закрытый и исторический период расширяет существующий Schedule Plan: даты
  начала/окончания редактируются через тот же plan flow, а backdated change
  использует signed impact preview. Параллельный legacy-редактор не добавлен.
- Group Lesson с отдельным плательщиком списывает subscription выбранного
  плательщика, но создаёт один client fact на участника и один teacher fact.
- Единственным writer расписания остаётся Plan; legacy series-write отклонён,
  удаление series стало soft-delete. Race с completion worker закрыт row locks.
- Любую ставку преподавателя меняют только Director/system_admin на всех
  backend write-path. Admin/Manager rate-поля игнорируются или получают `403`.
- Lead/Student card сохраняет безопасные поля и staff note автоматически:
  debounce 800 ms, single-flight/coalescing, expected version, retry и защита
  локального draft при `409`. Preview/commit финансов и расписания не autosave.

## Regression и supply-chain gates

- Backend: `267/267` suites, `3308/3308` tests; typecheck и production build
  PASS. Flutter: analyze `0`, `1413/1413` tests PASS.
- Exact product tree артефактов не изменился между feature candidate и финальным
  infra-only commit. Server image имеет те же 10 RootFS layers, migration head
  `0142`, `USER=magiccrm` и readiness healthcheck.
- Два независимых review финального deploy state machine: P0/P1 `0`.
  Gitleaks exact commits: `0`; Trivy: High `0`, Critical `0`, Secrets `0`.
- Android APK: package `magic.crm`, `1.5.21+201`, target `36`, min `24`, v2
  signature PASS. AAB standard jarsigner PASS. Windows portable/Setup прошли
  packaging/hash gates; Authenticode остаётся `NotSigned`, как в предыдущем
  канале, и не заявляется как пройденная подпись.

## Backup и rollback

- Исходный pre-cutover encrypted backup:
  `magicmusiccrm-staging-20260829T013647Z.tgz.enc`, `187008` bytes,
  SHA-256 `b75d1d7230353bf420e7b5de458e9ce601db39a098350395b06630a27ca752d2`.
- После сохранения schema 0142 перед повторным cutover:
  `magicmusiccrm-staging-20260829T024517Z.tgz.enc`, `187536` bytes,
  SHA-256 `579c2d32c6e223056d3b72815d03bda6ea3dbff44ddeb4f42bc2d9a4e169b324`.
  Exact candidate/rollback isolated restore PASS, residue `0`.
- Post-deploy backup:
  `magicmusiccrm-staging-20260829T025527Z.tgz.enc`, `187536` bytes,
  SHA-256 `e648efa03d6fef22f8d79bf2e8255143054395dfefe35e31a397de697c9f4450`.
  Все три backup скопированы off-host с совпавшим SHA-256.
- Immediate server rollback после RBAC hotfix — exact base image
  `magicmusiccrm-server:1.5.21-201-63f0021a`; более глубокий rollback остаётся
  `1.5.18-198-744959ef`. Down migration 0142 запрещён; все server images
  проверены на retained schema 0142. Manifests build 200 сохранены в
  `/opt/magicmusiccrm/releases/client-manifest-rollback-200-20260829T025053Z`.

## Cutover и восстановление

До финального PASS state machine fail-closed выявил два deploy-only дефекта.
Ранний candidate был остановлен до mutation из-за слишком узкого allowlist
исторического migration ID. Следующая попытка использовала недопустимый для
production workers-disabled override; exact build 198 был вручную восстановлен,
schema не менялась. Затем candidate `6cebe7cc` успешно применил 0142, но raw
SHA `pg_get_functiondef()` различался из-за сохранённых CRLF. Тот же false
negative отклонил уже healthy rollback proof, поэтому API/Caddy остались
fail-closed; exact build 198 был восстановлен поверх retained 0142, public
live/ready вернулись `200/200`, reconciliation `issues=[]`, outbox `0/0`.

Финальный runner `63f0021a` canonicalizes только `CRLF → LF`, оставляя lone CR
и изменения body hash-significant. Preflight принимает только exact rollback
0141 либо exact candidate 0142 с повторным чтением migration и полным DB-object
contract. Повторный cutover завершился:

`DEPLOY_API_RELEASE|PASS|image=magicmusiccrm-server:1.5.21-201-63f0021a|revision=63f0021ae7fd357876cd632138130fea8f2ba50e|migration=0142_schedule_plan_series_subscription_snapshot`

После cutover API/Caddy `running`, API `healthy`, restart `0`; все шесть
workers включены. Public live/ready дважды `200/200`, readiness сообщает
database/migrations/workers `ok`, outbox pending/dead `0/0`; V7 reconciliation
дважды вернул `issues=[]`, свежих API error/fatal/unhandled строк нет.

## Server-only RBAC hotfix `f09cef3a`

После base cutover exact-image review обнаружил P1 в HTTP route authorizer:
teacher rate/history/bulk-rate routes требовали широкое право
`commerce.teacher_payroll.write`, доступное операционным Admin/Manager. Service
уже запрещал им менять ставку, поэтому business mutation не происходила, но
невалидный запрос мог попасть в DTO validation и вернуть `400` до owner-only
проверки `403`.

Исправление не создало второй RBAC-контур: все rate-write routes переведены на
каноническое `config.commerce.manage`, а commit-time проверка текущей DB-роли
добавлена в ту же транзакцию до idempotency/version/mutation. Director и
system_admin могут менять ставки; Admin/Manager получают fail-closed `403`.
Компенсационные операции расписания выбирают owner capability только при
реальном изменении ставки, иначе сохраняют штатный `schedule.lesson.write`.
Stale Director→Manager и stale Manager→Director claims закрыты проверкой роли
из БД; payout creation сохранил отдельное операционное право.

Hotfix прошёл isolated production-like gate: `267/267` suites,
`3351/3351` tests, typecheck/build, actor matrix `9/9`, access coverage
`344/344`, два независимых exact-commit review P0/P1 `0`. Semgrep OWASP,
Gitleaks, Trivy image/Dockerfile дали High/Critical/Secrets `0`; strict security
gate — `11 PASS / 0 WARN / 0 FAIL`. Exact image имеет 10 layers,
`USER=magiccrm`, OCI revision `f09cef3a82e96904dc0422c0a03ab590f8dadb54`
и version `1.5.21+201.server.f09cef3a`. Offline tar SHA-256:
`c96041f5e62b21b77c3efcb0e35b3eafa796a7ebb33cf50ce560f99191fd38b6`.

Перед hotfix создан свежий encrypted backup
`/opt/magicmusiccrm/backups/encrypted/magicmusiccrm-staging-20260829T034831Z.tgz.enc`,
`187568` bytes, SHA-256
`9ae736cf8cfb6fb0c0faa8ee704177224c26aec7cbd0ccbbb0e150925a0829e7`.
Он скопирован off-host с совпавшим hash; isolated candidate/base-rollback
compatibility drill на migration 0142 завершился PASS.

Exact deploy завершился:

`DEPLOY_API_RELEASE|PASS|image=magicmusiccrm-server:1.5.21-201-f09cef3a|revision=f09cef3a82e96904dc0422c0a03ab590f8dadb54|migration=0142_schedule_plan_series_subscription_snapshot`

Production marker, image ID, OCI labels и non-root user совпали с candidate;
API `running/healthy`, restart `0`, OOM `false`, все шесть workers включены.
Public live/ready и DB/migration/worker checks дважды PASS, reconciliation
дважды `issues=[]`, outbox `0/0`, свежие API/Caddy 5xx `0`. Унаутентифицированные
rate writes вернули `401` без изменения состояния. Отдельный production smoke
с Manager/Director не выполнялся: задокументированный Manager login вернул
`401`, сохранённые tokens истекли, действующие production credentials не были
предоставлены. Аккаунты и tokens ради теста не создавались; role-specific
защита подтверждена exact-image тестами и отсутствием production mutation.
Client artifacts, manifests и tag `v1.5.21` этим server-only hotfix не менялись.

## Клиент и публичные артефакты

Оба manifest показывают build `201`, version `1.5.21+201`; release history
начинается `201 → 200`. Public streaming SHA-256 совпал с origin-файлами:

- Windows ZIP: `19768771`,
  `0ccf0fd16786a50749b70a0b65e4209a86673c7c664b28c5d713766f8800b246`.
- Setup EXE: `15553500`,
  `3c058cc3566030c1da669cb00cf67c37540ea38629107bd7cf7a1c9d90b5fe15`.
- APK: `87662928`,
  `f220bc6ca8d97cfc0f6739e7735f52ff07a3c57d105ae8c0f93d1f8fb0994dc2`.
- AAB: `61220482`,
  `62e798b4c76bc174898c6fa47a22257d79ea30e94ca56a90db020ab2a0932733`.

Manifest SHA-256: `5bdf7d8f94b6de81e064e245f942c34f70bfc29de50cc4dbbcdf53bb218a7759`;
history SHA-256:
`a44d6eed7b6c1f6a3e16cce28f705b7d0ea92a3e7cb9c41ab68fff3378c4ead7`.
GitHub Release: https://github.com/MagicMusicCRM/MagicMusicCRM/releases/tag/v1.5.21
