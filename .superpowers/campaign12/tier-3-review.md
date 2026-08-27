# Campaign 12 Tier 3 review

## Final status: ACCEPTED

- Tier 3 base: `37667c097e850092dbafaa0480c5e4b64e623025`.
- Integrated lane HEAD: `8b15134f7d5860cb09e1f8875f0096d7402df074`.
- Final reviewed code/test HEAD: `b586a29dc362b8a860d233f3846d9caff1d2c6a6`.
- Independent reviewer: `/root/campaign12_tier3_review`.
- Initial totals: Critical **0**, Important **4**, Minor **2**.
- Final totals: Critical **0**, Important **0**, Minor **0**.

## Accepted lanes and integration

| Lane | Source commit | Integration merge |
|---|---|---|
| G — Chat info | `d972e2b6840e0eec3d2d3d714d12db05cbac4a33` | `26326e6d` |
| H — Teacher stats | `6910b207daf37499c9eada0d1c0b16661ebc8a6b` | `4039ae24` |
| I — Subscription issue | `f3282da96b2ff1a3acd653ff6ec84703d0002618` | `8b15134f` |

All 19 verify-only paths are blob-identical to the Tier 3 base. The final
integrated smoke passed 48/48 tests; analyzer passed 23/23 targets, formatting
checked 20 files with zero changes, and both scoped and integrated
`git diff --check` passed.

## Findings and fixes

| Finding | Disposition | Fix evidence |
|---|---|---|
| Important — stale preview race | Closed | `9b60d5be`; request id, draft generation, and identity reject stale success/error; runtime test commits only preview/payload/identity B. |
| Important — form-view CCN 19 | Closed | `bf86a873`; exact indexed health `8.10`, NLOC `404`, max CCN `6`. |
| Important — percent→fixed stale visible value | Closed | `3a1d9908`; draft clears and the value field remounts by mode; widget test observes an empty `EditableText`. |
| Important — lexical/fixed-list guards | Closed | `275472a7`, `3d8d4ce1`, `ac16dfac`; shared analyzer-AST guard dynamically discovers owners and has adversarial bypass fixtures. |
| Minor — invalid total | Closed | `3a1d9908`; malformed percent, over-base fixed discount, and non-positive surcharge display `Итого: Не указано`. |
| Minor — verify-only inventory 16/19 | Closed | `b586a29d`; executable plan inventory asserts exactly 19 paths and the live diff is empty. |

The proposed H late-initializer issue was rejected after runtime
characterization in `d563fd4f`: both numeric zero and null open, save, and
produce the intended result.

## Structural and tool evidence

RepoWise was rebuilt from the Tier base because ordinary merge-DAG incremental
updates had previously served stale rows. Exact index SHA is
`b586a29dc362b8a860d233f3846d9caff1d2c6a6`; all 18 production owners are
`<=500` NLOC and max CCN is `10`. Every extracted owner has raw health at least
`8.09` and no god/brain marker. Thin compatibility shells retain low headline
scores from historical churn/co-change only; their current maintainability is
`8.8..9.3` and their AST budgets pass.

RepoWise change risk ranks the deliberately broad tier at percentile `97`
(`Elevated`), driven by 7,204 added lines across 36 files; this is mitigated by
the lane contracts, exact verify-only boundary, focused smoke, AST guards, and
independent review. Coverage map status is present but stale for new owners, so
fresh LCOV remains a Task M global-gate requirement.

Sentrux exact-worktree scan recorded 2,550 files, 5,232 import edges, and quality
signal `5752`; its current root-cause bottleneck is depth `14`. This campaign
continues to remove the remaining god files before the later depth campaign.

Final independent re-review verdict: Critical/Important/Minor **0/0/0 NEW**;
ready to merge **Yes**.
