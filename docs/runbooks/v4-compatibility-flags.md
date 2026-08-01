# v4 Compatibility Flags & Kill Switches

Access and schedule start in `shadow` mode: the legacy path remains
authoritative and the v4 decision is compared using safe IDs/booleans only.

| Domain | Mode flag | Kill switch |
|---|---|---|
| Access | `V4_ACCESS_MODE=legacy|shadow|v4` | `V4_ACCESS_KILL_SWITCH=true` |
| Schedule | `V4_SCHEDULE_MODE=legacy|shadow|v4` | `V4_SCHEDULE_KILL_SWITCH=true` |

`v4` mode is allowed only after
`npm --prefix server run v4:shadow-compare -- --require-zero-unexplained`
reports zero unexplained differences. A kill switch always forces the effective
path back to `legacy` and disables shadow work immediately; restart the service
after changing environment values.

Set `V4_PARITY_UNEXPLAINED_DIFFS=0` only from the accepted machine report.
`GET /health/ready` publishes the resolved modes and returns
`checks.v4Rollout=blocked` if a domain requests `v4` while that value is nonzero.

Safe sequence: `legacy → shadow → v4`. Rollback sequence: set the domain kill
switch to `true`, restart, verify health and actor/schedule smoke, then diagnose
the ID-only shadow report before clearing the switch.
