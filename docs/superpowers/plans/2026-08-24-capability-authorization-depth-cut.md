# Capability Authorization Depth Cut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `EffectiveAccessEvaluator -> HardInvariantPolicy` while preserving every capability decision and mutation invariant.

**Architecture:** Capability-specific hard denies become a pure function beside the authoritative capability registry. The stateless effective evaluator calls that function directly; the mutation-oriented `HardInvariantPolicy` delegates to the same function so there is one rule source.

**Tech Stack:** NestJS 11, TypeScript 5.8, Jest 30, RepoWise, Sentrux

**Spec:** `docs/superpowers/specs/2026-08-24-sentrux-depth-double-cut-design.md`

## Global Constraints

- Preserve all RBAC decisions, hard-deny precedence, exception codes, decision sources, and reason strings.
- Do not change capability keys, role packages, rollout flags, resource scope, endpoints, DTOs, database schema, or production state.
- Keep role assignment, user deactivation, override mutation, emergency-surface, and last-system-admin rules in `HardInvariantPolicy`.
- Run Sentrux rescan, health, and architectural rules after each committed task.
- Keep each logical refactor in its own commit and do not include unrelated working-tree changes.

## File Structure

- `server/src/access-control/capability-registry.ts`: capability definitions plus the pure capability hard-deny decision.
- `server/src/access-control/capability-registry.spec.ts`: direct unit contract for capability hard denies.
- `server/src/access-control/hard-invariant.policy.ts`: mutation invariants and compatibility delegation.
- `server/src/access-control/effective-access-evaluator.ts`: stateless effective-access composition.
- `server/src/access-control/effective-access-evaluator.spec.ts`: six-role and precedence contract.
- `server/src/access-control/capability-request-authorizer.ts`: request-time evaluator construction.
- `server/src/access-control/access-mutations.service.ts`: access snapshot evaluator construction.
- `server/src/crm/clients/client-card.integration.spec.ts`: integration construction update.

---

### Task 1: Centralize capability hard-deny rules

**Files:**
- Create: `server/src/access-control/capability-registry.spec.ts`
- Modify: `server/src/access-control/capability-registry.ts`
- Modify: `server/src/access-control/hard-invariant.policy.ts`

**Interfaces:**
- Consumes: existing `AccessRole` and `CapabilityKey` registry types.
- Produces: `CapabilityHardInvariantDecision` and `resolveCapabilityHardInvariant(role, capabilityKey)`.

- [ ] **Step 1: Write the failing registry contract test**

```ts
import { resolveCapabilityHardInvariant } from "./capability-registry";

describe("resolveCapabilityHardInvariant", () => {
  it.each([
    ["teacher", "schedule.lesson.write", "teacher_hard_deny"],
    ["admin", "config.crm.edit", "config_role_hard_deny"],
    ["admin", "workflow.task.write", "admin_persona_hard_deny"],
    ["manager", "commerce.school_finance.read", "director_or_system_admin_required"],
  ] as const)("denies %s / %s", (role, capabilityKey, reason) => {
    expect(resolveCapabilityHardInvariant(role, capabilityKey)).toEqual({
      allowed: false,
      reason,
    });
  });

  it("does not hard-deny a valid package decision or system_admin", () => {
    expect(resolveCapabilityHardInvariant("manager", "report.status.read")).toBeNull();
    expect(resolveCapabilityHardInvariant("system_admin", "config.crm.edit")).toBeNull();
  });
});
```

- [ ] **Step 2: Run the new test and verify the missing export failure**

Run:

```powershell
Set-Location server
npm test -- --runTestsByPath src/access-control/capability-registry.spec.ts
```

Expected: FAIL because `resolveCapabilityHardInvariant` is not exported.

- [ ] **Step 3: Add the pure registry decision**

Move the four capability deny sets from `hard-invariant.policy.ts` into
`capability-registry.ts`, then add:

```ts
export interface CapabilityHardInvariantDecision {
  allowed: false;
  reason: string;
}

export function resolveCapabilityHardInvariant(
  role: AccessRole,
  capabilityKey: CapabilityKey,
): CapabilityHardInvariantDecision | null {
  if (role === "system_admin") return null;
  if (role === "teacher" && TEACHER_HARD_DENIES.has(capabilityKey)) {
    return { allowed: false, reason: "teacher_hard_deny" };
  }
  if (
    (role === "client" || role === "teacher" || role === "admin") &&
    CONFIG_CAPABILITIES.has(capabilityKey)
  ) {
    return { allowed: false, reason: "config_role_hard_deny" };
  }
  if (role === "admin" && ADMIN_PERSONA_DENIED_CAPABILITIES.has(capabilityKey)) {
    return { allowed: false, reason: "admin_persona_hard_deny" };
  }
  if (DIRECTOR_ONLY_CAPABILITIES.has(capabilityKey) && role !== "director") {
    return { allowed: false, reason: "director_or_system_admin_required" };
  }
  return null;
}
```

