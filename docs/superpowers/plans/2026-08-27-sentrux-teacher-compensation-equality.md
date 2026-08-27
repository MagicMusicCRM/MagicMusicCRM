# Sentrux Teacher Compensation Equality Cut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Partition `calculateTeacherCompensation` into three bounded decision helpers while preserving every financial result and error precedence and strictly improving server-only Sentrux equality.

**Architecture:** The exported function remains the only public entry point and ordered orchestrator. Three non-exported same-file helpers own numeric parsing/limits, override policy, and exhaustive mode calculation; no import, DTO, persistence, transaction, or database boundary changes.

**Tech Stack:** NestJS, TypeScript 5.8, Jest 30, PostgreSQL, RepoWise 0.42, Sentrux 0.5.7

**Spec:** `docs/superpowers/specs/2026-08-27-five-hour-hotspot-sprint-design.md`

## Global Constraints

- Modify only `server/src/crm/commerce/lesson-settlement.calculation.ts` and `server/src/crm/commerce/lesson-settlement.calculation.spec.ts`.
- Preserve the exported signature, seven-key result, all error codes, exact error order, half-up rounding, all five modes, and equal/changed override behavior.
- Do not change imports, persistence, transactions, PostgreSQL source, routes, DTOs, public exports, lockfiles, Sentrux policy, or Sentrux baseline.
- Require `calculateTeacherCompensation` CCN `<= 8`, each new helper CCN `<= 10`, and file max CCN `<= 15`.
- Produce one focused lane commit; RepoWise reindex and paired stock Sentrux scans belong to the coordinator after cherry-pick.

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `server/src/crm/commerce/lesson-settlement.calculation.ts` | Modify | Public orchestrator plus three private decision helpers |
| `server/src/crm/commerce/lesson-settlement.calculation.spec.ts` | Modify | Complete result, rounding, override, and precedence characterization |
| `server/src/crm/commerce/lesson-settlement.port.ts` | Verify only | Authoritative five-value compensation union |
| `server/src/crm/commerce/lesson-settlement-execution.ts` | Verify only | Production consumer |
| Persistence/PostgreSQL specs | Run only | Downstream financial invariants |

The authoritative union is:

```ts
export type TeacherCompensationFactType =
  | "none"
  | "standard"
  | "percent"
  | "fixed"
  | "hourly";
```

At approved HEAD the target is CCN 31, cognitive complexity 34, and 58 NLOC; file coverage is 84% lines and 70.45% branches.

## Shared Test Types

Add these immediately inside the existing `describe` block:

```ts
type TeacherInput = Parameters<typeof calculateTeacherCompensation>[0];
type TeacherResult = ReturnType<typeof calculateTeacherCompensation>;

const validTeacherInput: TeacherInput = {
  durationMinutes: 60,
  legacyType: "fixed",
  legacyRateRubles: "700.00",
  mode: "fixed",
  configuredValue: "50000",
};
```

---

### Task 1: Replace partial mode assertions with complete results

**Files:**

- Modify: `server/src/crm/commerce/lesson-settlement.calculation.spec.ts:55-156`

**Interfaces:**

- Consumes: public `calculateTeacherCompensation`
- Produces: full seven-key compatibility fixtures for every mode and legacy calculation

- [ ] **Step 1: Replace the five-mode table (5 minutes).**

Replace the current partial five-mode test with:

