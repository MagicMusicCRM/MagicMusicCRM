# INT-S0 — Baseline & Evidence Integration Gate

**Date:** 2026-07-25

**Result:** PASS

**Tested revision:** `f77ea8970d1a6f97cc485cb46cdef2f7cc207769`

**Machine result:** `docs/audits/v4-s0-gate-result.json`

## Scope

Gate запущен командой:

```powershell
pwsh -File scripts/v4_sprint_gate.ps1 -Sprint S0
```

Скрипт создал detached clean worktree из tested revision, выполнил все gates
из lock-файлов, проверил отсутствие skipped integration suites и удалил
worktree после завершения. Основной developer worktree не использовался как
доказательство clean-checkout.

## Results

| Gate | Result |
|---|---:|
| S0 tasks/evidence inventory | PASS |
| Current-state inventory `-Check` | PASS |
| Backend `npm ci` | 681 packages from lock |
| Backend typecheck/build | PASS / PASS |
| Explicit platform PostgreSQL suite | 1/1 suite, 5/5 tests |
| Full backend regression | 103/103 suites, 929/929 tests |
| Flutter analyze | No issues found |
| Flutter full test | 400/400 tests |
| Dependency lock integrity | PASS |
| Clean tracked worktree | PASS |
| Skipped integration suites | 0 |

Полный gate завершился за `519.322 s`.

## Data gates

- Read-only preflight выполнен дважды: `15` checks, `19` стабильных findings,
  digest
  `ad5b694d8de542f2e9e30d553935c85e66acfb4d8012dd54eda88ee48be7cadf`.
- Оба preflight-run подтвердили `transaction_read_only=on` и отклонение
  контрольного write с SQLSTATE `25006`.
- Reconciliation clean fixture: `8 → 8`, unexplained drift `0`.
- Reconciliation drift fixture: `8 → 9`, найден ровно `1` искусственный
  duplicate; Ed25519 signatures обоих отчётов проверены.

## Reproducibility correction

Первые диагностические прогоны обнаружили, что source digest inventory
зависел от CRLF/LF при `core.autocrlf=true`. `scripts/v4_inventory.ps1`
теперь нормализует line endings до LF перед SHA-256. Отдельный detached
worktree probe и итоговый полный gate подтвердили одинаковый digest.

## Known baseline observations

`npm ci` по-прежнему сообщает четыре ранее зафиксированные transitive
advisories (`1 low`, `3 high`). INT-S0 не меняет lock-файлы и не расширяет
scope до dependency upgrade; ни одна проверка не была отключена ради PASS.

## Conclusion

T8.1.1–T8.1.5 интегрированы: baseline воспроизводим, данные измеримы,
platform primitives проходят реальные concurrency tests, а preflight и
reconciliation пригодны как gates для следующих sprint/domain migrations.
Sprint S1 может начинаться с `T2.1.1`.
