# Schedule Commerce Reconciliation and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconcile legacy scheduled lesson defaults, prove the unified schedule/payment workflows without 500 responses, and cut a verified `1.5.31+211` Windows and production release with a compatible rollback.

**Architecture:** Add a domain-aware dry-run/apply reconciliation command that classifies records before any mutation and invokes existing versioned services for safe repairs. Then run focused, full, device, security, image, backup/restore, and post-deploy checks against one exact commit; publish client manifests only after backend readiness and reconciliation are clean.

**Tech Stack:** NestJS 11, TypeScript 5.8, PostgreSQL, Jest 30, Flutter/Dart, PowerShell, Docker/OCI, Inno Setup, existing guarded production scripts.

**Spec:** `docs/superpowers/specs/2026-09-03-unified-student-schedule-and-settlement-policy-design.md`

## Global Constraints

- Dry-run is mandatory before apply; no production mutation or deploy occurs without a fresh explicit owner command.
- Historical terminal settlements, audit history, reservation history, and manual operator choices are never rewritten.
- Repairs use expected version, idempotency, domain services, audit/outbox, and transaction boundaries.
- Production release requires a fresh encrypted off-host backup, isolated candidate/rollback restore drill, exact-image evidence, and post-deploy reconciliation.
- Schema migration `0147_lesson_reservation_history` remains the database head for this release; policy metadata and partial durations use existing revisioned JSON/fact contracts, so release 211 adds no schema migration. Destructive down migration is forbidden after new financial facts exist.
- Public release artifacts and `assets/release_history.json` must agree with `pubspec.yaml` version `1.5.31+211` and build `211` before manifest switch.

---

### Task 1: Add dry-run/apply reconciliation for legacy automatic defaults

**Files:**
- Create: `server/src/migration/commerce/v8/lesson-settlement-policy-data.ts`
- Create: `server/src/migration/commerce/v8/lesson-settlement-policy-data.spec.ts`
- Create: `server/src/migration/commerce/v8/lesson-settlement-policy-report.ts`
- Create: `server/src/migration/commerce/v8/settlement-policy-configuration.ts`
- Create: `server/src/migration/commerce/v8/settlement-policy-configuration.spec.ts`
- Modify: `server/package.json`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: server-owned settlement resolver, lesson planned-settlement service, schedule-plan mutation service, current lifecycle/version, and audit metadata.
- Produces: `npm run v8:settlement-policy:reconcile -- --output <path>` and `npm run v8:settlement-policy:apply -- --input <dry-run-report> --output <path>`.
- Produces: `ensureSystemSettlementPolicyRevision(client: PoolClient, actorUserId: string): Promise<{ revisionId: string; created: boolean }>`.
- Produces: `classifySettlementPolicyCandidate(input: SettlementPolicyCandidateInput): SettlementPolicyClassification`.

- [ ] **Step 1: Write failing classification and immutability tests**

```ts
it("classifies only provable automatic full-rate omissions as repairable", () => {
  expect(classifySettlementPolicyCandidate(candidate({
    lifecycleState: "scheduled",
    settlementTypeKey: "lesson",
    teacherCompensationRuleKey: "none",
    teacherCompensationSource: null,
    manualReason: null,
  }))).toBe("repairable_automatic");
});

it.each([
  { lifecycleState: "successfully_completed", reason: "terminal" },
  { lifecycleState: "cancelled", reason: "terminal" },
  { teacherCompensationSource: "manual", reason: "explicit_manual" },
  { manualReason: "Договорённость", reason: "explicit_manual" },
])("does not repair $reason records", (override) => {
  expect(classifySettlementPolicyCandidate(candidate(override))).not.toBe("repairable_automatic");
});
```

Add schedule-series cases for full settlement + missing source, zero settlement + `none`, partial values, inactive penalty, malformed legacy JSON, and records changed after report generation.

Add configuration tests proving apply publishes one system-owned policy revision
with `penalty_lesson` inactive, all duration modes present, and no duplicate
revision on idempotent rerun.

- [ ] **Step 2: Run the reconciliation tests**

Run: `cd server; npm test -- --runTestsByPath src/migration/commerce/v8/lesson-settlement-policy-data.spec.ts src/migration/commerce/v8/settlement-policy-configuration.spec.ts`

Expected: FAIL because the V8 reconciliation command does not exist.

- [ ] **Step 3: Implement a PII-free signed report**

