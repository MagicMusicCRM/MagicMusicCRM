import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { NotificationsService } from "../notifications/notifications.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { LeadIntakeService } from "./lead-intake.service";

describe("LeadIntakeService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const makeLeads = (db: { query?: jest.Mock; transaction?: jest.Mock }) => {
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanWriteCrm: jest.fn(),
      assertCanReadOperationalData: jest.fn(),
    };
    const notifications = {
      notifyNewLead: jest.fn().mockResolvedValue(undefined),
    };
    const realtime = { emitCrmChanged: () => undefined };
    const service = new LeadIntakeService(
      db as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      notifications as unknown as NotificationsService,
      realtime as unknown as RealtimeBus,
    );
    return { service, audit, policy, notifications };
  };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    );
    return { query, transaction, ...makeLeads({ query, transaction }) };
  };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    );
    return { query, transaction, ...makeLeads({ query, transaction }) };
  };

  it("resolves a lead chat user via an explicit crm link", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [{ id: "lead-a", name: "Иван", phone: "+7 999 000-00-00" }] },
      { rows: [{ user_id: "user-x" }] },
    ]);
    const result = await service.resolveLeadChatUser(actor, "lead-a");
    expect(result).toEqual({ userId: "user-x", name: "Иван" });
  });

  it("resolves a lead chat user by matching phone when no link exists", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [{ id: "lead-a", name: "Иван", phone: "+7 (999) 000-00-00" }] },
      { rows: [] },
      { rows: [{ user_id: "user-phone" }] },
    ]);
    const result = await service.resolveLeadChatUser(actor, "lead-a");
    expect(result.userId).toBe("user-phone");
  });

  it("returns null lead chat user when nothing matches", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [{ id: "lead-a", name: "Иван", phone: null }] },
      { rows: [] },
    ]);
    const result = await service.resolveLeadChatUser(actor, "lead-a");
    expect(result.userId).toBeNull();
  });

  it("resolveLeadChatUser phone-lookup SQL uses +7 canonical expression (regression KVA-184)", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ id: "lead-a", name: "Иван Петров", phone: "89091234567" }] },
      { rows: [] },
      { rows: [] },
    ]);

    await service.resolveLeadChatUser(actor, "lead-a");

    const phoneMatchSql: string = query.mock.calls[2][0];
    const phoneMatchParam: string = query.mock.calls[2][1][0];
    expect(phoneMatchParam).toBe("+79091234567");
    expect(phoneMatchSql).toContain("'+7'");
    expect(phoneMatchSql).toContain("case");
  });

  it("resolves a contact for a chat user, preferring crm links", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [{ entity_type: "lead", entity_id: "lead-1" }] },
      { rows: [] },
    ]);
    const result = await service.resolveContactForUser(actor, "user-x");
    expect(result).toEqual({ studentId: null, leadId: "lead-1" });
  });

  it("falls back to an owned student when a chat user has no crm links", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [] },
      { rows: [{ id: "student-9" }] },
    ]);
    const result = await service.resolveContactForUser(actor, "user-x");
    expect(result).toEqual({ studentId: "student-9", leadId: null });
  });

  it("save-from-chat returns the existing lead when already linked", async () => {
    const { service } = createServiceWithQueryResults([
      {
        rows: [
          { profile_id: "p1", user_id: "u1", first_name: "Иван", last_name: "П", phone: "+7 999 111-22-33" },
        ],
      },
      { rows: [{ entity_id: "lead-existing" }] },
    ]);
    const result = await service.saveContactFromChat(actor, { userId: "u1", as: "lead" });
    expect(result).toEqual({ leadId: "lead-existing", created: false });
  });

  it("save-from-chat returns the existing student for a known profile", async () => {
    const { service } = createServiceWithQueryResults([
      {
        rows: [
          { profile_id: "p1", user_id: "u1", first_name: "Иван", last_name: null, phone: null },
        ],
      },
      { rows: [{ id: "student-existing" }] },
    ]);
    const result = await service.saveContactFromChat(actor, { userId: "u1", as: "student" });
    expect(result).toEqual({ studentId: "student-existing", created: false });
  });

  it("save-from-chat creates and links a new lead from a chat partner", async () => {
    const query = jest
      .fn()
      .mockResolvedValueOnce({
        rows: [
          { profile_id: "p1", user_id: "u1", first_name: "Иван", last_name: "П", phone: "+7 999 111-22-33" },
        ],
      })
      .mockResolvedValueOnce({ rows: [] }) // no existing link
      .mockResolvedValueOnce({ rows: [{ id: "status-new" }] }); // «Новый» status lookup (KVA-175)
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [{ id: "lead-new" }] }) // insert lead
      .mockResolvedValueOnce({ rows: [] }); // insert crm link
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const { service, audit } = makeLeads({ query, transaction });
    const result = await service.saveContactFromChat(actor, { userId: "u1", as: "lead" });
    expect(result).toEqual({ leadId: "lead-new", created: true });
    expect(clientQuery).toHaveBeenCalledTimes(2);
    expect(clientQuery.mock.calls[0][1]).toContain("status-new");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.lead_created", entityId: "lead-new" }),
    );
  });

  it("autoCreateLeadFromChat is idempotent when the user is already linked", async () => {
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // advisory lock
      .mockResolvedValueOnce({ rows: [{ entity_type: "lead", entity_id: "lead-existing" }] });
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const { service, audit } = makeLeads({ transaction });
    const result = await service.autoCreateLeadFromChat(actor, "user-1");
    expect(result).toEqual({ leadId: "lead-existing", created: false });
    const lockSql = String(clientQuery.mock.calls[0][0]);
    expect(lockSql).toContain("pg_advisory_xact_lock");
    const allSql = clientQuery.mock.calls.map((c: unknown[]) => String(c[0])).join("\n");
    expect(allSql).not.toContain("insert into app.leads");
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("autoCreateLeadFromChat creates a lead and link when user is not yet linked", async () => {
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // advisory lock
      .mockResolvedValueOnce({ rows: [] }) // user_crm_links → not linked
      .mockResolvedValueOnce({ rows: [{ first_name: "Иван", last_name: "Петров", phone: "+79991234567" }] })
      .mockResolvedValueOnce({ rows: [{ id: "status-new" }] })
      .mockResolvedValueOnce({ rows: [{ id: "lead-new" }] })
      .mockResolvedValueOnce({ rows: [] });
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const { service, audit } = makeLeads({ transaction });
    const result = await service.autoCreateLeadFromChat(actor, "user-1");
    expect(result).toEqual({ leadId: "lead-new", created: true });
    expect(clientQuery).toHaveBeenCalledTimes(6);
    expect(String(clientQuery.mock.calls[0][0])).toContain("pg_advisory_xact_lock");
    const statusCall = clientQuery.mock.calls.find((c: unknown[]) => String(c[0]).includes("новый"));
    expect(statusCall).toBeDefined();
    expect(String(statusCall![0])).toContain("'новый'");
    const insertCall = clientQuery.mock.calls.find((c: unknown[]) => String(c[0]).includes("insert into app.leads"));
    expect(insertCall).toBeDefined();
    expect(String(insertCall![0])).toContain("'Через приложение'");
    const linkCall = clientQuery.mock.calls.find((c: unknown[]) => String(c[0]).includes("insert into app.user_crm_links"));
    expect(linkCall).toBeDefined();
    expect(String(linkCall![0])).toContain("'auto_phone'");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.lead_created",
        entityType: "lead",
        entityId: "lead-new",
        metadata: expect.objectContaining({ fromApp: true, userId: "user-1" }),
      }),
    );
  });

  it("autoCreateLeadFromChat returns {leadId:null, created:false} when user has no profile", async () => {
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // advisory lock
      .mockResolvedValueOnce({ rows: [] }) // user_crm_links → not linked
      .mockResolvedValueOnce({ rows: [] }); // profile → missing
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const { service, audit } = makeLeads({ transaction });
    const result = await service.autoCreateLeadFromChat(actor, "user-no-profile");
    expect(result).toEqual({ leadId: null, created: false });
    const allSql = clientQuery.mock.calls.map((c: unknown[]) => String(c[0])).join("\n");
    expect(allSql).not.toContain("insert into app.leads");
    expect(audit.record).not.toHaveBeenCalled();
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

  describe("createLeadFromSiteWebhook", () => {
    it("webhook lead normalizes phone, stamps «Новый» and notifies staff", async () => {
      const { service, query, notifications, audit } = createServiceWithQueryResults([
        { rows: [{ id: "status-new" }] }, // lead_statuses «Новый»
        { rows: [{ id: "lead-web" }] }, // insert into app.leads
      ]);
      const result = await service.createLeadFromSiteWebhook({
        name: "Мария",
        phone: "8 (999) 123-45-67",
        discipline: "Вокал",
        comment: "Хочу пробное занятие",
      });
      expect(result).toEqual({ leadId: "lead-web" });
      const insert = query.mock.calls.find((c) =>
        String(c[0]).includes("insert into app.leads"),
      );
      expect(insert![1]).toEqual([
        "Мария",
        "+79991234567",
        null,
        "site",
        "Дисциплина: Вокал\nХочу пробное занятие",
        "status-new",
      ]);
      expect(notifications.notifyNewLead).toHaveBeenCalledWith({
        leadId: "lead-web",
        name: "Мария",
        source: "site",
      });
      expect(audit.record).toHaveBeenCalledWith(
        expect.objectContaining({
          action: "crm.lead_created",
          entityType: "lead",
          entityId: "lead-web",
          metadata: expect.objectContaining({ fromSiteWebhook: true }),
        }),
      );
    });
  });
});