```ts
it.each([
  {
    mode: "none",
    configuredValue: "0",
    expected: {
      standardAmountMinor: "75000",
      defaultValue: "0",
      actualValue: "0",
      rateMinor: "0",
      snapshotRate: "0.00",
      amountMinor: "0",
      overrideReason: null,
    },
  },
  {
    mode: "standard",
    configuredValue: "0",
    expected: {
      standardAmountMinor: "75000",
      defaultValue: "75000",
      actualValue: "75000",
      rateMinor: "75000",
      snapshotRate: "750.00",
      amountMinor: "75000",
      overrideReason: null,
    },
  },
  {
    mode: "percent",
    configuredValue: "5000",
    expected: {
      standardAmountMinor: "75000",
      defaultValue: "75000",
      actualValue: "5000",
      rateMinor: "75000",
      snapshotRate: "750.00",
      amountMinor: "37500",
      overrideReason: null,
    },
  },
  {
    mode: "fixed",
    configuredValue: "60000",
    expected: {
      standardAmountMinor: "75000",
      defaultValue: "60000",
      actualValue: "60000",
      rateMinor: "60000",
      snapshotRate: "600.00",
      amountMinor: "60000",
      overrideReason: null,
    },
  },
  {
    mode: "hourly",
    configuredValue: "120000",
    expected: {
      standardAmountMinor: "75000",
      defaultValue: "120000",
      actualValue: "120000",
      rateMinor: "120000",
      snapshotRate: "1200.00",
      amountMinor: "90000",
      overrideReason: null,
    },
  },
] satisfies Array<{
  mode: TeacherInput["mode"];
  configuredValue: string;
  expected: TeacherResult;
}>)("calculates the complete $mode result", ({
  mode,
  configuredValue,
  expected,
}) => {
  expect(calculateTeacherCompensation({
    durationMinutes: 45,
    legacyType: "hourly",
    legacyRateRubles: "1000.00",
    mode,
    configuredValue,
  })).toEqual(expected);
});
```

- [ ] **Step 2: Add complete legacy standard calculations (5 minutes).**

```ts
it.each([
  {
    legacyType: "fixed",
    expected: {
      standardAmountMinor: "100000",
      defaultValue: "100000",
      actualValue: "100000",
      rateMinor: "100000",
      snapshotRate: "1000.00",
      amountMinor: "100000",
      overrideReason: null,
    },
  },
  {
    legacyType: "hourly",
    expected: {
      standardAmountMinor: "75000",
      defaultValue: "75000",
      actualValue: "75000",
      rateMinor: "75000",
      snapshotRate: "750.00",
      amountMinor: "75000",
      overrideReason: null,
    },
  },
  {
    legacyType: "none",
    expected: {
      standardAmountMinor: "0",
      defaultValue: "0",
      actualValue: "0",
      rateMinor: "0",
      snapshotRate: "0.00",
      amountMinor: "0",
      overrideReason: null,
    },
  },
] satisfies Array<{
  legacyType: TeacherInput["legacyType"];
  expected: TeacherResult;
}>)("preserves the complete legacy $legacyType result", ({
  legacyType,
  expected,
}) => {
  expect(calculateTeacherCompensation({
    durationMinutes: 45,
    legacyType,
    legacyRateRubles: "1000.00",
    mode: "standard",
    configuredValue: "0",
  })).toEqual(expected);
});
```

- [ ] **Step 3: Add half-up boundary coverage (5 minutes).**