Replace `HardInvariantPolicy.capabilityDecision` with delegation while retaining
its public return type:

```ts
capabilityDecision(
  role: AccessRole,
  capabilityKey: CapabilityKey,
): InvariantDecision | null {
  return resolveCapabilityHardInvariant(role, capabilityKey);
}
```

- [ ] **Step 4: Run registry, evaluator, and access-mutation tests**

```powershell
Set-Location server
npm test -- --runTestsByPath src/access-control/capability-registry.spec.ts src/access-control/effective-access-evaluator.spec.ts src/access-control/access-mutations-postgres.integration.spec.ts
```

Expected: PASS with unchanged decision reasons.

- [ ] **Step 5: Run typecheck and Sentrux gate**

```powershell
Set-Location server
npm run typecheck
Set-Location ..
```

Then call Sentrux `rescan`, `health`, and `check_rules`. Expected: typecheck
PASS, rules PASS, no new cycle, and `quality_signal >= 4975`.

- [ ] **Step 6: Commit the centralized rule source**

```powershell
git add -- server/src/access-control/capability-registry.ts server/src/access-control/capability-registry.spec.ts server/src/access-control/hard-invariant.policy.ts
git commit -m "refactor(access): centralize capability hard denies"
```

---

### Task 2: Make effective access evaluation stateless

**Files:**
- Modify: `server/src/access-control/effective-access-evaluator.ts`
- Modify: `server/src/access-control/effective-access-evaluator.spec.ts`
- Modify: `server/src/access-control/capability-request-authorizer.ts`
- Modify: `server/src/access-control/access-mutations.service.ts`
- Modify: `server/src/crm/clients/client-card.integration.spec.ts`

**Interfaces:**
- Consumes: `resolveCapabilityHardInvariant(role, capabilityKey)` from Task 1.
- Produces: dependency-free `new EffectiveAccessEvaluator()` with unchanged `evaluate(input)` output.

- [ ] **Step 1: Update the evaluator test to require a dependency-free constructor**

Remove the `HardInvariantPolicy` import and change the fixture to:

```ts
const evaluator = new EffectiveAccessEvaluator();
```

Keep the existing six-role matrix, teacher hard-deny, system-admin,
fail-closed, override, and resource-scope expectations unchanged.

- [ ] **Step 2: Run the evaluator test and verify constructor failure**

```powershell
Set-Location server
npm test -- --runTestsByPath src/access-control/effective-access-evaluator.spec.ts
```

Expected: FAIL because the current constructor requires `HardInvariantPolicy`.

- [ ] **Step 3: Rewire the evaluator to the registry function**

In `effective-access-evaluator.ts`, import
`resolveCapabilityHardInvariant`, remove the `HardInvariantPolicy` import and
constructor, and replace the policy call with:

```ts
const invariant = resolveCapabilityHardInvariant(
  input.actor.role,
  input.capability.key,
);
```

In `capability-request-authorizer.ts`, remove the `HardInvariantPolicy` import
and construct:

```ts
const decision = new EffectiveAccessEvaluator().evaluate({
```

In both `access-mutations.service.ts` construction sites and the client-card
integration fixture, use `new EffectiveAccessEvaluator()`.

- [ ] **Step 4: Run the focused authorization contract**

```powershell
Set-Location server
npm test -- --runTestsByPath src/access-control/capability-registry.spec.ts src/access-control/effective-access-evaluator.spec.ts src/access-control/capability-request-authorizer.spec.ts src/common/security/jwt-auth.guard.spec.ts src/access-control/access-mutations-postgres.integration.spec.ts src/crm/clients/client-card.integration.spec.ts
```

Expected: PASS. No decision source, reason, or authorization outcome changes.

- [ ] **Step 5: Run typecheck and build**

```powershell
Set-Location server
npm run typecheck
npm run build
Set-Location ..
```

Expected: both commands PASS.

- [ ] **Step 6: Run Sentrux gate**

Call Sentrux `rescan`, `health`, and `check_rules`. Expected: rules PASS, no new
cycle, `quality_signal >= 4975`; depth may remain 13 until the notification cut.

- [ ] **Step 7: Commit the access dependency cut**

```powershell
git add -- server/src/access-control/effective-access-evaluator.ts server/src/access-control/effective-access-evaluator.spec.ts server/src/access-control/capability-request-authorizer.ts server/src/access-control/access-mutations.service.ts server/src/crm/clients/client-card.integration.spec.ts
git commit -m "refactor(access): flatten effective access evaluation"
```
