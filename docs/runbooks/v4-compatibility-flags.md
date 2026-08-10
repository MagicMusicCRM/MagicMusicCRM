# v4 Compatibility Flags & Kill Switches

In development and staging, access and schedule may start in `shadow` mode:
the legacy path remains authoritative and the v4 decision is compared using
safe IDs/booleans only. Production is fail-closed and starts only when both
domains are explicitly in verified `v4` mode.

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

For `NODE_ENV=production`, configuration validation requires exactly:

- `V4_ACCESS_MODE=v4` and `V4_SCHEDULE_MODE=v4`;
- both `V4_*_KILL_SWITCH=false`;
- `V4_PARITY_UNEXPLAINED_DIFFS=0`.

Missing values, `legacy`, `shadow`, an enabled kill switch, or non-zero parity
stop the process before it can serve traffic. Shadow comparison and kill-switch
rehearsal therefore happen in staging, not inside the production process.

Staging sequence: `legacy → shadow → v4`. Production rollback uses the accepted
previous immutable release and its matching configuration; it does not silently
switch the current candidate to a legacy path.
