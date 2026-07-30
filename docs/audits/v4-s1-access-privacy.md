# INT-S1 — Access & Privacy

Дата: 2026-07-30  
Статус: PASS

## Gate

- Все `T2.1.1–T2.4.1` и `T1.1.1–T1.1.2` закрыты, обязательные evidence присутствуют.
- Access policy/mutations/invalidation: 7/7 suites, 103/103 tests.
- Actor Matrix и teacher payload scan: 2/2 suites, 9/9 tests.
- Flutter capability shell/editor/RBAC: 25/25 tests.
- Backend typecheck: clean.

## Инварианты

- Шесть ролей совпадают с approved allow/deny и resource projection.
- Manager role/override mutations denied; Flutter access controls=0.
- Director управляет только lower roles и не видит `system_admin`.
- `system_admin` скрыт из business surface и получает root только через emergency surface.
- Две сессии получают committed access invalidation, control/route исчезает не позднее 5 секунд.
- Teacher payload содержит 0 contact/finance/subscription/private-comment leaks.

Machine-readable result: `docs/audits/v4-s1-gate-result.json`.

