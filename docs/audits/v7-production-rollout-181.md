# Production rollout `1.5.1+181`

Дата: `2026-08-11`

Результат: **PASS**

Owner mega-UAT: **IN PROGRESS**, этим rollout не закрыта

## Решение и неизменяемый кандидат

- Владелец разрешил релиз `1.5.1+181` только после подтверждения зелёных gates;
  ранее отдельно принят риск unsigned Windows distribution.
- Source revision: `17ce254f11f353ffe0f6c7914f8f80a942fcf8e4`.
- Предыдущий production image:
  `sha256:a07c39ffe05acf5743ae1a103a1358b2ad24305ef193b2e5579b4923baf9292f`.
- Развёрнутый exact image:
  `sha256:5fbd5a299bb43bb32f5269e446102c6014aac94f803d950b4cfafe217f7ba09f`.
- OCI version/revision и non-root user после cutover: `1.5.1+181`, `17ce254…`,
  `magiccrm`.

До изменения production кандидат прошёл backend `158/158` suites и
`1258/1258` tests, Flutter `667/667`, analyze/build/typecheck, clean migration
ledger `0001..0118`, exact-image live/ready/degraded-503 runtime gate, Trivy
`0` High/Critical/secrets, Gitleaks `0` и production dependency audit `0`.

## Backup и restore-check

- Создан новый encrypted backup
  `magicmusiccrm-staging-20260811T082548Z.tgz.enc`, размер `33 518 176` bytes.
- SHA-256: `00277F6F8639F10BA0A625EA95DA88D2257E08057C15FB5CB42C3B9E56CD18D8`;
  production и off-host копии совпали.
- Финальный isolated restore выполнен отдельной временной БД через containerized
  `pg_restore`; сверены ключевые aggregate counts, применена candidate migration
  `0118`, reconciliation вернула `issues=[]`.
- Два первых запуска restore harness остановились до восстановления данных из-за
  локальной области переменной passphrase и отсутствия host `pg_restore`; оба
  временных окружения очищены. Финальный независимый gate завершился `PASS`,
  остаточных restore DB/containers нет, plaintext backup не оставлен.

## Серверный cutover и rollback

- Перед cutover сохранены Compose/env/revision copies с ограниченным доступом.
- Предыдущий image сохранён immutable-тегом
  `magicmusiccrm-server:rollback-pre-1.5.1-181-20260811T083534Z`.
- Completion worker был выключен на время пересоздания API, candidate прошёл
  worker-paused readiness gate, затем worker включён и API пересоздан штатно.
- Автоматический rollback был вооружён, но не запускался: все финальные gates
  завершились успешно.

Итог после cutover:

- `/health/live` и `/health/ready`: `ok`, migration
  `0118_lesson_participant_exclusions`;
- worker due/claimed/retry/poison: `0/0/0/0`;
- outbox pending/dead-letter: `0/0`;
- access/schedule effective path: `v4/v4`;
- reconciliation дважды: `issues=[]`;
- пять production role login/profile checks: `5/5`
  (`client/teacher/admin/manager/director`), без сохранения credentials/tokens;
- пять public readiness samples: average `0.1361 s`, max `0.4178 s`;
- API restarts/runtime errors/Caddy 5xx: `0/0/0`.

## Публикация клиентов

Старые `latest.json` и `latest-v2.json` сохранены как rollback-копии. Сначала
под versioned именами опубликованы и сверены все client artifacts, затем оба
манифеста атомарно переключены на build `181`. HTTPS HEAD всех четырёх файлов
вернул `200`, локальные и remote SHA-256 совпали:

| Artifact | SHA-256 |
|---|---|
| Windows ZIP | `78D5F7B3C559C4155959D766F2593F69E445F665C54DF416B4BE58ED3BFA7067` |
| Windows Setup | `CC8970F75CE22E57445D67EF58CDA5E0A9A176ECEC12EADE73C451DA5BFEE8B6` |
| Android APK | `2A8EDF3548873FFA64402B405EDD11D8CF815DBB89C64A42204E09F403A1739A` |
| Android AAB | `823579EDEE8CAFA3C2F22965E14EC02971F1613FE1C6CA3045924F79FF94ABB8` |

Оба публичных манифеста возвращают `version=1.5.1+181`, `buildNumber=181`,
правильный Windows ZIP URL и его SHA-256. Post-rollout Windows executable с
ранее зафиксированным hash оставался запущенным после 15 секунд. Android API 35
повторно установил APK, вывел `magic.crm` в foreground и сохранил работающий
процесс; FATAL/ANR/`E/flutter` — `0`.

## Оставшиеся условия

- Интерактивный elevated install/launch/uninstall smoke нового unsigned Setup
  не выполнен из non-interactive сессии; portable Windows ZIP проверен.
- Матрица owner mega-UAT остаётся `10 PASS / 29 PARTIAL / 61 PENDING`.
- `T7.1.4`, `T7.1.2` и `INT-S6` нельзя закрыть одним фактом технически успешного
  rollout: затронутым предметным строкам ещё нужны уникальные production
  UI/API/DB-доказательства и итоговая owner-приёмка.
