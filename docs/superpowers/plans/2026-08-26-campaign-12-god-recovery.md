# Campaign-12 God-Class Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove up to twelve production `god_class` owners in one staged campaign, moving the authoritative production count from `23` to `11` when all twelve lanes pass without changing runtime, API, security, transaction, history, or UI contracts.

**Architecture:** Four dependency-ordered tiers run three isolated lane worktrees from one exact integrated baseline per tier. Each lane lands one semantic cut with a permanent structural guard and focused smoke; the integrator applies lanes in A–L order, owns shared wiring and tier review, and runs repository-wide suites, coverage, recount, Sentrux, and whole-campaign review exactly once after Tier 4.

**Tech Stack:** NestJS 11, TypeScript 5.8, Jest 30, PostgreSQL, Flutter 3.41.4, Dart 3.11.1, Riverpod, `flutter_test`, RepoWise, Sentrux.

**Spec:** `docs/superpowers/specs/2026-08-26-campaign-12-god-recovery-design.md`

## Global Constraints

- Full SHA `41bc4a8c32aeb74263dfa5de975bba1c8f50c868` is the approved source-metrics baseline only. The executable Campaign baseline is the clean full SHA returned by `git rev-parse HEAD` immediately after the commit containing this approved plan and before any implementation; record that literal SHA in all three Tier 1 lane reports and reuse it in the final evidence. Lane A, B, and C start from that same executable baseline; later tiers start from the exact accepted integration commit captured after the preceding tier review commit.
- The production-only RepoWise baseline contains `781` files and exactly `23` `god_class` owners. Acceptance is `23 -> 11` when all twelve lanes integrate, or an exact decrease equal to the number of accepted lanes when a failing lane is omitted.
- Each Tier 1 lane report begins with `Campaign baseline: ` followed by the same lowercase 40-character executable SHA. Final-gate commands derive the baseline from these three independently committed reports and fail when a report is missing, malformed, or disagrees.
- Tier and lane order is fixed: A/B/C, Tier 1 integration/review, D/E/F, Tier 2 integration/review, G/H/I, Tier 3 integration/review, J/K/L, Tier 4 integration/review, then the single global acceptance/evidence task.
- Every lane is one integrated semantic cut. It characterizes missing observable behavior, extracts cohesive owners behind the existing public runtime, removes the god owner or leaves a behavior-free compatibility facade, adds a permanent AST/widget guard, and produces one reversible implementation commit plus one lane report.
- New production owners require RepoWise health `>= 7.0`, max CCN `<= 10`, and no `god_class` or `brain_method`. Every owner and compatibility facade obeys its exact lane NLOC, dependency, method-count, transaction, and direct-delegation ceiling; every new Flutter production file is at most `500` NLOC.
- A lane may modify only its listed files. Shared Nest wiring belongs to the named tier integrator; shared Flutter parents and shared characterization tests are verify-only. An unplanned shared-file requirement stops that lane for an integrator ruling.
- Lane smoke is limited to the exact focused tests, restricted typecheck/analyze/format, live invariant searches, `git diff --check`, `repowise update --index-only`, and targeted health listed in that lane. No lane or tier runs full backend Jest, full Flutter tests, repository coverage, a production recount, Sentrux campaign acceptance, or whole-campaign review.
- Preserve all controller method calls, endpoint paths, DTO imports, guards, role decorators, public signatures, parameter order, response shapes, Russian error text, exported type paths, expected-version rules, idempotency keys, request IDs, audit actions, outbox payloads, and append-only facts.
- Messenger preserves membership and branch scope, masking, message/reference/attachment validation, transaction boundaries, audit, lead intake, realtime, and post-commit fanout order.
- Payroll preserves expected versions, rate and payout transaction boundaries, idempotency, audit/outbox, append-only facts, calculation precision, and export shape. Subscription issues preserve preview/blocker/commit lifecycle, transaction and projection ordering, audit/outbox, and historical records.
- Profile and Auth preserve fail-closed RBAC, credential/OTP/recovery behavior, token/session semantics, password hashing, resource scope, audit, and response shape. LessonTransition and SchedulePlan preserve lock order, expected versions, idempotency, lesson history, neutral command metadata, audit/outbox, and append-only schedule facts.
- Existing Flutter public constructors, callbacks, provider ownership, payload maps, optimistic versions, widget keys, Russian copy, navigation results, dialogs, toasts, error states, focus, scrolling, and accessibility semantics remain stable.
- Flutter continues through existing services/providers; no direct database or Supabase access is introduced. All UI remains Russian and uses only Deep Charcoal & Sophisticated Gold; no light theme, glow, bright gradient, or legacy styling returns.
- Do not edit production deployment state, migrations, production data, secrets, env files, PII, dumps, backups, generated coverage artifacts, or unrelated dirty files.
- Tier 2 cannot start until Tier 1 Critical/Important findings are `0/0`; Tier 3 cannot start until Tier 2 is `0/0`; Tier 4 cannot start until Tier 3 is `0/0`. Minor hardening is deferred only by an explicit owner ruling with its global-gate cost.
- If the final global gate fails, identify the owning cut from lane/tier commit boundaries, fix only that lane, rerun its exact smoke, and rerun the single global gate. Accepted sibling lanes are not rewritten.

## File Ownership and Worktree Scheme

| Tier | Lane | Branch | Worktree | Exclusive production package |
|---:|:---:|---|---|---|
| 1 | A | `codex/campaign12-messenger` | `../MagicMusicCRM-campaign12-a-messenger` | `server/src/messenger` except integrator-owned module wiring |
| 1 | B | `codex/campaign12-payroll` | `../MagicMusicCRM-campaign12-b-payroll` | `server/src/crm/payroll*` and `server/src/crm/payroll/**` |
| 1 | C | `codex/campaign12-subscription-issue` | `../MagicMusicCRM-campaign12-c-subscription-issue` | `server/src/crm/commerce/subscription-issue*` plus listed extracted files |
| 2 | D | `codex/campaign12-profile` | `../MagicMusicCRM-campaign12-d-profile` | `server/src/profile` |
| 2 | E | `codex/campaign12-auth` | `../MagicMusicCRM-campaign12-e-auth` | `server/src/auth` |
| 2 | F | `codex/campaign12-lesson-transition` | `../MagicMusicCRM-campaign12-f-lesson-transition` | listed schedule transition/metadata files and `crm.module.ts` |
| 3 | G | `codex/campaign12-chat-info` | `../MagicMusicCRM-campaign12-g-chat-info` | `lib/core/widgets/telegram/chat_info_*` |
| 3 | H | `codex/campaign12-teacher-stats` | `../MagicMusicCRM-campaign12-h-teacher-stats` | `lib/features/manager/presentation/widgets/teacher_stats_*` |
| 3 | I | `codex/campaign12-subscription-issue-ui` | `../MagicMusicCRM-campaign12-i-subscription-issue-ui` | `lib/features/crm/presentation/client_card/subscription_issue_*` |
| 4 | J | `codex/campaign12-schedule-plan` | `../MagicMusicCRM-campaign12-j-schedule-plan` | listed schedule-plan files and `crm.module.ts` |
| 4 | K | `codex/campaign12-staff-detail` | `../MagicMusicCRM-campaign12-k-staff-detail` | `lib/features/admin/presentation/widgets/staff_detail_*` |
| 4 | L | `codex/campaign12-schedule-reference` | `../MagicMusicCRM-campaign12-l-schedule-reference` | `lib/features/admin/presentation/widgets/schedule_reference_*` |

Create each tier only after its predecessor review commit. These commands guarantee all three lanes in a tier share one full SHA:

```powershell
$SourceMetricsBaseline = '41bc4a8c32aeb74263dfa5de975bba1c8f50c868'
if (git status --porcelain) {
  throw 'Commit or remove every working-tree change before freezing Campaign-12.'
}
git merge-base --is-ancestor $SourceMetricsBaseline HEAD
if ($LASTEXITCODE -ne 0) {
  throw 'The approved source-metrics baseline is not an ancestor of HEAD.'
}
$CampaignBaseline = (git rev-parse HEAD).Trim()
if ($CampaignBaseline.Length -ne 40) {
  throw "Campaign baseline is not a full SHA: $CampaignBaseline"
}
git show-ref --verify --quiet refs/heads/codex/campaign12-integration
if ($LASTEXITCODE -eq 0) {
  throw 'Branch codex/campaign12-integration already exists; inspect it before continuing.'
}
git switch -c codex/campaign12-integration $CampaignBaseline

$Tier1Base = $CampaignBaseline
git worktree add ../MagicMusicCRM-campaign12-a-messenger -b codex/campaign12-messenger $Tier1Base
git worktree add ../MagicMusicCRM-campaign12-b-payroll -b codex/campaign12-payroll $Tier1Base
git worktree add ../MagicMusicCRM-campaign12-c-subscription-issue -b codex/campaign12-subscription-issue $Tier1Base

$Tier2Base = (git rev-parse HEAD).Trim()
git worktree add ../MagicMusicCRM-campaign12-d-profile -b codex/campaign12-profile $Tier2Base
git worktree add ../MagicMusicCRM-campaign12-e-auth -b codex/campaign12-auth $Tier2Base
git worktree add ../MagicMusicCRM-campaign12-f-lesson-transition -b codex/campaign12-lesson-transition $Tier2Base

$Tier3Base = (git rev-parse HEAD).Trim()
git worktree add ../MagicMusicCRM-campaign12-g-chat-info -b codex/campaign12-chat-info $Tier3Base
git worktree add ../MagicMusicCRM-campaign12-h-teacher-stats -b codex/campaign12-teacher-stats $Tier3Base
git worktree add ../MagicMusicCRM-campaign12-i-subscription-issue-ui -b codex/campaign12-subscription-issue-ui $Tier3Base

$Tier4Base = (git rev-parse HEAD).Trim()
git worktree add ../MagicMusicCRM-campaign12-j-schedule-plan -b codex/campaign12-schedule-plan $Tier4Base
git worktree add ../MagicMusicCRM-campaign12-k-staff-detail -b codex/campaign12-staff-detail $Tier4Base
git worktree add ../MagicMusicCRM-campaign12-l-schedule-reference -b codex/campaign12-schedule-reference $Tier4Base
```

Before each three-worktree block, assert the current integration branch is clean and record the corresponding base SHA in all three lane reports. Never remove or reuse a dirty worktree.

## Shared Backend Boundary-Test Helpers

All four structural suites use these shared test-local helpers. Copy this block into each boundary spec so every lane remains independently executable:

```ts
import * as ts from "typescript";

const sourceNloc = (source: string) =>
  source.replace(/\/\*[\s\S]*?\*\//g, "").split(/\r?\n/).filter((line) => {
    const value = line.trim();
    return value.length > 0 && !value.startsWith("//");
  }).length;

const parsedClass = (source: string) => {
  const file = ts.createSourceFile(
    "facade.ts", source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS,
  );
  const classes = file.statements.filter(ts.isClassDeclaration);
  expect(classes).toHaveLength(1);
  return { file, declaration: classes[0]! };
};

const identifierName = (node: ts.Node | undefined) =>
  node && ts.isIdentifier(node) ? node.text : null;

const exactConstructorTypes = (source: string) => {
  const { file, declaration } = parsedClass(source);
  const constructors = declaration.members.filter(ts.isConstructorDeclaration);
  expect(constructors).toHaveLength(1);
  expect(constructors[0]!.body?.statements).toHaveLength(0);
  return constructors[0]!.parameters.map((parameter) => parameter.type?.getText(file));
};

const exactMethodNames = (source: string) => {
  const { declaration } = parsedClass(source);
  return declaration.members.filter(ts.isMethodDeclaration)
    .map((method) => identifierName(method.name));
};

const assertDirectDelegations = (
  source: string,
  contracts: ReadonlyArray<{
    method: string;
    owner: string;
    parameters: readonly string[];
  }>,
) => {
  const { declaration } = parsedClass(source);
  const methods = declaration.members.filter(ts.isMethodDeclaration);
  expect(methods).toHaveLength(contracts.length);
  methods.forEach((method, index) => {
    const contract = contracts[index]!;
    expect(identifierName(method.name)).toBe(contract.method);
    expect(method.parameters.map((parameter) => identifierName(parameter.name)))
      .toEqual(contract.parameters);
    expect(method.body?.statements).toHaveLength(1);
    const statement = method.body!.statements[0]!;
    expect(ts.isReturnStatement(statement)).toBe(true);
    const call = (statement as ts.ReturnStatement).expression;
    expect(call && ts.isCallExpression(call)).toBe(true);
    const expression = (call as ts.CallExpression).expression;
    expect(ts.isPropertyAccessExpression(expression)).toBe(true);
    const ownerAccess = (expression as ts.PropertyAccessExpression).expression;
    expect(ts.isPropertyAccessExpression(ownerAccess)).toBe(true);
    expect((ownerAccess as ts.PropertyAccessExpression).name.text).toBe(contract.owner);
    expect((call as ts.CallExpression).arguments.map(identifierName))
      .toEqual(contract.parameters);
  });
};

const arraySection = (source: string, property: string) => {
  const propertyStart = source.indexOf(`${property}:`);
  if (propertyStart < 0) throw new Error(`Missing ${property} section`);
  const arrayStart = source.indexOf("[", propertyStart);
  let depth = 0;
  for (let index = arrayStart; index < source.length; index += 1) {
    if (source[index] === "[") depth += 1;
    if (source[index] === "]") depth -= 1;
    if (depth === 0) return source.slice(arrayStart + 1, index);
  }
  throw new Error(`Unclosed ${property} section`);
};

const privateProviders = (moduleSource: string) => {
  const providers = arraySection(moduleSource, "providers");
  const exports = arraySection(moduleSource, "exports");
  return [...providers.matchAll(/\b([A-Z][A-Za-z0-9]+(?:Service|Repository))\b/g)]
    .map((match) => match[1]!)
    .filter((name) => !new RegExp(`\\b${name}\\b`).test(exports));
};

const transactionCallCount = (source: string) =>
  source.match(/\.transaction\s*\(/g)?.length ?? 0;

const versionedMutationCount = (source: string) =>
  source.match(/executeVersionedMutation\s*(?:<[^>]+>)?\s*\(/g)?.length ?? 0;
```

---

## Task A: Split MessengerService into chat semantic owners

**Baseline evidence:** `server/src/messenger/messenger.service.ts` has health `1.74`, `1043` NLOC, max CCN `16`, weighted deficit `6529`, and coverage `89.69%` lines / `69.85%` branches.

### Files

- Create: `server/src/messenger/messenger.constants.ts`
- Create: `server/src/messenger/messenger-chat-access.service.ts`
- Create: `server/src/messenger/messenger-system-chat.service.ts`
- Create: `server/src/messenger/messenger-chat-query.service.ts`
- Create: `server/src/messenger/messenger-chat-command.service.ts`
- Create: `server/src/messenger/messenger-message-delivery.service.ts`
- Create: `server/src/messenger/messenger-service-boundary.spec.ts`
- Create: `.superpowers/campaign12/reports/tier1-lane-a.md`
- Modify: `server/src/messenger/messenger.service.ts`
- Modify: `server/src/messenger/messenger.service.spec.ts`
- Modify: `server/src/messenger/direct-chat-postgres.integration.spec.ts`
- Modify: `server/src/messenger/channel-group-postgres.integration.spec.ts`
- Verify only: `server/src/messenger/messenger.controller.ts`
- Integrator only: `server/src/messenger/messenger.module.ts`

### Interfaces

**Consumes:**

```ts
MessengerPolicy.getChatAccess(actor: ActorContext, chatId: string)
MessengerPolicy.assertCanReadChat(actor: ActorContext, chat: ChatAccessRecord): void
MessengerPolicy.assertCanWriteChat(actor: ActorContext, chat: ChatAccessRecord): void
MessengerPolicy.assertNotBlacklisted(actor: ActorContext): Promise<void>
DatabaseService.transaction<T>(work: (client: PoolClient) => Promise<T>): Promise<T>
LeadIntakePort.autoCreateLeadFromChat(actor: ActorContext, userId: string): Promise<void>
```

**Produces:**

```ts
export const ANNOUNCEMENTS_CHAT_SLUG = "announcements" as const;

export type MessengerChatAccess = NonNullable<
  Awaited<ReturnType<MessengerPolicy["getChatAccess"]>>
>;

export class MessengerChatAccessService {
  constructor(private readonly policy: MessengerPolicy);
  requireChat(actor: ActorContext, chatId: string): Promise<MessengerChatAccess>;
}

export class MessengerSystemChatService {
  constructor(private readonly database: DatabaseService);
  bootstrapAnnouncements(): Promise<void>;
  ensureAnnouncementsChat(): Promise<void>;
}

export class MessengerChatQueryService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: MessengerPolicy,
    private readonly access: MessengerChatAccessService,
  );
  listChats(actor: ActorContext, query: MessengerListQuery);
  getMessages(actor: ActorContext, chatId: string, query: MessengerListQuery);
  listChatMembers(actor: ActorContext, chatId: string);
  getChat(actor: ActorContext, chatId: string);
}

export class MessengerMessageDeliveryService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: MessengerPolicy,
    private readonly access: MessengerChatAccessService,
    @Inject(LEAD_INTAKE_PORT) private readonly leadIntake: LeadIntakePort,
    private readonly realtime: RealtimeGateway,
    private readonly fanout: MessengerFanoutService,
  );
  sendMessage(actor: ActorContext, chatId: string, dto: SendMessageDto);
}

export class MessengerChatCommandService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: MessengerPolicy,
    private readonly access: MessengerChatAccessService,
    private readonly realtime: RealtimeGateway,
    private readonly queries: MessengerChatQueryService,
  );
  createDirectChat(actor: ActorContext, dto: CreateDirectChatDto);
  createGroup(actor: ActorContext, dto: CreateGroupChatDto);
  updateGroupMembers(actor: ActorContext, chatId: string, dto: UpdateGroupMembersDto);
  leaveGroup(actor: ActorContext, chatId: string);
  setChatMute(actor: ActorContext, chatId: string, dto: SetChatMuteDto);
}
```

The facade remains `MessengerService implements OnModuleInit`, retains `static readonly announcementsSlug`, and exposes exactly these twelve methods in this order:

```ts
onModuleInit(): Promise<void>
ensureAnnouncementsChat(): Promise<void>
listChats(actor: ActorContext, query: MessengerListQuery)
getMessages(actor: ActorContext, chatId: string, query: MessengerListQuery)
listChatMembers(actor: ActorContext, chatId: string)
sendMessage(actor: ActorContext, chatId: string, dto: SendMessageDto)
createDirectChat(actor: ActorContext, dto: CreateDirectChatDto)
createGroup(actor: ActorContext, dto: CreateGroupChatDto)
updateGroupMembers(actor: ActorContext, chatId: string, dto: UpdateGroupMembersDto)
leaveGroup(actor: ActorContext, chatId: string)
getChat(actor: ActorContext, chatId: string)
setChatMute(actor: ActorContext, chatId: string, dto: SetChatMuteDto)
```

- [ ] **Step A1: Add RED lifecycle, rollback, and ordering characterization**

Reuse the existing actor/chat/DTO fixtures and extend its local service factory so it returns `database`, `audit`, `leadIntake`, `realtime`, `fanout`, `queries`, and the facade. Add these exact tests and assertions to `server/src/messenger/messenger.service.spec.ts`:

```ts
const clientActor = { userId: "user-a", role: "client" as const };
const managerActor = { userId: "manager-a", role: "manager" as const };
const administrationChatId = "11111111-1111-4111-8111-111111111111";
const groupChatId = "22222222-2222-4222-8222-222222222222";
const addedUserId = "33333333-3333-4333-8333-333333333333";
const removedUserId = "44444444-4444-4444-8444-444444444444";
const textMessageDto = { content: "Сообщение" };

const deferred = <T>() => {
  let resolve!: (value: T | PromiseLike<T>) => void;
  const promise = new Promise<T>((complete) => {
    resolve = complete;
  });
  return { promise, resolve };
};

it("onModuleInit resolves and logs when announcements provisioning fails", async () => {
  const warn = jest.spyOn(Logger.prototype, "warn").mockImplementation();
  const harness = createService({
    database: { transaction: jest.fn().mockRejectedValue(new Error("bootstrap failed")) },
  });

  await expect(harness.service.onModuleInit()).resolves.toBeUndefined();
  expect(warn).toHaveBeenCalledWith(
    expect.stringContaining("ensureAnnouncementsChat failed: Error: bootstrap failed"),
  );
});

it("sendMessage emits no lead-intake, realtime or fanout event when its transaction rejects", async () => {
  const harness = createService({
    database: { transaction: jest.fn().mockRejectedValue(new Error("rollback")) },
  });

  await expect(
    harness.service.sendMessage(clientActor, administrationChatId, textMessageDto),
  ).rejects.toThrow("rollback");
  expect(harness.leadIntake.autoCreateLeadFromChat).not.toHaveBeenCalled();
  expect(harness.realtime.publishAdminInboxEvent).not.toHaveBeenCalled();
  expect(harness.fanout.publishMessageEventForAudience).not.toHaveBeenCalled();
  expect(harness.fanout.fanoutChatListUpdate).not.toHaveBeenCalled();
});

it("updateGroupMembers performs audit and realtime only after its transaction commits", async () => {
  const commit = deferred<void>();
  const harness = createService({ transactionCommit: commit.promise });
  const pending = harness.service.updateGroupMembers(
    managerActor,
    groupChatId,
    { addUserIds: [addedUserId], removeUserIds: [removedUserId] },
  );

  await Promise.resolve();
  expect(harness.audit.record).not.toHaveBeenCalled();
  expect(harness.realtime.publishChatEvent).not.toHaveBeenCalled();
  expect(harness.realtime.publishUserEvent).not.toHaveBeenCalled();

  commit.resolve();
  await pending;
  expect(harness.audit.record).toHaveBeenCalledWith({
    actor: managerActor,
    action: "messenger.group_members_updated",
    entityType: "chat",
    entityId: groupChatId,
  });
  expect(harness.audit.record.mock.invocationCallOrder[0]).toBeLessThan(
    harness.realtime.publishChatEvent.mock.invocationCallOrder[0],
  );
  expect(harness.realtime.publishChatEvent.mock.invocationCallOrder[0]).toBeLessThan(
    harness.queries.getChat.mock.invocationCallOrder[0],
  );
  expect(harness.queries.getChat.mock.invocationCallOrder[0]).toBeLessThan(
    harness.realtime.publishUserEvent.mock.invocationCallOrder[0],
  );
});
```

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/messenger/messenger.service.spec.ts --runInBand
```

Expected: FAIL because the current class still owns lifecycle, delivery, and command orchestration and the new composition helper does not exist.

- [ ] **Step A2: Extract the announcement constant, access boundary, and system-chat owner**

Move the stable slug to `messenger.constants.ts`. Move current lines `62-111` into `MessengerSystemChatService`: `bootstrapAnnouncements()` contains the current best-effort `try/catch/Logger.warn`, while `ensureAnnouncementsChat()` retains the single transaction, conflict-safe chat creation, and active-user membership backfill. Move current `requireChat` behavior into `MessengerChatAccessService.requireChat` without changing the Russian `NotFoundException`.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/messenger/messenger.service.spec.ts -t "onModuleInit resolves and logs" --runInBand
```

Expected: PASS.

- [ ] **Step A3: Extract the chat query owner without changing SQL or mapping**

Move `listChats`, cursor encode/decode/calendar validation, `canWriteChatSummary`, `getMessages`, `listChatMembers`, and `getChat` to `MessengerChatQueryService`. Preserve SQL parameter ordering, PostgreSQL six-digit cursor timestamps, the strict branch predicate, archived/folder semantics, `limit + 1`, client staff-identity masking, `toChatSummaryDto`, `toMessageDto`, and `toChatMemberDto` calls byte-for-byte except for owner references.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/messenger/messenger.service.spec.ts -t "listChats|staff-identity masking|lists active chat members" --runInBand
```

Expected: PASS for cursor, folder, branch, member, read, and masking cases.

- [ ] **Step A4: Extract message delivery with the exact commit-to-fanout order**

Move `sendMessage`, `ChatAttachmentRow`, attachment validation, payload validation, and reference validation to `MessengerMessageDeliveryService`. Preserve this order:

```text
require chat -> write policy -> blacklist policy -> payload/reference validation
-> message/last_message/resurface transaction commit
-> best-effort lead intake
-> administration archive-state patch
-> audience-specific message.created
-> chat-list fanout
```

Remove the unused `RealtimeBus` dependency rather than transferring it to an owner.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/messenger/messenger.service.spec.ts -t "чёрный список|publishes message.created|attachment|voice message|reply|forwarding|auto-creates a lead|fanoutChatListUpdate|resurface" --runInBand
```

Expected: PASS, including no external effects on rollback and masked/unmasked audience payloads.

- [ ] **Step A5: Extract direct, administration, group, membership, leave, and mute commands**