```ts
it.each([
  {
    name: "legacy hourly below half",
    input: {
      durationMinutes: 29,
      legacyType: "hourly",
      legacyRateRubles: "0.01",
      mode: "standard",
      configuredValue: "0",
    },
    expected: {
      standardAmountMinor: "0", defaultValue: "0", actualValue: "0",
      rateMinor: "0", snapshotRate: "0.00", amountMinor: "0",
      overrideReason: null,
    },
  },
  {
    name: "legacy hourly exact half",
    input: {
      durationMinutes: 30,
      legacyType: "hourly",
      legacyRateRubles: "0.01",
      mode: "standard",
      configuredValue: "0",
    },
    expected: {
      standardAmountMinor: "1", defaultValue: "1", actualValue: "1",
      rateMinor: "1", snapshotRate: "0.01", amountMinor: "1",
      overrideReason: null,
    },
  },
  {
    name: "teacher hourly below half",
    input: {
      durationMinutes: 29,
      legacyType: "none",
      legacyRateRubles: "0",
      mode: "hourly",
      configuredValue: "1",
    },
    expected: {
      standardAmountMinor: "0", defaultValue: "1", actualValue: "1",
      rateMinor: "1", snapshotRate: "0.01", amountMinor: "0",
      overrideReason: null,
    },
  },
  {
    name: "teacher hourly exact half",
    input: {
      durationMinutes: 30,
      legacyType: "none",
      legacyRateRubles: "0",
      mode: "hourly",
      configuredValue: "1",
    },
    expected: {
      standardAmountMinor: "0", defaultValue: "1", actualValue: "1",
      rateMinor: "1", snapshotRate: "0.01", amountMinor: "1",
      overrideReason: null,
    },
  },
  {
    name: "percent below half",
    input: {
      durationMinutes: 60,
      legacyType: "fixed",
      legacyRateRubles: "0.01",
      mode: "percent",
      configuredValue: "4999",
    },
    expected: {
      standardAmountMinor: "1", defaultValue: "1", actualValue: "4999",
      rateMinor: "1", snapshotRate: "0.01", amountMinor: "0",
      overrideReason: null,
    },
  },
  {
    name: "percent exact half",
    input: {
      durationMinutes: 60,
      legacyType: "fixed",
      legacyRateRubles: "0.01",
      mode: "percent",
      configuredValue: "5000",
    },
    expected: {
      standardAmountMinor: "1", defaultValue: "1", actualValue: "5000",
      rateMinor: "1", snapshotRate: "0.01", amountMinor: "1",
      overrideReason: null,
    },
  },
] satisfies Array<{
  name: string;
  input: TeacherInput;
  expected: TeacherResult;
}>)("$name uses half-up rounding", ({ input, expected }) => {
  expect(calculateTeacherCompensation(input)).toEqual(expected);
});
```

- [ ] **Step 4: Replace override partial assertions (5 minutes).**

```ts
it.each([
  {
    name: "numerically equal override",
    input: {
      ...validTeacherInput,
      overrideValue: "050000",
      overrideReason: "Игнорируется",
    },
    expected: {
      standardAmountMinor: "70000",
      defaultValue: "50000",
      actualValue: "50000",
      rateMinor: "50000",
      snapshotRate: "500.00",
      amountMinor: "50000",
      overrideReason: null,
    },
  },
  {
    name: "changed override",
    input: {
      ...validTeacherInput,
      overrideValue: "60000",
      overrideReason: "  Согласовано директором  ",
    },
    expected: {
      standardAmountMinor: "70000",
      defaultValue: "50000",
      actualValue: "60000",
      rateMinor: "60000",
      snapshotRate: "600.00",
      amountMinor: "60000",
      overrideReason: "Согласовано директором",
    },
  },
  {
    name: "percent validates the overridden value",
    input: {
      ...validTeacherInput,
      mode: "percent",
      configuredValue: "20001",
      overrideValue: "20000",
      overrideReason: "  Согласовано директором  ",
    },
    expected: {
      standardAmountMinor: "70000",
      defaultValue: "70000",
      actualValue: "20000",
      rateMinor: "70000",
      snapshotRate: "700.00",
      amountMinor: "140000",
      overrideReason: "Согласовано директором",
    },
  },
] satisfies Array<{
  name: string;
  input: TeacherInput;
  expected: TeacherResult;
}>)("$name returns the complete normalized result", ({ input, expected }) => {
  expect(calculateTeacherCompensation(input)).toEqual(expected);
});
```

