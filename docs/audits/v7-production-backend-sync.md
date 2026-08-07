# V7 — синхронизация production backend и повторная LIVE-проверка

**Дата:** 2026-08-07

**Кандидат:** `1.5.1+157`

**Развёрнутая ревизия:** `4f1cf3c052f13839930726f1a8b9a738e9fdd01a`

**Итог:** **PRODUCTION BACKEND PASS**

## Причина сбоя

Production работал на ревизии `0488e19` и имел только 102 миграции с последней
`0101_canonical_shared_tasks`. Клиент `1.5.1+157` уже использовал v7 endpoints и
схему `0102..0113`, поэтому карточка клиента получала реальные `404`. Ошибка была
version skew между выпущенным Flutter-клиентом и старым backend/БД, а не
отсутствием реализации в текущем репозитории.

## Резервирование и rollback

- PostgreSQL custom dump:
  `/opt/magicmusiccrm/backups/manual/pre-v7-production-sync-20260807T190035Z.dump`,
  SHA-256 `1ef60ff3e9bb32487f0ae83fc2c034666d53d816207efe6d2b687ef163cc59d3`;
  `pg_restore --list` — PASS.
- Старые исходники:
  `/opt/magicmusiccrm/backups/manual/server-pre-v7-production-sync-20260807T190035Z.tgz`,
  SHA-256 `68f43f3bbbdceb1db520543589f56e2c50922b70c694243ddee902e8fdfd20ea`.
- Объединённая зашифрованная off-host копия: 33,965,344 bytes, SHA-256
  `3bb1a1924d9e9390adf9ce1e32f6937062e2ae5692bd1bbe20123545a37f9fb6`;
  локальный и серверный hashes совпали.
- Старый image сохранён как `magicmusiccrm-v3-api:pre-v7-production-sync`,
  старые исходники — в
  `/opt/magicmusiccrm/releases/pre-v7-production-sync-20260807T190035Z/server`.

## Deployment и схема

- Candidate image собран на сервере из проверенного архива ревизии `4f1cf3c` и
  переключён как `magicmusiccrm-v3-api:latest`.
- API container: `running`, `healthy`, restart count `0`, OOM `false`.
- Применены миграции `0102..0113`; всего в production `114`, последняя —
  `0113_lesson_settlement_plan_revisions`.
- Reconciliation выполнен дважды с одинаковым SHA-256
  `8b17c759359d996cc641a9472c1755bf428b461712848d7286e76ea907c18947`;
  оба результата: `{"backfill":null,"issues":[]}`.

## Production smoke

Публичный HTTPS, реальный Director и production-данные:

| Проверка | Результат |
|---|---:|
| `GET /api/health` | `200` |
| `GET /crm/clients/student/:id/internal-note` | `200` |
| `GET /crm/clients/student/:id/operational-history` | `200` |
| `GET /crm/schedule-plans?studentId=:id&includeEnded=true` | `200` |
| `GET /crm/schedule-series?studentId=:id` | `200` |
| `GET /crm/students/:id/commerce` | `200` |
| Login/profile/access roles `magic1..5` | `5/5` |
| Повторный вход Client → Director → Client | PASS |
| Прямой HTTPS health burst через Wi-Fi | `30/30` |
| Caddy errors после стабилизации | `0` |

Строгий query contract расписаний принимает `studentId`; первоначальный ручной
probe со старыми `clientType/clientId` ожидаемо вернул `400`. Flutter-клиент уже
использует правильный `studentId`, поэтому код менять не потребовалось.

## LIVE UI

- Windows: [карточка/обзор](v7-26-point-ui-evidence/windows/03-postdeploy-client-overview-live.png),
  [раздел занятий](v7-26-point-ui-evidence/windows/02-postdeploy-client-lessons-live.png).
- Android 15: [карточка/обзор](v7-26-point-ui-evidence/android/23-postdeploy-student-overview-live.png),
  [раздел занятий](v7-26-point-ui-evidence/android/24-postdeploy-client-lessons-live.png).
- Android process log scan: `FATAL`, Flutter exception и API `4xx/5xx` — `0`.

Production сейчас не содержит постоянных расписаний (`schedule_plans=0`),
поэтому ради скриншота рабочие данные не создавались. LIVE UI подтверждает
корректный empty state; active/ended/tray состояния дополнительно покрыты
реальными device renders и PostgreSQL lifecycle tests из 26-point pack.

## Локальная сеть проверки

Повторный Windows device-runner дважды встретил TLS EOF через установленный
адаптер `happ-tun`. В те же минуты production containers оставались healthy,
Caddy не фиксировал запросов с ошибкой, а принудительный прямой Wi-Fi-путь дал
`30/30` и role matrix `5/5`. Это локальная transport-проблема VPN-пути, не
backend-регрессия; настройки VPN и маршрутизации пользователя не изменялись.
