# Epic C · C6 — Auto-lead from admin chat (backend) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a non-staff user (a client) sends a message to the administration chat and isn't already a lead/student, auto-create a lead tagged `source='Через приложение'` in the «Новый» funnel column — idempotently, without blocking message delivery — and expose a count endpoint for the «Клиенты» nav badge.

**Architecture:** A new idempotent `CrmService.autoCreateLeadFromChat(actor, senderUserId)` creates the tagged lead (status = the «Новый» status looked up by name, or null fallback) and links the user via `user_crm_links`. `MessengerService.sendMessage`, after it publishes the realtime event, fires this method (fire-and-forget, swallowing errors) only for a non-staff sender in an `administration` chat. `MessengerModule` imports `CrmModule` (no circular dependency exists) to inject `CrmService`. A `countAppLeads` endpoint backs the nav badge (the badge UI itself is the Flutter task, deferred).

**Tech Stack:** NestJS/TypeScript, PostgreSQL, Jest. No new dependency.

**Linear:** KVA-180 (Epic C), task C6. Spec §4C (C6). Depends on the «Новый» lead status existing (from HolliHop import) — falls back to null status if absent.

## Global Constraints

- `autoCreateLeadFromChat(actor: ActorContext, senderUserId: string): Promise<{ leadId: string | null; created: boolean }>` MUST be idempotent: if `senderUserId` is already linked to a lead OR a student via `app.user_crm_links` (entity_type in ('lead','student'), not deleted), return `{ leadId: <existing lead or null>, created: false }` without creating anything.
- The created lead: `source = 'Через приложение'`; `status_id` = the id of the lead status whose `lower(btrim(name)) = 'новый'` (single lookup; null if none exists); `created_by = actor.userId`; first/last/phone copied from the sender's profile. Link via `user_crm_links (entity_type='lead', link_source='auto_app', confirmed_at=now())` `on conflict do nothing`. Audit `crm.lead_created` with metadata `{ fromApp: true, userId }`. Create the lead + link in ONE `database.transaction`.
- The messenger hook fires ONLY when `chat.type === 'administration'` AND the sender is NOT staff (`!isStaffRole(actor.role)`), AFTER the message is committed + the realtime event published. It is fire-and-forget: `void this.crm.autoCreateLeadFromChat(actor, actor.userId).catch(() => undefined)` — it MUST NOT block or fail message delivery.
- `MessengerModule` imports `CrmModule` (which exports `CrmService`). Confirm no import cycle (CrmModule must not transitively import MessengerModule). If a cycle exists, use `forwardRef` — but verify first; none is expected.
- `countAppLeads(actor): Promise<{ count: number }>` gates `assertCanReadOperationalData`; counts `app.leads where source = 'Через приложение' and deleted_at is null`.
- Out of scope (other C sub-plans): the Flutter nav badge UI, the lead-board cleanup (prod-data: remove Контакт/Переговоры/Договор, unassigned→Новый, Архив, recolor, hide-converted), and all the «Клиенты» Flutter UI (rename, segment, Ученики board, drag-convert, unified card, config).
- Run from `server/`: tests `npm test`; types `npm run typecheck`.

---

## File Structure

- **Modify** `server/src/crm/crm.service.ts` — add `autoCreateLeadFromChat`, `countAppLeads`.
- **Modify** `server/src/crm/crm.controller.ts` — add `GET /crm/leads/app-count`.
- **Modify** `server/src/crm/crm.service.spec.ts` — tests.
- **Modify** `server/src/messenger/messenger.service.ts` — fire the hook in `sendMessage`.
- **Modify** `server/src/messenger/messenger.module.ts` — import `CrmModule`.
- **Modify** `server/src/messenger/messenger.service.spec.ts` — tests for the hook.

---

## Task 1: CrmService.autoCreateLeadFromChat + countAppLeads