- [ ] **Step 5: Run the characterization baseline (5 minutes).**

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/lesson-settlement.calculation.spec.ts
```

Expected: PASS. This is deliberately GREEN characterization for a behavior-neutral refactor.

### Task 2: Freeze multi-invalid error precedence

**Files:**

- Modify: `server/src/crm/commerce/lesson-settlement.calculation.spec.ts`

**Interfaces:**

- Produces: an ordered public-function table covering all eight error codes

- [ ] **Step 1: Add the precedence table (5 minutes).**

```ts
it.each([
  {
    name: "duration before every later invalidity",
    input: {
      durationMinutes: 0,
      legacyRateRubles: "bad",
      mode: "percent",
      configuredValue: "bad",
      overrideValue: "bad",
      overrideReason: " ",
    },
    code: "INVALID_LESSON_DURATION",
  },
  {
    name: "legacy money before teacher syntax",
    input: {
      legacyRateRubles: "bad",
      mode: "percent",
      configuredValue: "bad",
      overrideValue: "bad",
      overrideReason: " ",
    },
    code: "INVALID_MONEY",
  },
  {
    name: "teacher syntax before teacher limit",
    input: {
      legacyRateRubles: "92233720368547758.08",
      mode: "standard",
      configuredValue: "bad",
      overrideValue: "9223372036854775808",
    },
    code: "INVALID_TEACHER_VALUE",
  },
  {
    name: "teacher limit before override prohibition",
    input: {
      mode: "standard",
      configuredValue: "9223372036854775808",
      overrideValue: "1",
    },
    code: "TEACHER_VALUE_TOO_LARGE",
  },
  {
    name: "override prohibition before reason and final limit",
    input: {
      legacyRateRubles: "92233720368547758.08",
      mode: "standard",
      configuredValue: "0",
      overrideValue: "1",
    },
    code: "TEACHER_OVERRIDE_NOT_ALLOWED",
  },
  {
    name: "percent limit before reason and final limit",
    input: {
      legacyRateRubles: "92233720368547758.08",
      mode: "percent",
      configuredValue: "0",
      overrideValue: "20001",
    },
    code: "INVALID_TEACHER_PERCENT",
  },
  {
    name: "changed override reason before final limit",
    input: {
      legacyRateRubles: "92233720368547758.08",
      mode: "fixed",
      configuredValue: "1",
      overrideValue: "2",
      overrideReason: " ",
    },
    code: "TEACHER_OVERRIDE_REASON_REQUIRED",
  },
  {
    name: "final standard limit",
    input: {
      legacyRateRubles: "92233720368547758.08",
      mode: "fixed",
      configuredValue: "1",
    },
    code: "TEACHER_AMOUNT_TOO_LARGE",
  },
  {
    name: "final calculated amount limit",
    input: {
      durationMinutes: 61,
      legacyType: "none",
      legacyRateRubles: "0",
      mode: "hourly",
      configuredValue: "9223372036854775807",
    },
    code: "TEACHER_AMOUNT_TOO_LARGE",
  },
  {
    name: "none rejects even an equal override",
    input: {
      mode: "none",
      configuredValue: "0",
      overrideValue: "0",
      overrideReason: "Игнорируется",
    },
    code: "TEACHER_OVERRIDE_NOT_ALLOWED",
  },
] satisfies Array<{
  name: string;
  input: Partial<TeacherInput>;
  code: string;
}>)("$name", ({ input, code }) => {
  expect(() => calculateTeacherCompensation({
    ...validTeacherInput,
    ...input,
  })).toThrow(new LessonSettlementCalculationError(code));
});
```

- [ ] **Step 2: Run the expanded public-function suite (5 minutes).**

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/lesson-settlement.calculation.spec.ts
```

Expected: PASS with the order `duration -> legacy money -> teacher syntax -> teacher limit -> override prohibition -> percent limit -> reason -> final amount limit`.

### Task 3: Partition the decision function

**Files:**

- Modify: `server/src/crm/commerce/lesson-settlement.calculation.ts:71-136`

**Interfaces:**

- Produces: `parseTeacherValues`, `teacherOverrideState`, `resolveTeacherModeValues`
- Preserves: the byte-identical exported input signature and result keys

- [ ] **Step 1: Record the structural RED (2 minutes).**

```powershell
repowise health . --file server/src/crm/commerce/lesson-settlement.calculation.ts --format json
```