Move `createDirectChat`, `createAdministrationChat`, `createGroup`, `updateGroupMembers`, `leaveGroup`, `setChatMute`, `insertMembers`, and `assertActiveUsers` to `MessengerChatCommandService`. Preserve member prevalidation before transactions, system-chat prohibitions, actor-removal/contradiction checks, group transaction boundaries, audit payloads, and post-commit event order. `updateGroupMembers` calls `queries.getChat(actor, chatId)` only after its transaction and audit/realtime update.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/messenger/messenger.service.spec.ts -t "createGroup|updateGroupMembers|leaveGroup|mute|administration chat|direct chat" --runInBand
```

Expected: PASS for group membership, fanout, direct/admin creation, leave, and mute contracts.

- [ ] **Step A6: Replace MessengerService with an exact facade and add the permanent guard**

Give the facade exactly four `private readonly` dependencies: system chats, queries, delivery, and commands. Every public method contains one direct `return this.<owner>.<method>(same arguments)` statement. `onModuleInit` delegates to `bootstrapAnnouncements`; `announcementsSlug` aliases `ANNOUNCEMENTS_CHAT_SLUG`.

In `messenger-service-boundary.spec.ts`, parse the facade with the TypeScript AST and assert:

```ts
expect(sourceNloc(facade)).toBeLessThanOrEqual(100);
expect(constructor.parameters).toHaveLength(4);
expect(publicMethods).toHaveLength(12);
expect(facade).not.toMatch(/DatabaseService|MessengerPolicy|AuditService|RealtimeBus|\.transaction\s*\(|select\s|insert\s|update\s|delete\s/i);
expect(transactionBoundaryCount(systemChats)).toBe(1);
expect(transactionBoundaryCount(delivery)).toBe(1);
expect(transactionBoundaryCount(commands)).toBe(4);
expect(transactionBoundaryCount(queries)).toBe(0);
expect(transactionBoundaryCount(access)).toBe(0);
```

Also assert exact method/owner/argument mappings, NLOC ceilings `system <=100`, `access <=80`, `query <=600`, `command <=400`, `delivery <=300`, and source ordering for delivery and group side effects. Read `messenger.module.ts` but defer its provider assertions to Task T1.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/messenger/messenger.service.spec.ts src/messenger/messenger-service-boundary.spec.ts --runInBand
```

Expected: PASS.

- [ ] **Step A7: Run lane smoke, record evidence, and commit Lane A**

Run only:

```powershell
npm --prefix server test -- --runTestsByPath src/messenger/messenger.service.spec.ts src/messenger/messenger-service-boundary.spec.ts --runInBand
npm --prefix server run typecheck
git diff --check
repowise update --index-only
```

Begin `.superpowers/campaign12/reports/tier1-lane-a.md` with the literal prefix `Campaign baseline: ` followed immediately by `$Tier1Base` resolved to its lowercase 40-character SHA. Then record command exits, Jest counts/duration, old/new NLOC, max CCN, health, weighted deficit, and god/brain status. Use RepoWise `get_health` for `messenger.service.ts` and the five new owner files; require every new owner health `>=7.0`, max CCN `<=10`, and no god/brain finding.

Commit:

```powershell
git add server/src/messenger/messenger.constants.ts server/src/messenger/messenger-chat-access.service.ts server/src/messenger/messenger-system-chat.service.ts server/src/messenger/messenger-chat-query.service.ts server/src/messenger/messenger-chat-command.service.ts server/src/messenger/messenger-message-delivery.service.ts server/src/messenger/messenger-service-boundary.spec.ts server/src/messenger/messenger.service.ts server/src/messenger/messenger.service.spec.ts server/src/messenger/direct-chat-postgres.integration.spec.ts server/src/messenger/channel-group-postgres.integration.spec.ts .superpowers/campaign12/reports/tier1-lane-a.md
git commit -m "refactor(messenger): split chat orchestration owners"
```

---

## Task B: Split PayrollService into ledger, command, report, and export owners

**Baseline evidence:** `server/src/crm/payroll.service.ts` has health `3.42`, `1178` NLOC, max CCN `23`, weighted deficit `5395`, and coverage `93.70%` lines / `71.53%` branches.

### Files

- Create: `server/src/crm/payroll/payroll.types.ts`
- Create: `server/src/crm/payroll/payroll-accrual-calculator.ts`
- Create: `server/src/crm/payroll/payroll-read.repository.ts`
- Create: `server/src/crm/payroll/teacher-payroll-query.service.ts`
- Create: `server/src/crm/payroll/teacher-payroll-command.service.ts`
- Create: `server/src/crm/payroll/teacher-stats-report.service.ts`
- Create: `server/src/crm/payroll/teacher-stats-csv.service.ts`
- Create: `server/src/crm/payroll/payroll-service-boundary.spec.ts`
- Create: `.superpowers/campaign12/reports/tier1-lane-b.md`
- Modify: `server/src/crm/payroll.service.ts`
- Modify: `server/src/crm/payroll.service.spec.ts`
- Modify: `server/src/crm/payroll-postgres.integration.spec.ts`
- Verify only: `server/src/crm/crm-people.controller.ts`
- Integrator only: `server/src/crm/crm.module.ts`

### Interfaces

**Produces shared types and calculation boundary:**

```ts
export type TeacherStatsUnitType =
  | "group"
  | "individual"
  | "group_trial"
  | "individual_trial";

export interface PayrollMutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

export interface PayrollLessonFilters {
  teacherId?: string | null;
  branchId?: string | null;
  from?: string | null;
  to?: string | null;
}

export interface PayrollLessonAccrual {
  hours: number;
  rate: number;
  coefficient: number;
  amount: number;
}

export interface TeacherPayrollHeader {
  id: string;
  version: string | number;
}

export interface TeacherMovementTotals {
  paid: number;
  bonus: number;
  deduction: number;
}

export interface TeacherReportReadInput {
  teacherId: string | null;
  lessonTeacherIds: string[];
  includeMovementOnly: boolean;
  from: string;
  to: string;
  status: string | null;
  discipline: string | null;
  category: string | null;
}

export interface TeacherReportRow {
  id: string;
  name: string;
  salary: string | number | null;
}

export class PayrollAccrualCalculator {
  toDateOnly(value: Date | string): string;
  round2(value: number): number;
  computeLessonAccrual(lesson: PayrollLessonRow, rates: Map<string, TeacherRateEntry[]>): PayrollLessonAccrual;
  unitTypeFor(lesson: PayrollLessonRow): TeacherStatsUnitType;
  unitKeyFor(lesson: PayrollLessonRow): string;
  unitNameFor(lesson: PayrollLessonRow): string;
}

export class PayrollReadRepository {
  constructor(private readonly database: DatabaseService);
  loadPayrollLessons(filters: PayrollLessonFilters): Promise<PayrollLessonRow[]>;
  loadTeacherRates(teacherIds: string[]): Promise<Map<string, TeacherRateEntry[]>>;
  findTeacherPayrollHeader(teacherId: string): Promise<TeacherPayrollHeader | null>;
  listTeacherPayouts(teacherId: string): Promise<TeacherPayoutRow[]>;
  listReportTeachers(input: TeacherReportReadInput): Promise<TeacherReportRow[]>;
  loadPeriodMovements(teacherIds: string[], from: string, to: string): Promise<Map<string, TeacherMovementTotals>>;
  findPayout(entryId: string): Promise<TeacherPayoutRow | null>;
  findRate(entryId: string): Promise<TeacherRateRow | null>;
}
```

**Produces semantic services:**

```ts
TeacherPayrollQueryService.constructor(
  repository: PayrollReadRepository,
  policy: CrmPolicy,
  calculator: PayrollAccrualCalculator,
)
TeacherPayrollQueryService.getTeacherPayroll(actor: ActorContext, teacherId: string)

TeacherPayrollCommandService.constructor(
  repository: PayrollReadRepository,
  policy: CrmPolicy,
  integrity: PlatformIntegrityService,
  calculator: PayrollAccrualCalculator,
)
TeacherPayrollCommandService.createTeacherPayout(actor, teacherId, dto, metadata)
TeacherPayrollCommandService.setTeacherRate(actor, teacherId, dto, metadata)
TeacherPayrollCommandService.updateTeacherRate(actor, teacherId, entryId, dto, metadata)
TeacherPayrollCommandService.deleteTeacherRate(actor, teacherId, entryId, dto, metadata)
TeacherPayrollCommandService.updateTeacherPayout(actor, teacherId, entryId, dto, metadata)
TeacherPayrollCommandService.deleteTeacherPayout(actor, teacherId, entryId, dto, metadata)

TeacherStatsReportService.constructor(
  repository: PayrollReadRepository,
  policy: CrmPolicy,
  calculator: PayrollAccrualCalculator,
)
TeacherStatsReportService.getTeacherStatsReport(actor: ActorContext, query: TeacherStatsQuery)
TeacherStatsCsvService.constructor(report: TeacherStatsReportService)
TeacherStatsCsvService.exportTeacherStatsReport(actor: ActorContext, query: TeacherStatsQuery): Promise<string>
```

`PayrollService` re-exports `TeacherStatsUnitType` and `TeacherRateEntry` from its existing import path. Its constructor has exactly query, commands, report, and CSV dependencies; it retains the nine current public method signatures.

- [ ] **Step B1: Add RED correction-envelope and append-only characterization**

Extend the local factory so it accepts a supplied integrity mock and returns the command owner through the facade. Use `teacherId = "11111111-1111-4111-8111-111111111111"`, `entryId = "22222222-2222-4222-8222-222222222222"`, actor `{ userId: "manager-a", role: "director" }`, and metadata `{ idempotencyKey: "payroll-key-001", requestId: "request-001" }`. Add these exact tests and assertions to `server/src/crm/payroll.service.spec.ts`:

```ts
const teacherId = "11111111-1111-4111-8111-111111111111";
const entryId = "22222222-2222-4222-8222-222222222222";
const directorActor = { userId: "manager-a", role: "director" as const };
const metadata = {
  idempotencyKey: "payroll-key-001",
  requestId: "request-001",
};

const createMutationService = (integrityResult: {
  resultRef: { entryId: string };
  version: number;
  replayed: boolean;
}) => {
  const repository = {} as PayrollReadRepository;
  const policy = {
    assertCanReadPayroll: jest.fn(),
    assertCanManagePayrollHistory: jest.fn(),
  } as unknown as CrmPolicy;
  const integrity = {
    executeVersionedMutation: jest.fn().mockResolvedValue(integrityResult),
  } as unknown as PlatformIntegrityService;
  const commands = new TeacherPayrollCommandService(
    repository,
    policy,
    integrity,
    new PayrollAccrualCalculator(),
  );
  const service = new PayrollService(
    {} as TeacherPayrollQueryService,
    commands,
    {} as TeacherStatsReportService,
    {} as TeacherStatsCsvService,
  );
  return { service, integrity, policy };
};

it("updateTeacherRate preserves expected-version, correction audit and outbox metadata", async () => {
  const dto = {
    expectedVersion: 7,
    reasonText: "Исправление ставки",
    rate: 1250,
    effectiveFrom: "2026-08-01",
  };
  const { service, integrity, policy } = createMutationService({
    resultRef: { entryId }, version: 8, replayed: false,
  });

  await expect(
    service.updateTeacherRate(directorActor, teacherId, entryId, dto, metadata),
  ).resolves.toEqual({
    id: entryId,
    teacherId,
    rate: 1250,
    effectiveFrom: "2026-08-01",
    version: 8,
    replayed: false,
  });
  expect(policy.assertCanManagePayrollHistory).toHaveBeenCalledWith(directorActor);
  expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
    expect.objectContaining({
      operation: "crm.teacher-rate.update",
      aggregateType: "teacher:payroll",
      aggregateId: teacherId,
      expectedVersion: 7,
      idempotencyKey: "payroll-key-001",
      requestId: "request-001",
      authorization: { actor: directorActor, capabilityKey: "commerce.teacher_payroll.write" },
      audit: expect.objectContaining({
        action: "crm.teacher_rate_updated",
        reason: "TEACHER_RATE_CORRECTION",
        reasonText: "Исправление ставки",
        beforeRef: { entryId },
      }),
      outbox: {
        type: "crm.teacher_payroll.changed",
        payload: { action: "rate_updated", entityId: teacherId, entryId },
      },
    }),
  );
});

it("updateTeacherPayout preserves expected-version, correction audit and outbox metadata", async () => {
  const dto = {
    expectedVersion: 7,
    reasonText: "Исправление выплаты",
    kind: "bonus" as const,
    amount: 2500,
    comment: "Премия",
    paidAt: "2026-08-20T12:00:00.000Z",
  };
  const { service, integrity, policy } = createMutationService({
    resultRef: { entryId }, version: 8, replayed: false,
  });

  await expect(
    service.updateTeacherPayout(directorActor, teacherId, entryId, dto, metadata),
  ).resolves.toEqual({
    id: entryId,
    teacherId,
    kind: "bonus",
    amount: 2500,
    comment: "Премия",
    paidAt: "2026-08-20T12:00:00.000Z",
    version: 8,
    replayed: false,
  });
  expect(policy.assertCanManagePayrollHistory).toHaveBeenCalledWith(directorActor);
  expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
    expect.objectContaining({
      operation: "crm.teacher-payout.update",
      aggregateType: "teacher:payroll",
      aggregateId: teacherId,
      expectedVersion: 7,
      idempotencyKey: "payroll-key-001",
      requestId: "request-001",
      authorization: { actor: directorActor, capabilityKey: "commerce.teacher_payroll.write" },
      audit: expect.objectContaining({
        action: "crm.teacher_payout_updated",
        reason: "TEACHER_PAYOUT_CORRECTION",
        reasonText: "Исправление выплаты",
        beforeRef: { entryId },
      }),
      outbox: {
        type: "crm.teacher_payroll.changed",
        payload: { action: "payout_updated", entityId: teacherId, entryId },
      },
    }),
  );
});
```

Create the initial boundary test with:

```ts
it("rate and payout deletion soft-void history without physical DELETE", () => {
  expect(productionPayrollSource).not.toMatch(/delete\s+from\s+app\.(teacher_rates|teacher_payouts)/i);
  expect(commandSource).toMatch(/set\s+deleted_at\s*=\s*clock_timestamp\(\)/i);
  expect(commandSource).toMatch(/deleted_by\s*=\s*\$3/i);
});
```

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll/payroll-service-boundary.spec.ts --runInBand
```

Expected: FAIL because the facade and command boundary have not been extracted.

- [ ] **Step B2: Extract payroll types, calculator, and read repository**

Move row/filter/report contracts to `payroll.types.ts`; keep `TeacherStatsUnitType` and `TeacherRateEntry` exported. Move `toDateOnly`, `round2`, `computeLessonAccrual`, `unitTypeFor`, `unitKeyFor`, and `unitNameFor` to `PayrollAccrualCalculator`. Split `computeLessonAccrual` into settled-fact, effective-rate, attendance-coefficient, and rounded-amount helpers so no method exceeds CCN `10`.

Move all read SQL from `loadPayrollLessons`, `loadTeacherRates`, payroll header/payout reads, teacher-name/filter reads, and period movement reads into `PayrollReadRepository`. Preserve query text, parameter order, settlement effective-view use, chronological rate ordering, trial lead join, payout-only teacher behavior, and soft-delete filters.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts -t "ставку по дате|immutable settlement|коэффициенты статусов|trial|payout-only" --runInBand
```

Expected: PASS.

- [ ] **Step B3: Extract the payroll query owner**

Move `getTeacherPayroll` to `TeacherPayrollQueryService`. It must call `policy.assertCanReadPayroll(actor)` before reads, use repository lessons/rates/header/payouts, calculate each lesson before summing, and return the current response keys unchanged: version, lesson counts, hours, accrued/bonus/deduction/paid/debt totals, currentRate, rateHistory, and payouts.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts -t "getTeacherPayroll|задолженность" --runInBand
```

Expected: PASS.

- [ ] **Step B4: Extract the six payroll mutations into one integrity owner**

Move create/set/update/delete methods and `voidPayrollEntry` to `TeacherPayrollCommandService`. Preserve all metadata validation, reason validation, actor policy calls, operation names, expected versions, capability, audit, outbox, SQL, result refs, replay flags, and response shapes. Create/set retain `assertCanReadPayroll`; correction/void retain `assertCanManagePayrollHistory`. Keep all writes inside `PlatformIntegrityService.executeVersionedMutation`; do not introduce a direct `database.transaction`.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll-postgres.integration.spec.ts -t "payout|rate|expected-version|append-only|director|DELETE revoked" --runInBand
```

Expected: PASS for mutation envelopes, replay/stale behavior, soft voiding, RBAC, audit, and outbox.

- [ ] **Step B5: Extract report projection and CSV export**

Move `getTeacherStatsReport` to `TeacherStatsReportService`. Break it into period resolution, lesson filtering, teacher selection, unit accumulation, teacher projection, and totals projection helpers. Preserve default UTC month, inverted-period error, movement scope, status/discipline/category filters, payout-only rows, four unit types, trial keying by lead, settled/editable lesson IDs, Russian sorting, and every numeric field.

Move `exportTeacherStatsReport` to `TeacherStatsCsvService`. It delegates to the report owner and preserves BOM, semicolon delimiter, CRLF, Russian headings/type labels, formula-prefix escaping, unit rows, teacher totals, and overall totals.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts -t "teacher-stats|экспортирует отчёт|inverted report period|payout-only" --runInBand
```

Expected: PASS.

- [ ] **Step B6: Replace PayrollService with the nine-delegation facade and complete the guard**

Give the facade four `private readonly` dependencies. Preserve public method order and parameter types. Each body is one direct return to query, commands, report, or CSV.

Complete `payroll-service-boundary.spec.ts` with exact assertions:

```ts
expect(sourceNloc(facade)).toBeLessThanOrEqual(120);
expect(constructor.parameters).toHaveLength(4);
expect(publicMethods).toHaveLength(9);
expect(versionedMutationCount(commandSource)).toBe(5);
expect(otherProductionSources).not.toMatch(/executeVersionedMutation|\.transaction\s*\(/);
expect(productionPayrollSource).not.toMatch(/delete\s+from\s+app\.(teacher_rates|teacher_payouts)/i);
```

Assert all nine owner/method/argument mappings and NLOC ceilings: types `<=180`, calculator `<=260`, repository `<=360`, query `<=180`, command `<=520`, report `<=420`, CSV `<=170`. Defer `CrmModule` provider assertions to Task T1.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll/payroll-service-boundary.spec.ts --runInBand
```

Expected: PASS.

- [ ] **Step B7: Run lane smoke, record evidence, and commit Lane B**

Run only:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll/payroll-service-boundary.spec.ts --runInBand
npm --prefix server run typecheck
git diff --check
repowise update --index-only
```

Begin `.superpowers/campaign12/reports/tier1-lane-b.md` with the literal prefix `Campaign baseline: ` followed immediately by `$Tier1Base` resolved to its lowercase 40-character SHA. Then record exact evidence and use RepoWise `get_health` for the facade and calculator/repository/query/command/report/CSV files; require health `>=7.0`, CCN `<=10`, and no god/brain finding for every new owner.

Commit:

```powershell
git add server/src/crm/payroll.service.ts server/src/crm/payroll.service.spec.ts server/src/crm/payroll-postgres.integration.spec.ts server/src/crm/payroll/payroll.types.ts server/src/crm/payroll/payroll-accrual-calculator.ts server/src/crm/payroll/payroll-read.repository.ts server/src/crm/payroll/teacher-payroll-query.service.ts server/src/crm/payroll/teacher-payroll-command.service.ts server/src/crm/payroll/teacher-stats-report.service.ts server/src/crm/payroll/teacher-stats-csv.service.ts server/src/crm/payroll/payroll-service-boundary.spec.ts .superpowers/campaign12/reports/tier1-lane-b.md
git commit -m "refactor(crm): split payroll semantic owners"
```

---

## Task C: Split SubscriptionIssueService into preview, terms, and commit owners

**Baseline evidence:** `server/src/crm/commerce/subscription-issue.service.ts` has health `3.60`, `1008` NLOC, max CCN `18`, weighted deficit `4435`, and coverage `89.22%` lines / `78.57%` branches. It has no colocated unit spec.

### Files

- Create: `server/src/crm/commerce/subscription-issue.contracts.ts`
- Create: `server/src/crm/commerce/subscription-commercial-terms.service.ts`
- Create: `server/src/crm/commerce/subscription-purchase-preview.service.ts`
- Create: `server/src/crm/commerce/subscription-purchase-command.service.ts`
- Create: `server/src/crm/commerce/subscription-grant-command.service.ts`
- Create: `server/src/crm/commerce/subscription-issue-result.service.ts`
- Create: `server/src/crm/commerce/subscription-issue.service.spec.ts`
- Create: `server/src/crm/commerce/subscription-issue-boundary.spec.ts`
- Create: `.superpowers/campaign12/reports/tier1-lane-c.md`
- Modify: `server/src/crm/commerce/subscription-issue.service.ts`
- Modify: `server/src/crm/commerce/subscription-issue-postgres.integration.spec.ts`
- Modify: `server/src/crm/commerce/subscription-cancel-postgres.integration.spec.ts`
- Modify: `server/src/crm/commerce/subscription-replace-postgres.integration.spec.ts`
- Verify only: `server/src/crm/commerce/subscription-issue.repository.ts`
- Verify only: `server/src/crm/subscription-commerce.controller.ts`
- Integrator only: `server/src/crm/crm.module.ts`

### Interfaces

**Produces contracts and commercial normalization:**

```ts
export interface CommerceMutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

export interface IssueMutationResult extends Record<string, unknown> {
  entityId: string;
  version: number;
}

export interface NormalizedDiscount {
  snapshot: IssuedDiscountSnapshot;
  columns: IssueDiscountColumns;
  finalPriceMinor: string;
}

export interface NormalizedSurcharge {
  snapshot: IssuedSurchargeSnapshot;
  amountMinor: string;
}

export interface NormalizedPurchase {
  discount: NormalizedDiscount;
  surcharge: NormalizedSurcharge;
  finalPriceMinor: string;
  installments: PlannedInstallment[];
  snapshot: IssuedCommercialSnapshot;
  purchaseReason: string | null;
}

export interface NormalizedIssue {
  discount: NormalizedDiscount;
  surcharge: NormalizedSurcharge;
  finalPriceMinor: string;
  installments: PlannedInstallment[];
  snapshot: IssuedCommercialSnapshot;
}

export type UnsignedPurchaseTokenPayload = Omit<
  SubscriptionPurchasePreviewTokenPayload,
  "issuedAtSeconds" | "expiresAtSeconds"
>;

export class SubscriptionCommercialTermsService {
  assertPaymentMethod(value: string | undefined): asserts value is "cash" | "cashless" | undefined;
  normalizePurchase(recipientStudentId: string, dto: PurchaseSubscriptionPreviewDto, packageRow: IssuePackageRow): NormalizedPurchase;
  normalizeIssue(dto: IssueSubscriptionDto, packageRow: IssuePackageRow): NormalizedIssue;
  auditReasonForPurchase(normalized: NormalizedPurchase): string;
}
```

`normalizeDiscount` is split into separate none, percent, and fixed paths. `normalizePurchase` and `normalizeIssue` reuse discount, surcharge, installment, and snapshot helpers; no normalization method may exceed CCN `10`.

**Produces preview and command owners:**

```ts
export class SubscriptionPurchasePreviewService {
  constructor(
    private readonly repository: SubscriptionIssueRepository,
    private readonly policy: CrmPolicy,
    private readonly terms: SubscriptionCommercialTermsService,
    private readonly previewTokens: SubscriptionPreviewTokenService,
  );
  previewPurchase(actor: ActorContext, recipientStudentId: string, dto: PurchaseSubscriptionPreviewDto);
  decodeBoundToken(actor: ActorContext, recipientStudentId: string, dto: PurchaseSubscriptionCommandDto): SubscriptionPurchasePreviewTokenPayload;
  assertPurchaseContext(context: PurchaseContext, recipientStudentId: string, payerStudentId: string): IssuePackageRow;
  createTokenPayload(actor: ActorContext, recipientStudentId: string, dto: PurchaseSubscriptionPreviewDto, context: PurchaseContext, normalized: NormalizedPurchase): UnsignedPurchaseTokenPayload;
  assertStillCurrent(signed: SubscriptionPurchasePreviewTokenPayload, current: UnsignedPurchaseTokenPayload): void;
}

export class SubscriptionPurchaseCommandService {
  constructor(
    private readonly repository: SubscriptionIssueRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly reservations: SubscriptionReservationService,
    private readonly preview: SubscriptionPurchasePreviewService,
    private readonly terms: SubscriptionCommercialTermsService,
    private readonly results: SubscriptionIssueResultService,
  );
  purchase(actor: ActorContext, recipientStudentId: string, dto: PurchaseSubscriptionCommandDto, metadata: CommerceMutationMetadata);
}

export class SubscriptionGrantCommandService {
  constructor(
    private readonly repository: SubscriptionIssueRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
    private readonly reservations: SubscriptionReservationService,
    private readonly terms: SubscriptionCommercialTermsService,
    private readonly results: SubscriptionIssueResultService,
  );
  issue(actor: ActorContext, studentId: string, dto: IssueSubscriptionDto, metadata: CommerceMutationMetadata);
}

export class SubscriptionIssueResultService {
  constructor(private readonly repository: SubscriptionIssueRepository);
  load(subscriptionId: string, subscriptionVersion: number);
}
```

`SubscriptionIssueService` re-exports `CommerceMutationMetadata` from its existing path, injects preview/purchase/grant owners, and preserves the exact three current public signatures.

- [ ] **Step C1: Add RED preview, token, persistence-order, and replay characterization**

Create a local `createHarness` that builds the real terms, preview, purchase, grant, result, and facade owners around typed Jest mocks. Its default context has recipient `11111111-1111-4111-8111-111111111111`, payer `22222222-2222-4222-8222-222222222222`, package `33333333-3333-4333-8333-333333333333`, package price `8000`, currency `RUB`, student/package versions `1`, and payer balance `10000`. Its integrity mock invokes `command.mutate(client, 1)` before resolving `{ resultRef, version: 1, replayed }`. Add these exact tests and assertions:

```ts
it("previewPurchase reports the exact insufficient-balance blocker without invoking integrity", async () => {
  const harness = createHarness({ payerBalanceMinor: "5000" });
  const response = await harness.service.previewPurchase(
    harness.actor,
    harness.recipientStudentId,
    harness.previewDto,
  );

  expect(response).toMatchObject({
    finalPriceMinor: "8000",
    payerBalanceMinor: "5000",
    balanceAfterMinor: "-3000",
    canCommit: false,
    shortageMinor: "3000",
    previewToken: "signed-preview-token",
    previewExpiresAt: "2026-08-26T12:10:00.000Z",
  });
  expect(harness.integrity.executeVersionedMutation).not.toHaveBeenCalled();
});

it("purchase rejects a preview bound to another actor before creating facts", async () => {
  const harness = createHarness({ tokenActorUserId: "another-user" });

  await expect(
    harness.service.purchase(
      harness.actor,
      harness.recipientStudentId,
      harness.commandDto,
      harness.metadata,
    ),
  ).rejects.toMatchObject({
    response: { code: "PREVIEW_TOKEN_SCOPE_MISMATCH" },
  });
  expect(harness.repository.createIssuedSubscription).not.toHaveBeenCalled();
  expect(harness.repository.createInstallments).not.toHaveBeenCalled();
  expect(harness.repository.createObligations).not.toHaveBeenCalled();
  expect(harness.repository.createIssueLifecycle).not.toHaveBeenCalled();
});

it("purchase rejects stale student, package or balance facts before creating facts", async () => {
  const harness = createHarness({ tokenPayerBalanceMinor: "9000" });

  await expect(
    harness.service.purchase(
      harness.actor,
      harness.recipientStudentId,
      harness.commandDto,
      harness.metadata,
    ),
  ).rejects.toMatchObject({ response: { code: "PURCHASE_PREVIEW_STALE" } });
  expect(harness.repository.createIssuedSubscription).not.toHaveBeenCalled();
  expect(harness.repository.createInstallments).not.toHaveBeenCalled();
  expect(harness.repository.createObligations).not.toHaveBeenCalled();
  expect(harness.repository.createIssueLifecycle).not.toHaveBeenCalled();
});

it("purchase writes subscription, installments, obligations and lifecycle in that order", async () => {
  const harness = createHarness();
  await harness.service.purchase(
    harness.actor,
    harness.recipientStudentId,
    harness.commandDto,
    harness.metadata,
  );

  expect(harness.repository.createIssuedSubscription.mock.invocationCallOrder[0]).toBeLessThan(
    harness.repository.createInstallments.mock.invocationCallOrder[0],
  );
  expect(harness.repository.createInstallments.mock.invocationCallOrder[0]).toBeLessThan(
    harness.repository.createObligations.mock.invocationCallOrder[0],
  );
  expect(harness.repository.createObligations.mock.invocationCallOrder[0]).toBeLessThan(
    harness.repository.createIssueLifecycle.mock.invocationCallOrder[0],
  );
  expect(harness.integrity.executeVersionedMutation.mock.invocationCallOrder[0]).toBeLessThan(
    harness.results.load.mock.invocationCallOrder[0],
  );
});

it("purchase and issue publish reservations only for a non-replayed commit", async () => {
  const committed = createHarness({ replayed: false });
  await committed.service.purchase(
    committed.actor,
    committed.recipientStudentId,
    committed.commandDto,
    committed.metadata,
  );
  expect(committed.reservations.publishPostCommit).toHaveBeenCalledTimes(1);
  expect(committed.integrity.executeVersionedMutation.mock.invocationCallOrder[0]).toBeLessThan(
    committed.reservations.publishPostCommit.mock.invocationCallOrder[0],
  );

  const replayedPurchase = createHarness({ replayed: true });
  await replayedPurchase.service.purchase(
    replayedPurchase.actor,
    replayedPurchase.recipientStudentId,
    replayedPurchase.commandDto,
    replayedPurchase.metadata,
  );
  expect(replayedPurchase.reservations.publishPostCommit).not.toHaveBeenCalled();

  const committedIssue = createHarness({ replayed: false });
  await committedIssue.service.issue(
    committedIssue.actor,
    committedIssue.recipientStudentId,
    committedIssue.issueDto,
    committedIssue.metadata,
  );
  expect(committedIssue.reservations.publishPostCommit).toHaveBeenCalledTimes(1);
  expect(committedIssue.integrity.executeVersionedMutation.mock.invocationCallOrder[0]).toBeLessThan(
    committedIssue.reservations.publishPostCommit.mock.invocationCallOrder[0],
  );

  const replayedIssue = createHarness({ replayed: true });
  await replayedIssue.service.issue(
    replayedIssue.actor,
    replayedIssue.recipientStudentId,
    replayedIssue.issueDto,
    replayedIssue.metadata,
  );
  expect(replayedIssue.reservations.publishPostCommit).not.toHaveBeenCalled();
});
```

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-issue.service.spec.ts --runInBand
```

Expected: FAIL because the unit composition and semantic owners do not exist.

- [ ] **Step C2: Extract contracts and commercial terms with CCN at most ten**

Move `CommerceMutationMetadata`, mutation/normalization types, discount normalization, installment normalization, surcharge normalization, payment-method validation, purchase normalization, issue normalization, audit-reason selection, and snapshot creation into contracts and terms files. Preserve every Russian message, error code, field name, BigInt formula, basis-point rounding rule, amount limit, installment date/total rule, commercial snapshot key, and payment method.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-issue.service.spec.ts -t "previewPurchase reports" --runInBand
```

Expected: PASS for exact commercial totals and blocker fields.

- [ ] **Step C3: Extract preview, purchase context, and signed-token policy**

Move `previewPurchase`, purchase-context validation, token payload creation, actor/recipient/payer/package/funding binding, stale fingerprint comparison, and purchase-student lookup into `SubscriptionPurchasePreviewService`. Preview remains read-only apart from `readPurchasePreviewContext` transaction and token signing. Preserve `canCommit`, `shortageMinor`, `balanceAfterMinor`, package version, currency, installments, token, and expiry fields.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-issue.service.spec.ts -t "previewPurchase|bound to another actor|stale student" --runInBand
```

Expected: PASS.

- [ ] **Step C4: Extract stable issue-result projection**

Move `loadStableIssueResult` to `SubscriptionIssueResultService.load`. Preserve `ISSUE_RESULT_MISSING`, parallel installment/obligation reads, active status, version argument, zero actual payments, obligation/net signs, and all subscription/installment/obligation response keys.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-issue.service.spec.ts -t "writes subscription" --runInBand
```

Expected: the result owner is reached only after the mocked integrity commit resolves.

- [ ] **Step C5: Extract purchase and grant commits without changing transaction order**

Move `purchase` to `SubscriptionPurchaseCommandService` and `issue` to `SubscriptionGrantCommandService`. Preserve metadata validation, deterministic SHA-256 UUID construction, actor policy, integrity authorization, operation/idempotency/request/aggregate/expectedVersion fields, audit/outbox payloads, repository calls, and reservation publication.

Purchase order inside the integrity callback is exact:

```text
decode and bind token -> sorted recipient/payer locks -> package FOR SHARE
-> balance read -> context/terms normalization -> current fingerprint check
-> insufficient-balance blocker -> subscription -> installments
-> append-only obligations -> lifecycle -> audit.afterRef
```

Grant order is exact:

```text
scope assertion -> deterministic id -> integrity authorization
-> student lock -> package FOR SHARE -> normalized issue terms
-> subscription -> installments -> append-only obligations
-> lifecycle -> audit.afterRef
```

Both owners call result projection after integrity returns and call `reservations.publishPostCommit` only inside `if (!result.replayed)`.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-issue.service.spec.ts --runInBand
```

Expected: PASS for token scope/staleness, persistence order, stable result, and replay-safe post-commit publication.

- [ ] **Step C6: Replace SubscriptionIssueService with a three-delegation facade and add the guard**

Keep `CommerceMutationMetadata` import compatibility by re-exporting it from `subscription-issue.service.ts`. Give the facade exactly preview, purchase, and grant dependencies. Each method is a one-statement direct delegation with unchanged parameters.

In `subscription-issue-boundary.spec.ts`, assert:

```ts
expect(sourceNloc(facade)).toBeLessThanOrEqual(70);
expect(constructor.parameters).toHaveLength(3);
expect(publicMethods).toHaveLength(3);
expect(versionedMutationCount(purchaseSource)).toBe(1);
expect(versionedMutationCount(grantSource)).toBe(1);
expect(otherIssueSources).not.toMatch(/executeVersionedMutation/);
expect(allIssueSources).not.toMatch(/delete\s+from\s+app\./i);
```

Assert exact direct-delegation mappings, NLOC ceilings `terms <=400`, `preview <=260`, `purchase <=300`, `grant <=240`, `result <=180`, purchase/grant source ordering, and that `publishPostCommit` occurs after the integrity call under `!result.replayed`. Defer module provider assertions to Task T1.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-issue.service.spec.ts src/crm/commerce/subscription-issue-boundary.spec.ts --runInBand
```

Expected: PASS.

- [ ] **Step C7: Run lane smoke, record evidence, and commit Lane C**

Run only:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-issue.service.spec.ts src/crm/commerce/subscription-issue-boundary.spec.ts --runInBand
npm --prefix server run typecheck
git diff --check
repowise update --index-only
```

Begin `.superpowers/campaign12/reports/tier1-lane-c.md` with the literal prefix `Campaign baseline: ` followed immediately by `$Tier1Base` resolved to its lowercase 40-character SHA. Then record exact evidence and use RepoWise `get_health` for the facade and terms/preview/purchase/grant/result files; require health `>=7.0`, CCN `<=10`, and no god/brain finding for every new owner.

Commit:

```powershell
git add server/src/crm/commerce/subscription-issue.contracts.ts server/src/crm/commerce/subscription-commercial-terms.service.ts server/src/crm/commerce/subscription-purchase-preview.service.ts server/src/crm/commerce/subscription-purchase-command.service.ts server/src/crm/commerce/subscription-grant-command.service.ts server/src/crm/commerce/subscription-issue-result.service.ts server/src/crm/commerce/subscription-issue.service.ts server/src/crm/commerce/subscription-issue.service.spec.ts server/src/crm/commerce/subscription-issue-boundary.spec.ts server/src/crm/commerce/subscription-issue-postgres.integration.spec.ts server/src/crm/commerce/subscription-cancel-postgres.integration.spec.ts server/src/crm/commerce/subscription-replace-postgres.integration.spec.ts .superpowers/campaign12/reports/tier1-lane-c.md
git commit -m "refactor(commerce): split subscription issue owners"
```

---

## Task T1: Integrate, wire, smoke, and review Tier 1

### Files

- Modify: `server/src/messenger/messenger.module.ts`
- Modify: `server/src/crm/crm.module.ts`
- Create: `.superpowers/campaign12/reports/tier1-integration.md`
- Create: `.superpowers/campaign12/reports/tier1-review.md`
- Verify only: `server/src/app.module.spec.ts`
- Verify only: `server/src/messenger/messenger.controller.ts`
- Verify only: `server/src/crm/crm-people.controller.ts`
- Verify only: `server/src/crm/subscription-commerce.controller.ts`

### Interfaces

`MessengerModule` registers these private providers:

```ts
MessengerChatAccessService
MessengerSystemChatService
MessengerChatQueryService
MessengerChatCommandService
MessengerMessageDeliveryService
```

It continues to export only `MessengerService`, `MessengerPolicyModule`, and `RealtimeGateway` from the affected surface.

`CrmModule` registers these private providers:

```ts
PayrollAccrualCalculator
PayrollReadRepository
TeacherPayrollQueryService
TeacherPayrollCommandService
TeacherStatsReportService
TeacherStatsCsvService
SubscriptionCommercialTermsService
SubscriptionPurchasePreviewService
SubscriptionPurchaseCommandService
SubscriptionGrantCommandService
SubscriptionIssueResultService
```

None of these eleven owners is added to `CrmModule.exports`.

- [ ] **Step T1.1: Apply the three lane commits in dependency order**

Apply Lane A, then Lane B, then Lane C to the Tier 1 integration branch. After each application run `git diff --check`. If a lane touches `messenger.module.ts`, `crm.module.ts`, a controller, or another lane package, stop that application and return it to the owning lane; do not resolve the scope expansion silently.

- [ ] **Step T1.2: Add centralized MessengerModule wiring**

Import the five Messenger owners, add them once to `providers` before `MessengerService`, keep both controllers unchanged, and keep the existing export surface. Extend `messenger-service-boundary.spec.ts` so it reads the wired module and asserts every owner is present in `providers` and absent from `exports`.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/messenger/messenger.service.spec.ts src/messenger/messenger-service-boundary.spec.ts src/messenger/messenger-policy.module.spec.ts --runInBand
```

Expected: PASS.

- [ ] **Step T1.3: Add centralized CrmModule wiring for Payroll and SubscriptionIssue**

Import the six Payroll owners and five SubscriptionIssue owners, register each once in `providers`, retain `PayrollService`, `SubscriptionIssueRepository`, and `SubscriptionIssueService`, and do not alter `exports`. Extend both boundary specs to assert the exact provider/export rules.

Run:

```powershell
npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll/payroll-service-boundary.spec.ts src/crm/commerce/subscription-issue.service.spec.ts src/crm/commerce/subscription-issue-boundary.spec.ts --runInBand
```

Expected: PASS.

- [ ] **Step T1.4: Run the wired Tier 1 smoke once**

Run only these commands:

```powershell
npm --prefix server test -- --runTestsByPath src/messenger/messenger.service.spec.ts src/messenger/messenger-service-boundary.spec.ts --runInBand
npm --prefix server test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll/payroll-service-boundary.spec.ts --runInBand
npm --prefix server test -- --runTestsByPath src/crm/commerce/subscription-issue.service.spec.ts src/crm/commerce/subscription-issue-boundary.spec.ts --runInBand
npm --prefix server test -- --runTestsByPath src/app.module.spec.ts src/messenger/messenger-policy.module.spec.ts --runInBand
npm --prefix server run typecheck
git diff --check
repowise update --index-only
```

Query RepoWise health for all three facades and all sixteen new semantic owners. Record exact commands, exits, counts, durations, provider/export assertions, target health/NLOC/CCN/deficits, and the integrated commit range in `.superpowers/campaign12/reports/tier1-integration.md`.

- [ ] **Step T1.5: Obtain one independent Tier 1 review**

Give the reviewer the Campaign-12 baseline-to-Tier-1 diff, the three lane reports, the integration report, and the approved spec. Require explicit findings grouped as Critical, Important, and Minor for:

```text
scope and facade contracts
RBAC/resource scope and failure behavior
transaction/idempotency/audit/outbox/history preservation
realtime and post-commit ordering
permanent structural guards and private module wiring
```

Record the reviewer identity, reviewed commit range, every finding, and disposition in `.superpowers/campaign12/reports/tier1-review.md`. Tier 2 cannot start while any Critical or Important finding remains open. A Minor finding may be deferred only with an explicit owner ruling and stated global-gate cost.

- [ ] **Step T1.6: Fix reviewer findings at the owning lane boundary**

For each accepted Critical or Important finding, change only the owning lane files, add or tighten one focused regression assertion, rerun that lane's exact smoke from T1.4, then rerun `src/app.module.spec.ts`, typecheck, `git diff --check`, and targeted RepoWise health. Update both integration and review reports with the fix commit and evidence.

- [ ] **Step T1.7: Commit centralized wiring and Tier 1 evidence**

Run `git diff --check`, confirm the two module files plus the two Tier 1 reports are the only integrator-owned changes, and commit:

```powershell
git add server/src/messenger/messenger.module.ts server/src/messenger/messenger-service-boundary.spec.ts server/src/crm/crm.module.ts server/src/crm/payroll/payroll-service-boundary.spec.ts server/src/crm/commerce/subscription-issue-boundary.spec.ts .superpowers/campaign12/reports/tier1-integration.md .superpowers/campaign12/reports/tier1-review.md
git commit -m "refactor(server): wire Campaign-12 tier 1 owners"
```

Tier 1 is complete only when all four focused Jest invocations, typecheck, diff check, targeted health gates, module boundary assertions, and the independent review pass with Critical/Important `0/0`.

### Task D: Split `ProfileService` into self, directory, notes, and record owners

**Baseline:** `server/src/profile/profile.service.ts` is health `2.78`, `656` NLOC, max CCN `10`, weighted deficit `3,424`.

**Files:**

- Create: `server/src/profile/profile-record.repository.ts`
- Create: `server/src/profile/my-profile.service.ts`
- Create: `server/src/profile/profile-directory.service.ts`
- Create: `server/src/profile/profile-notes.service.ts`
- Rewrite: `server/src/profile/profile.service.ts`
- Modify: `server/src/profile/profile.module.ts`
- Modify: `server/src/profile/profile.service.spec.ts`
- Create: `server/src/profile/my-profile.service.spec.ts`
- Create: `server/src/profile/profile-directory.service.spec.ts`
- Create: `server/src/profile/profile-notes.service.spec.ts`
- Create: `server/src/profile/profile-boundaries.spec.ts`
- Report: `.superpowers/campaign12/lane-d-profile-report.md`

**Verify-only:** `server/src/profile/profile.controller.ts`, `server/src/profile/profile.policy.ts`, `server/src/profile/profile-linking.service.ts`, and every profile DTO.

**Interfaces:**

- `ProfileRecordRepository.ensure(userId: string): Promise<void>`.
- `ProfileRecordRepository.findByUserId(userId: string): Promise<ProfileRow | undefined>`.
- `ProfileRecordRepository.findById(profileId: string): Promise<ProfileRow | undefined>`.
- `MyProfileService.getMe(actor: ActorContext)` and `updateMe(actor: ActorContext, dto: UpdateProfileDto)`.
- `ProfileDirectoryService.listProfiles(actor: ActorContext, query: ListProfilesQuery)`, `getProfile(actor: ActorContext, profileId: string)`, and `listProfileLinks(actor: ActorContext, profileId: string)`.
- `ProfileNotesService.listProfileNotes(actor: ActorContext, profileId: string)` and `createProfileNote(actor: ActorContext, profileId: string, body: string)`.
- `ProfileService` consumes `MyProfileService`, `ProfileDirectoryService`, and `ProfileNotesService`; controllers continue consuming only `ProfileService`.

- [ ] **D1 RED: Add missing self-profile characterization tests**

Create exact cases in `my-profile.service.spec.ts`:

```ts
it("creates a missing profile once, reloads it, and keeps oldest branch as home", async () => {
  repository.findByUserId
    .mockResolvedValueOnce(undefined)
    .mockResolvedValueOnce(profileRow);
  repository.ensure.mockResolvedValue(undefined);
  database.query.mockResolvedValue({
    rows: [{ branch_id: "branch-2" }, { branch_id: "branch-9" }],
  });

  await expect(service.getMe(actor)).resolves.toMatchObject({
    id: "profile-a",
    branchIds: ["branch-2", "branch-9"],
    homeBranchId: "branch-2",
  });
  expect(repository.ensure).toHaveBeenCalledTimes(1);
  expect(repository.ensure).toHaveBeenCalledWith(actor.userId);
  expect(repository.findByUserId).toHaveBeenCalledTimes(2);
});

it("rejects an avatar outside the actor-owned active avatar boundary", async () => {
  repository.ensure.mockResolvedValue(undefined);
  database.query.mockResolvedValueOnce({ rows: [] });
  await expect(
    service.updateMe(actor, { avatarFileId: "avatar-a" }),
  ).rejects.toThrow("Файл аватара не найден.");
  expect(database.query).toHaveBeenCalledWith(
    expect.stringMatching(/owner_user_id = \$2[\s\S]*purpose = 'profile_avatar'[\s\S]*deleted_at is null/),
    ["avatar-a", actor.userId],
  );
  expect(audit.record).not.toHaveBeenCalled();
});
```

Also assert that whitespace name/phone inputs are passed as `null` beside SQL `coalesce`, complete clients call only `autoCreateLeadFromChat(actor, actor.userId, "onboarding")`, complete non-clients call only `linkProfileByPhone(actor, profile, "auto_phone")`, incomplete profiles call neither, and `profile.updated` is the final side effect.

- [ ] **D2 RED: Add directory and notes characterization tests**

```ts
it("caps the directory at 100 and keeps system-admin visibility actor-scoped", async () => {
  database.query.mockResolvedValue({ rows: [] });
  await service.listProfiles(actor, { limit: 500, q: "  Анна  " });
  expect(policy.assertCanListProfiles).toHaveBeenCalledWith(actor);
  expect(database.query).toHaveBeenCalledWith(
    expect.stringMatching(/u\.is_app_account = true[\s\S]*u\.role <> 'system_admin'/),
    [null, "Анна", 100, actor.role],
  );
});

it("keeps note ordering, author fallback, and audit payload", async () => {
  repository.findById.mockResolvedValue(profileRow);
  database.query.mockResolvedValueOnce({ rows: [{ ...noteRow, author_id: null }] });
  await expect(service.listProfileNotes(actor, "profile-a")).resolves.toEqual({
    items: [expect.objectContaining({ author: null })],
  });
  expect(database.query).toHaveBeenCalledWith(
    expect.stringMatching(/order by n\.created_at desc, n\.id desc[\s\S]*limit 100/),
    ["profile-a"],
  );
});
```

Add exact assertions that `getProfile` passes `profile.user_id` to `assertCanReadProfile`, linked entity projection remains student/lead-only with limit `500`, null link names map to `"—"`, blank notes fail after trimming, and note insert precedes `profile.note_created` with `{ noteId }`.

- [ ] **D3 RED: Run the characterization tests and confirm the new owners are absent**

Run:

```powershell
Set-Location server
npm test -- --runTestsByPath src/profile/my-profile.service.spec.ts src/profile/profile-directory.service.spec.ts src/profile/profile-notes.service.spec.ts
```

Expected: FAIL because the three service modules do not exist.

- [ ] **D4 Implementation: Extract the record repository and semantic owners**

Move the baseline SQL and mapping without changing predicates or operation order. Use these exact internal contracts while moving `getMe` lines 69-97, `updateMe` lines 99-174, directory lines 176-441 and 470-523, notes lines 443-466 and 525-567, and repository/mapping lines 569-689:

```ts
export interface ProfileDtoProjection {
  id: string;
  userId: string;
  email: string;
  role: UserRole;
  firstName: string | null;
  lastName: string | null;
  phone: string | null;
  dob: Date | string | null;
  avatarFileId: string | null;
  emailOtp2faEnabled: boolean;
  isAppAccount: boolean;
  phoneVerifiedAt: Date | string | null;
  createdAt: Date | string;
  updatedAt: Date | string;
}
export interface ProfileSummaryProjection {
  id: string;
  userId: string;
  email: string;
  role: UserRole;
  firstName: string | null;
  lastName: string | null;
  phone: string | null;
  isAppAccount: boolean;
  phoneVerifiedAt: Date | string | null;
  linkedStudents: number;
  linkedLeads: number;
  linkedTeachers: number;
  linkedStaff: number;
  candidateStudents: number;
  candidateLeads: number;
  candidateTeachers: number;
  candidateStaff: number;
}
export interface ProfileNoteProjection {
  id: string;
  profileId: string;
  authorId: string | null;
  body: string;
  createdAt: Date | string;
  author: {
    id: string;
    email: string | null;
    firstName: string | null;
    lastName: string | null;
  } | null;
}
export interface ProfileRecordPort {
  ensure(userId: string): Promise<void>;
  findByUserId(userId: string): Promise<ProfileRow | undefined>;
  findById(profileId: string): Promise<ProfileRow | undefined>;
  toProfileDto(row: ProfileRow): ProfileDtoProjection;
  toProfileSummaryDto(row: ProfileRow): ProfileSummaryProjection;
  toProfileNoteDto(row: ProfileNoteRow): ProfileNoteProjection;
}
export interface MyProfileOperations {
  getMe(actor: ActorContext): Promise<ProfileDtoProjection & {
    branchIds: string[];
    homeBranchId: string | null;
  }>;
  updateMe(actor: ActorContext, dto: UpdateProfileDto): Promise<ProfileDtoProjection>;
}
export interface ProfileDirectoryOperations {
  listProfiles(actor: ActorContext, query: ListProfilesQuery): Promise<{
    items: ProfileSummaryProjection[];
    total: number;
  }>;
  getProfile(actor: ActorContext, profileId: string): Promise<ProfileDtoProjection>;
  listProfileLinks(actor: ActorContext, profileId: string): Promise<{
    items: Array<{ entityType: string; entityId: string; name: string }>;
  }>;
}
export interface ProfileNoteOperations {
  listProfileNotes(actor: ActorContext, profileId: string): Promise<{
    items: ProfileNoteProjection[];
  }>;
  createProfileNote(actor: ActorContext, profileId: string, body: string): Promise<ProfileNoteProjection>;
}
```

The comments in the outline identify exact existing bodies to move; do not introduce a transaction because the current service has none.

- [ ] **D5 Facade: Replace `ProfileService` with exact direct delegations**

```ts
@Injectable()
export class ProfileService {
  constructor(
    private readonly self: MyProfileService,
    private readonly directory: ProfileDirectoryService,
    private readonly notes: ProfileNotesService,
  ) {}

  getMe(actor: ActorContext) { return this.self.getMe(actor); }
  updateMe(actor: ActorContext, dto: UpdateProfileDto) { return this.self.updateMe(actor, dto); }
  listProfiles(actor: ActorContext, query: ListProfilesQuery) { return this.directory.listProfiles(actor, query); }
  getProfile(actor: ActorContext, profileId: string) { return this.directory.getProfile(actor, profileId); }
  listProfileLinks(actor: ActorContext, profileId: string) { return this.directory.listProfileLinks(actor, profileId); }
  listProfileNotes(actor: ActorContext, profileId: string) { return this.notes.listProfileNotes(actor, profileId); }
  createProfileNote(actor: ActorContext, profileId: string, body: string) { return this.notes.createProfileNote(actor, profileId, body); }
}
```

Register `ProfileRecordRepository`, `MyProfileService`, `ProfileDirectoryService`, and `ProfileNotesService` in `ProfileModule.providers`. Keep `ProfileModule.exports` equal to `[ProfileService]`.

- [ ] **D6 Guard: Enforce the facade and module boundary**

In `profile-boundaries.spec.ts`, parse the facade with TypeScript AST and assert:

```ts
expect(sourceNloc(facade)).toBeLessThanOrEqual(90);
expect(exactConstructorTypes(facade)).toEqual([
  "MyProfileService",
  "ProfileDirectoryService",
  "ProfileNotesService",
]);
expect(exactMethodNames(facade)).toEqual([
  "getMe", "updateMe", "listProfiles", "getProfile",
  "listProfileLinks", "listProfileNotes", "createProfileNote",
]);
expect(facade).not.toMatch(/DatabaseService|\.transaction\(|select\s|insert\s|update\s|delete\s|AuditService|ProfilePolicy/iu);
expect(privateProviders(profileModule)).toEqual(expect.arrayContaining([
  "ProfileRecordRepository", "MyProfileService",
  "ProfileDirectoryService", "ProfileNotesService",
]));
```

For every facade method, assert one return statement, one call, exact argument identifiers, and exact target owner. Assert each new production file is at most `500` NLOC.

- [ ] **D7 Smoke: Run the complete lane check once**

```powershell
Set-Location server
npm test -- --runTestsByPath src/profile/profile.service.spec.ts src/profile/my-profile.service.spec.ts src/profile/profile-directory.service.spec.ts src/profile/profile-notes.service.spec.ts src/profile/profile.policy.spec.ts src/profile/profile-boundaries.spec.ts
npm run typecheck -- --pretty false
Set-Location ..
git diff --check
repowise update --index-only
@(
  'server/src/profile/profile.service.ts',
  'server/src/profile/profile-record.repository.ts',
  'server/src/profile/my-profile.service.ts',
  'server/src/profile/profile-directory.service.ts',
  'server/src/profile/profile-notes.service.ts'
) | ForEach-Object { repowise health --file $_ --format json }
```

Expected: all focused tests and typecheck pass; facade guard passes; each new owner reports health `>=7.0`, max CCN `<=10`, and no god/brain finding.

- [ ] **D8 Report: Record exact lane evidence**

Write `.superpowers/campaign12/lane-d-profile-report.md` with baseline/after health, NLOC, max CCN, weighted deficit for the facade and each new owner; test counts/durations; `git diff --check`; preserved routes/RBAC/audit order; and intended commit message `refactor(profile): split profile service semantic owners`. D9 prints the resulting SHA for the tier ledger.

- [ ] **D9 Commit: Create the reversible lane commit**

```powershell
git add server/src/profile
git commit -m "refactor(profile): split profile service semantic owners"
git rev-parse HEAD
```

---

### Task E: Split `AuthService` into security workflow owners

**Baseline:** `server/src/auth/auth.service.ts` is health `1.68`, `865` NLOC, max CCN `11`, weighted deficit `5,467`, with five recent bug-fix commits.

**Files:**

- Create: `server/src/auth/auth.types.ts`
- Create: `server/src/auth/auth-normalization.ts`
- Create: `server/src/auth/auth-rate-limit.service.ts`
- Create: `server/src/auth/auth-email-challenge.service.ts`
- Create: `server/src/auth/auth-registration.service.ts`
- Create: `server/src/auth/auth-login.service.ts`
- Create: `server/src/auth/auth-verification.service.ts`
- Create: `server/src/auth/auth-password-recovery.service.ts`
- Create: `server/src/auth/auth-account.service.ts`
- Rewrite: `server/src/auth/auth.service.ts`
- Modify: `server/src/auth/auth.module.ts`
- Modify: `server/src/auth/auth.service.spec.ts`
- Create: `server/src/auth/auth-boundaries.spec.ts`
- Report: `.superpowers/campaign12/lane-e-auth-report.md`

**Verify-only:** `server/src/auth/auth.controller.ts`, every auth DTO, `password.service.ts`, and `session.service.ts`.

**Interfaces:**

```ts
export interface AuthUserResponse {
  id: string;
  email: string;
  role: UserRole;
  emailVerified: boolean;
}
export interface SignupResponse {
  user: AuthUserResponse;
  emailVerificationRequired: boolean;
}
export interface AcceptedResponse { accepted: true; }
```

`AuthService` continues exporting those three interfaces from its historical path. Its twelve public methods retain the current explicit return types.

- [ ] **E1 RED: Add missing enumeration, delivery, credentials, and replay tests**

Add these exact cases to `auth.service.spec.ts` while retaining every current case:

```ts
it("does not reveal an unknown OTP identity", async () => {
  database.query.mockResolvedValueOnce({ rows: [] });
  await expect(service.requestOtp(" missing@example.com ")).resolves.toEqual({ accepted: true });
  expect(notifications.sendEmail).not.toHaveBeenCalled();
  expect(audit.record).not.toHaveBeenCalled();
});

it("maps duplicate email and leaves sessions untouched", async () => {
  database.query
    .mockResolvedValueOnce({ rows: [userRecord] })
    .mockRejectedValueOnce(Object.assign(new Error("duplicate"), { code: "23505" }));
  passwordService.verify.mockResolvedValue(true);
  await expect(service.changeEmail(actor, "new@example.com", "secret123"))
    .rejects.toThrow("Пользователь с такой почтой уже существует.");
  expect(sessions.revokeAll).not.toHaveBeenCalled();
});
```

Also assert: required OTP delivery failure consumes its new challenge and issues no session; client `setPassword` writes `managed_password_ciphertext=null`; non-client set/reset uses `encryptForManagedAccess`; session revocation precedes success audit; valid email-verification token audits once and replay returns the exact invalid/expired error.

- [ ] **E2 RED: Run the focused auth tests before extraction**

```powershell
Set-Location server
npm test -- --runTestsByPath src/auth/auth.service.spec.ts src/auth/auth-boundaries.spec.ts
```

Expected: the pre-extraction behavior cases pass and the boundary suite fails because extracted files and the direct facade do not exist.

- [ ] **E3 Implementation: Create shared contracts and security helpers**

Move `UserRecord`, `CountRecord`, and `IdentityRecord` to `auth.types.ts`. Export pure helpers from `auth-normalization.ts` with these signatures:

```ts
export const normalizeEmail = (email: string): string;
export const normalizePhone = (phone?: string | null): string | null;
export const splitFullName = (fullName: string): [string, string | null];
export const sha256 = (value: string): string;
export const otpHash = (email: string, code: string): string;
export const toAuthUserResponse = (user: UserRecord): AuthUserResponse;
```

Create `AuthRateLimitService` methods `assertLoginAllowed(emailHash)`, `assertOtpVerifyAllowed(emailHash)`, `assertSignupAllowed(ipHash)`, `assertResetConfirmAllowed(ipHash)`, `isOtpRequestLimited(emailHash)`, and `isResetRequestLimited(userId)`. Preserve every current limit, interval, audit action, status `429`, and Russian message.

Create `AuthEmailChallengeService` methods:

```ts
createEmailVerificationChallenge(userId: string, email: string): Promise<void>;
createOtpChallenge(user: UserRecord, email: string, options?: { requireDelivery?: boolean }): Promise<void>;
sendPasswordReset(user: UserRecord, token: string): Promise<void>;
```

Required delivery failure must consume the inserted challenge before throwing `ServiceUnavailableException` with code `OTP_DELIVERY_UNAVAILABLE`.

- [ ] **E4 Implementation: Extract five workflow services**

Use these exact public surfaces:

```ts
@Injectable() export class AuthRegistrationService {
  signup(dto: SignupDto, clientIp?: string): Promise<SignupResponse>;
}
@Injectable() export class AuthLoginService {
  login(dto: LoginDto): Promise<{ user: AuthUserResponse; session?: TokenPair; emailOtpRequired?: boolean }>;
  refresh(refreshToken: string): Promise<{ session: TokenPair }>;
  logoutAll(actor: ActorContext): Promise<{ success: true }>;
}
@Injectable() export class AuthVerificationService {
  requestOtp(emailInput: string): Promise<AcceptedResponse>;
  verifyOtp(emailInput: string, code: string): Promise<{ user: AuthUserResponse; session?: TokenPair }>;
  verifyEmail(token: string): Promise<{ user: AuthUserResponse }>;
}
@Injectable() export class AuthPasswordRecoveryService {
  requestPasswordReset(emailInput: string): Promise<AcceptedResponse>;
  resetPassword(token: string, password: string, clientIp?: string): Promise<{ user: AuthUserResponse }>;
}
@Injectable() export class AuthAccountService {
  setPassword(actor: ActorContext, password: string): Promise<{ user: AuthUserResponse }>;
  changeEmail(actor: ActorContext, emailInput: string, currentPassword: string): Promise<{ user: AuthUserResponse }>;
  listIdentities(actor: ActorContext): Promise<{ items: Array<{ provider: string }> }>;
}
```

Split password authentication, OTP decision, and session issuance inside `AuthLoginService` so each method has max CCN `<=10`. Preserve the absence of an explicit `DatabaseService.transaction` and every current partial-success sequence.

- [ ] **E5 Facade: Replace `AuthService` with exact direct delegations**

```ts
@Injectable()
export class AuthService {
  constructor(
    private readonly registration: AuthRegistrationService,
    private readonly loginFlow: AuthLoginService,
    private readonly verification: AuthVerificationService,
    private readonly recovery: AuthPasswordRecoveryService,
    private readonly account: AuthAccountService,
  ) {}
  signup(dto: SignupDto, clientIp?: string) { return this.registration.signup(dto, clientIp); }
  login(dto: LoginDto) { return this.loginFlow.login(dto); }
  refresh(refreshToken: string) { return this.loginFlow.refresh(refreshToken); }
  logoutAll(actor: ActorContext) { return this.loginFlow.logoutAll(actor); }
  requestOtp(emailInput: string) { return this.verification.requestOtp(emailInput); }
  verifyOtp(emailInput: string, code: string) { return this.verification.verifyOtp(emailInput, code); }
  requestPasswordReset(emailInput: string) { return this.recovery.requestPasswordReset(emailInput); }
  resetPassword(token: string, password: string, clientIp?: string) { return this.recovery.resetPassword(token, password, clientIp); }
  setPassword(actor: ActorContext, password: string) { return this.account.setPassword(actor, password); }
  changeEmail(actor: ActorContext, emailInput: string, currentPassword: string) { return this.account.changeEmail(actor, emailInput, currentPassword); }
  listIdentities(actor: ActorContext) { return this.account.listIdentities(actor); }
  verifyEmail(token: string) { return this.verification.verifyEmail(token); }
}
export type { AcceptedResponse, AuthUserResponse, SignupResponse } from "./auth.types";
```

Register all seven new injectable owners in `AuthModule.providers`. Keep `AuthModule.exports` exactly `[AuthService, PasswordService, SessionService]`.

- [ ] **E6 Guard: Enforce the security facade and private wiring**

```ts
expect(sourceNloc(facade)).toBeLessThanOrEqual(140);
expect(exactConstructorTypes(facade)).toEqual([
  "AuthRegistrationService", "AuthLoginService", "AuthVerificationService",
  "AuthPasswordRecoveryService", "AuthAccountService",
]);
expect(exactMethodNames(facade)).toEqual([
  "signup", "login", "refresh", "logoutAll", "requestOtp", "verifyOtp",
  "requestPasswordReset", "resetPassword", "setPassword", "changeEmail",
  "listIdentities", "verifyEmail",
]);
expect(facade).not.toMatch(/DatabaseService|AuditService|NotificationsService|PasswordService|SessionService|createHash|randomBytes|randomInt|process\.env|select\s|insert\s|update\s/iu);
```

Assert exact owner/argument delegation for all twelve methods, each new production owner `<=500` NLOC, all new providers private, and the three historical module exports unchanged.

- [ ] **E7 Smoke: Run the complete security lane check once**

```powershell
Set-Location server
npm test -- --runTestsByPath src/auth/auth.service.spec.ts src/auth/auth-boundaries.spec.ts src/auth/password-policy.spec.ts src/auth/password.service.spec.ts src/auth/session.service.spec.ts src/auth/auth.controller.spec.ts
npm run typecheck -- --pretty false
Set-Location ..
git diff --check
repowise update --index-only
@(
  'server/src/auth/auth.service.ts',
  'server/src/auth/auth-registration.service.ts',
  'server/src/auth/auth-login.service.ts',
  'server/src/auth/auth-verification.service.ts',
  'server/src/auth/auth-password-recovery.service.ts',
  'server/src/auth/auth-account.service.ts',
  'server/src/auth/auth-rate-limit.service.ts',
  'server/src/auth/auth-email-challenge.service.ts'
) | ForEach-Object { repowise health --file $_ --format json }
```

Expected: focused tests/typecheck pass; no route or controller diff; every new owner meets the health/CCN gate.

- [ ] **E8 Report: Record exact security evidence**

Write `.superpowers/campaign12/lane-e-auth-report.md` with before/after metrics, test totals/durations, response-shape check, OTP/credential/session/audit sequencing check, facade guard result, and intended commit message `refactor(auth): split authentication workflows`. E9 prints the resulting SHA for the tier ledger.

- [ ] **E9 Commit: Create the reversible auth commit**

```powershell
git add server/src/auth
git commit -m "refactor(auth): split authentication workflows"
git rev-parse HEAD
```

---

### Task F: Split `LessonTransitionService` and publish neutral command metadata

**Baseline:** `server/src/crm/schedule/lesson-transition.service.ts` is health `4.58`, `1,535` NLOC, max CCN `36`, weighted deficit `5,250`.

**Files:**

- Create: `server/src/crm/schedule/lesson-command-metadata.ts`
- Create: `server/src/crm/schedule/lesson-transition.types.ts`
- Create: `server/src/crm/schedule/lesson-transition.rules.ts`
- Create: `server/src/crm/schedule/lesson-transition-preparation.service.ts`
- Create: `server/src/crm/schedule/lesson-transition-financial.service.ts`
- Create: `server/src/crm/schedule/lesson-transition-commit.service.ts`
- Create: `server/src/crm/schedule/lesson-transition-preview.service.ts`
- Create: `server/src/crm/schedule/lesson-transition-command.service.ts`
- Create: `server/src/crm/schedule/lesson-bulk-transition.service.ts`
- Rewrite: `server/src/crm/schedule/lesson-transition.service.ts`
- Modify: `server/src/crm/schedule/lesson-command.service.ts`
- Modify: `server/src/crm/schedule/lesson-series-command.service.ts`
- Modify: `server/src/crm/schedule/lesson-settlement-correction.service.ts`
- Modify: `server/src/crm/schedule/schedule-plan.service.ts` only to switch the metadata type import
- Modify: `server/src/crm/crm.module.ts`
- Modify: `server/src/crm/schedule/reschedule-postgres.integration.spec.ts`
- Create: `server/src/crm/schedule/lesson-command-metadata.spec.ts`
- Create: `server/src/crm/schedule/lesson-transition-boundaries.spec.ts`
- Create: `server/src/crm/schedule/lesson-transition-order.spec.ts`
- Report: `.superpowers/campaign12/lane-f-lesson-transition-report.md`

**Verify-only:** `server/src/crm/crm-schedule.controller.ts`, all transition DTOs, platform integrity, lifecycle, reservation, settlement, preview-token, and constraint-engine implementations.

**Produces for Task J:**

```ts
// server/src/crm/schedule/lesson-command-metadata.ts
export interface LessonCommandMetadata {
  idempotencyKey: string;
  requestId: string;
}
```

`lesson-command.service.ts` must re-export this interface from the historical path. All five services import the neutral file directly: lesson command, lesson series command, settlement correction, lesson transition, and schedule plan. Keep each service's current validator because their error bodies differ.

- [ ] **F1 RED: Add metadata ownership and transition ordering tests**

In `lesson-command-metadata.spec.ts`, read the five production sources and assert:

```ts
expect(metadataSource).toMatch(/export interface LessonCommandMetadata\s*{\s*idempotencyKey: string;\s*requestId: string;\s*}/s);
for (const source of fiveConsumers) {
  expect(source).toMatch(/from "\.\/lesson-command-metadata"/);
}
expect(lessonCommandSource).toMatch(/export type { LessonCommandMetadata } from "\.\/lesson-command-metadata"/);
expect(schedulePlanSource).not.toMatch(/LessonCommandMetadata.*lesson-command\.service/);
```

In `lesson-transition-order.spec.ts`, add runtime mock-order tests that assert:

```ts
expect(advisoryKeys).toEqual([...new Set(advisoryKeys)].sort());
expect(events).toEqual([
  "source-for-update", "settlement-review", "advisory-locks",
  "constraint-validation", "coverage-lock", "successor-insert",
  "source-settlement", "fingerprint-check", "successor-allocation",
  "transition-append", "mutation-resolved", "publish-source", "publish-successor",
]);
expect(previewClientQueries).toEqual([
  "savepoint lesson_transition_preview",
  "rollback to savepoint lesson_transition_preview",
  "release savepoint lesson_transition_preview",
]);
```

Add bulk assertions for deterministic lesson-ID sorting, duplicate rejection, maximum `500`, single versioned mutation, stale fingerprint rollback, and publication only after mutation resolution.

- [ ] **F2 RED: Run new boundary tests and verify failure**

```powershell
Set-Location server
npm test -- --runTestsByPath src/crm/schedule/lesson-command-metadata.spec.ts src/crm/schedule/lesson-transition-boundaries.spec.ts src/crm/schedule/lesson-transition-order.spec.ts
```

Expected: FAIL because the neutral contract and extracted owner files do not exist.

- [ ] **F3 Implementation: Create neutral metadata and transition rule/type boundaries**

Create the two-field metadata interface exactly as shown above. Move exported `CommittedTransition` and `LessonTransitionPreviewResult` plus internal source/draft/result types into `lesson-transition.types.ts`; re-export the two public types from `lesson-transition.service.ts`.

`lesson-transition.types.ts` owns the exact baseline declarations currently at `lesson-transition.service.ts:47-167`: `TransitionOperation`, `TransitionState`, `GroupParticipantSnapshot`, `TransitionLessonRow`, `GroupLessonDraft`, `TransitionSuccessor`, `TransitionSource`, `TransitionPreviewDto`, `TransitionCommandDto`, `CommittedTransition`, `CalculatedTransitionPreview`, `BulkTransitionResultRef`, and `LessonTransitionPreviewResult`. Preserve every property and union member while moving them. Add these workflow contracts in the same file so the extracted owners share one definition:

```ts
export type TerminalTransitionState = Exclude<
  TransitionState,
  "scheduled" | "settlement_pending"
>;

export interface LessonTransitionCommandResult {
  source: { id: string; state: TerminalTransitionState; version: number };
  successor: { id: string; state: "scheduled"; version: 1 } | null;
  transitionId: string;
  clientFinancialFactIds: string[];
  teacherFinancialFactId: string;
  financialDecision: LessonFinancialDecision;
  replayed: boolean;
}

export interface LessonBulkTransitionPreviewResult {
  items: Array<LessonTransitionPreviewResult & {
    lessonId: string;
    operation: TransitionOperation;
  }>;
  canConfirm: boolean;
  confirmRequired: true;
  previewToken?: string;
  previewExpiresAt?: string;
}

export interface LessonBulkTransitionCommandResult {
  bulkId: string;
  items: CommittedTransition[];
  replayed: boolean;
}

export type TransitionFinancialProjection = {
  clientFacts: Array<Omit<LessonSettlementResult["clientFacts"][number], "id">>;
  teacherFact: Omit<LessonSettlementResult["teacherFact"], "id">;
};

export interface TransitionFingerprintInput {
  operation: TransitionOperation;
  source: TransitionSource;
  successor: TransitionSuccessor | null;
  dto: TransitionPreviewDto;
  coverage: LessonSettlementCoverageSnapshot;
  financial: TransitionFinancialProjection;
}

export interface BulkFingerprintItem {
  lessonId: string;
  operation: TransitionOperation;
  preview: Pick<CalculatedTransitionPreview, "transitionFingerprint">;
}

export interface CommitTransitionInput {
  actor: ActorContext;
  lessonId: string;
  dto: TransitionPreviewDto;
  operation: TransitionOperation;
  successorId: string | null;
  nextVersion: number;
  expectedFingerprint?: string;
}
```

`lesson-transition.rules.ts` exports deterministic functions with these signatures:

```ts
export function targetTransitionState(operation: TransitionOperation): TerminalTransitionState;
export function transitionReasonCode(dto: TransitionPreviewDto): string;
export function assertTransitionReason(dto: TransitionPreviewDto, operation: TransitionOperation): void;
export function assertTransitionConfirmed(confirm: true): void;
export function assertTransitionMetadata(metadata: LessonCommandMetadata): void;
export function stableTransitionId(seed: string): string;
export function normalizeBulkTransitionItems(dto: LessonBulkTransitionPreviewDto): LessonBulkTransitionItemDto[];
export function transitionFingerprint(input: TransitionFingerprintInput): string;
export function bulkTransitionFingerprint(dto: LessonBulkTransitionPreviewDto, items: BulkFingerprintItem[]): string;
```

Split group immutable checks into subject, financial, compensation, and control helpers. Split bulk header and per-item validation so no method exceeds CCN `10`.

- [ ] **F4 Implementation: Extract preparation, financial, and commit owners**

```ts
@Injectable() export class LessonTransitionPreparationService {
  loadSource(lessonId: string, client?: PoolClient, lock?: boolean): Promise<TransitionSource>;
  assertSource(source: TransitionSource, expectedVersion: number, operation: TransitionOperation): void;
  assertSettlementReviewPlan(client: PoolClient, lessonId: string, operation: TransitionOperation): Promise<void>;
  successorDraft(dto: UpsertLessonDto, source: TransitionSource): TransitionSuccessor;
  validateSuccessor(client: PoolClient, lessonId: string, successor: TransitionSuccessor): Promise<{ valid: boolean; violations: unknown[] }>;
  calculatePreview(client: PoolClient, actor: ActorContext, lessonId: string, dto: TransitionPreviewDto, operation: TransitionOperation): Promise<CalculatedTransitionPreview>;
}

@Injectable() export class LessonTransitionFinancialService {
  previewFinancial(client: PoolClient, actor: ActorContext, source: TransitionSource, lessonId: string, operation: TransitionOperation, dto: TransitionPreviewDto): Promise<LessonSettlementResult>;
  applyCompletedRescheduleCorrection(client: PoolClient, source: TransitionSource, actor: ActorContext, dto: TransitionPreviewDto, correctionId: string): Promise<LessonSettlementResult>;
  cloneAndAllocateSuccessor(client: PoolClient, sourceLessonId: string, successorId: string, actor: ActorContext, reasonText?: string, branchId?: string, fallbackDecision?: LessonFinancialDecision): Promise<void>;
}

@Injectable() export class LessonTransitionCommitService {
  commit(client: PoolClient, input: CommitTransitionInput): Promise<CommittedTransition>;
}
```

`commit` preserves this order: locked source and review plan; sorted advisory resource locks; successor validation; settlement coverage lock; successor and immutable snapshot; source state plus settlement/terminal reservation or append-only completed correction; fingerprint comparison; successor plan/allocation; completed source update; lifecycle transition append.

- [ ] **F5 Implementation: Extract preview, command, and bulk workflow owners**

```ts
@Injectable() export class LessonTransitionPreviewService {
  previewReschedule(actor: ActorContext, lessonId: string, dto: LessonReschedulePreviewDto): Promise<LessonTransitionPreviewResult>;
  previewCancel(actor: ActorContext, lessonId: string, dto: LessonCancelPreviewDto): Promise<LessonTransitionPreviewResult>;
  previewSettle(actor: ActorContext, lessonId: string, dto: LessonSettlePreviewDto): Promise<LessonTransitionPreviewResult>;
}
@Injectable() export class LessonTransitionCommandService {
  reschedule(actor: ActorContext, lessonId: string, dto: LessonRescheduleCommandDto, metadata: LessonCommandMetadata): Promise<LessonTransitionCommandResult>;
  cancel(actor: ActorContext, lessonId: string, dto: LessonCancelCommandDto, metadata: LessonCommandMetadata): Promise<LessonTransitionCommandResult>;
  settle(actor: ActorContext, lessonId: string, dto: LessonSettleCommandDto, metadata: LessonCommandMetadata): Promise<LessonTransitionCommandResult>;
}
@Injectable() export class LessonBulkTransitionService {
  previewBulk(actor: ActorContext, dto: LessonBulkTransitionPreviewDto): Promise<LessonBulkTransitionPreviewResult>;
  bulk(actor: ActorContext, dto: LessonBulkTransitionCommandDto, metadata: LessonCommandMetadata): Promise<LessonBulkTransitionCommandResult>;
}
```

Single operations retain `schedule.lesson.{operation}`, aggregate `schedule:lesson`, DTO expected version, current audit action/beforeRef, and `schedule.lesson.changed`. Bulk retains `schedule.lesson.bulk-transition`, aggregate `schedule:lesson-bulk`, expected version `0`, `crm.lessons_bulk_transitioned`, and `schedule.lessons.changed`. Source then successor settlement publication remains post-commit.

- [ ] **F6 Facade: Replace `LessonTransitionService` with eight direct delegations**

```ts
@Injectable()
export class LessonTransitionService {
  constructor(
    private readonly previews: LessonTransitionPreviewService,
    private readonly commands: LessonTransitionCommandService,
    private readonly bulkTransitions: LessonBulkTransitionService,
  ) {}
  previewReschedule(actor: ActorContext, lessonId: string, dto: LessonReschedulePreviewDto) { return this.previews.previewReschedule(actor, lessonId, dto); }
  previewCancel(actor: ActorContext, lessonId: string, dto: LessonCancelPreviewDto) { return this.previews.previewCancel(actor, lessonId, dto); }
  previewSettle(actor: ActorContext, lessonId: string, dto: LessonSettlePreviewDto) { return this.previews.previewSettle(actor, lessonId, dto); }
  reschedule(actor: ActorContext, lessonId: string, dto: LessonRescheduleCommandDto, metadata: LessonCommandMetadata) { return this.commands.reschedule(actor, lessonId, dto, metadata); }
  cancel(actor: ActorContext, lessonId: string, dto: LessonCancelCommandDto, metadata: LessonCommandMetadata) { return this.commands.cancel(actor, lessonId, dto, metadata); }
  settle(actor: ActorContext, lessonId: string, dto: LessonSettleCommandDto, metadata: LessonCommandMetadata) { return this.commands.settle(actor, lessonId, dto, metadata); }
  previewBulk(actor: ActorContext, dto: LessonBulkTransitionPreviewDto) { return this.bulkTransitions.previewBulk(actor, dto); }
  bulk(actor: ActorContext, dto: LessonBulkTransitionCommandDto, metadata: LessonCommandMetadata) { return this.bulkTransitions.bulk(actor, dto, metadata); }
}
```

Register the six extracted injectable services in `CrmModule.providers`; export none. Rebuild both normal and injected-failure graphs in `reschedule-postgres.integration.spec.ts` with the same real collaborators.

- [ ] **F7 Guard: Enforce ownership, transaction, and metadata boundaries**

```ts
expect(sourceNloc(facade)).toBeLessThanOrEqual(130);
expect(exactConstructorTypes(facade)).toEqual([
  "LessonTransitionPreviewService",
  "LessonTransitionCommandService",
  "LessonBulkTransitionService",
]);
expect(exactMethodNames(facade)).toEqual([
  "previewReschedule", "previewCancel", "previewSettle",
  "reschedule", "cancel", "settle", "previewBulk", "bulk",
]);
expect(facade).not.toMatch(/DatabaseService|PlatformIntegrityService|\.transaction\(|executeVersionedMutation|select\s|insert\s|update\s/iu);
expect(transactionCallCount(previewOwner)).toBe(1);
expect(transactionCallCount(bulkOwner)).toBe(1);
expect(versionedMutationCount(commandOwner)).toBe(1);
expect(versionedMutationCount(bulkOwner)).toBe(1);
```

Also assert each new production file `<=500` NLOC, max CCN from RepoWise `<=10`, post-commit publication appears only in command/bulk owners, metadata has exactly two required fields, all five consumers import the neutral module, and `CrmModule` does not export extracted owners.

- [ ] **F8 Smoke: Run the complete transition lane check once**

```powershell
Set-Location server
npm test -- --runTestsByPath src/crm/schedule/lesson-command-metadata.spec.ts src/crm/schedule/lesson-transition-boundaries.spec.ts src/crm/schedule/lesson-transition-order.spec.ts
npm test -- --runTestsByPath src/crm/schedule/reschedule-postgres.integration.spec.ts --testNamePattern="dry-runs the exact facts|rejects stale/tampered previews|commits a signed bulk transition"
npm run typecheck -- --pretty false
Set-Location ..
git diff --check
repowise update --index-only
@(
  'server/src/crm/schedule/lesson-transition.service.ts',
  'server/src/crm/schedule/lesson-transition-preparation.service.ts',
  'server/src/crm/schedule/lesson-transition-financial.service.ts',
  'server/src/crm/schedule/lesson-transition-commit.service.ts',
  'server/src/crm/schedule/lesson-transition-preview.service.ts',
  'server/src/crm/schedule/lesson-transition-command.service.ts',
  'server/src/crm/schedule/lesson-bulk-transition.service.ts'
) | ForEach-Object { repowise health --file $_ --format json }
```

Expected: both boundary tests, three named PostgreSQL cases, and typecheck pass; original god owner is gone; neutral metadata is ready for Task J.

- [ ] **F9 Report: Record transition and dependency evidence**

Write `.superpowers/campaign12/lane-f-lesson-transition-report.md` with metrics for every owner, exact selected PostgreSQL tests/durations, neutral metadata consumer list, lock/transaction/audit/outbox/history assertions, guard result, and intended commit message `refactor(schedule): split lesson transition workflows`. F10 prints the resulting SHA for the tier ledger.

- [ ] **F10 Commit: Create the reversible transition commit**

```powershell
git add server/src/crm/schedule server/src/crm/crm.module.ts
git commit -m "refactor(schedule): split lesson transition workflows"
git rev-parse HEAD
```


### Tier 2 Integration and Review: D, E, F

**Branches:** `codex/campaign12-profile`, `codex/campaign12-auth`, `codex/campaign12-lesson-transition`.

**Files reviewed together:** every file in Tasks D/E/F, `profile.module.ts`, `auth.module.ts`, `crm.module.ts`, and the prerequisite-only metadata import in `schedule-plan.service.ts`.

- [ ] **T2.1 Integrate the three accepted lane commits in D/E/F order**

```powershell
git merge --no-ff codex/campaign12-profile -m "merge(campaign12): integrate profile lane"
git merge --no-ff codex/campaign12-auth -m "merge(campaign12): integrate auth lane"
git merge --no-ff codex/campaign12-lesson-transition -m "merge(campaign12): integrate lesson transition lane"
git status --short --branch
git diff --check HEAD~3..HEAD
```

Expected: clean merges, no unresolved paths, no unrelated files.

- [ ] **T2.2 Verify module wiring has no collision**

```powershell
rg -n "ProfileRecordRepository|MyProfileService|ProfileDirectoryService|ProfileNotesService" server/src/profile/profile.module.ts
rg -n "AuthRegistrationService|AuthLoginService|AuthVerificationService|AuthPasswordRecoveryService|AuthAccountService|AuthRateLimitService|AuthEmailChallengeService" server/src/auth/auth.module.ts
rg -n "LessonTransitionPreparationService|LessonTransitionFinancialService|LessonTransitionCommitService|LessonTransitionPreviewService|LessonTransitionCommandService|LessonBulkTransitionService" server/src/crm/crm.module.ts
rg -n "LessonCommandMetadata" server/src/crm/schedule/lesson-command-metadata.ts server/src/crm/schedule/schedule-plan.service.ts
```

Expected: D owns only profile-module wiring, E only auth-module wiring, F only CRM-module wiring; schedule plan imports metadata from `lesson-command-metadata.ts`.

- [ ] **T2.3 Re-run the three focused lane smokes on the integrated graph**

```powershell
Set-Location server
npm test -- --runTestsByPath src/profile/profile.service.spec.ts src/profile/my-profile.service.spec.ts src/profile/profile-directory.service.spec.ts src/profile/profile-notes.service.spec.ts src/profile/profile.policy.spec.ts src/profile/profile-boundaries.spec.ts
npm test -- --runTestsByPath src/auth/auth.service.spec.ts src/auth/auth-boundaries.spec.ts src/auth/password-policy.spec.ts src/auth/password.service.spec.ts src/auth/session.service.spec.ts src/auth/auth.controller.spec.ts
npm test -- --runTestsByPath src/crm/schedule/lesson-command-metadata.spec.ts src/crm/schedule/lesson-transition-boundaries.spec.ts src/crm/schedule/lesson-transition-order.spec.ts
npm test -- --runTestsByPath src/crm/schedule/reschedule-postgres.integration.spec.ts --testNamePattern="dry-runs the exact facts|rejects stale/tampered previews|commits a signed bulk transition"
npm run typecheck -- --pretty false
Set-Location ..
git diff --check
```

Expected: all named tests and backend typecheck pass. This is the Tier 2 synchronization gate, not the campaign-wide suite.

- [ ] **T2.4 Run one integrated risk and ownership review**

```powershell
repowise update --index-only
repowise risk -t server/src/profile/profile.service.ts -t server/src/auth/auth.service.ts -t server/src/crm/schedule/lesson-transition.service.ts -t server/src/crm/schedule/schedule-plan.service.ts --format json --full
```

Reviewer checks exact public signatures, fail-closed RBAC, credential/OTP/session behavior, transaction and post-commit boundaries, metadata dependency direction, no new cycle, all facade guards, and no Critical or Important finding.

- [ ] **T2.5 Record the tier review**

Write `.superpowers/campaign12/tier-2-review.md` with the three commit SHAs, merge SHAs, smoke counts/durations, RepoWise metrics, risk arrays, module ownership result, and reviewer severity counts. Tier 3 starts only when Critical/Important are `0/0`.

- [ ] **T2.6 Commit the accepted Tier 2 review evidence**

Verify the report contains the three lane SHAs, three merge SHAs, exact smoke results, risk output, and reviewer Critical/Important `0/0`, then commit:

```powershell
git diff --check
git add .superpowers/campaign12/tier-2-review.md
git commit -m "docs(health): record Campaign-12 tier 2 review"
git rev-parse HEAD
```

Capture the resulting full SHA as `$Tier3Base` before creating G/H/I worktrees.

---


### Task G: Split ChatInfoDialog after Messenger and Profile

**Baseline:** `lib/core/widgets/telegram/chat_info_dialog.dart::_ChatInfoDialogState` — health `1.00`, `807` NLOC, max CCN `45`, weighted deficit `5649`.

**Files:**

- Modify: `lib/core/widgets/telegram/chat_info_dialog.dart`
- Delete: `lib/core/widgets/telegram/chat_info_dialog_views.dart`
- Delete: `lib/core/widgets/telegram/chat_info_dialog_dialogs.dart`
- Create: `lib/core/widgets/telegram/chat_info_models.dart`
- Create: `lib/core/widgets/telegram/chat_info_controller.dart`
- Create: `lib/core/widgets/telegram/chat_info_view.dart`
- Create: `lib/core/widgets/telegram/chat_info_tabs.dart`
- Create: `lib/core/widgets/telegram/chat_info_member_dialogs.dart`
- Create: `test/features/messenger/chat_info_dialog_contract_test.dart`
- Create: `test/features/messenger/chat_info_dialog_architecture_test.dart`
- Create: `docs/superpowers/reports/campaign-12/lane-g-chat-info.md`

**Verify only — do not edit:**

- `lib/core/services/magic_messenger_service.dart`
- `lib/core/services/magic_profile_admin_service.dart`
- `lib/core/services/magic_settings_service.dart`
- `lib/core/services/chat_attachment_service.dart`
- `lib/features/messenger/presentation/screens/messenger_screen_shell.dart`
- `lib/features/messenger/presentation/screens/messenger_screen_conversation_view.dart`
- `test/features/messenger/channel_group_lifecycle_widget_test.dart`
- `integration_test/channel_group_device_test.dart`

**Interfaces:**

```dart
class ChatInfoRequest {
  const ChatInfoRequest({
    required this.chatType,
    required this.chatId,
    required this.userRole,
  });

  final String chatType;
  final String chatId;
  final String userRole;
}

class ChatHistoryBuckets {
  const ChatHistoryBuckets({
    required this.media,
    required this.files,
    required this.links,
  });

  factory ChatHistoryBuckets.fromMessages(
    Iterable<Map<String, dynamic>> messages,
  );

  final List<Map<String, dynamic>> media;
  final List<Map<String, dynamic>> files;
  final List<Map<String, dynamic>> links;
}

class ChatInfoSnapshot {
  const ChatInfoSnapshot({
    required this.loading,
    required this.data,
    required this.members,
    required this.history,
    required this.notes,
    required this.isMuted,
  });

  final bool loading;
  final Map<String, dynamic>? data;
  final List<Map<String, dynamic>> members;
  final ChatHistoryBuckets history;
  final List<Map<String, dynamic>> notes;
  final bool isMuted;
}

class ChatInfoController extends ChangeNotifier {
  ChatInfoController({
    required ChatInfoRequest request,
    required bool initialIsMuted,
    required MagicMessengerService messenger,
    required MagicProfileAdminService profiles,
    required MagicSettingsService settings,
  });

  ChatInfoSnapshot get snapshot;
  ChatInfoAccessPolicy get access;
  Map<String, dynamic>? get conversationPartner;
  String? get notesProfileId;

  Future<void> load();
  Future<void> updateRequest(
    ChatInfoRequest request, {
    required bool initialIsMuted,
  });
  Future<void> setMuted(
    bool value,
    Future<void> Function(bool value)? persist,
  );
  Future<Map<String, dynamic>> createNote(String body);
  Future<void> addMembers(Set<String> userIds);
  Future<void> removeMember(String userId);
  Future<void> leaveGroup();
  Future<Map<String, dynamic>> ensureDirectChat(String userId);
  Future<List<Map<String, dynamic>>> listProfilesForMembership();
  void replaceChannel(Map<String, dynamic> channel);
}
```

`ChatInfoDialog` keeps its current constructor exactly. `ChatInfoView` consumes one `ChatInfoViewModel`, the existing `TabController`, and one `ChatInfoActions` callback interface. `_ChatInfoDialogState` owns only Flutter lifecycle, dialogs/navigation, controller listening, and callback forwarding.

**Observable invariants:**

- Direct/group load order remains chat, members, eligible notes, then history. Channel uses `listChannels`; `admin_chat` uses only `getAdminChatAvatar` before history.
- History requests keep `limit: 100`, a `15` second timeout, and reverse results before classification. MIME/type/extension image detection is unchanged, voice attachments remain excluded from files, and links still come from `content`.
- Notes exist only for direct chats and `admin|manager|director|system_admin`. Group mutation remains forbidden for system groups and non-manager-tier roles.
- Mute is optimistic and rolls back with `Не удалось изменить уведомления чата`. Leave closes the panel/route before `onLeftGroup`. Direct-member navigation calls `ensureDirectChat`, closes, then calls `onNavigateToChat`.
- Member removal mutates, removes locally, then calls `onUpdate`; member addition mutates and reloads members.
- Keep `Медиа`, `Файлы`, `Ссылки`, `Заметки`, `Нет медиа`, `Нет файлов`, `Нет ссылок`, `Заметок пока нет`, `Добавить`, `Выйти`, `Информация не найдена`, and Hero tag `avatar_${widget.chatId}`.

- [ ] **Step G1: Add the missing characterization and controller tests**

Create `chat_info_dialog_contract_test.dart` with tests named exactly:

```dart
testWidgets('manager direct chat loads notes and classifies history', ...);
testWidgets('teacher direct chat has no notes surface or notes request', ...);
testWidgets('failed mute restores the previous state and reports the error', ...);
testWidgets('chat identity change clears stale members history and notes', ...);
test('history buckets keep images files links and exclude voice files', ...);
```

The fake API must assert the direct manager path requests chat, members, messages with `limit == 100`, and profile notes; seed one image, one PDF, one voice attachment, and one HTTPS link. Assert four tabs for manager, three for teacher, image/file/link counts of `1/1/1`, no voice file, exact mute snackbar, and absence of old member/media/note text after a `chatId` rebuild.

- [ ] **Step G2: Run the new tests and verify RED**

Run:

```powershell
flutter test test/features/messenger/chat_info_dialog_contract_test.dart
```

Expected: FAIL because `chat_info_models.dart` and `ChatHistoryBuckets.fromMessages` do not exist.

- [ ] **Step G3: Extract models and controller**

Implement the interfaces above. Move all service reads, history classification, partner/profile derivation, role policy, request switching, member mutations, note mutations, and mute rollback into the controller/models. Preserve swallowed history failures: a failed history request must not discard successfully loaded chat metadata.

- [ ] **Step G4: Extract independent views and member dialogs**

Move root composition to `chat_info_view.dart`, tabs/media/files/links/notes to `chat_info_tabs.dart`, and member selection plus resolved attachment image widgets to the named independent files. Remove both `part` directives and both old files; no extension may target `_ChatInfoDialogState`.

- [ ] **Step G5: Add the permanent structural guard**

In `chat_info_dialog_architecture_test.dart`, compute NLOC as nonblank, non-`//` lines and import count with `RegExp(r'^import ', multiLine: true)`. Assert shell NLOC `<= 260`, imports `<= 12`, all five new files exist and are `<= 500` NLOC, both old part files do not exist, and shell contains none of `part `, `part of`, `_ChatInfoViews`, `_AddMembersDialogState`, `listMessages`, `listChannelPosts`, `listProfileNotes`, `createProfileNote`, `updateGroupMembers`.

- [ ] **Step G6: Run lane smoke**

```powershell
flutter test test/features/messenger/chat_info_dialog_contract_test.dart test/features/messenger/chat_info_dialog_architecture_test.dart
flutter test test/features/messenger/channel_group_lifecycle_widget_test.dart --plain-name "manager removes another participant from a group"
flutter analyze --no-pub lib/core/widgets/telegram/chat_info_dialog.dart lib/core/widgets/telegram/chat_info_models.dart lib/core/widgets/telegram/chat_info_controller.dart lib/core/widgets/telegram/chat_info_view.dart lib/core/widgets/telegram/chat_info_tabs.dart lib/core/widgets/telegram/chat_info_member_dialogs.dart
dart format --output=none --set-exit-if-changed lib/core/widgets/telegram/chat_info_dialog.dart lib/core/widgets/telegram/chat_info_models.dart lib/core/widgets/telegram/chat_info_controller.dart lib/core/widgets/telegram/chat_info_view.dart lib/core/widgets/telegram/chat_info_tabs.dart lib/core/widgets/telegram/chat_info_member_dialogs.dart test/features/messenger/chat_info_dialog_contract_test.dart test/features/messenger/chat_info_dialog_architecture_test.dart
rg -n "limit: 100|Duration\(seconds: 15\)|onLeftGroup|onNavigateToChat|is_current_user|is_system|listProfileNotes|createProfileNote" lib/core/widgets/telegram -g "chat_info_*.dart"
git diff --check
repowise update --index-only
repowise health --file lib/core/widgets/telegram/chat_info_dialog.dart --format json
```

Expected: focused tests/analyze/format/diff pass; source check shows every listed invariant; original and every new owner meet the global Flutter health constraints.

- [ ] **Step G7: Write the lane report and commit once**

Write the baseline, dependency SHAs for Tier A/D, exact command outputs, focused pass counts, old/new health/NLOC/CCN/deficit, new-owner health, and verify-only diff confirmation to `lane-g-chat-info.md`.

```powershell
git add lib/core/widgets/telegram/chat_info_dialog.dart lib/core/widgets/telegram/chat_info_models.dart lib/core/widgets/telegram/chat_info_controller.dart lib/core/widgets/telegram/chat_info_view.dart lib/core/widgets/telegram/chat_info_tabs.dart lib/core/widgets/telegram/chat_info_member_dialogs.dart lib/core/widgets/telegram/chat_info_dialog_views.dart lib/core/widgets/telegram/chat_info_dialog_dialogs.dart test/features/messenger/chat_info_dialog_contract_test.dart test/features/messenger/chat_info_dialog_architecture_test.dart docs/superpowers/reports/campaign-12/lane-g-chat-info.md
git commit -m "refactor(messenger-ui): split chat info dialog owners"
```

---

### Task H: Split TeacherStatsWidget after Payroll

**Baseline:** `_TeacherStatsWidgetState` — health `3.04`, `1074` NLOC, max CCN `22`, weighted deficit `5327`.

**Files:**

- Modify: `lib/features/manager/presentation/widgets/teacher_stats_widget.dart`
- Create: `lib/features/manager/presentation/widgets/teacher_stats_models.dart`
- Create: `lib/features/manager/presentation/widgets/teacher_stats_controller.dart`
- Create: `lib/features/manager/presentation/widgets/teacher_stats_view.dart`
- Create: `lib/features/manager/presentation/widgets/teacher_stats_components.dart`
- Create: `lib/features/manager/presentation/widgets/teacher_stats_rate_dialogs.dart`
- Create: `test/features/manager/teacher_stats_controller_test.dart`
- Create: `test/features/manager/teacher_stats_architecture_test.dart`
- Create: `docs/superpowers/reports/campaign-12/lane-h-teacher-stats.md`

**Verify only:** `magic_crm_service.dart`, `magic_crm_service_core.dart`, `magic_crm_service_schedule.dart`, `magic_settings_service.dart`, `report_export_files.dart`, `reports_widget.dart`, `teacher_stats_bulk_rate_test.dart`, and `teacher_payroll_device_test.dart`.

**Interfaces:**

```dart
class TeacherStatsQuery {
  const TeacherStatsQuery({
    required this.from,
    required this.to,
    this.branchId,
    this.teacherId,
    this.unitType,
    this.status,
    this.discipline,
    this.category,
  });

  final DateTime from;
  final DateTime to;
  final String? branchId;
  final String? teacherId;
  final String? unitType;
  final String? status;
  final String? discipline;
  final String? category;
}

class TeacherStatsRateChange {
  const TeacherStatsRateChange({
    required this.lessonIds,
    required this.teacherRate,
    required this.reasonText,
  });
  final List<String> lessonIds;
  final num? teacherRate;
  final String reasonText;
}

class TeacherStatsController extends ChangeNotifier {
  TeacherStatsController({
    required MagicCrmService crm,
    required MagicSettingsService settings,
    required ReportFileOpener reportFileOpener,
    required DateTimeRange? filterRange,
    required String? branchId,
    required bool canCorrectSettledPayroll,
    DateTime Function()? clock,
  });

  TeacherStatsState get state;
  Future<void> initialize();
  Future<void> updateSharedFilter(DateTimeRange? filterRange, String? branchId);
  Future<void> setQuery(TeacherStatsQuery query);
  Future<void> loadReport();
  Future<void> applyRate(TeacherStatsRateChange change);
  Future<void> updateGroupRate(String groupId, num? rate);
  Future<ReportFileOpenResult> export();
  void toggleUnit(String unitKey, List<String> lessonIds);
  void clearSelection();
}
```

**Invariants:** preserve inclusive UI end date as exclusive `end + 1 day`; hide period/branch controls with external range; forward all seven optional query fields; clear selection on reload; allow settled correction only to director/system_admin; use one bulk request; keep numeric zero; update group with `setTeacherRate: true`; validate CSV BOM and use `teacher-stats-yyyy-MM-dd.csv`; preserve keys `branch-*`, `teacher-*`, `unit-*`, `status-*`, `disc-*`, `cat-*` and current lock text.

- [ ] **Step H1: Add RED controller/contract tests**

Create tests named `external range and branch produce the exact report query`, `all report filters are forwarded to export`, `group rate uses the group update contract`, and `report reload clears selected units`. Assert exact UTC from/to, seven filter values, BOM bytes, filename, one group PATCH with `setTeacherRate == true`, and empty selection after query change.

- [ ] **Step H2: Run RED**

```powershell
flutter test test/features/manager/teacher_stats_controller_test.dart
```

Expected: FAIL because `TeacherStatsController` and `TeacherStatsQuery` do not exist.

- [ ] **Step H3: Extract models/controller and rate dialogs**

Move report/catalog loading, query updates, selection, rate commands, export, number/hour/rate formatting, and capability-derived selection policy to the named owners. Keep dialogs responsible only for collecting `TeacherStatsRateChange`; controller performs mutations and reload.

- [ ] **Step H4: Extract the stateless report view**

Move filters, selection bar, and the error/empty body to `teacher_stats_view.dart`; keep the coherent card, unit-row, total, and badge continuation in `teacher_stats_components.dart` so neither stateless owner exceeds 500 NLOC. The shell keeps the public constructor, provider reads used to instantiate/update the controller, controller listener, and lifecycle disposal.

- [ ] **Step H5: Add structural guard**

Assert main NLOC `<= 240`, imports `<= 12`, every new file `<= 500` NLOC, and absence from main of `_buildFilters`, `_buildUnitRow`, `_applyBulkRate`, `_editUnitLessonRate`, `getTeacherStatsReport`, `exportTeacherStatsReport`, `setLessonsTeacherRate`, and `updateGroup`.

- [ ] **Step H6: Run lane smoke**

```powershell
flutter test test/features/manager/teacher_stats_bulk_rate_test.dart test/features/manager/teacher_stats_controller_test.dart test/features/manager/teacher_stats_architecture_test.dart
flutter analyze --no-pub lib/features/manager/presentation/widgets/teacher_stats_widget.dart lib/features/manager/presentation/widgets/teacher_stats_models.dart lib/features/manager/presentation/widgets/teacher_stats_controller.dart lib/features/manager/presentation/widgets/teacher_stats_view.dart lib/features/manager/presentation/widgets/teacher_stats_components.dart lib/features/manager/presentation/widgets/teacher_stats_rate_dialogs.dart
dart format --output=none --set-exit-if-changed lib/features/manager/presentation/widgets/teacher_stats_*.dart test/features/manager/teacher_stats_*_test.dart
rg -n "editableLessonIds|settledLessons|setLessonsTeacherRate|setTeacherRate: true|teacher-stats-|validateReportExportBytes" lib/features/manager/presentation/widgets/teacher_stats_*.dart
git diff --check
repowise update --index-only
repowise health --file lib/features/manager/presentation/widgets/teacher_stats_widget.dart --format json
```

- [ ] **Step H7: Report and one commit**

Record Tier B dependency SHA, commands, pass counts, metrics, all extracted-owner health results, and verify-only diff confirmation in `lane-h-teacher-stats.md`.

```powershell
git add lib/features/manager/presentation/widgets/teacher_stats_widget.dart lib/features/manager/presentation/widgets/teacher_stats_models.dart lib/features/manager/presentation/widgets/teacher_stats_controller.dart lib/features/manager/presentation/widgets/teacher_stats_view.dart lib/features/manager/presentation/widgets/teacher_stats_components.dart lib/features/manager/presentation/widgets/teacher_stats_rate_dialogs.dart test/features/manager/teacher_stats_controller_test.dart test/features/manager/teacher_stats_architecture_test.dart docs/superpowers/reports/campaign-12/lane-h-teacher-stats.md
git commit -m "refactor(reports): split teacher statistics owners"
```

---

### Task I: Split SubscriptionIssueSheet after SubscriptionIssueService

**Baseline:** `_SubscriptionIssueFormState` — health `3.04`, `1114` NLOC, max CCN `19`, weighted deficit `5525`.

**Files:**

- Modify: `lib/features/crm/presentation/client_card/subscription_issue_sheet.dart`
- Create: `lib/features/crm/presentation/client_card/subscription_issue_models.dart`
- Create: `lib/features/crm/presentation/client_card/subscription_issue_pricing.dart`
- Create: `lib/features/crm/presentation/client_card/subscription_issue_controller.dart`
- Create: `lib/features/crm/presentation/client_card/subscription_issue_form_view.dart`
- Create: `lib/features/crm/presentation/client_card/subscription_issue_components.dart`
- Create: `test/features/commerce/subscription_issue_controller_test.dart`
- Create: `test/features/commerce/subscription_issue_architecture_test.dart`
- Create: `test/features/commerce/subscription_issue_ui_regression_test.dart`
- Create: `docs/superpowers/reports/campaign-12/lane-i-subscription-issue.md`

**Verify only:** `client_card_student.dart`, `client_card.dart`, `magic_crm_service.dart`, `magic_crm_service_finance.dart`, and `subscription_issue_form_test.dart`.

**Interfaces:**

```dart
enum SubscriptionIssueSubmitResult { previewLoaded, committed, blocked, failed }
typedef SubscriptionIdentityFactory = MagicMutationIdentity Function();

class SubscriptionIssuePricing {
  const SubscriptionIssuePricing({
    required this.basePriceMinor,
    required this.discountMinor,
    required this.surchargeMinor,
    required this.finalPriceMinor,
    required this.amountsValid,
    required this.installments,
  });

  static SubscriptionIssuePricing calculate({
    required SubscriptionIssueDraft draft,
    required BigInt basePriceMinor,
    required DateTime commandTimestamp,
  });
}

class SubscriptionIssueController extends ChangeNotifier {
  SubscriptionIssueController({
    required Map<String, dynamic> package,
    required String recipientStudentId,
    required String recipientLabel,
    required SubscriptionIssuePreview onPreview,
    required SubscriptionIssueSubmit onSubmit,
    DateTime? commandTimestamp,
    SubscriptionIdentityFactory? identityFactory,
  });

  SubscriptionIssueDraft get draft;
  SubscriptionIssuePricing get pricing;
  SubscriptionPurchasePreview? get preview;
  MagicMutationIdentity get identity;
  bool get busy;
  bool get attempted;
  bool get fieldsEnabled;
  String? get error;

  void selectPayer(SearchableSelectItem item);
  void selectFundingMode(SubscriptionFundingMode mode);
  void selectDiscountMode(SubscriptionIssueDiscountMode mode);
  void setDiscountValue(String value);
  void setDiscountReason(String value);
  void setSurchargeEnabled(bool value);
  void setSurchargeAmount(String value);
  void setSurchargeReason(String value);
  void setPurchaseReason(String value);
  void setInstallmentCount(int value);
  PurchaseSubscriptionInput buildPurchase();
  Future<SubscriptionIssueSubmitResult> submit();
}
```

Keep `showSubscriptionIssueFormSheet`, `SubscriptionIssueForm`, `SubscriptionIssueSubmission`, `SubscriptionIssueSubmit`, `SubscriptionIssuePreview`, and `SubscriptionIssueDiscountMode` import-compatible through declarations or exports from the public shell.

**Invariants:** first submit previews and second commits; preview and commit inputs match; pricing change clears preview/error and rotates identity; a stale in-flight preview can never publish after the draft/identity changes; attempted commit freezes fields; retry reuses identity/input; percent supports two decimals and PostgreSQL half-up; changing discount mode clears both draft and visible amount; fixed discount is positive and no more than base; malformed/invalid monetary inputs render the total as `Не указано`; surcharge is positive with reason; foreign payer requires reason; installment count is `2..12`, remainder goes to first payments, dates are UTC month-clamped; insufficient balance never commits; all existing `subscription-*` keys and submit labels remain exact.

- [ ] **Step I1: Add RED pricing/controller tests**

Test exact cases: `0,01` percent produces one basis point; `100,01` is rejected; fixed amount above base is rejected; enabled surcharge needs positive amount and reason; final minor amount below installment count yields `Итог должен позволять 3 положительных платежа.`; `canCommit=false` never invokes submit and exposes `На личном счёте недостаточно средств.`; a pricing change after preview rotates identity; a late preview is discarded after draft/identity rotation; a failed commit retry keeps identity and purchase JSON. Add widget regressions for percent-to-fixed visible-value reset and unavailable totals for malformed, over-base, and non-positive monetary inputs.

- [ ] **Step I2: Run RED**

```powershell
flutter test test/features/commerce/subscription_issue_controller_test.dart
```

Expected: FAIL because the controller/pricing owners do not exist.

- [ ] **Step I3: Extract draft, pricing, and submit controller**

Move parsing, validation, half-up calculation, installment construction, purchase building, preview/commit state machine, identity lifecycle, error mapping, and immutable attempted state into models/pricing/controller. Preserve `MagicMutationIdentity.create('subscription-purchase')` as the production factory.

- [ ] **Step I4: Extract form view and components**

Move price/preview/installment/error/retry components and the form sections to independent stateless files. Keep the shell responsible for form key, dirty-exit scope, controller listener/disposal, focus dismissal, and `Navigator.pop(context, true)` only after `committed`.

- [ ] **Step I5: Add structural guard**

Discover every `subscription_issue_*.dart` owner and parse it with analyzer AST. Assert shell `<= 220` NLOC, imports `<= 12`, `_SubscriptionIssueFormState <= 160` NLOC, every new file `<= 500` NLOC, every executable max CCN `<= 10`, bounded callable/type/member god/brain proxies, and absence from shell of pricing orchestration. Assert preview and submit effects occur only in `subscription_issue_controller.dart`, including aliases and typed/property invocations; negative fixtures must prove comments, strings, whitespace, aliases, a new owner, CCN, and type growth cannot bypass the guard.

- [ ] **Step I6: Run lane smoke**

```powershell
flutter test test/features/commerce/subscription_issue_form_test.dart test/features/commerce/subscription_issue_controller_test.dart test/features/commerce/subscription_issue_architecture_test.dart test/features/commerce/subscription_issue_ui_regression_test.dart
flutter analyze --no-pub lib/features/crm/presentation/client_card/subscription_issue_sheet.dart lib/features/crm/presentation/client_card/subscription_issue_models.dart lib/features/crm/presentation/client_card/subscription_issue_pricing.dart lib/features/crm/presentation/client_card/subscription_issue_controller.dart lib/features/crm/presentation/client_card/subscription_issue_form_view.dart lib/features/crm/presentation/client_card/subscription_issue_components.dart
dart format --output=none --set-exit-if-changed lib/features/crm/presentation/client_card/subscription_issue_*.dart test/features/commerce/subscription_issue_*_test.dart
rg -n "previewToken|MagicMutationIdentity|canCommit|purchaseReason|installments|subscription-issue-submit|subscription-purchase-preview" lib/features/crm/presentation/client_card/subscription_issue_*.dart
git diff --check
repowise update --index-only
repowise health --file lib/features/crm/presentation/client_card/subscription_issue_sheet.dart --format json
```

- [ ] **Step I7: Report and commit**

Record Tier C dependency SHA, exact smoke output, idempotency assertions, metrics, extracted-owner health, and verify-only diff confirmation in `lane-i-subscription-issue.md`.

```powershell
git add lib/features/crm/presentation/client_card/subscription_issue_sheet.dart lib/features/crm/presentation/client_card/subscription_issue_models.dart lib/features/crm/presentation/client_card/subscription_issue_pricing.dart lib/features/crm/presentation/client_card/subscription_issue_controller.dart lib/features/crm/presentation/client_card/subscription_issue_form_view.dart lib/features/crm/presentation/client_card/subscription_issue_components.dart test/features/commerce/subscription_issue_controller_test.dart test/features/commerce/subscription_issue_architecture_test.dart test/features/commerce/subscription_issue_ui_regression_test.dart docs/superpowers/reports/campaign-12/lane-i-subscription-issue.md
git commit -m "refactor(commerce-ui): split subscription issue form owners"
```

## Tier 3 Shared Boundary

Lanes G/H/I may start only after Tier A/B/C and Tier D are integrated as specified. Their commits must not modify any verify-only file above. After cherry-picking G, H, and I, the integrator verifies `git diff $Tier3Base..HEAD --` against those paths, runs each listed lane smoke against the integrated graph, and owns any shared wiring commit. Shared review hardening centralizes the analyzer-AST metric machinery under `test/support/architecture/` and declares `analyzer` once as a direct dev dependency; raw RepoWise health/history/coverage remains an exact indexed tier/global gate rather than a flaky Dart unit property. No lane adds shared wiring opportunistically.

---


### Tier 3 Integration and Review: G, H, I

**Branches:** `codex/campaign12-chat-info`, `codex/campaign12-teacher-stats`, `codex/campaign12-subscription-issue-ui`.

**Files reviewed together:** every file in Tasks G/H/I and every verify-only path named by those tasks. No shared Flutter parent or shared characterization test may change.

- [x] **T3.1 Integrate the three accepted lane commits in G/H/I order**

```powershell
$Tier3Base = (git rev-parse HEAD).Trim()
git merge --no-ff codex/campaign12-chat-info -m "merge(campaign12): integrate chat info lane"
git merge --no-ff codex/campaign12-teacher-stats -m "merge(campaign12): integrate teacher stats lane"
git merge --no-ff codex/campaign12-subscription-issue-ui -m "merge(campaign12): integrate subscription issue UI lane"
git status --short --branch
git diff --check "$Tier3Base..HEAD"
```

Expected: clean merges, no unresolved paths, and no unrelated file.

- [x] **T3.2 Prove every shared and verify-only path remained unchanged**

```powershell
$Tier3VerifyOnly = @(
  'lib/core/services/magic_messenger_service.dart',
  'lib/core/services/magic_profile_admin_service.dart',
  'lib/core/services/magic_settings_service.dart',
  'lib/core/services/chat_attachment_service.dart',
  'lib/features/messenger/presentation/screens/messenger_screen_shell.dart',
  'lib/features/messenger/presentation/screens/messenger_screen_conversation_view.dart',
  'test/features/messenger/channel_group_lifecycle_widget_test.dart',
  'integration_test/channel_group_device_test.dart',
  'lib/core/services/magic_crm_service.dart',
  'lib/core/services/magic_crm_service_core.dart',
  'lib/core/services/magic_crm_service_schedule.dart',
  'lib/core/services/magic_crm_service_finance.dart',
  'lib/features/manager/presentation/reporting/report_export_files.dart',
  'lib/features/manager/presentation/widgets/reports_widget.dart',
  'lib/features/crm/presentation/client_card/client_card_student.dart',
  'lib/features/crm/presentation/client_card/client_card.dart',
  'test/features/manager/teacher_stats_bulk_rate_test.dart',
  'integration_test/teacher_payroll_device_test.dart',
  'test/features/commerce/subscription_issue_form_test.dart'
)
if ($Tier3VerifyOnly.Count -ne 19) {
  throw "Tier 3 verify-only inventory drifted: $($Tier3VerifyOnly.Count)"
}
$Tier3SharedDiff = @(git diff --name-only "$Tier3Base..HEAD" -- $Tier3VerifyOnly)
if ($Tier3SharedDiff.Count -ne 0) {
  throw "Tier 3 modified verify-only paths: $($Tier3SharedDiff -join ', ')"
}
```

Expected: the command exits without throwing and `$Tier3SharedDiff` is empty.

- [x] **T3.3 Re-run the exact Lane G smoke on the integrated graph**

```powershell
flutter test test/features/messenger/chat_info_dialog_contract_test.dart test/features/messenger/chat_info_dialog_architecture_test.dart
flutter test test/features/messenger/channel_group_lifecycle_widget_test.dart --plain-name "manager removes another participant from a group"
flutter analyze --no-pub lib/core/widgets/telegram/chat_info_dialog.dart lib/core/widgets/telegram/chat_info_models.dart lib/core/widgets/telegram/chat_info_controller.dart lib/core/widgets/telegram/chat_info_view.dart lib/core/widgets/telegram/chat_info_tabs.dart lib/core/widgets/telegram/chat_info_member_dialogs.dart
dart format --output=none --set-exit-if-changed lib/core/widgets/telegram/chat_info_dialog.dart lib/core/widgets/telegram/chat_info_models.dart lib/core/widgets/telegram/chat_info_controller.dart lib/core/widgets/telegram/chat_info_view.dart lib/core/widgets/telegram/chat_info_tabs.dart lib/core/widgets/telegram/chat_info_member_dialogs.dart test/features/messenger/chat_info_dialog_contract_test.dart test/features/messenger/chat_info_dialog_architecture_test.dart
rg -n "limit: 100|Duration\(seconds: 15\)|onLeftGroup|onNavigateToChat|is_current_user|is_system|listProfileNotes|createProfileNote" lib/core/widgets/telegram -g "chat_info_*.dart"
git diff --check
repowise update --index-only
repowise health --file lib/core/widgets/telegram/chat_info_dialog.dart --format json
```

Expected: focused tests/analyze/format/diff pass; source check shows each listed invariant.

- [x] **T3.4 Re-run the exact Lane H smoke on the integrated graph**

```powershell
flutter test test/features/manager/teacher_stats_bulk_rate_test.dart test/features/manager/teacher_stats_controller_test.dart test/features/manager/teacher_stats_architecture_test.dart test/features/manager/teacher_stats_rate_dialogs_test.dart
flutter analyze --no-pub lib/features/manager/presentation/widgets/teacher_stats_widget.dart lib/features/manager/presentation/widgets/teacher_stats_models.dart lib/features/manager/presentation/widgets/teacher_stats_controller.dart lib/features/manager/presentation/widgets/teacher_stats_view.dart lib/features/manager/presentation/widgets/teacher_stats_components.dart lib/features/manager/presentation/widgets/teacher_stats_rate_dialogs.dart
dart format --output=none --set-exit-if-changed lib/features/manager/presentation/widgets/teacher_stats_*.dart test/features/manager/teacher_stats_*_test.dart
rg -n "editableLessonIds|settledLessons|setLessonsTeacherRate|setTeacherRate: true|teacher-stats-|validateReportExportBytes" lib/features/manager/presentation/widgets/teacher_stats_*.dart
git diff --check
repowise update --index-only
repowise health --file lib/features/manager/presentation/widgets/teacher_stats_widget.dart --format json
```

Expected: all named tests and checks pass with the Tier B backend contract already integrated.

- [x] **T3.5 Re-run the exact Lane I smoke on the integrated graph**

```powershell
flutter test test/features/commerce/subscription_issue_form_test.dart test/features/commerce/subscription_issue_controller_test.dart test/features/commerce/subscription_issue_architecture_test.dart test/features/commerce/subscription_issue_ui_regression_test.dart
flutter analyze --no-pub lib/features/crm/presentation/client_card/subscription_issue_sheet.dart lib/features/crm/presentation/client_card/subscription_issue_models.dart lib/features/crm/presentation/client_card/subscription_issue_pricing.dart lib/features/crm/presentation/client_card/subscription_issue_controller.dart lib/features/crm/presentation/client_card/subscription_issue_form_view.dart lib/features/crm/presentation/client_card/subscription_issue_components.dart
dart format --output=none --set-exit-if-changed lib/features/crm/presentation/client_card/subscription_issue_*.dart test/features/commerce/subscription_issue_*_test.dart
rg -n "previewToken|MagicMutationIdentity|canCommit|purchaseReason|installments|subscription-issue-submit|subscription-purchase-preview" lib/features/crm/presentation/client_card/subscription_issue_*.dart
git diff --check
repowise update --index-only
repowise health --file lib/features/crm/presentation/client_card/subscription_issue_sheet.dart --format json
```

Expected: all named tests and checks pass; preview/commit identity and blocker contracts remain exact.

- [x] **T3.6 Run one integrated Tier 3 risk and ownership review**

```powershell
repowise update --index-only
repowise risk -t lib/core/widgets/telegram/chat_info_dialog.dart -t lib/features/manager/presentation/widgets/teacher_stats_widget.dart -t lib/features/crm/presentation/client_card/subscription_issue_sheet.dart --format json --full
```

The independent reviewer receives `$Tier3Base..HEAD`, the three lane reports, the exact smoke output, and the approved spec. Review exact public constructors and callbacks, provider/service ownership, request and mutation payloads, optimistic identity/version behavior, keys/copy/navigation/toasts/accessibility, structural guards, verify-only scope, and new dependency cycles. Write all findings and dispositions to `.superpowers/campaign12/tier-3-review.md`; Tier 4 cannot start with a Critical or Important finding.

- [x] **T3.7 Commit the accepted Tier 3 review evidence**

```powershell
git diff --check
git add .superpowers/campaign12/tier-3-review.md
git commit -m "docs(health): record Campaign-12 tier 3 review"
git rev-parse HEAD
```

Capture the resulting full SHA as `$Tier4Base` before creating J/K/L worktrees.

---

### Task J: Split `SchedulePlanService` after neutral metadata is integrated

**Dependency:** Task F is integrated and `schedule-plan.service.ts` imports `LessonCommandMetadata` from `./lesson-command-metadata`.

**Baseline:** `server/src/crm/schedule/schedule-plan.service.ts` is health `3.58`, `1,148` NLOC, max CCN `19`, weighted deficit `5,074`.

**Files:**

- Create: `server/src/crm/schedule/schedule-plan-definition.service.ts`
- Create: `server/src/crm/schedule/schedule-plan-overlap-analyzer.ts`
- Create: `server/src/crm/schedule/schedule-plan-query.service.ts`
- Create: `server/src/crm/schedule/schedule-plan-constraint-preview.service.ts`
- Create: `server/src/crm/schedule/schedule-plan-mutation.service.ts`
- Create: `server/src/crm/schedule/schedule-plan-end.service.ts`
- Rewrite: `server/src/crm/schedule/schedule-plan.service.ts`
- Modify: `server/src/crm/crm.module.ts`
- Modify: `server/src/crm/schedule/schedule-plan-postgres.integration.spec.ts`
- Create: `server/src/crm/schedule/schedule-plan-services.spec.ts`
- Create: `server/src/crm/schedule/schedule-plan-boundaries.spec.ts`
- Report: `.superpowers/campaign12/lane-j-schedule-plan-report.md`

**Verify-only:** `crm-schedule.controller.ts`, schedule-plan DTO/repository/types, lesson series command, materializer, lifecycle, reservation, settlement, preview-token, and constraint-engine implementations.

**Interfaces:**

- `SchedulePlanQueryService.list(actor, query)` and `tray(actor, planId, query)`.
- `SchedulePlanConstraintPreviewService.previewConstraints(actor, dto)` and `previewUpdateConstraints(actor, planId, dto)`.
- `SchedulePlanMutationService.create(actor, dto, metadata)` and `update(actor, planId, dto, metadata)`.
- `SchedulePlanEndService.previewEnd(actor, planId, dto)` and `end(actor, planId, dto, metadata)`.
- `SchedulePlanService` consumes those four owners and remains the only controller-facing service.

The extracted files define and use these exact data contracts; controller-facing result shapes stay unchanged:

```ts
export interface NormalizedSchedulePlanCreate {
  kind: "individual" | "group";
  title: string;
  studentId: string | null;
  groupId: string | null;
  subscriptionId: string | null;
  activeFrom: string;
  activeUntil: string | null;
  participants: SchedulePlanParticipantDto[];
  rows: SchedulePlanRowDto[];
}

export interface PreparedSchedulePlanUpdate {
  plan: LockedSchedulePlan;
  participants: SchedulePlanParticipantDto[];
  subscriptionId: string | null;
  activeUntil: string | null;
  studentIds: string[];
  activeSeries: Awaited<
    ReturnType<SchedulePlanRepository["activeSeries"]>
  >["rows"];
  effectiveFrom: string;
}

export interface SchedulePlanValidationInput {
  planId: string;
  kind: "individual" | "group";
  studentId: string | null;
  groupId: string | null;
  subscriptionId: string | null;
  participants: SchedulePlanParticipantDto[];
  rows: SchedulePlanRowDto[];
}

export interface NormalizedSchedulePlanEnd {
  expectedVersion: number;
  lastDate: string;
  reasonText: string;
}

export type SchedulePlanRowPreview = Awaited<
  ReturnType<LessonSeriesCommandService["previewPlanRow"]>
> & { index: number };

export interface SchedulePlanConstraintProjection {
  valid: boolean;
  conflicts: ReturnType<typeof groupScheduleConflicts>;
  rows: Array<{
    index: number;
    valid: boolean;
    occurrencesChecked: number;
    failures: SchedulePlanRowPreview["failures"];
    suggestions: SchedulePlanRowPreview["suggestions"];
  }>;
}

export interface SchedulePlanTrayProjection {
  planId: string;
  items: Array<{
    id: string;
    scheduledAt: string;
    localDate: string;
    localTime: string;
    state: string;
    settlementMarkers: Array<Record<string, unknown>>;
    relationMarker: "source" | "successor" | "none";
    predecessorId: string | null;
    successorId: string | null;
    teacher: { id: string; name: string | null } | null;
    room: { id: string; name: string | null } | null;
  }>;
  hasPrevious: boolean;
  hasNext: boolean;
  previousCursor: string | null;
  nextCursor: string | null;
}

export interface SchedulePlanMutationResult {
  id: string;
  seriesIds: string[];
  lessonIds: string[];
  version: number;
  replayed: boolean;
}

export interface SchedulePlanEndPreviewProjection {
  plan: { id: string; title: string; version: number; lastDate: string };
  impact: {
    activeSeries: number;
    futureUnsettledLessons: number;
    activeReservations: number;
    reservedUnits: string;
    preservedTerminalLessons: number;
  };
  canConfirm: true;
  confirmRequired: true;
  previewToken: string;
  previewExpiresAt: string;
}

export interface SchedulePlanEndResult {
  id: string;
  status: "ended";
  version: number;
  endedLessons: number;
  releasedReservations: number;
  preservedTerminalLessons: number;
  replayed: boolean;
}
```

- [ ] **J1 RED: Add lock, end, tray, and overlap characterization tests**

In `schedule-plan-services.spec.ts`, use ordered mocks and assert:

```ts
expect(advisoryKeys).toEqual([...new Set([
  "plan:plan-a", "group:group-a",
  "client:student:student-a", "client:student:student-b",
  "subscription:subscription-a", "subscription:subscription-b",
  "branch:branch-a", "room:room-a", "teacher:teacher-a",
])].sort());
expect(subscriptionSql).toMatch(/order by id for update/);
expect(updateEvents).toEqual([
  "plan-lock", "participant-lock", "resource-locks", "subscription-lock",
  "active-series-read", "series-locks", "insert-continuations",
  "retire-old-series", "replace-participants", "update-plan",
  "validate-new-series", "materialize-new-series",
]);
expect(endEvents).toEqual([
  "plan-lock", "local-date-check", "current-series-read", "series-locks",
  "locked-impact", "fingerprint-check", "finish-plan", "cancel-lessons",
  "append-transitions", "release-reservations",
]);
```

Add exact tray failures `SCHEDULE_PLAN_TRAY_CURSOR_REQUIRED` and `SCHEDULE_PLAN_TRAY_CURSOR_INVALID`, limit clamp `1..40`, previous-page reversal, `(scheduledAt,id)` cursors, and symmetric row-overlap assertions for each student with rule ID `schedule_plan.rows`.

- [ ] **J2 RED: Run new service tests and verify failure**

```powershell
Set-Location server
npm test -- --runTestsByPath src/crm/schedule/schedule-plan-services.spec.ts src/crm/schedule/schedule-plan-boundaries.spec.ts
```

Expected: FAIL because the six extracted production files do not exist.

- [ ] **J3 Implementation: Extract definition and overlap owners**

```ts
@Injectable() export class SchedulePlanDefinitionService {
  normalizeCreate(dto: CreateSchedulePlanDto): NormalizedSchedulePlanCreate;
  assertRows(rows: SchedulePlanRowDto[]): void;
  prepareUpdate(client: PoolClient, planId: string, dto: UpdateSchedulePlanDto): Promise<PreparedSchedulePlanUpdate>;
  lockAndValidate(client: PoolClient, input: SchedulePlanValidationInput): Promise<void>;
  normalizeEnd(dto: SchedulePlanEndPreviewDto): NormalizedSchedulePlanEnd;
  assertEndable(client: PoolClient, plan: LockedSchedulePlan, input: NormalizedSchedulePlanEnd): Promise<void>;
  planId(actorUserId: string, idempotencyKey: string): string;
  seriesId(planId: string, version: number, index: number): string;
  lessonIds(client: PoolClient, seriesId: string): Promise<string[]>;
}

export class SchedulePlanOverlapAnalyzer {
  addCrossRowViolations(rows: SchedulePlanRowDto[], previews: SchedulePlanRowPreview[], studentIds: string[]): void;
}
```

Split create subject, period, participant, row identity, resource locks, and membership checks into methods below CCN `10`. Split overlap search, shared-resource projection, and symmetric failure append so no method exceeds CCN `10`.

- [ ] **J4 Implementation: Extract query and constraint-preview owners**

```ts
@Injectable() export class SchedulePlanQueryService {
  list(actor: ActorContext, query: SchedulePlanQuery): ReturnType<SchedulePlanRepository["list"]>;
  tray(actor: ActorContext, planId: string, query: SchedulePlanTrayQuery): Promise<SchedulePlanTrayProjection>;
}
@Injectable() export class SchedulePlanConstraintPreviewService {
  previewConstraints(actor: ActorContext, dto: SchedulePlanConstraintPreviewDto): Promise<SchedulePlanConstraintProjection>;
  previewUpdateConstraints(actor: ActorContext, planId: string, dto: UpdateSchedulePlanDto): Promise<SchedulePlanConstraintProjection>;
}
```

Keep actor-scoped repository reads, exact keyset cursor validation/projection, two database transactions, settlement plan preparation, series preview options, overlap enrichment, and grouped conflict shape.

- [ ] **J5 Implementation: Extract mutation and end owners**

```ts
@Injectable() export class SchedulePlanMutationService {
  create(actor: ActorContext, dto: CreateSchedulePlanDto, metadata: LessonCommandMetadata): Promise<SchedulePlanMutationResult>;
  update(actor: ActorContext, planId: string, dto: UpdateSchedulePlanDto, metadata: LessonCommandMetadata): Promise<SchedulePlanMutationResult>;
}
@Injectable() export class SchedulePlanEndService {
  previewEnd(actor: ActorContext, planId: string, dto: SchedulePlanEndPreviewDto): Promise<SchedulePlanEndPreviewProjection>;
  end(actor: ActorContext, planId: string, dto: SchedulePlanEndCommandDto, metadata: LessonCommandMetadata): Promise<SchedulePlanEndResult>;
}
```

Create/update preserve aggregate `schedule:plan`, deterministic IDs, expected versions `0`/DTO version, `crm.schedule_plan_created`/`crm.schedule_plan_updated`, and `schedule.plan.changed`. End preserves signed impact fingerprint, audit `crm.schedule_plan_ended`, series locks before locked impact, append-only lesson transitions, terminal history, reservation release, and `replayed`.

- [ ] **J6 Facade: Replace `SchedulePlanService` with eight direct delegations**

```ts
@Injectable()
export class SchedulePlanService {
  constructor(
    private readonly queries: SchedulePlanQueryService,
    private readonly previews: SchedulePlanConstraintPreviewService,
    private readonly mutations: SchedulePlanMutationService,
    private readonly ending: SchedulePlanEndService,
  ) {}
  list(actor: ActorContext, query: SchedulePlanQuery) { return this.queries.list(actor, query); }
  previewConstraints(actor: ActorContext, dto: SchedulePlanConstraintPreviewDto) { return this.previews.previewConstraints(actor, dto); }
  previewUpdateConstraints(actor: ActorContext, planId: string, dto: UpdateSchedulePlanDto) { return this.previews.previewUpdateConstraints(actor, planId, dto); }
  previewEnd(actor: ActorContext, planId: string, dto: SchedulePlanEndPreviewDto) { return this.ending.previewEnd(actor, planId, dto); }
  end(actor: ActorContext, planId: string, dto: SchedulePlanEndCommandDto, metadata: LessonCommandMetadata) { return this.ending.end(actor, planId, dto, metadata); }
  tray(actor: ActorContext, planId: string, query: SchedulePlanTrayQuery) { return this.queries.tray(actor, planId, query); }
  create(actor: ActorContext, dto: CreateSchedulePlanDto, metadata: LessonCommandMetadata) { return this.mutations.create(actor, dto, metadata); }
  update(actor: ActorContext, planId: string, dto: UpdateSchedulePlanDto, metadata: LessonCommandMetadata) { return this.mutations.update(actor, planId, dto, metadata); }
}
```

Register `SchedulePlanDefinitionService`, `SchedulePlanQueryService`, `SchedulePlanConstraintPreviewService`, `SchedulePlanMutationService`, and `SchedulePlanEndService` in `CrmModule.providers`; export none. Rebuild the integration-test graph with the same real repository, series, materializer, lifecycle, reservation, token, and settlement collaborators.

- [ ] **J7 Guard: Enforce facade and transaction ownership**

```ts
expect(sourceNloc(facade)).toBeLessThanOrEqual(150);
expect(exactConstructorTypes(facade)).toEqual([
  "SchedulePlanQueryService", "SchedulePlanConstraintPreviewService",
  "SchedulePlanMutationService", "SchedulePlanEndService",
]);
expect(exactMethodNames(facade)).toEqual([
  "list", "previewConstraints", "previewUpdateConstraints", "previewEnd",
  "end", "tray", "create", "update",
]);
expect(facade).not.toMatch(/DatabaseService|PlatformIntegrityService|SchedulePlanRepository|\.transaction\(|executeVersionedMutation|select\s|insert\s|update\s/iu);
expect(transactionCallCount(previewOwner)).toBe(2);
expect(transactionCallCount(endOwner)).toBe(1);
expect(versionedMutationCount(mutationOwner)).toBe(2);
expect(versionedMutationCount(endOwner)).toBe(1);
```

Assert every new production file `<=500` NLOC, neutral metadata import only, exact direct delegation, extracted providers private, CRM exports unchanged, and RepoWise max CCN `<=10`.

- [ ] **J8 Smoke: Run the complete schedule-plan lane check once**

```powershell
Set-Location server
npm test -- --runTestsByPath src/crm/schedule/schedule-plan-services.spec.ts src/crm/schedule/schedule-plan-boundaries.spec.ts
npm test -- --runTestsByPath src/crm/schedule/schedule-plan-postgres.integration.spec.ts --testNamePattern="creates one open-ended individual plan|applies one concurrent effective edit|rejects a stale end preview|pages a bounded plan tray"
npm run typecheck -- --pretty false
Set-Location ..
git diff --check
repowise update --index-only
@(
  'server/src/crm/schedule/schedule-plan.service.ts',
  'server/src/crm/schedule/schedule-plan-definition.service.ts',
  'server/src/crm/schedule/schedule-plan-query.service.ts',
  'server/src/crm/schedule/schedule-plan-constraint-preview.service.ts',
  'server/src/crm/schedule/schedule-plan-mutation.service.ts',
  'server/src/crm/schedule/schedule-plan-end.service.ts',
  'server/src/crm/schedule/schedule-plan-overlap-analyzer.ts'
) | ForEach-Object { repowise health --file $_ --format json }
```

Expected: named unit/integration tests and typecheck pass; all extracted owners meet health/CCN; original schedule-plan god owner is gone.

- [ ] **J9 Report: Record schedule-plan evidence**

Write `.superpowers/campaign12/lane-j-schedule-plan-report.md` with before/after metrics, selected PostgreSQL test results/durations, metadata dependency check, lock ordering, expected version/idempotency/audit/outbox/history evidence, facade guard, and intended commit message `refactor(schedule): split schedule plan workflows`. J10 prints the resulting SHA for the tier ledger.

- [ ] **J10 Commit: Create the reversible schedule-plan commit**

```powershell
git add server/src/crm/schedule server/src/crm/crm.module.ts
git commit -m "refactor(schedule): split schedule plan workflows"
git rev-parse HEAD
```

---

### Task K: Split StaffDetailDialog

**Baseline:** `_StaffDetailDialogState` — health `1.04`, `662` NLOC, max CCN `30`, weighted deficit `4608`.

**Files:**

- Modify: `lib/features/admin/presentation/widgets/staff_detail_dialog.dart`
- Create: `lib/features/admin/presentation/widgets/staff_detail_model.dart`
- Create: `lib/features/admin/presentation/widgets/staff_detail_controller.dart`
- Create: `lib/features/admin/presentation/widgets/staff_detail_content.dart`
- Create: `lib/features/admin/presentation/widgets/staff_detail_access_flow.dart`
- Create: `test/features/settings/staff_detail_dialog_contract_test.dart`
- Create: `test/features/admin/presentation/widgets/staff_detail_architecture_test.dart`
- Create: `docs/superpowers/reports/campaign-12/lane-k-staff-detail.md`

**Verify only:** `magic_crm_service.dart`, `magic_crm_service_core.dart`, `manage_entities_widget.dart`, `manage_entities_scheduling.dart`, `provision_access_dialog.dart`, `person_lifecycle_dialog.dart`, `person_access_role_dialog.dart`, `system_settings_workspace_test.dart`, and `settings_test_api.dart`.

**Interfaces:**

```dart
class StaffDetailDraft {
  StaffDetailDraft.fromStaff(Map<String, dynamic> staff);
  String firstName;
  String lastName;
  String canonicalPhone;
  String email;
  String position;
  String birthday;
  String role;
  String status;
  Set<String> branchIds;
  String? linkSearchValue();
  Map<String, dynamic> customDataPatch();
}

class StaffDetailController extends ChangeNotifier {
  StaffDetailController({
    required MagicCrmService crm,
    required Map<String, dynamic> staff,
  });
  Map<String, dynamic> get staff;
  StaffDetailDraft get draft;
  List<Map<String, dynamic>> get branches;
  bool get loadingBranches;
  bool get saving;
  String? get branchesError;
  Future<void> loadBranches();
  Future<void> save();
  Future<Map<String, dynamic>> loadCredentials();
  Future<Map<String, dynamic>> provisionAccess({String? email, String? password});
  void applyAccessRole(String role);
}
```

`StaffDetailDialog` and `StaffDetailDialog.show` remain exact. `StaffDetailContent` receives controller, form key, current role, and callbacks for provision, lifecycle, role, linking, save, and cancel.

**Invariants:** legacy profile fallback for first/last/phone; canonical phone wins over email for linking; migration/local invalid emails never link; save requires first/last/status and one branch; update payload contains firstName/lastName/phone/position/status/branchIds and only changed nonempty birthday in customDataPatch; it never contains email/password/role; credentials/access/lifecycle are director/system_admin only; role change also needs profile user ID; archived disables access/save but keeps restore; save pops true before snackbar; linking requests navigation then root-pops false; preserve `staff-change-access-role`.

- [ ] **Step K1: Add RED controller/widget tests**

Cover exact branch load failure/retry text, save payload and forbidden keys, empty-branch snackbar/no mutation, manager-vs-director actions, archived disable/restore behavior, canonical-phone linking precedence, and invalid-email suppression.

- [ ] **Step K2: Run RED**

```powershell
flutter test test/features/settings/staff_detail_dialog_contract_test.dart
```

Expected: FAIL because `StaffDetailController` and `StaffDetailDraft` do not exist.

- [ ] **Step K3: Extract model/controller and access flow**

Move fallback parsing, controllers/draft, branch loading, validation payload, save, credential reads/provision, label/date helpers, and role application into the named owners. Access flow remains responsible for opening the existing provision/lifecycle/role dialogs and translating successful results.

- [ ] **Step K4: Extract stateless content and close shell**

Move summary chips, access controls, identity fields, branch chips, role/status fields, and actions to `staff_detail_content.dart`. Shell keeps provider/controller lifecycle, dialog/navigation orchestration, form validation trigger, pop results, and snackbars.

- [ ] **Step K5: Add structural guard**

Assert shell `<= 240` NLOC, imports `<= 14`, every new file `<= 500` NLOC, at most one `magicCrmServiceProvider` occurrence, and no `updateStaff`, `getStaffAccess`, `provisionStaffAccess`, `_credentialHelper`, `_branchesText`, or `_dropdownItems` in shell.

- [ ] **Step K6: Run lane smoke**

```powershell
flutter test test/features/settings/staff_detail_dialog_contract_test.dart test/features/admin/presentation/widgets/staff_detail_architecture_test.dart
flutter test test/features/settings/system_settings_workspace_test.dart --plain-name "staff card without access saves profile data without credentials"
flutter test test/features/settings/system_settings_workspace_test.dart --plain-name "director creates login access for a legacy staff record"
flutter analyze --no-pub lib/features/admin/presentation/widgets/staff_detail_dialog.dart lib/features/admin/presentation/widgets/staff_detail_model.dart lib/features/admin/presentation/widgets/staff_detail_controller.dart lib/features/admin/presentation/widgets/staff_detail_content.dart lib/features/admin/presentation/widgets/staff_detail_access_flow.dart
dart format --output=none --set-exit-if-changed lib/features/admin/presentation/widgets/staff_detail_*.dart test/features/settings/staff_detail_dialog_contract_test.dart test/features/admin/presentation/widgets/staff_detail_architecture_test.dart
rg -n "customDataPatch|branchIds|canonicalPhone|profile_user_id|lifecycle_state|staff-change-access-role" lib/features/admin/presentation/widgets/staff_detail_*.dart
git diff --check
repowise update --index-only
repowise health --file lib/features/admin/presentation/widgets/staff_detail_dialog.dart --format json
```

- [ ] **Step K7: Report and commit**

Write focused evidence, payload assertions, metrics, health for every owner, and verify-only diff confirmation to `lane-k-staff-detail.md`.

```powershell
git add lib/features/admin/presentation/widgets/staff_detail_dialog.dart lib/features/admin/presentation/widgets/staff_detail_model.dart lib/features/admin/presentation/widgets/staff_detail_controller.dart lib/features/admin/presentation/widgets/staff_detail_content.dart lib/features/admin/presentation/widgets/staff_detail_access_flow.dart test/features/settings/staff_detail_dialog_contract_test.dart test/features/admin/presentation/widgets/staff_detail_architecture_test.dart docs/superpowers/reports/campaign-12/lane-k-staff-detail.md
git commit -m "refactor(admin-ui): split staff detail dialog owners"
```

---

### Task L: Split ScheduleReferenceSettings

**Baseline:** `_ScheduleReferenceSettingsState` — health `2.14`, `763` NLOC, max CCN `11`, weighted deficit `4471`.

**Files:**

- Modify: `lib/features/admin/presentation/widgets/schedule_reference_settings.dart`
- Create: `lib/features/admin/presentation/widgets/schedule_reference_models.dart`
- Create: `lib/features/admin/presentation/widgets/schedule_reference_controller.dart`
- Create: `lib/features/admin/presentation/widgets/schedule_reference_view.dart`
- Create: `lib/features/admin/presentation/widgets/schedule_reference_cards.dart`
- Create: `lib/features/admin/presentation/widgets/schedule_reference_dialogs.dart`
- Create: `test/features/settings/schedule_reference_controller_test.dart`
- Create: `test/features/admin/presentation/widgets/schedule_reference_architecture_test.dart`
- Create: `docs/superpowers/reports/campaign-12/lane-l-schedule-reference.md`

**Verify only:** `magic_crm_service.dart`, `magic_crm_service_schedule.dart`, `manage_entities_widget.dart`, `system_settings_workspace_test.dart`, `settings_test_api.dart`, and `configuration_settings_device_test.dart`.

**Interfaces:**

```dart
class BranchHoursDraft {
  const BranchHoursDraft({
    required this.version,
    required this.timezone,
    required this.weekly,
    required this.exceptions,
  });
  factory BranchHoursDraft.fromJson(Map<String, dynamic> json);
  final int version;
  final String timezone;
  final Map<int, Map<String, dynamic>> weekly;
  final List<Map<String, dynamic>> exceptions;
}

class TeacherScheduleDraft {
  const TeacherScheduleDraft({
    required this.version,
    required this.assignments,
    required this.recurring,
    required this.extraRecurring,
    required this.intervals,
  });
  factory TeacherScheduleDraft.fromJson(Map<String, dynamic> json);
  final int version;
  final Map<String, Map<String, dynamic>> assignments;
  final Map<int, Map<String, dynamic>> recurring;
  final List<Map<String, dynamic>> extraRecurring;
  final List<Map<String, dynamic>> intervals;
}

class ScheduleReferenceController extends ChangeNotifier {
  ScheduleReferenceController({
    required MagicCrmService crm,
    required ScheduleReferenceSection section,
    required bool canEdit,
    DateTime Function()? clock,
  });
  Future<void> loadCatalogs();
  Future<void> selectBranch(String branchId);
  Future<void> selectTeacher(String teacherId);
  Future<void> saveBranchHours();
  Future<void> saveAssignments();
  Future<void> saveAvailability();
  void setBranchDayEnabled(int weekday, bool enabled);
  void setBranchTime(int weekday, String field, String value);
  void replaceBranchException(Map<String, dynamic> exception);
  void removeBranchException(String date);
  void setAssignment(String branchId, bool selected);
  void setRecurringEnabled(int weekday, bool enabled);
  void setRecurringTime(int weekday, String field, String value);
  void addUnavailableInterval(Map<String, dynamic> interval);
  void removeUnavailableInterval(Map<String, dynamic> interval);
}
```

**Invariants:** first valid branch/teacher selection; stale responses ignored; branch payload keeps expectedVersion/timezone/weekly/exceptions while dropping only nulls; assignment defaults `activeFrom` to `1970-01-01`; returned version feeds the next mutation; duplicate recurring rules remain in `extraRecurring`, lock editing, and survive save; new recurring rules keep timezone/validFrom; intervals use UTC, `available: false`, and required reason; `canEdit=false` is fail-closed in both UI and controller; preserve `settings-branch-*`, `settings-teacher-*`, weekday semantics, error/empty copy, and success toasts.

- [ ] **Step L1: Add RED controller/widget tests**

Assert branch save body at version `2`; assignment body at version `3` followed by availability version `4`; duplicate recurring preservation/lock; late response rejection after selection change; no mutation when read-only; and exact section-specific retry text.

- [ ] **Step L2: Run RED**

```powershell
flutter test test/features/settings/schedule_reference_controller_test.dart
```

Expected: FAIL because the typed drafts/controller do not exist.

- [ ] **Step L3: Extract models/controller**

Move catalog/reference loading, request-generation protection, parsing, all draft mutations, expected-version updates, payload cleaning, and save state into the controller/models. Reject mutation methods when `canEdit` is false before any service call.

- [ ] **Step L4: Extract views/cards/dialogs**

Move selectors/root states to `schedule_reference_view.dart`, hours/assignments/availability/time rows to `schedule_reference_cards.dart`, and date/time/reason collection to `schedule_reference_dialogs.dart`. Keep the shell as provider/controller lifecycle composition only.

- [ ] **Step L5: Add structural guard**

Assert shell `<= 180` NLOC, imports `<= 10`, every new file `<= 500` NLOC, and no service method names, `_availabilityCard`, `_assignmentsCard`, `_hoursCard`, or `_save` in shell. Assert shared files remain absent from the lane diff.

- [ ] **Step L6: Run lane smoke**

```powershell
flutter test test/features/settings/schedule_reference_controller_test.dart test/features/admin/presentation/widgets/schedule_reference_architecture_test.dart
flutter test test/features/settings/system_settings_workspace_test.dart --plain-name "branch hours and teacher schedules are separate read-only views"
flutter test test/features/settings/system_settings_workspace_test.dart --plain-name "director saves branch assignments and working hours for all three teachers"
flutter analyze --no-pub lib/features/admin/presentation/widgets/schedule_reference_settings.dart lib/features/admin/presentation/widgets/schedule_reference_models.dart lib/features/admin/presentation/widgets/schedule_reference_controller.dart lib/features/admin/presentation/widgets/schedule_reference_view.dart lib/features/admin/presentation/widgets/schedule_reference_cards.dart lib/features/admin/presentation/widgets/schedule_reference_dialogs.dart
dart format --output=none --set-exit-if-changed lib/features/admin/presentation/widgets/schedule_reference_*.dart test/features/settings/schedule_reference_controller_test.dart test/features/admin/presentation/widgets/schedule_reference_architecture_test.dart
rg -n "expectedVersion|extraRecurring|activeFrom|available.*false|settings-branch-|settings-teacher-" lib/features/admin/presentation/widgets/schedule_reference_*.dart
git diff --check
repowise update --index-only
repowise health --file lib/features/admin/presentation/widgets/schedule_reference_settings.dart --format json
```

- [ ] **Step L7: Report and commit**

Write version-chain evidence, read-only proof, commands, metrics, extracted-owner health, and verify-only diff confirmation to `lane-l-schedule-reference.md`.

```powershell
git add lib/features/admin/presentation/widgets/schedule_reference_settings.dart lib/features/admin/presentation/widgets/schedule_reference_models.dart lib/features/admin/presentation/widgets/schedule_reference_controller.dart lib/features/admin/presentation/widgets/schedule_reference_view.dart lib/features/admin/presentation/widgets/schedule_reference_cards.dart lib/features/admin/presentation/widgets/schedule_reference_dialogs.dart test/features/settings/schedule_reference_controller_test.dart test/features/admin/presentation/widgets/schedule_reference_architecture_test.dart docs/superpowers/reports/campaign-12/lane-l-schedule-reference.md
git commit -m "refactor(schedule-ui): split schedule reference owners"
```

## Tier 4 Shared Boundary

Lanes K and L are independent leaf cuts and must not edit `lib/core/services/magic_crm_service.dart`, `lib/features/admin/presentation/widgets/manage_entities_widget.dart`, or `test/features/settings/system_settings_workspace_test.dart`. Lane J owns no Flutter file. After J/K/L are applied, the integrator verifies the shared paths are unchanged, runs the K/L focused shared-test commands once against the integrated tier, and owns any required shared wiring commit. No Tier 4 lane runs a global suite.

### Tier 4 Integration and Review: J, K, L

**Backend scope:** Task J files plus `server/src/crm/crm.module.ts`. Flutter lanes K/L must not edit backend files.

- [x] **T4.1 Integrate Task J before the two Flutter leaf commits**

```powershell
git merge --no-ff codex/campaign12-schedule-plan -m "merge(campaign12): integrate schedule plan lane"
git merge --no-ff codex/campaign12-staff-detail -m "merge(campaign12): integrate staff detail lane"
git merge --no-ff codex/campaign12-schedule-reference -m "merge(campaign12): integrate schedule reference lane"
git status --short --branch
git diff --check HEAD~3..HEAD
```

Expected: only Task J changes backend files; K/L introduce no `server/` diff.

- [x] **T4.2 Verify final backend wiring and metadata direction**

```powershell
rg -n "SchedulePlanDefinitionService|SchedulePlanQueryService|SchedulePlanConstraintPreviewService|SchedulePlanMutationService|SchedulePlanEndService" server/src/crm/crm.module.ts
rg -n "from \"\.\/lesson-command-metadata\"" server/src/crm/schedule/schedule-plan.service.ts server/src/crm/schedule/schedule-plan-mutation.service.ts server/src/crm/schedule/schedule-plan-end.service.ts
rg -n "LessonCommandMetadata.*lesson-command\.service" server/src/crm/schedule
```

Expected: five private schedule-plan providers are present; all metadata imports are neutral; the final command returns no match.

- [x] **T4.3 Re-run Task J focused smoke on the integrated Tier 4 graph**

```powershell
Set-Location server
npm test -- --runTestsByPath src/crm/schedule/schedule-plan-services.spec.ts src/crm/schedule/schedule-plan-boundaries.spec.ts
npm test -- --runTestsByPath src/crm/schedule/schedule-plan-postgres.integration.spec.ts --testNamePattern="creates one open-ended individual plan|applies one concurrent effective edit|rejects a stale end preview|pages a bounded plan tray"
npm run typecheck -- --pretty false
Set-Location ..
git diff --check
```

Expected: focused schedule-plan evidence passes after K/L integration. Do not run the campaign-wide backend suite in this task.

- [x] **T4.4 Perform the backend portion of the Tier 4 review**

```powershell
repowise update --index-only
repowise risk -t server/src/crm/schedule/schedule-plan.service.ts -t server/src/crm/schedule/schedule-plan-definition.service.ts -t server/src/crm/schedule/schedule-plan-mutation.service.ts -t server/src/crm/schedule/schedule-plan-end.service.ts --format json --full
```

Reviewer verifies eight public signatures, controller route/DTO/header stability, policy and platform capability checks, three preview transactions, three versioned mutations, lock order, append-only series/lesson history, audit/outbox payloads, neutral metadata direction, no new dependency cycle, and Critical/Important `0/0`.

- [x] **T4.5 Record the backend Tier 4 result**

Write the backend section of `.superpowers/campaign12/tier-4-review.md` with Task J and merge SHAs, smoke counts/durations, RepoWise health/risk arrays, module and metadata checks, and reviewer severity counts. This report hands the integrated candidate to the separate single campaign gate.


- [x] **T4.6 Prove Tier 4 Flutter shared paths remained unchanged**

```powershell
$Tier4Base = (git merge-base codex/campaign12-schedule-plan codex/campaign12-staff-detail).Trim()
$Tier4VerifyOnly = @(
  'server/src/crm/crm-schedule.controller.ts',
  'server/src/crm/dto/schedule-plan.dto.ts',
  'server/src/crm/schedule/schedule-plan.repository.ts',
  'server/src/crm/schedule/schedule-plan.types.ts',
  'server/src/crm/schedule/lesson-series-command.service.ts',
  'server/src/crm/schedule/schedule-series-materializer.service.ts',
  'server/src/crm/schedule/lesson-lifecycle.repository.ts',
  'server/src/crm/commerce/subscription-reservation.service.ts',
  'server/src/crm/commerce/lesson-settlement.service.ts',
  'server/src/crm/commerce/subscription-preview-token.service.ts',
  'server/src/crm/schedule/constraint-engine.service.ts',
  'server/src/crm/schedule/constraint-engine.repository.ts',
  'server/src/crm/schedule/constraint-engine.rules.ts',
  'server/src/crm/schedule/constraint-engine.types.ts',
  'lib/core/services/magic_crm_service.dart',
  'lib/core/services/magic_crm_service_core.dart',
  'lib/core/services/magic_crm_service_schedule.dart',
  'lib/features/admin/presentation/widgets/manage_entities_widget.dart',
  'lib/features/admin/presentation/widgets/manage_entities_scheduling.dart',
  'lib/features/admin/presentation/widgets/provision_access_dialog.dart',
  'lib/features/admin/presentation/widgets/person_lifecycle_dialog.dart',
  'lib/features/admin/presentation/widgets/person_access_role_dialog.dart',
  'test/features/settings/system_settings_workspace_test.dart',
  'test/support/settings_test_api.dart',
  'integration_test/configuration_settings_device_test.dart'
)
if ($Tier4VerifyOnly.Count -ne 25) {
  throw "Tier 4 verify-only inventory drifted: $($Tier4VerifyOnly.Count)"
}
$Tier4SharedDiff = @(git diff --name-only "$Tier4Base..HEAD" -- $Tier4VerifyOnly)
if ($Tier4SharedDiff.Count -ne 0) {
  throw "Tier 4 modified verify-only paths: $($Tier4SharedDiff -join ', ')"
}
$Tier4BackendDiffFromFlutter = @(
  git diff --name-only "$Tier4Base..codex/campaign12-staff-detail" -- server
  git diff --name-only "$Tier4Base..codex/campaign12-schedule-reference" -- server
)
if ($Tier4BackendDiffFromFlutter.Count -ne 0) {
  throw "Tier 4 Flutter branches contain backend changes: $($Tier4BackendDiffFromFlutter -join ', ')"
}
```

Expected: both arrays are empty.

- [x] **T4.7 Re-run the exact Lane K smoke on the integrated graph**

```powershell
flutter test test/features/settings/staff_detail_dialog_contract_test.dart test/features/admin/presentation/widgets/staff_detail_architecture_test.dart
flutter test test/features/settings/system_settings_workspace_test.dart --plain-name "staff card without access saves profile data without credentials"
flutter test test/features/settings/system_settings_workspace_test.dart --plain-name "director creates login access for a legacy staff record"
flutter analyze --no-pub lib/features/admin/presentation/widgets/staff_detail_dialog.dart lib/features/admin/presentation/widgets/staff_detail_model.dart lib/features/admin/presentation/widgets/staff_detail_controller.dart lib/features/admin/presentation/widgets/staff_detail_content.dart lib/features/admin/presentation/widgets/staff_detail_access_flow.dart
dart format --output=none --set-exit-if-changed lib/features/admin/presentation/widgets/staff_detail_*.dart test/features/settings/staff_detail_dialog_contract_test.dart test/features/admin/presentation/widgets/staff_detail_architecture_test.dart
rg -n "customDataPatch|branchIds|canonicalPhone|profile_user_id|lifecycle_state|staff-change-access-role" lib/features/admin/presentation/widgets/staff_detail_*.dart
git diff --check
repowise update --index-only
repowise health --file lib/features/admin/presentation/widgets/staff_detail_dialog.dart --format json
```

Expected: all named tests and checks pass; save/access/linking invariants remain exact.

- [x] **T4.8 Re-run the exact Lane L smoke on the integrated graph**

```powershell
flutter test test/features/settings/schedule_reference_controller_test.dart test/features/admin/presentation/widgets/schedule_reference_architecture_test.dart
flutter test test/features/settings/system_settings_workspace_test.dart --plain-name "branch hours and teacher schedules are separate read-only views"
flutter test test/features/settings/system_settings_workspace_test.dart --plain-name "director saves branch assignments and working hours for all three teachers"
flutter analyze --no-pub lib/features/admin/presentation/widgets/schedule_reference_settings.dart lib/features/admin/presentation/widgets/schedule_reference_models.dart lib/features/admin/presentation/widgets/schedule_reference_controller.dart lib/features/admin/presentation/widgets/schedule_reference_view.dart lib/features/admin/presentation/widgets/schedule_reference_cards.dart lib/features/admin/presentation/widgets/schedule_reference_dialogs.dart
dart format --output=none --set-exit-if-changed lib/features/admin/presentation/widgets/schedule_reference_*.dart test/features/settings/schedule_reference_controller_test.dart test/features/admin/presentation/widgets/schedule_reference_architecture_test.dart
rg -n "expectedVersion|extraRecurring|activeFrom|available.*false|settings-branch-|settings-teacher-" lib/features/admin/presentation/widgets/schedule_reference_*.dart
git diff --check
repowise update --index-only
repowise health --file lib/features/admin/presentation/widgets/schedule_reference_settings.dart --format json
```

Expected: all named tests and checks pass; version chaining, duplicate recurring preservation, and fail-closed read-only behavior remain exact.

- [x] **T4.9 Complete and commit the integrated Tier 4 review**

Append the Flutter scope, K/L lane and merge SHAs, exact smoke counts/durations, verify-only proof, targeted RepoWise health/risk, and reviewer findings to `.superpowers/campaign12/tier-4-review.md`. The independent reviewer examines the complete J/K/L tier diff for backend lock/version/idempotency/audit/outbox/history contracts, Flutter provider/payload/key/copy/navigation contracts, all permanent guards, neutral metadata direction, and scope ownership. Require Critical/Important `0/0`, then commit:

```powershell
git diff --check
git add .superpowers/campaign12/tier-4-review.md docs/superpowers/plans/2026-08-26-campaign-12-god-recovery.md
git commit -m "docs(health): record Campaign-12 tier 4 review"
git rev-parse HEAD
```

Tier 4 hands this exact code-and-tier-evidence HEAD to the one global campaign gate below.

---


### Task M: Run the single global acceptance gate and commit exact evidence

**Files:**

- Create: `.superpowers/campaign12/campaign-12-global-evidence.md`
- Create: `.superpowers/campaign12/campaign-12-whole-review.md`
- Modify: `docs/superpowers/specs/2026-08-26-campaign-12-god-recovery-design.md`
- Modify: `docs/superpowers/plans/2026-08-26-campaign-12-god-recovery.md`
- Generate ignored: `server/coverage/lcov.info`
- Generate ignored: `coverage/lcov.info`

**Interfaces:**

- Consumes: the literal executable `$CampaignBaseline` recorded identically in the Tier 1 lane reports, source-metrics SHA `41bc4a8c32aeb74263dfa5de975bba1c8f50c868`, all accepted A–L lane commits, four tier review commits, exact backend/Flutter LCOV, RepoWise output, and Sentrux output.
- Produces: one accepted Campaign-12 code HEAD, one evidence commit, exact `23 -> 11` production-owner proof when all twelve lanes passed, and a whole-campaign Critical/Important `0/0` review.

- [ ] **M1 Freeze the integrated code candidate and commit range**

Run from the integration worktree root:

```powershell
$Tier1Reports = @(
  '.superpowers/campaign12/reports/tier1-lane-a.md',
  '.superpowers/campaign12/reports/tier1-lane-b.md',
  '.superpowers/campaign12/reports/tier1-lane-c.md'
)
$RecordedBaselines = @($Tier1Reports | ForEach-Object {
  $Match = [regex]::Match(
    (Get-Content -Raw -LiteralPath $_),
    '(?m)^Campaign baseline: `?([0-9a-f]{40})`?\s*$'
  )
  if (-not $Match.Success) { throw "Missing Campaign baseline marker in $_" }
  $Match.Groups[1].Value
} | Sort-Object -Unique)
if ($RecordedBaselines.Count -ne 1) {
  throw "Tier 1 reports disagree on Campaign baseline: $($RecordedBaselines -join ', ')"
}
$CampaignBaseline = $RecordedBaselines[0]
$CampaignCodeHead = (git rev-parse HEAD).Trim()
$CampaignRange = "$CampaignBaseline..$CampaignCodeHead"
git status --short --branch
git diff --check $CampaignRange
git log --reverse --format='%H %s' $CampaignRange
git diff --stat $CampaignRange
```

Expected: the worktree is clean; the range contains only accepted lane, tier wiring, focused-fix, and tier evidence commits; every tier report records Critical/Important `0/0`. Record `$CampaignBaseline`, `$CampaignCodeHead`, and the commit ledger in `campaign-12-global-evidence.md`.

- [ ] **M2 Run full backend Jest, typecheck, and Nest build once**

```powershell
$env:NODE_OPTIONS = '--max-old-space-size=8192'
npm --prefix server test -- --runInBand
npm --prefix server run typecheck
npm --prefix server run build
```

Expected: every backend Jest suite/test passes, typecheck exits `0`, and Nest build exits `0`. Record exact suites, tests, durations, exit codes, and any Node heap exception; no result from an earlier SHA counts.

- [ ] **M3 Run full Flutter tests and analyzer once**

```powershell
flutter test
flutter analyze
```

Expected: every Flutter test passes and analyzer reports no issue. Record exact test count, duration, analyzer duration, and exit codes.

- [ ] **M4 Generate, hash, and ingest fresh backend and Flutter LCOV**

```powershell
$env:NODE_OPTIONS = '--max-old-space-size=8192'
npm --prefix server test -- --coverage --coverageReporters=lcov --runInBand
$BackendLcov = Get-Item -LiteralPath server/coverage/lcov.info
$BackendLcov | Select-Object FullName,Length,LastWriteTimeUtc
$BackendLcovHash = Get-FileHash -LiteralPath server/coverage/lcov.info -Algorithm SHA256
$BackendLcovHash

flutter test --coverage
$FlutterLcov = Get-Item -LiteralPath coverage/lcov.info
$FlutterLcov | Select-Object FullName,Length,LastWriteTimeUtc
$FlutterLcovHash = Get-FileHash -LiteralPath coverage/lcov.info -Algorithm SHA256
$FlutterLcovHash

repowise coverage add server/coverage/lcov.info coverage/lcov.info
repowise coverage status
```

Expected: both full coverage runs pass on `$CampaignCodeHead`; both artifacts have nonzero length and fresh timestamps; both SHA-256 values and RepoWise resolved-file/line/branch totals are recorded. The ignored LCOV files remain uncommitted.

- [ ] **M5 Prove exact RepoWise index, every owner, and the production-only `23 -> 11` recount**

```powershell
$Tier1Reports = @(
  '.superpowers/campaign12/reports/tier1-lane-a.md',
  '.superpowers/campaign12/reports/tier1-lane-b.md',
  '.superpowers/campaign12/reports/tier1-lane-c.md'
)
$CampaignBaseline = @($Tier1Reports | ForEach-Object {
  $Match = [regex]::Match((Get-Content -Raw -LiteralPath $_), '(?m)^Campaign baseline: `?([0-9a-f]{40})`?\s*$')
  if (-not $Match.Success) { throw "Missing Campaign baseline marker in $_" }
  $Match.Groups[1].Value
} | Sort-Object -Unique)
if ($CampaignBaseline.Count -ne 1) { throw 'Tier 1 Campaign baselines disagree.' }
$CampaignBaseline = $CampaignBaseline[0]
$CampaignCodeHead = (git rev-parse HEAD).Trim()
repowise update --index-only
$IndexStatus = repowise status --format json | ConvertFrom-Json
if (-not $IndexStatus.indexed) {
  throw 'RepoWise index is absent.'
}
if ($IndexStatus.state.last_sync_commit -ne $CampaignCodeHead) {
  throw "RepoWise index mismatch: indexed=$($IndexStatus.state.last_sync_commit), code=$CampaignCodeHead"
}

$Health = repowise health --format json | ConvertFrom-Json
$ProductionMetrics = @($Health.metrics | Where-Object {
  $Path = $_.file_path -replace '\\', '/'
  ($Path -like 'lib/*' -or $Path -like 'server/src/*') -and
  $Path -notmatch '(^|/)(test|tests|integration_test|coverage|generated|build|dist|docs|fixtures?|mocks?|__tests__)(/|$)' -and
  $Path -notmatch '(\.spec|\.test|\.integration\.spec|\.contract\.spec|\.e2e-spec)\.(ts|dart)$' -and
  $Path -notmatch '\.(g|freezed|mocks)\.dart$' -and
  $Path -notlike 'server/src/migration/*'
})
$ProductionPaths = [System.Collections.Generic.HashSet[string]]::new(
  [string[]]@($ProductionMetrics.file_path | ForEach-Object { $_ -replace '\\', '/' })
)
$ProductionFindings = @($Health.findings | Where-Object {
  $ProductionPaths.Contains(($_.file_path -replace '\\', '/'))
})

$ExpectedRemainingGodOwners = @(
  'lib/features/admin/presentation/widgets/reference_catalog_lifecycle_dialog.dart::_ReferenceCatalogLifecycleDialogState',
  'lib/features/crm/presentation/client_card/client_card.dart::_ClientCardState',
  'lib/features/crm/presentation/client_card/preferred_schedule_editor.dart::_PreferredScheduleEditorState',
  'lib/features/manager/presentation/tasks/shared_task_editor.dart::_SharedTaskEditorState',
  'lib/features/manager/presentation/widgets/finance_widget.dart::_FinanceWidgetState',
  'lib/features/manager/presentation/widgets/student_funnel_editor.dart::_StudentFunnelEditorState',
  'lib/features/manager/presentation/widgets/students_board_widget.dart::_StudentsBoardWidgetState',
  'lib/core/workspace/production_workspace_host.dart::_ProductionWorkspaceHostState',
  'server/src/crm/finance.service.ts::FinanceService',
  'server/src/crm/schedule/lesson-command.service.ts::LessonCommandService',
  'server/src/crm/student-funnel.service.ts::StudentFunnelService'
) | Sort-Object
$ActualRemainingGodOwners = @(
  $ProductionFindings |
    Where-Object biomarker_type -eq 'god_class' |
    ForEach-Object { "$(($_.file_path -replace '\\', '/'))::$($_.function_name)" } |
    Sort-Object
)
$GodOwnerDelta = @(Compare-Object $ExpectedRemainingGodOwners $ActualRemainingGodOwners)
if ($ActualRemainingGodOwners.Count -ne 11 -or $GodOwnerDelta.Count -ne 0) {
  throw "Production god owners are not the exact accepted 11: $($GodOwnerDelta | Out-String)"
}

$ChangedProductionFiles = @(
  git diff --name-only "$CampaignBaseline..$CampaignCodeHead" -- lib server/src |
    ForEach-Object { $_ -replace '\\', '/' } |
    Where-Object { $ProductionPaths.Contains($_) }
)
$ChangedProductionSet = [System.Collections.Generic.HashSet[string]]::new(
  [string[]]$ChangedProductionFiles
)
$ChangedBrainFindings = @($ProductionFindings | Where-Object {
  $_.biomarker_type -eq 'brain_method' -and
  $ChangedProductionSet.Contains(($_.file_path -replace '\\', '/'))
})
if ($ChangedBrainFindings.Count -ne 0) {
  throw "Campaign introduced or retained brain methods: $($ChangedBrainFindings | ConvertTo-Json -Depth 20)"
}

$AddedProductionFiles = @(
  git diff --name-only --diff-filter=A "$CampaignBaseline..$CampaignCodeHead" -- lib server/src |
    ForEach-Object { $_ -replace '\\', '/' } |
    Where-Object { $ProductionPaths.Contains($_) }
)
$AddedProductionSet = [System.Collections.Generic.HashSet[string]]::new(
  [string[]]$AddedProductionFiles
)
$NewOwnerMetrics = @($ProductionMetrics | Where-Object {
  $AddedProductionSet.Contains(($_.file_path -replace '\\', '/'))
})
$MissingHealth = @($AddedProductionFiles | Where-Object {
  $_ -notin @($NewOwnerMetrics.file_path | ForEach-Object { $_ -replace '\\', '/' })
})
$FailedNewOwnerMetrics = @($NewOwnerMetrics | Where-Object {
  $_.score -lt 7.0 -or $_.max_ccn -gt 10
})
$NewOwnerGodBrain = @($ProductionFindings | Where-Object {
  $AddedProductionSet.Contains(($_.file_path -replace '\\', '/')) -and
  $_.biomarker_type -in @('god_class', 'brain_method')
})
if ($MissingHealth.Count -ne 0 -or $FailedNewOwnerMetrics.Count -ne 0 -or $NewOwnerGodBrain.Count -ne 0) {
  throw "New owner gate failed. Missing=$($MissingHealth -join ', '); metrics=$($FailedNewOwnerMetrics | ConvertTo-Json -Depth 20); findings=$($NewOwnerGodBrain | ConvertTo-Json -Depth 20)"
}

$OriginalOwnerFiles = @(
  'server/src/messenger/messenger.service.ts',
  'server/src/crm/payroll.service.ts',
  'server/src/crm/commerce/subscription-issue.service.ts',
  'server/src/profile/profile.service.ts',
  'server/src/auth/auth.service.ts',
  'server/src/crm/schedule/lesson-transition.service.ts',
  'lib/core/widgets/telegram/chat_info_dialog.dart',
  'lib/features/manager/presentation/widgets/teacher_stats_widget.dart',
  'lib/features/crm/presentation/client_card/subscription_issue_sheet.dart',
  'server/src/crm/schedule/schedule-plan.service.ts',
  'lib/features/admin/presentation/widgets/staff_detail_dialog.dart',
  'lib/features/admin/presentation/widgets/schedule_reference_settings.dart'
)
$OwnerEvidenceFiles = @($OriginalOwnerFiles + $AddedProductionFiles | Sort-Object -Unique)
$OwnerEvidence = @($ProductionMetrics | Where-Object {
  ($_.file_path -replace '\\', '/') -in $OwnerEvidenceFiles
} | Select-Object file_path,score,nloc,max_ccn,line_coverage_pct,branch_coverage_pct)
if ($OwnerEvidence.Count -ne $OwnerEvidenceFiles.Count) {
  throw "Owner health evidence is incomplete: expected $($OwnerEvidenceFiles.Count), got $($OwnerEvidence.Count)."
}
$OwnerEvidence | Sort-Object file_path | Format-Table -AutoSize
```

Expected: index `last_sync_commit` equals `$CampaignCodeHead`; the same production filter is recorded with its final file count; actual god owners equal the exact eleven-owner allowlist; all twelve target owners are absent; no changed production file has `brain_method`; every added production owner has health `>=7.0`, CCN `<=10`, no god/brain finding, and its task-specific NLOC guard passes in the full structural suites.

- [ ] **M6 Run full-range change risk and assert the hard arrays**

```powershell
$Tier1Reports = @(
  '.superpowers/campaign12/reports/tier1-lane-a.md',
  '.superpowers/campaign12/reports/tier1-lane-b.md',
  '.superpowers/campaign12/reports/tier1-lane-c.md'
)
$CampaignBaseline = @($Tier1Reports | ForEach-Object {
  $Match = [regex]::Match((Get-Content -Raw -LiteralPath $_), '(?m)^Campaign baseline: `?([0-9a-f]{40})`?\s*$')
  if (-not $Match.Success) { throw "Missing Campaign baseline marker in $_" }
  $Match.Groups[1].Value
} | Sort-Object -Unique)
if ($CampaignBaseline.Count -ne 1) { throw 'Tier 1 Campaign baselines disagree.' }
$CampaignBaseline = $CampaignBaseline[0]
$CampaignCodeHead = (git rev-parse HEAD).Trim()
$CampaignRange = "$CampaignBaseline..$CampaignCodeHead"
$ChangeRiskFile = '.superpowers/campaign12/campaign-12-change-risk.json'
repowise risk $CampaignRange --ext '.ts,.dart' --baseline 200 --exclude '*.spec.ts' --exclude '*.test.dart' --exclude 'test/**' --exclude 'integration_test/**' --format json --full |
  Set-Content -LiteralPath $ChangeRiskFile -Encoding utf8
$ChangeRisk = Get-Content -Raw -LiteralPath $ChangeRiskFile | ConvertFrom-Json

$ChangedFiles = @(git diff --name-only $CampaignRange)
$ChangedProductionFiles = @(
  $ChangedFiles | Where-Object {
    ($_ -like 'lib/*' -or $_ -like 'server/src/*') -and
    $_ -notmatch '(\.spec|\.test|\.integration\.spec|\.contract\.spec|\.e2e-spec)\.(ts|dart)$' -and
    $_ -notlike 'server/src/migration/*'
  }
)
$RiskArgs = @()
$ChangedProductionFiles | ForEach-Object { $RiskArgs += @('--target', $_) }
$ChangedFiles | ForEach-Object { $RiskArgs += @('--changed-file', $_) }
$PrRiskFile = '.superpowers/campaign12/campaign-12-pr-risk.json'
& repowise risk @RiskArgs --format json --full |
  Set-Content -LiteralPath $PrRiskFile -Encoding utf8
$PrRisk = Get-Content -Raw -LiteralPath $PrRiskFile | ConvertFrom-Json

$HardArrayNames = @(
  'breaking_changes',
  'will_break_consumers',
  'missing_cross_repo_cochanges',
  'dependency_cycles',
  'conformance_violations'
)
$NonEmptyHardArrays = @($HardArrayNames | Where-Object {
  @($PrRisk.directive.$_).Count -ne 0
})
$SecuritySignals = @(
  $PrRisk.targets.PSObject.Properties.Value |
    ForEach-Object { @($_.security_signals) }
)
if ($NonEmptyHardArrays.Count -ne 0 -or $SecuritySignals.Count -ne 0) {
  throw "RepoWise hard gate failed. Arrays=$($NonEmptyHardArrays -join ', '); security=$($SecuritySignals | ConvertTo-Json -Depth 20)"
}
```

The first `repowise risk` command is the CLI equivalent of RepoWise `get_change_risk` for the full `base..head` range. Also call MCP `get_change_risk` once with the resolved literal full-SHA `revspec`, `extensions=[".ts",".dart"]`, the same four test/spec exclusions, and `baseline=200`; record `risk_percentile`, `review_priority`, `classification`, score, probability, changed-file totals, impacted tests, and missing-test status. Record PR blast radius and the empty `breaking_changes`, `will_break_consumers`, `missing_cross_repo_cochanges`, `dependency_cycles`, `conformance_violations`, and target `security_signals` arrays.

- [ ] **M7 Run Sentrux rescan, health, and rules at the code HEAD**

```powershell
sentrux check
sentrux gate
```

Then call Sentrux MCP `rescan`, `health`, and `check_rules` on the repository root. Acceptance is exact: quality `>=5757`, dependency depth raw `<=13`, acyclicity score `10000` with raw cycles `0`, and architectural rules `2/2` with zero violation. Record equality, modularity, redundancy, file/import/line counts, and every root-cause delta; any root-cause regression blocks acceptance even when aggregate quality rises.

- [ ] **M8 Obtain one independent whole-campaign review**

Give the reviewer the literal `$CampaignBaseline..$CampaignCodeHead` range, approved spec, this master plan, twelve lane reports, four tier reports, both LCOV hashes/status, exact RepoWise index/health/recount/risk JSON, Sentrux output, and full backend/Flutter gate output. The reviewer must report Critical, Important, and Minor findings for these exact areas:

```text
scope, dependency order, facade/public API/DTO stability
RBAC/resource scope, credentials, OTP, sessions, and failure behavior
transaction, lock, expected-version, idempotency, audit, outbox, history, and post-commit ordering
Flutter providers, payload maps, keys, Russian copy, theme, navigation, toasts, focus, scrolling, and accessibility
permanent guards, module privacy, neutral metadata direction, new owners, cycles, and evidence provenance
```

Write the reviewer identity, literal commit range, all findings, dispositions, and severity totals to `.superpowers/campaign12/campaign-12-whole-review.md`. Acceptance requires Critical/Important `0/0`; an unresolved Minor requires an explicit owner ruling and cost.

- [ ] **M9 Update Results, verify evidence, and create the evidence commit**

Append a `## Results` section to both the approved spec and this plan using only measured output from M1–M8. Each Results section records full 40-character baseline/code/evidence/index SHAs; all lane/tier commits; backend and Flutter counts/durations; both LCOV sizes/hashes and RepoWise ingestion totals; every original/new owner health/NLOC/CCN/coverage; exact production filter and `23 -> 11` owner list; full-range and PR risk with hard arrays; Sentrux metrics; whole-review severities; accepted lane count; recovered weighted deficit; and any explicit owner ruling. Mark the campaign accepted only when every M1–M8 gate passes.

Verify and commit:

```powershell
git diff --check
git status --short
git check-ignore -v server/coverage/lcov.info coverage/lcov.info
git add .superpowers/campaign12/campaign-12-global-evidence.md .superpowers/campaign12/campaign-12-whole-review.md .superpowers/campaign12/campaign-12-change-risk.json .superpowers/campaign12/campaign-12-pr-risk.json docs/superpowers/specs/2026-08-26-campaign-12-god-recovery-design.md docs/superpowers/plans/2026-08-26-campaign-12-god-recovery.md
git diff --cached --check
git commit -m "docs(health): record Campaign-12 recovery evidence"
$CampaignEvidenceHead = (git rev-parse HEAD).Trim()
repowise update --index-only
$FinalIndexStatus = repowise status --format json | ConvertFrom-Json
if ($FinalIndexStatus.state.last_sync_commit -ne $CampaignEvidenceHead) {
  throw "Final evidence index mismatch: indexed=$($FinalIndexStatus.state.last_sync_commit), evidence=$CampaignEvidenceHead"
}
git status --short --branch
```

Expected: the evidence commit contains only the four evidence files and two Results-bearing docs; both LCOV artifacts remain ignored; RepoWise is exact at the evidence HEAD; the worktree is clean. Campaign-12 is complete only with all twelve accepted lanes, production `god_class 23 -> 11`, no changed brain finding, new-owner health/CCN and task-specific NLOC gates green, hard arrays empty, Sentrux `5757/13/10000/2-of-2` or better, and whole-review Critical/Important `0/0`.