**Files:**
- Modify: `server/src/crm/crm.service.ts`, `server/src/crm/crm.controller.ts`, `server/src/crm/crm.service.spec.ts`

**Interfaces:**
- Produces: `autoCreateLeadFromChat(actor, senderUserId)`, `countAppLeads(actor)`; route `GET /crm/leads/app-count`.

- [ ] **Step 1: Write the failing tests**

Add to `server/src/crm/crm.service.spec.ts` (use `createServiceWithQueryResults` for sequential mocks; the transaction-aware variant if the method uses `database.transaction` — mirror the existing merge/saveContactFromChat test style):

```typescript
  it("autoCreateLeadFromChat is idempotent when the user is already linked", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ entity_id: "lead-existing" }] }, // user_crm_links lookup → already linked
    ]);
    const result = await service.autoCreateLeadFromChat(actor, "user-1");
    expect(result).toEqual({ leadId: "lead-existing", created: false });
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).not.toContain("insert into app.leads");
  });

  it("counts app-sourced leads", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ count: "7" }] },
    ]);
    const result = await service.countAppLeads(actor);
    expect(result).toEqual({ count: 7 });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("'Через приложение'");
  });
```

> The "creates a lead" happy path uses `database.transaction`; if you add a happy-path test, build the service with a `transaction` mock that calls back with `{ query }` (the merge-test pattern) and assert the insert SQL contains `'Через приложение'` and the status lookup `'новый'`. The two tests above are the minimum (idempotency + count); add the happy-path test too if straightforward.

- [ ] **Step 2: Run to verify failure**

Run: `cd server && npx jest src/crm/crm.service.spec.ts -t "autoCreateLeadFromChat|app-sourced"`
Expected: FAIL — `service.autoCreateLeadFromChat is not a function`.

- [ ] **Step 3: Implement the service methods**

Add to `CrmService` in `server/src/crm/crm.service.ts` (model the transaction + audit + link on the existing `saveContactFromChat`):

```typescript
  // Auto-create a lead when a non-staff user first writes to the admin chat.
  // Idempotent: skips if the user is already linked to a lead or student.
  async autoCreateLeadFromChat(
    actor: ActorContext,
    senderUserId: string,
  ): Promise<{ leadId: string | null; created: boolean }> {
    const linked = await this.database.query<{ entity_type: string; entity_id: string }>(
      `select entity_type, entity_id from app.user_crm_links
        where user_id = $1 and entity_type in ('lead', 'student') and deleted_at is null
        limit 1`,
      [senderUserId],
    );
    if (linked.rows[0]) {
      const existing = linked.rows[0];
      return { leadId: existing.entity_type === "lead" ? existing.entity_id : null, created: false };
    }

    const profileRes = await this.database.query<{
      first_name: string | null;
      last_name: string | null;
      phone: string | null;
    }>(
      `select p.first_name, p.last_name, p.phone
         from app.profiles p
         join app.users u on u.id = p.user_id and u.deleted_at is null
        where p.user_id = $1 and p.deleted_at is null
        limit 1`,
      [senderUserId],
    );
    const profile = profileRes.rows[0];
    if (!profile) return { leadId: null, created: false };

    const statusRes = await this.database.query<{ id: string }>(
      `select id from app.lead_statuses where lower(btrim(name)) = 'новый' limit 1`,
    );
    const newStatusId = statusRes.rows[0]?.id ?? null;
    const matchedPhone = this.normalizeContactPhone(profile.phone);

    const leadId = await this.database.transaction(async (client) => {
      const inserted = await client.query<{ id: string }>(
        `insert into app.leads (first_name, last_name, phone, source, status_id, created_by)
         values ($1, $2, $3, 'Через приложение', $4, $5)
         returning id`,
        [profile.first_name, profile.last_name, profile.phone, newStatusId, actor.userId],
      );
      const id = inserted.rows[0].id;
      await client.query(
        `insert into app.user_crm_links
           (user_id, entity_type, entity_id, matched_phone, link_source, created_by, confirmed_at)
         values ($1, 'lead', $2, $3, 'auto_app', $4, now())
         on conflict do nothing`,
        [senderUserId, id, matchedPhone, actor.userId],
      );
      return id;
    });

    await this.audit.record({
      actor,
      action: "crm.lead_created",
      entityType: "lead",
      entityId: leadId,
      metadata: { fromApp: true, userId: senderUserId },
    });
    return { leadId, created: true };
  }

  async countAppLeads(actor: ActorContext): Promise<{ count: number }> {
    this.policy.assertCanReadOperationalData(actor);
    const result = await this.database.query<{ count: string }>(
      `select count(*)::text as count from app.leads where source = 'Через приложение' and deleted_at is null`,
    );
    return { count: Number(result.rows[0]?.count ?? 0) };
  }
```