Expected before implementation: `calculateTeacherCompensation` CCN 31, cognitive 34, and 58 NLOC. Behavior tests remain green; complexity is the RED signal.

- [ ] **Step 2: Add numeric parsing and limits (5 minutes).**

Insert before the exported function:

```ts
function parseTeacherValues(
  configuredValue: string,
  overrideValue: string | undefined,
): { configured: bigint; overridden: bigint } {
  if (
    !/^\d+$/.test(configuredValue) ||
    (overrideValue !== undefined && !/^\d+$/.test(overrideValue))
  ) {
    throw new LessonSettlementCalculationError("INVALID_TEACHER_VALUE");
  }
  const configured = BigInt(configuredValue);
  const overridden = overrideValue === undefined
    ? configured
    : BigInt(overrideValue);
  if (configured > maxMinor || overridden > maxMinor) {
    throw new LessonSettlementCalculationError("TEACHER_VALUE_TOO_LARGE");
  }
  return { configured, overridden };
}
```

- [ ] **Step 3: Add override policy (5 minutes).**

```ts
function teacherOverrideState(
  mode: TeacherCompensationFactType,
  overrideValue: string | undefined,
  configured: bigint,
  overridden: bigint,
  overrideReason: string | undefined,
): { hasOverride: boolean; normalizedReason: string | undefined } {
  if (
    (mode === "none" || mode === "standard") &&
    overrideValue !== undefined
  ) {
    throw new LessonSettlementCalculationError(
      "TEACHER_OVERRIDE_NOT_ALLOWED",
    );
  }
  if (mode === "percent" && overridden > 20_000n) {
    throw new LessonSettlementCalculationError("INVALID_TEACHER_PERCENT");
  }
  const hasOverride =
    overrideValue !== undefined && overridden !== configured;
  const normalizedReason = overrideReason?.trim();
  if (hasOverride && !normalizedReason) {
    throw new LessonSettlementCalculationError(
      "TEACHER_OVERRIDE_REASON_REQUIRED",
    );
  }
  return { hasOverride, normalizedReason };
}
```

- [ ] **Step 4: Add exhaustive mode calculation (5 minutes).**

```ts
function resolveTeacherModeValues(
  mode: TeacherCompensationFactType,
  standardAmount: bigint,
  configured: bigint,
  overridden: bigint,
  durationMinutes: number,
): {
  defaultValue: bigint;
  actualValue: bigint;
  rate: bigint;
  amount: bigint;
} {
  switch (mode) {
    case "none":
      return { defaultValue: 0n, actualValue: 0n, rate: 0n, amount: 0n };
    case "standard":
      return {
        defaultValue: standardAmount,
        actualValue: standardAmount,
        rate: standardAmount,
        amount: standardAmount,
      };
    case "percent":
      return {
        defaultValue: standardAmount,
        actualValue: overridden,
        rate: standardAmount,
        amount: roundRatio(standardAmount * overridden, 10_000n),
      };
    case "fixed":
      return {
        defaultValue: configured,
        actualValue: overridden,
        rate: overridden,
        amount: overridden,
      };
    case "hourly":
      return {
        defaultValue: configured,
        actualValue: overridden,
        rate: overridden,
        amount: roundRatio(
          overridden * BigInt(durationMinutes),
          60n,
        ),
      };
    default:
      mode satisfies never;
      return {
        defaultValue: configured,
        actualValue: overridden,
        rate: overridden,
        amount: overridden,
      };
  }
}
```

The `satisfies never` expression makes a future union member fail typecheck. The fallback preserves the current untyped-runtime behavior for an invalid value instead of adding a new error contract.

- [ ] **Step 5: Replace only the exported body (5 minutes).**

Keep the current signature and replace its body with:

