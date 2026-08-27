# Campaign-12 independent whole-campaign review

- Reviewer: `/root/campaign12_whole_review`
- Literal range: `9cb1f506a5c5418650926fe53b81fe2667ba9bd7..734a5f0f44b6bd9ec8861c05ec4e0c3959f697f1`
- Verdict: **ACCEPTED**
- Severity totals: Critical **0**, Important **0**, Minor **1**

## Corrective dispositions

1. **ChatInfoController — resolved.** Disposed/request/mute/membership
   generations now invalidate late or stale async completions. Delayed success,
   delayed error, stale mute, and post-dispose I/O tests protect the contract.
2. **TeacherStatsController — resolved.** Per-operation generations protect
   reference, report, query, rate, group-rate, and export lifecycles. Tests
   cover delayed success/error, latest-request-wins, and post-dispose I/O.
3. **SubscriptionIssueSheet — resolved.** Both post-await accesses to the
   `DirtyFormExitController` are guarded by `mounted`. Delayed preview and
   delayed commit disposal tests reproduce and protect the fix.
4. **Messenger and SubscriptionIssue DI guards — resolved.** Their AST tests
   now assert exact parameter names, owner types, and `private readonly`
   modifiers instead of only constructor arity.

Focused corrective evidence is Flutter `45/45` with targeted analyzer zero,
backend boundary tests `12/12` with typecheck PASS, and `git diff --check`
PASS. The final full Flutter gate is recorded in the global evidence file.

## Remaining Minor and owner ruling

The active-app-account lookup remains duplicated between
`auth-password-recovery.service.ts` and `auth-verification.service.ts`. The
predicates are currently identical, so this is a future drift risk rather than
a security or behavior regression. It is explicitly deferred to the planned
Auth repository consolidation, where a shared repository owner can preserve
enumeration resistance without widening this corrective lifecycle commit.

## Metric rulings

- The persisted Sentrux whole-repository baseline is stale. The exact Campaign
  baseline is fan-out `32 -> 35`, while production improves `23 -> 22`; the
  four added fan-out files are test/spec guards with no runtime blast.
- RepoWise missing-test ranges in `magic_crm_service.dart` and
  `lesson-command.service.ts` are compile-time barrel/type-only wiring already
  covered by direct architecture and contract tests.
- RepoWise percentile `100/high` is treated as the expected size/diffusion
  signal for the 106-production-file campaign, not defect evidence; acceptance
  still requires the separately verified empty hard/security arrays.

Final reviewer ruling: the campaign range has no unresolved Critical or
Important finding and is accepted subject only to the executable global gate.