> Confirm `user_crm_links` has a `link_source` value `'auto_app'` allowed (check the `0016` check constraint — it lists `'manual_phone'`/`'auto_phone'`; if `'auto_app'` is NOT allowed by the constraint, use the closest allowed value, e.g. `'auto_phone'`, and report the choice). If the constraint rejects an unknown value the insert throws inside the transaction — pick an allowed value.

- [ ] **Step 4: Add the controller route**

Add to `server/src/crm/crm.controller.ts` (mirror the existing `@Get` + `@CurrentActor()` pattern):

```typescript
  @Get("leads/app-count")
  countAppLeads(@CurrentActor() actor: ActorContext) {
    return this.crm.countAppLeads(actor);
  }
```

> Place this route so it doesn't collide with a `leads/:id`-style param route — a literal `leads/app-count` before any `leads/:something` param route (NestJS matches in declaration order). Verify against the existing lead routes.

- [ ] **Step 5: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the new tests pass; full suite green.

- [ ] **Step 6: Commit**

```bash
git add server/src/crm/crm.service.ts server/src/crm/crm.controller.ts server/src/crm/crm.service.spec.ts
git commit -m "feat(crm): autoCreateLeadFromChat (idempotent, source=Через приложение, status Новый) + app-leads count (KVA-180)"
```

---

## Task 2: Fire the hook from messenger.sendMessage

**Files:**
- Modify: `server/src/messenger/messenger.module.ts`
- Modify: `server/src/messenger/messenger.service.ts`
- Modify: `server/src/messenger/messenger.service.spec.ts`

**Interfaces:**
- Consumes: `CrmService.autoCreateLeadFromChat` (Task 1), `isStaffRole` from `../common/security/actor-context`.

- [ ] **Step 1: Import CrmModule into MessengerModule**

In `server/src/messenger/messenger.module.ts`, add `CrmModule` to the `imports` array (import it from `../crm/crm.module`). Confirm `CrmModule` exports `CrmService` (it does). Confirm there is NO import cycle (CrmModule does not import MessengerModule) — if `npm run typecheck`/boot reveals a cycle, wrap with `forwardRef(() => CrmModule)` and inject with `@Inject(forwardRef(() => CrmService))`; verify first, none is expected.

- [ ] **Step 2: Inject CrmService into MessengerService**

Add `private readonly crm: CrmService` to the `MessengerService` constructor (import `CrmService` from `../crm/crm.service`).

- [ ] **Step 3: Write the failing test**

Add to `server/src/messenger/messenger.service.spec.ts` (mirror the existing sendMessage test setup; add a `crm` mock with `autoCreateLeadFromChat: jest.fn().mockResolvedValue({ leadId: "l1", created: true })` to the service construction):

```typescript
  it("auto-creates a lead when a non-staff user posts to the administration chat", async () => {
    // ... build the service so chat lookup returns { type: 'administration', ... } and actor.role is a client ...
    await service.sendMessage(clientActor, adminChatId, { content: "Здравствуйте" } as never);
    expect(crm.autoCreateLeadFromChat).toHaveBeenCalledWith(clientActor, clientActor.userId);
  });

  it("does NOT auto-create a lead for a staff sender or a non-administration chat", async () => {
    await service.sendMessage(staffActor, adminChatId, { content: "ok" } as never);
    expect(crm.autoCreateLeadFromChat).not.toHaveBeenCalled();
  });
```

