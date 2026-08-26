Campaign baseline: 9cb1f506a5c5418650926fe53b81fe2667ba9bd7

# Tier 1 Lane C — Subscription issue owners

## Scope delivered

- Split the unchanged `SubscriptionIssueService` API into preview, commercial terms, purchase command, grant command, and stable result owners.
- Preserved the preview/blocker/commit lifecycle, signed-token binding and stale checks, deterministic IDs, mutation metadata, audit/outbox payloads, append-only fact ordering, stable projection, and replay-safe reservation publication.
- Kept `CommerceMutationMetadata` import-compatible through the existing facade path.
- Updated only the three lane-owned PostgreSQL integration compositions; `crm.module.ts` wiring remains deferred to the Tier 1 integrator.

## TDD and lane smoke evidence

1. RED: `npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-issue.service.spec.ts --runInBand`
   - Failed because the five semantic owner modules did not exist and the facade still required five legacy dependencies.
2. GREEN: `npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-issue.service.spec.ts src/crm/commerce/subscription-issue-boundary.spec.ts --runInBand`
   - PASS: 2 suites, 9 tests, 0 failures.
3. `npm --prefix server run typecheck`
   - PASS: `tsc --noEmit`, exit 0.
4. `git diff --check`
   - PASS: exit 0; only Git line-ending notices were emitted.

## Permanent boundary evidence

- Facade: 43 NLOC, exactly 3 constructor dependencies, exactly 3 one-statement direct delegations.
- Ceilings: terms 357, preview 196, purchase 250, grant 182, result 66 NLOC.
- Exactly one `executeVersionedMutation` call exists in each command owner and none exists in the facade, contracts, terms, preview, or result owners.
- Purchase and grant guards enforce persistence ordering and `publishPostCommit` after integrity only under `!result.replayed`.
- No Lane C issue source contains `delete from app.`.

## RepoWise evidence

- Shared index lock: `Global\MagicMusicCRM_Campaign12_RepoWise` held for the complete successful update and health block and released in `finally`.
- `repowise update --index-only`: exit 0, `Already up to date.`
- Targeted CLI form: `repowise health --module server/src/crm/commerce --format json`.
- The module JSON explicitly resolved every live Lane C file from `C:\Users\Alinka\Documents\Codex Import\MagicMusicCRM-campaign12-c-subscription-issue`:

| Owner | Health | NLOC | Max CCN | god_class / brain_method |
|---|---:|---:|---:|---|
| `subscription-issue.service.ts` | 8.39 | 43 | 1 | none |
| `subscription-commercial-terms.service.ts` | 8.70 | 357 | 7 | none |
| `subscription-purchase-preview.service.ts` | 7.97 | 196 | 6 | none |
| `subscription-purchase-command.service.ts` | 7.80 | 250 | 5 | none |
| `subscription-grant-command.service.ts` | 8.78 | 182 | 5 | none |
| `subscription-issue-result.service.ts` | 9.47 | 66 | 3 | none |

All production owners satisfy health `>= 7.0`, max CCN `<= 10`, and no god/brain finding.

## Self-review

- Compared the baseline monolith against all extracted production sources: no Russian message, error code, audit marker, or outbox marker was lost or added.
- Confirmed public facade method names, parameter order, metadata export path, transaction callback order, result projection order, and replay behavior.
- No Critical, Important, or Minor findings remain in the Lane C diff.