```ts
export type SettlementPolicyClassification =
  | "clean"
  | "repairable_automatic"
  | "explicit_manual"
  | "historical_terminal"
  | "ambiguous"
  | "invalid";

export interface SettlementPolicyRepairCandidate {
  entityType: "lesson_plan" | "schedule_series";
  entityId: string;
  expectedVersion: number;
  currentDecisionHash: string;
  proposedDecision: LessonFinancialDecision;
  classification: SettlementPolicyClassification;
  reasonCode: string;
}

export interface SettlementPolicyReconciliationReport {
  mode: "dry-run" | "apply";
  generatedAt: string;
  candidateRevision: string;
  counts: Record<SettlementPolicyClassification, number>;
  candidates: SettlementPolicyRepairCandidate[];
  issues: Array<{ entityType: string; entityId: string; code: string }>;
  invariants: {
    futureLessonCountBefore: number;
    futureLessonCountAfter: number;
    activeReservationUnitsBefore: string;
    activeReservationUnitsAfter: string;
    effectiveTeacherFactCountBefore: number;
    effectiveTeacherFactCountAfter: number;
    schedulePlanVersionChanges: Array<{ planId: string; before: number; after: number }>;
  };
  reportSha256: string;
}
```

The report contains UUIDs, hashes, counts, and reason codes only; no client, student, teacher names, contacts, notes, tokens, or environment values. Exit code is 0 for clean/repairable dry-run, 2 for ambiguous/invalid data, and 1 for execution failure.

- [ ] **Step 4: Implement apply through domain commands**

Apply accepts only a report produced from the same candidate revision, recomputes `reportSha256` over the canonical report without that field, re-reads each entity, checks expected version and decision hash, skips terminal/manual records, and calls the existing planned-settlement or plan-row mutation command with deterministic idempotency key `v8:settlement-policy:<entityType>:<entityId>:<currentDecisionHash>`. Before repairing rows it calls `ensureSystemSettlementPolicyRevision` in the controlled migration path and records the new revision ID in the apply report. It writes `teacherCompensationSource: "automatic"`, appends audit/outbox, and emits a new result report with before/after lesson, reservation, teacher-fact, and plan-version invariants. A changed record is reported as `RECONCILIATION_STALE_CANDIDATE`; the command does not overwrite it.

Add scripts:

```json
"v8:settlement-policy:reconcile": "ts-node src/migration/commerce/v8/lesson-settlement-policy-data.ts",
"v8:settlement-policy:apply": "ts-node src/migration/commerce/v8/lesson-settlement-policy-data.ts --apply"
```

Ignore generated `dist/release211/` evidence while keeping curated Markdown evidence tracked.

- [ ] **Step 5: Run tests, typecheck, and commit**

Run: `cd server; npm test -- --runTestsByPath src/migration/commerce/v8/lesson-settlement-policy-data.spec.ts src/migration/commerce/v8/settlement-policy-configuration.spec.ts src/crm/commerce/lesson-settlement-plan.persistence.spec.ts src/crm/schedule/schedule-plan-services.spec.ts; npm run typecheck`

Expected: PASS; a second apply reports zero mutations and the same aggregate state.

```powershell
git add server/src/migration/commerce/v8/lesson-settlement-policy-data.ts server/src/migration/commerce/v8/lesson-settlement-policy-data.spec.ts server/src/migration/commerce/v8/lesson-settlement-policy-report.ts server/src/migration/commerce/v8/settlement-policy-configuration.ts server/src/migration/commerce/v8/settlement-policy-configuration.spec.ts server/package.json .gitignore
git commit -m "feat: reconcile automatic lesson settlement defaults"
```

---

### Task 2: Lock product rules and error-contract regression coverage

**Files:**
- Create: `server/src/crm/schedule/schedule-commerce-http.contract.spec.ts`
- Modify: `server/src/common/filters/safe-exception.filter.ts`
- Modify: `server/src/common/filters/safe-exception.filter.spec.ts`
- Modify: `docs/product/CURRENT-PRODUCT-RULES.md`
- Modify: `docs/architecture/CURRENT-DECISIONS.md`
- Modify: `docs/architecture/NEXT-AGENT-HANDOFF.md`

**Interfaces:**
- Consumes: final endpoints and error codes from the first three implementation plans.
- Produces: an authenticated HTTP matrix covering timeline, plan row removal, cancel, reschedule, partial settlement, and settings protection with a hard `5xx == 0` assertion.