```ts
{
  if (!Number.isInteger(input.durationMinutes) || input.durationMinutes <= 0) {
    throw new LessonSettlementCalculationError("INVALID_LESSON_DURATION");
  }
  const legacyRate = rublesToMinor(input.legacyRateRubles);
  const standardAmount = input.legacyType === "fixed"
    ? legacyRate
    : input.legacyType === "hourly"
      ? roundRatio(legacyRate * BigInt(input.durationMinutes), 60n)
      : 0n;
  const { configured, overridden } = parseTeacherValues(
    input.configuredValue,
    input.overrideValue,
  );
  const { hasOverride, normalizedReason } = teacherOverrideState(
    input.mode,
    input.overrideValue,
    configured,
    overridden,
    input.overrideReason,
  );
  const { defaultValue, actualValue, rate, amount } =
    resolveTeacherModeValues(
      input.mode,
      standardAmount,
      configured,
      overridden,
      input.durationMinutes,
    );
  if (standardAmount > maxMinor || amount > maxMinor) {
    throw new LessonSettlementCalculationError("TEACHER_AMOUNT_TOO_LARGE");
  }
  return {
    standardAmountMinor: standardAmount.toString(),
    defaultValue: defaultValue.toString(),
    actualValue: actualValue.toString(),
    rateMinor: rate.toString(),
    snapshotRate: minorToRubles(rate),
    amountMinor: amount.toString(),
    overrideReason: hasOverride ? normalizedReason! : null,
  };
}
```

- [ ] **Step 6: Run GREEN behavior and structural checks (5 minutes).**

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/lesson-settlement.calculation.spec.ts
repowise health . --file server/src/crm/commerce/lesson-settlement.calculation.ts --format json
```

Expected: behavior PASS; exported function CCN `<= 8`, every new helper `<= 10`, and file maximum `<= 15`.

### Task 4: Run downstream financial gates and commit

**Files:**

- Verify only: calculation, catalog, execution, persistence, and PostgreSQL specs
- Commit only: calculation source and its direct spec

**Interfaces:**

- Produces: one cherry-pickable Lane C commit
- Commit message: `refactor(server): partition teacher compensation decisions`

- [ ] **Step 1: Run unit and persistence suites (5 minutes).**

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/lesson-settlement.calculation.spec.ts src/crm/commerce/lesson-settlement-catalog.spec.ts src/crm/commerce/lesson-settlement-execution.spec.ts src/crm/commerce/lesson-settlement-plan.persistence.spec.ts
```

Expected: all 4 suites pass.