> Match the existing `messenger.service.spec.ts` harness exactly (how it mocks `database`, `transaction`, `policy`, `realtime`). The key assertions: hook called for non-staff + administration; not called otherwise. Adjust the mock chat-row shape so `chat.type` is `'administration'` and the policy allows the send.

- [ ] **Step 4: Run to verify failure**

Run: `cd server && npx jest src/messenger/messenger.service.spec.ts -t "auto-create"`
Expected: FAIL — the hook isn't wired yet (`crm.autoCreateLeadFromChat` not called).

- [ ] **Step 5: Wire the hook in sendMessage**

In `MessengerService.sendMessage`, AFTER `this.realtime.publishChatEvent(chatId, "message.created", payload)` and BEFORE `return payload`, add (using the `chat` already loaded for the policy check + `isStaffRole`):

```typescript
    if (chat.type === "administration" && !isStaffRole(actor.role)) {
      void this.crm.autoCreateLeadFromChat(actor, actor.userId).catch(() => undefined);
    }
```

Add `import { isStaffRole } from "../common/security/actor-context";` if not already imported. Confirm the `chat` variable (with `.type`) is in scope at this point (it is loaded earlier for `assertCanWriteChat`); if the loaded chat object doesn't carry `.type`, read `chat.type` from wherever the policy got it (adjust to the actual variable holding the chat row).

- [ ] **Step 6: Run tests + typecheck**

Run: `cd server && npm run typecheck && npm test`
Expected: typecheck 0; the two new messenger tests pass; full suite green; the Nest app boots (MessengerModule + CrmModule wire without a cycle).

- [ ] **Step 7: Commit**

```bash
git add server/src/messenger/messenger.module.ts server/src/messenger/messenger.service.ts server/src/messenger/messenger.service.spec.ts
git commit -m "feat(messenger): auto-create lead when a non-staff user writes to admin chat (KVA-180)"
```

---

## Self-Review

- **Spec coverage (§4C C6):** auto-create lead on inbound admin-chat message from a non-staff user ✅; idempotent (skip if already lead/student) ✅; `status=Новый` + `source='Через приложение'` ✅; non-blocking (fire-and-forget) ✅; nav-badge count endpoint ✅. The Flutter nav badge UI is the deferred Flutter task.
- **Placeholder scan:** none — full TS/tests + exact commands.
- **No-cycle:** MessengerModule→CrmModule is one-way; verified at boot/typecheck (forwardRef fallback documented).
- **Non-blocking safety:** the hook is `void ... .catch(() => undefined)` after the message commits + publishes, so a CRM failure never breaks message delivery.
- **Idempotency:** the `user_crm_links` lead/student lookup guards against duplicate auto-leads on every subsequent message.

## Dependency note

This delivers C6. Remaining Epic C sub-plans: (a) the lead-board cleanup — a prod-data step (remove the 3 empty columns, migrate `Без статуса`→`Новый`, recolor `Отказ`→danger, renumber `sort_order`, mark `Успешный`/`Отказ` terminal for the «Архив»; link converted leads to students by phone+name then hide them) — done deliberately against prod data, not Docker; (b) the «Клиенты» Flutter UI (rename Лиды→Клиенты, extract a reusable Kanban board, segment Лиды/Ученики, the per-branch Ученики board reading `branch_disciplines`, drag-convert with the branch+discipline modal + Undo, the unified client card with the «Семья» (A3) + «История статусов» (A5) sections, and the column/branch-discipline config UI) — implemented + `flutter analyze`/`flutter test`, with on-device verification by the owner. The nav badge consumes `GET /crm/leads/app-count`.
