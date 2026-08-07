# 🔎 MagicMusicCRM v7 — Deep Probe и 26-point UI acceptance

| Поле | Значение |
|---|---|
| Дата | 2026-08-07 |
| Режим | Deep PROFILE → REASON → OBJECT → BENCHMARK → EMIT |
| Объём | Flutter + NestJS + PostgreSQL + Windows + Android 15/API 35 + production API |
| Кандидат | `1.5.1+157` |
| Решение | **ENGINEERING PASS; PRODUCTION BLOCKED BY VERSION SKEW** |

## 1. Executive conclusion

Кодовая и UI-поверхность v7 подтверждена по исходным 26 пунктам ТЗ: длинная/адаптивная карточка, навигационный workspace, расписания, commerce, задачи, analytics/configuration и role projection реально отрисованы на Windows/Android. Все 26 пунктов имеют UI evidence либо, для чисто серверных правил, авторитетный contract/reconciliation gate.

Приёмка выявила критичный deployment-разрыв: healthy production API отвечает `404` на три маршрута, которые присутствуют и проходят tests в текущем `server/`:

- `GET /crm/clients/student/:id/internal-note`;
- `GET /crm/clients/student/:id/operational-history`;
- `GET /crm/schedule-plans?clientType=student&clientId=:id`.

Следовательно, публичный frontend-only rollout запрещён. Нужен синхронный backend/migration deployment и повторный LIVE smoke.

## 2. Свежий профиль территории

Deep inventory построен из AST/Git/runtime roots без изменения production-кода.

| Слой | Модули / классы | Строки | Наблюдение |
|---|---:|---:|---|
| `lib/core` | 116 модулей | 27 383 | navigation/session/service trust boundary |
| `lib/features` | 144 модуля | 63 573 | основные production UI workflows |
| `server/src` | 528 модулей / 395 классов | 126 546 | NestJS policy/domain/API boundary |
| `server/db` | 232 файла | 50 814 | additive schema, migrations, reconcile |
| `integration_test` | 14+ сценариев | 2 401+ | Windows/Android runtime acceptance |
| `test/features` | 81 файла | 17 862 | widget/contract regressions |

High-churn seams остаются прежними: client card, schedule, CRM service/controller, router, tasks and reporting. Это аргумент за targeted device evidence, не за rewrite.

## 3. Runtime inspector

### Process roots

1. `lib/main.dart` — Flutter/Riverpod/GoRouter, account session, realtime, notification and Windows updater lifecycle.
2. `server/src/main.ts` — NestJS strict validation, auth/policy boundary, `/api`, CORS, Socket.IO and shutdown hooks.
3. PostgreSQL services/repositories — source of truth for finance, schedule collisions, subscriptions, tasks and access.

### Trust and recovery boundaries

- REST DTO/policy/DB boundary is strong; some Flutter reads remain map-decoded and therefore require runtime smoke.
- Realtime transport is account-scoped and reset before token replacement.
- Workspace persistence is account-scoped and cleared on logout/role change.
- External process spawn remains confined to the signed Windows update broker and repository security gate.

## 4. Что реально нашёл probe

| ID | Находка | Root cause | Действие | Retest |
|---|---|---|---|---|
| P7-01 | На Android tap по Student возвращал на сохранённую доску | async workspace restore происходил после incoming direct link | direct link повторно применяется после restore, если разрешён и отличается | regression + LIVE Android PASS |
| P7-02 | Замена абонемента падала на desktop layout | `Row(crossAxisAlignment: stretch)` находился в вертикально unbounded scroll | cross-axis заменён на `start` в общем comparison widget | Windows lifecycle integration PASS |
| P7-03 | Analytics device-test ожидал старую вкладку `Каталог` | тест отстал от unified IA | ожидание синхронизировано с `Обзор / Журналы`; добавлена XLSX evidence | Windows integration PASS |
| P7-04 | Note/history/plans не работают на real app | production backend старее frontend/server candidate | не маскировать; блокировать rollout до deployment | API probe: `404/404/404` |

## 5. Evidence и gates

- Каноническая матрица: [`docs/audits/v7-26-point-final-verification.md`](../../docs/audits/v7-26-point-final-verification.md).
- Каталог снимков: [`docs/audits/v7-26-point-ui-evidence/README.md`](../../docs/audits/v7-26-point-ui-evidence/README.md).
- Flutter analyze: PASS.
- Flutter full: **645/645**.
- Backend typecheck/build: PASS/PASS.
- Backend full: **155/155 suites, 1237/1237 tests**.
- Real accounts: **5/5 role shells** plus restart/logout/account-switch PASS.
- Android release update-over-install: stored session preserved.
- Production health: `200`; required v7 note/history/plan routes: `404`.

## 6. Risk matrix after retest

| Риск | Вероятность | Влияние | Состояние |
|---|---:|---:|---|
| Backend/frontend version skew | certain | critical | **OPEN — release blocker** |
| Restored workspace overrides compact deep link | low | high | fixed + regression |
| Wide subscription replacement layout crash | low | high | fixed + Windows integration |
| Real-client data variation reveals map-decoding drift | medium | high | keep LIVE smoke after deployment |
| Forbidden finance/config request from lower role | low | critical | Actor/full suites and real role shells green |
| Owner acceptance inferred from source presence | low | high | 26-row screenshot/contract matrix now canonical |

## 7. Decision and next gate

### PASS

- implementation coverage of all 26 requirements;
- Windows/Android production UI rendering;
- five-account authentication and session replacement;
- complete Flutter/backend regression gates;
- root fixes P7-01..P7-03.

### BLOCKED

- final production acceptance while the deployed server lacks current v7 endpoints.

### Required next action

Deploy the backend and migrations from the same accepted revision, then repeat real-account Windows/Android rows 3, 6, 7 and 26. Only a `200`/actor-correct response and clean UI on both platforms can change the release decision to APPROVED.