- [ ] **Step 2: Run the mandatory local PostgreSQL suite (5 minutes).**

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/lesson-settlement-postgres.integration.spec.ts
```

Expected: PASS against the configured loopback database. If local PostgreSQL is unavailable or the suite fails, omit Lane C; unit-only acceptance is forbidden.

- [ ] **Step 3: Run compiler and build gates (5 minutes).**

```powershell
npm --prefix server run typecheck
npm --prefix server run build
```

Expected: both commands exit 0.

- [ ] **Step 4: Check scope and whitespace (2 minutes).**

```powershell
git diff --check
git status --short
```

Expected: only the calculation source and calculation spec are modified. Do not run `repowise update` in the lane worktree.

- [ ] **Step 5: Commit Lane C (3 minutes).**

```powershell
git add -- server/src/crm/commerce/lesson-settlement.calculation.ts server/src/crm/commerce/lesson-settlement.calculation.spec.ts
git diff --cached --check
git commit -m "refactor(server): partition teacher compensation decisions"
```

Expected: one focused commit and a clean lane worktree.

### Task 5: Apply coordinator-owned equality acceptance

**Files:**

- No additional file changes
- Measure integrated main after accepted Lane B and cherry-picked Lane C

**Interfaces:**

- Consumes: the immediate stock `preC2` server snapshot and Lane C SHA
- Produces: accepted/rejected `postC2` equality result

- [ ] **Step 1: Verify all TypeScript sensor bytes (3 minutes).**

```powershell
$typeScriptSensorHashes = [ordered]@{
  "C:\Users\Alinka\.sentrux\plugins\typescript\plugin.toml" = "27219129BB53AFB16D2E3D407C592B2CF3F600A42F724A6EF9974FB9CA375406"
  "C:\Users\Alinka\.sentrux\plugins\typescript\queries\tags.scm" = "0977EE307FBBD8E9607932763BB81446D305D37A639E7FDBA0562FC542E40BA7"
  "C:\Users\Alinka\.sentrux\plugins\typescript\grammars\windows-x86_64.dll" = "37DD6AD9E4C9458CA45A3021A95F93F11C28B231DB7BCEF890D96376464BE169"
}
foreach ($sensorEntry in $typeScriptSensorHashes.GetEnumerator()) {
  $actualSensorHash = (
    Get-FileHash -Algorithm SHA256 -LiteralPath $sensorEntry.Key
  ).Hash
  if ($actualSensorHash -ne $sensorEntry.Value) {
    throw "TypeScript sensor hash mismatch: $($sensorEntry.Key)"
  }
}
```

- [ ] **Step 2: Capture the immediate stock pre-C2 snapshot (5 minutes).**

After Lane B acceptance and before Lane C cherry-pick, use a fresh stock Sentrux MCP process:

```text
mcp__sentrux__scan({"path":"C:/Users/Alinka/Documents/Codex Import/MagicMusicCRM/server"})
mcp__sentrux__health({})
```

If Lane B was omitted, this snapshot is M0. Store the complete response as `preC2`.

- [ ] **Step 3: Capture post-C2 under identical sensor bytes (5 minutes).**

Cherry-pick Lane C, restart a fresh stock MCP process, repeat the same calls, and store the response as `postC2`. Re-run the exact hash block from Step 1.

- [ ] **Step 4: Apply every equality predicate (3 minutes).**

Accept only when all predicates hold:

```text
postC2.root_causes.equality.score > preC2.root_causes.equality.score
postC2.root_causes.equality.raw < preC2.root_causes.equality.raw
postC2.root_causes.equality.score > 5475
postC2.root_causes.equality.raw < 0.4525196921628077
postC2.quality_signal >= preC2.quality_signal
postC2.total_import_edges <= preC2.total_import_edges
postC2.cross_module_edges <= preC2.cross_module_edges
postC2.root_causes.depth.raw <= preC2.root_causes.depth.raw
postC2.root_causes.acyclicity.raw == 0
```

These are the exact MCP field paths. Root equality 6,512 remains informational.

- [ ] **Step 5: Inspect RepoWise and run change risk (5 minutes).**

```powershell
repowise health . --file server/src/crm/commerce/lesson-settlement.calculation.ts --format json
git diff --check
sentrux check .
```

Call RepoWise MCP `get_change_risk` with the resolved full SHA `revspec = $integratedLaneC`, `baseline = 50`, and `extensions = [".ts"]`; run every additional coverage-backed impacted test it names. Required: Sentrux rules 2/2, target complexity gates met, no missing-test signal, and no unexplained high-severity finding. The orchestration plan performs the single final RepoWise reindex after all accepted structural commits.

## Rollback

Before commit:

```powershell
git restore --source=HEAD -- server/src/crm/commerce/lesson-settlement.calculation.ts server/src/crm/commerce/lesson-settlement.calculation.spec.ts
```

After integration, use the exact integrated SHA captured by the coordinator; never rediscover it by commit-message grep:

```powershell
if ([string]::IsNullOrWhiteSpace($integratedLaneC)) {
  throw "Integrated Lane C SHA was not supplied"
}
git cat-file -e "${integratedLaneC}^{commit}"
if ($LASTEXITCODE -ne 0) { throw "Integrated Lane C commit is invalid" }
git revert --no-edit $integratedLaneC
```

Rerun the complete calculation, downstream, PostgreSQL, RepoWise, and Sentrux gates. There are no migrations, persisted-format changes, environment changes, production mutations, or data operations to reverse.