- [ ] **Step 1: Write the failing HTTP matrix**

```ts
it.each([
  ["GET", `/crm/students/${studentId}/lesson-timeline`, undefined, 200],
  ["POST", `/crm/schedule-plans/${planId}/rows/${seriesId}/remove/preview`, rowPreview, 201],
  ["POST", `/crm/lessons/${lessonId}/cancel/preview`, cancelPreview, 201],
  ["POST", `/crm/lessons/${lessonId}/reschedule/preview`, movePreview, 201],
  ["POST", `/crm/lessons/${lessonId}/settle/preview`, invalidPartial, 422],
])("%s %s returns %s without 500", async (method, path, body, expected) => {
  const response = await request(app.getHttpServer())[method.toLowerCase()](path)
    .set(authHeaders)
    .send(body);
  expect(response.status).toBe(expected);
  expect(response.status).toBeLessThan(500);
});
```

Add stale-version, stale-token, forbidden configuration edit, cross-organization student, already-rescheduled source, and concurrent reservation conflict cases. Assert every error body contains stable `code` and safe Russian `message` where the API exposes a message.

- [ ] **Step 2: Run the HTTP contract and filter tests**

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/schedule-commerce-http.contract.spec.ts src/common/filters/safe-exception.filter.spec.ts`

Expected: FAIL for any uncaught domain error or missing stable code.

- [ ] **Step 3: Map only proven domain errors at the shared filter boundary**

Keep programmer/database failures as server errors with correlation IDs, but map known domain exception classes to their intended 409/422/403 status. The response logs include route, code, correlation ID, and stack server-side; the response body never includes SQL, stack, tokens, or raw exception text.

- [ ] **Step 4: Update current rules and decisions**

Document exact approved behavior: global student timeline, rule/exception ordering, signed row removal, cancellation/reschedule finances, independent partial minutes, group teacher fact, system-owned hidden catalogs, credited teacher analytics, penalty disabled for new decisions, and rollback compatibility. Replace superseded statements rather than adding contradictory duplicates.

Run: `cd server; npm test -- --runTestsByPath src/crm/schedule/schedule-commerce-http.contract.spec.ts src/common/filters/safe-exception.filter.spec.ts; npm run typecheck`

Expected: PASS with zero 5xx responses in the matrix.

- [ ] **Step 5: Commit rules and error contracts**

```powershell
git add server/src/crm/schedule/schedule-commerce-http.contract.spec.ts server/src/common/filters/safe-exception.filter.ts server/src/common/filters/safe-exception.filter.spec.ts docs/product/CURRENT-PRODUCT-RULES.md docs/architecture/CURRENT-DECISIONS.md docs/architecture/NEXT-AGENT-HANDOFF.md
git commit -m "test: lock unified schedule commerce contracts"
```

---

### Task 3: Run complete release-candidate verification

**Files:**
- Create: `docs/audits/v8-unified-schedule-commerce-release-211.md`
- Modify: `docs/architecture/NEXT-AGENT-HANDOFF.md`

**Interfaces:**
- Consumes: one clean commit containing the completed implementation plans.
- Produces: exact revision, test counts, risk output, image identity, reconciliation counts, artifact hashes, and known limitations for release 211.

- [ ] **Step 1: Run focused backend gates**

Run:

```powershell
Set-Location server
npm run test:schedule-v4
npm run test:commerce-v4
npm test -- --runInBand --runTestsByPath src/crm/payroll-postgres.integration.spec.ts src/crm/schedule/schedule-commerce-http.contract.spec.ts src/migration/commerce/v8/lesson-settlement-policy-data.spec.ts
npm test -- --runInBand
npm run typecheck
npm run build
Set-Location ..
```

Expected: every command exits 0; the full backend suite passes and the HTTP matrix reports zero 5xx. Record `git status --short` and require no tracked changes before assigning the image revision.

- [ ] **Step 2: Run full Flutter and responsive/device gates**

Run:

```powershell
flutter analyze
flutter test
flutter test integration_test/client_calendar_device_test.dart integration_test/lesson_settlement_device_test.dart integration_test/modal_device_test.dart integration_test/recurring_plans_device_test.dart integration_test/teacher_payroll_device_test.dart -d windows
```

Expected: zero analyzer findings; all unit/widget tests pass; the named Windows device tests cover a 390-equivalent narrow viewport and a 1440 desktop viewport for the calendar, transition forms, recurring rows, modal behavior, and teacher analytics.

- [ ] **Step 3: Run dry-run reconciliation against an isolated production-like restore**

Build the server image from the exact candidate commit, restore the newest scrubbed/authorized backup into an isolated network/volume, then run:

```bash
npm run v8:settlement-policy:reconcile -- --output /evidence/settlement-policy-dry-run.json
npm run v7:reconcile -- --output /evidence/v7-reconcile.json
```

Expected: V7 `issues=[]`; V8 has no `ambiguous` or `invalid` entries. Apply V8 only inside the isolated restore, run it a second time, and require second-apply mutation count `0`.

- [ ] **Step 4: Run structural and security gates**

Run: `repowise update --index-only`

Then request RepoWise `get_change_risk` for the candidate range and verify every high-risk symbol has direct test coverage. Run the repository’s current exact-image, Gitleaks, Trivy HIGH/CRITICAL, strict security, and production-like gates from `scripts/v7_production_image_gate.ps1` and `scripts/v7_production_like_gate.ps1`.

Expected: no new secret, HIGH, or CRITICAL finding; all release blockers resolved or explicitly recorded as pre-existing non-regressions with evidence.

- [ ] **Step 5: Write release evidence and commit it**

Record commands, timestamps, exact commit SHA, counts, image ID/digest, reconciliation hashes/counts, and remaining limitations in `docs/audits/v8-unified-schedule-commerce-release-211.md`. Do not commit raw logs, backups, environment files, auth data, or PII.

```powershell
git add docs/audits/v8-unified-schedule-commerce-release-211.md docs/architecture/NEXT-AGENT-HANDOFF.md
git commit -m "docs: record release 211 verification"
```

---

### Task 4: Build and verify version 1.5.31+211 artifacts

**Files:**
- Modify: `pubspec.yaml`
- Modify: `windows_installer.iss`
- Modify: `assets/release_history.json`
- Modify: `docs/audits/v8-unified-schedule-commerce-release-211.md`

**Interfaces:**
- Consumes: verified candidate commit from Task 3.
- Produces: `MagicMusicCRM-1.5.31-211-windows-x64.zip`, `MagicMusicCRM-1.5.31-211-Setup.exe`, `MagicMusicCRM-1.5.31-211.apk`, and `MagicMusicCRM-1.5.31-211.aab` in `dist/`.

- [ ] **Step 1: Bump every version source and add Russian release history**

Set:

```yaml
version: 1.5.31+211
msix_version: 1.5.31.211
```

Set Inno `AppVersion=1.5.31.211` and `OutputBaseFilename=MagicMusicCRM-1.5.31-211-Setup`. Add release history entry build 211 first, covering the unified lesson timeline, safe recurring-row removal, cancellation/reschedule, partial client/teacher hours, credited analytics, and hidden system policy.

- [ ] **Step 2: Build Windows and Android artifacts**

Run:

```powershell
flutter clean
flutter pub get
flutter build windows --release --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api --dart-define=APP_BUILD_NUMBER=211
Compress-Archive -Path build/windows/x64/runner/Release/* -DestinationPath dist/MagicMusicCRM-1.5.31-211-windows-x64.zip -Force
& "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe" windows_installer.iss
Copy-Item installer_output/MagicMusicCRM-1.5.31-211-Setup.exe dist/MagicMusicCRM-1.5.31-211-Setup.exe -Force
flutter build apk --release --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api --dart-define=APP_BUILD_NUMBER=211
flutter build appbundle --release --dart-define=MAGIC_API_BASE_URL=https://api.magicmusiccrm.ru/api --dart-define=APP_BUILD_NUMBER=211
Copy-Item build/app/outputs/flutter-apk/app-release.apk dist/MagicMusicCRM-1.5.31-211.apk -Force
Copy-Item build/app/outputs/bundle/release/app-release.aab dist/MagicMusicCRM-1.5.31-211.aab -Force
```

- [ ] **Step 3: Install and smoke-test the exact Setup artifact**

Install the Setup build in an isolated Windows user/session. Verify login/session preservation, global client timeline, plan row preview without committing a production mutation, edit/move/cancel preview, Analytics → `Расчёты преподавателей`, and adaptive surfaces at desktop/narrow widths. Confirm the running app reports `1.5.31+211`.

- [ ] **Step 4: Verify artifact hashes and release-history contract**

Run:

```powershell
Get-FileHash -Algorithm SHA256 dist/MagicMusicCRM-1.5.31-211-windows-x64.zip,dist/MagicMusicCRM-1.5.31-211-Setup.exe,dist/MagicMusicCRM-1.5.31-211.apk,dist/MagicMusicCRM-1.5.31-211.aab
$history = Get-Content assets/release_history.json -Raw | ConvertFrom-Json
if ($history.releases[0].version -ne '1.5.31+211' -or $history.releases[0].buildNumber -ne 211) { throw 'Release history mismatch' }
```

Expected: four non-zero artifacts, recorded SHA-256 values, and exact version agreement.

- [ ] **Step 5: Commit version metadata**

```powershell
git add pubspec.yaml windows_installer.iss assets/release_history.json docs/audits/v8-unified-schedule-commerce-release-211.md
git commit -m "chore: prepare release 1.5.31 build 211"
```

---

### Task 5: Deploy and publish only after the owner authorizes release

**Files:**
- Modify: `docs/audits/v8-unified-schedule-commerce-release-211.md`
- Modify: `docs/architecture/NEXT-AGENT-HANDOFF.md`

**Interfaces:**
- Consumes: explicit owner release command, exact final revision/image, verified artifacts, and compatible rollback image.
- Produces: healthy production backend, reconciled data, public build 211 manifests/artifacts, rollback evidence, and post-deploy monitoring evidence.

- [ ] **Step 1: Freeze candidate and rollback identities**

Record full 40-character candidate/rollback revisions, immutable image digests, version strings, current/expected migration `0147_lesson_reservation_history`, and the 0147 DB contract values required by `infra/scripts/deploy-api-release.sh`. The rollback runtime must accept both build-210 `financialDecision` and build-211 `successorFinancialDecision` reschedule payloads and normalize both as successor-only; the pre-bridge 210 server is not a valid rollback after build 211 is public. Build candidate and rolling-compatible rollback compose overrides under `/opt/magicmusiccrm/releases/1.5.31-211-<sha>/`.

- [ ] **Step 2: Create and verify a fresh encrypted off-host backup**

Use the established production backup job, copy the encrypted result off-host, and run `infra/scripts/verify-release-backup-compatibility.sh` in isolated networks/volumes with both candidate and rollback images. Require candidate migration/reconciliation and rollback reconciliation to pass; keep migration 0147 installed during application rollback.

- [ ] **Step 3: Run guarded backend cutover and production reconciliation**

Invoke `/opt/magicmusiccrm/infra/scripts/deploy-api-release.sh` with the recorded candidate/rollback overrides, images, revisions, versions, and exact 0147 contract arguments. After readiness is 200, run V7 reconciliation and V8 dry-run. If V8 reports only `repairable_automatic`, apply that exact content-addressed report, rerun both reconciliations, and require `issues=[]`, V8 second-apply mutations `0`, queues/poison `0`, restart count `0`, and fresh API/Caddy 5xx `0`.

Save the previous effective settlement-policy revision ID before apply. The
application rollback procedure restores that revision for new decisions after
writers stop, then runs V7/V8 reconciliation; it does not delete facts created
under the release-211 revision.

- [ ] **Step 4: Publish artifacts and manifests atomically**

Run:

```powershell
./scripts/publish-windows-update.ps1 -BuildNumber 211 -Version '1.5.31+211' -Notes $releaseNotes
```

The script verifies history/version/artifacts, uploads `release-history.json` before manifest switch, and atomically replaces `latest.json` and `latest-v2.json`. Verify each public URL and SHA-256, then publish the matching GitHub release tag `v1.5.31` using the same four artifacts and release notes.

- [ ] **Step 5: Verify, document, and commit release state**

Run authenticated read-only production checks for the student timeline, rule ordering, subscription badges, teacher analytics credited hours, and protected configuration. Exercise mutation previews only unless the owner supplied dedicated production fixtures. Repeat readiness, V7/V8 reconciliation, queue, restart, and 5xx checks after the observation window; record exact evidence and rollback boundary.

```powershell
git add docs/audits/v8-unified-schedule-commerce-release-211.md docs/architecture/NEXT-AGENT-HANDOFF.md
git commit -m "docs: record production release 211"
```
