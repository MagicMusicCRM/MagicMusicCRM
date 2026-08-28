import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
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
    const realtime = { emitCrmChanged: jest.fn() };
    const service = new LeadIntakeService(
      db as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      realtime as unknown as RealtimeBus,
    );
    return { service, audit, policy, realtime };
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

  const automaticProfileRows = (phone: string | null) => [
    { rows: [] },
    { rows: [{ profile_id: "profile-1", first_name: "Иван", last_name: "Петров", phone }] },
    { rows: [] },
    { rows: [] },
  ];

  const convertedLeadRows = (
    count: string,
    unavailableCount: string,
    id: string | null,
  ) => [
    ...automaticProfileRows("+79991234567"),
    { rows: [] },
    { rows: [{ id: null, count: "0" }] },
    { rows: [{ id: "lead-phone", count: "1" }] },
    { rows: [{ id, count, unavailable_count: unavailableCount }] },
  ];

  const noPhoneLeadRows = () => [
    ...automaticProfileRows(null),
    { rows: [{ id: "status-new" }] },
    { rows: [{ id: "lead-new" }] },
    { rows: [] },
  ];

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
    expect(phoneMatchSql).toContain("having count(*) = 1");
  });

  it("resolves a contact for a chat user, preferring crm links", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ entity_type: "lead", entity_id: "lead-1" }] },
      { rows: [] },
      { rows: [] },
    ]);
    const result = await service.resolveContactForUser(actor, "user-x");
    expect(result).toEqual({ studentId: null, leadId: "lead-1" });
    expect(String(query.mock.calls[0][0])).toContain("lead.deleted_at is null");
    expect(String(query.mock.calls[0][0])).toContain("student.deleted_at is null");
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
      { rows: [] }, // per-user advisory lock
      {
        rows: [
          { profile_id: "p1", user_id: "u1", first_name: "Иван", last_name: "П", phone: "+7 999 111-22-33" },
        ],
      },
      { rows: [] }, // no active student takes precedence over the lead link
      { rows: [{ entity_id: "lead-existing" }] },
    ]);
    const result = await service.saveContactFromChat(actor, { userId: "u1", as: "lead" });
    expect(result).toEqual({ leadId: "lead-existing", created: false });
  });

  it("save-from-chat returns the existing student for a known profile", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [] }, // per-user advisory lock
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

  it("assigns the application source to a student created from an app user", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // per-user advisory lock
      {
        rows: [
          {
            profile_id: "p1",
            user_id: "u1",
            first_name: "Иван",
            last_name: null,
            phone: "+79991112233",
          },
        ],
      },
      { rows: [] }, // no existing student
      { rows: [] }, // no linked lead
      { rows: [{ id: "student-new" }] },
      { rows: [] }, // crm link
    ]);

    await expect(
      service.saveContactFromChat(actor, { userId: "u1", as: "student" }),
    ).resolves.toEqual({ studentId: "student-new", created: true });

    const insert = query.mock.calls.find((call: unknown[]) =>
      String(call[0]).includes("insert into app.students"),
    );
    expect(String(insert?.[0])).toContain("source_id");
    expect(String(insert?.[0])).toContain("canonical_name");
  });

  it("serializes chat student promotion with lead-card conversion", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [] }, // per-user lead-intake lock
      {
        rows: [
          {
            profile_id: "p1",
            user_id: "u1",
            first_name: "Иван",
            last_name: null,
            phone: null,
          },
        ],
      },
      { rows: [] }, // no student before the concurrent converter commits
      { rows: [{ entity_id: "lead-a" }] },
      { rows: [] }, // shared per-lead conversion lock
      { rows: [{ id: "student-from-other-path" }] },
    ]);

    await expect(
      service.saveContactFromChat(actor, { userId: "u1", as: "student" }),
    ).resolves.toEqual({
      studentId: "student-from-other-path",
      created: false,
    });

    const leadLock = query.mock.calls.find((call: unknown[]) =>
      String(call[0]).includes("hashtextextended"),
    );
    expect(leadLock?.[1]).toEqual(["lead-a"]);
    expect(
      query.mock.calls.some((call: unknown[]) =>
        String(call[0]).includes("insert into app.students"),
      ),
    ).toBe(false);
  });

  it("save-from-chat creates and links a new lead from a chat partner", async () => {
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // per-user advisory lock
      .mockResolvedValueOnce({
        rows: [
          { profile_id: "p1", user_id: "u1", first_name: "Иван", last_name: "П", phone: "+7 999 111-22-33" },
        ],
      })
      .mockResolvedValueOnce({ rows: [] }) // no existing link
      .mockResolvedValueOnce({ rows: [] }) // no existing student
      .mockResolvedValueOnce({ rows: [] }) // per-phone advisory lock
      .mockResolvedValueOnce({ rows: [] }) // no existing lead by phone
      .mockResolvedValueOnce({ rows: [{ id: "status-new" }] }) // «Новый» status lookup
      .mockResolvedValueOnce({ rows: [{ id: "lead-new" }] }) // insert lead
      .mockResolvedValueOnce({ rows: [] }); // insert crm link
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const { service, audit } = makeLeads({ transaction });
    const result = await service.saveContactFromChat(actor, { userId: "u1", as: "lead" });
    expect(result).toEqual({ leadId: "lead-new", created: true });
    expect(clientQuery).toHaveBeenCalledTimes(9);
    expect(String(clientQuery.mock.calls[1][0])).toContain("u.role = 'client'");
    const insertLead = clientQuery.mock.calls.find((call: unknown[]) =>
      String(call[0]).includes("insert into app.leads"),
    );
    expect(insertLead?.[1]).toContain("status-new");
    expect(String(insertLead?.[0])).toContain("source_id");
    expect(String(insertLead?.[0])).toContain("canonical_name");
    expect(String(clientQuery.mock.calls[0][0])).toContain(
      "pg_advisory_xact_lock",
    );
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.lead_created", entityId: "lead-new" }),
    );
  });

  it("audits and publishes a unique phone claim of an existing lead", async () => {
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // per-user lock
      .mockResolvedValueOnce({
        rows: [
          {
            profile_id: "p1",
            user_id: "u1",
            first_name: "Иван",
            last_name: null,
            phone: "+7 999 111-22-33",
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [] }) // no existing lead link
      .mockResolvedValueOnce({ rows: [] }) // no student
      .mockResolvedValueOnce({ rows: [] }) // phone lock
      .mockResolvedValueOnce({ rows: [{ id: "lead-existing" }] })
      .mockResolvedValueOnce({ rows: [{ entity_id: "lead-existing" }] });
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const { service, audit, realtime } = makeLeads({ transaction });

    await expect(
      service.saveContactFromChat(actor, { userId: "u1", as: "lead" }),
    ).resolves.toEqual({ leadId: "lead-existing", created: false });

    const lookupSql = String(clientQuery.mock.calls[5][0]);
    expect(lookupSql).toContain("having count(*) = 1");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.client_user_linked",
        entityType: "lead",
        entityId: "lead-existing",
      }),
    );
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith({
      entity: "lead",
      action: "updated",
      id: "lead-existing",
    });
  });

  it("never returns a phone-matched lead owned by another chat user", async () => {
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // per-user lock
      .mockResolvedValueOnce({
        rows: [
          {
            profile_id: "p2",
            user_id: "u2",
            first_name: "Анна",
            last_name: null,
            phone: "+7 999 111-22-33",
          },
        ],
      })
      .mockResolvedValueOnce({ rows: [] }) // no lead link for u2
      .mockResolvedValueOnce({ rows: [] }) // no student for u2
      .mockResolvedValueOnce({ rows: [] }) // per-phone lock
      .mockResolvedValueOnce({ rows: [{ id: "family-phone-lead" }] })
      .mockResolvedValueOnce({ rows: [] }) // link lost a race / conflicts
      .mockResolvedValueOnce({ rows: [{ user_id: "u1" }] }) // different owner
      .mockResolvedValueOnce({ rows: [{ id: "status-new" }] })
      .mockResolvedValueOnce({ rows: [{ id: "lead-u2" }] })
      .mockResolvedValueOnce({ rows: [] });
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const { service } = makeLeads({ transaction });

    await expect(
      service.saveContactFromChat(actor, { userId: "u2", as: "lead" }),
    ).resolves.toEqual({ leadId: "lead-u2", created: true });

    const phoneLookup = clientQuery.mock.calls.find((call: unknown[]) =>
      String(call[0]).includes("owner_link.user_id <> $2"),
    );
    expect(phoneLookup).toBeDefined();
    expect(
      clientQuery.mock.calls.filter((call: unknown[]) =>
        String(call[0]).includes("insert into app.leads"),
      ),
    ).toHaveLength(1);
  });

  it("autoCreateLeadFromChat is idempotent when the user is already linked", async () => {
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // advisory lock
      .mockResolvedValueOnce({
        rows: [{
          profile_id: "profile-1",
          first_name: "Иван",
          last_name: "Петров",
          phone: "+79991234567",
        }],
      })
      .mockResolvedValueOnce({ rows: [] }) // no student identity
      .mockResolvedValueOnce({ rows: [{ entity_id: "lead-existing" }] });
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const { service, audit } = makeLeads({ transaction });
    const result = await service.autoCreateLeadFromChat(actor, "user-1");
    expect(result).toEqual({ leadId: "lead-existing", created: false });
    const lockSql = String(clientQuery.mock.calls[0][0]);
    expect(lockSql).toContain("pg_advisory_xact_lock");
    expect(clientQuery.mock.calls[0][1]).toEqual(["lead-intake:user-1"]);
    const allSql = clientQuery.mock.calls.map((c: unknown[]) => String(c[0])).join("\n");
    expect(allSql).toContain("lead.deleted_at is null");
    expect(allSql).toContain("s.profile_id = $2");
    expect(allSql).not.toContain("insert into app.leads");
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("autoCreateLeadFromChat creates a lead and link when user is not yet linked", async () => {
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // advisory lock
      .mockResolvedValueOnce({ rows: [{ profile_id: "profile-1", first_name: "Иван", last_name: "Петров", phone: "+79991234567" }] })
      .mockResolvedValueOnce({ rows: [] }) // no direct/profile student
      .mockResolvedValueOnce({ rows: [] }) // no existing lead link
      .mockResolvedValueOnce({ rows: [] }) // advisory phone lock
      .mockResolvedValueOnce({ rows: [{ id: null, count: "0" }] })
      .mockResolvedValueOnce({ rows: [{ id: null, count: "0" }] })
      .mockResolvedValueOnce({ rows: [{ id: "status-new" }] })
      .mockResolvedValueOnce({ rows: [{ id: "lead-new" }] })
      .mockResolvedValueOnce({ rows: [] });
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const outsideQuery = jest.fn();
    const { service, audit, realtime } = makeLeads({
      query: outsideQuery,
      transaction,
    });
    const result = await service.autoCreateLeadFromChat(actor, "user-1");
    expect(result).toEqual({ leadId: "lead-new", created: true });
    expect(transaction).toHaveBeenCalledTimes(1);
    expect(outsideQuery).not.toHaveBeenCalled();
    expect(clientQuery).toHaveBeenCalledTimes(10);
    expect(String(clientQuery.mock.calls[0][0])).toContain("pg_advisory_xact_lock");
    expect(clientQuery.mock.calls[0][1]).toEqual(["lead-intake:user-1"]);
    expect(clientQuery.mock.calls[4][1]).toEqual(["lead-phone:+79991234567"]);
    expect(String(clientQuery.mock.calls[4][0])).toContain("pg_advisory_xact_lock");
    expect(String(clientQuery.mock.calls[5][0])).toContain("from app.students student");
    expect(String(clientQuery.mock.calls[6][0])).toContain("from app.leads lead");
    const statusCall = clientQuery.mock.calls.find((c: unknown[]) => String(c[0]).includes("новый"));
    expect(statusCall).toBeDefined();
    expect(String(statusCall![0])).toContain("'новый'");
    const insertCall = clientQuery.mock.calls.find((c: unknown[]) => String(c[0]).includes("insert into app.leads"));
    expect(insertCall).toBeDefined();
    expect(String(insertCall![0])).toContain("source_id");
    expect(String(insertCall![0])).toContain("canonical_name");
    const linkCall = clientQuery.mock.calls.find((c: unknown[]) => String(c[0]).includes("insert into app.user_crm_links"));
    expect(linkCall).toBeDefined();
    expect(String(linkCall![0])).toContain("'auto_phone'");
    expect(audit.record).toHaveBeenCalledWith({
      actor,
      action: "crm.lead_created",
      entityType: "lead",
      entityId: "lead-new",
      metadata: { fromApp: true, userId: "user-1", intakeTrigger: "chat" },
    });
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith({ entity: "lead", action: "created", id: "lead-new" });
  });

  it("autoCreateLeadFromChat returns {leadId:null, created:false} when user has no profile", async () => {
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // advisory lock
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

  it("prefers an existing Student identity without evaluating an existing Lead", async () => {
    const clientQuery = jest.fn(async (sql: string) => {
      const text = String(sql);
      if (text.includes("from app.profiles p"))
        return { rows: [{ profile_id: "profile-1", first_name: "Иван", last_name: "Петров", phone: "+79991234567" }] };
      if (text.includes("from app.students s"))
        return { rows: [{ id: "student-existing" }] };
      if (text.includes("link.entity_type = 'lead'"))
        return { rows: [{ entity_id: "lead-would-win-if-queried" }] };
      return { rows: [] };
    });
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const { service, audit, realtime } = makeLeads({ transaction });

    await expect(
      service.autoCreateLeadFromChat(actor, "user-student"),
    ).resolves.toEqual({ leadId: null, created: false });

    const allSql = clientQuery.mock.calls.map((call: unknown[]) => String(call[0])).join("\n");
    expect(allSql).toContain("s.profile_id = $2");
    expect(
      clientQuery.mock.calls.some((call: unknown[]) =>
        String(call[0]).includes("link.entity_type = 'lead'"),
      ),
    ).toBe(false);
    expect(allSql).not.toContain("insert into app.leads");
    expect(audit.record).not.toHaveBeenCalled();
    expect(realtime.emitCrmChanged).not.toHaveBeenCalled();
  });

  it("autoCreateLeadFromChat links one matching student and never evaluates leads", async () => {
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // user lock
      .mockResolvedValueOnce({
        rows: [{
          profile_id: "profile-1",
          first_name: "Иван",
          last_name: "Петров",
          phone: "+79991234567",
        }],
      })
      .mockResolvedValueOnce({ rows: [] }) // no existing student identity
      .mockResolvedValueOnce({ rows: [] }) // no existing lead link
      .mockResolvedValueOnce({ rows: [] }) // phone lock
      .mockResolvedValueOnce({ rows: [{ id: "student-phone", count: "1" }] })
      .mockResolvedValueOnce({ rows: [{ entity_id: "student-phone" }] })
      .mockResolvedValueOnce({
        rows: [{ id: "student-phone" }],
        rowCount: 1,
      }); // merge + assign Student profile
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const { service, audit, realtime } = makeLeads({ transaction });

    await expect(
      service.autoCreateLeadFromChat(actor, "user-student", "onboarding"),
    ).resolves.toEqual({ leadId: null, created: false });

    const allSql = clientQuery.mock.calls
      .map((call: unknown[]) => String(call[0]))
      .join("\n");
    expect(allSql).toContain("profile.phone_normalized = $1");
    expect(allSql).toContain("update app.students");
    expect(allSql).not.toContain("from app.leads lead\n              where lead.phone_normalized");
    expect(allSql).not.toContain("insert into app.leads");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.client_user_linked",
        entityType: "student",
        entityId: "student-phone",
        metadata: expect.objectContaining({ intakeTrigger: "onboarding" }),
      }),
    );
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith({
      entity: "student",
      action: "updated",
      id: "student-phone",
    });
  });

  it("autoCreateLeadFromChat leaves multiple student matches for manual review", async () => {
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // user lock
      .mockResolvedValueOnce({
        rows: [{
          profile_id: "profile-1",
          first_name: "Иван",
          last_name: "Петров",
          phone: "+79991234567",
        }],
      })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] }) // phone lock
      .mockResolvedValueOnce({ rows: [{ id: "student-a", count: "2" }] });
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const { service, audit, realtime } = makeLeads({ transaction });

    await expect(
      service.autoCreateLeadFromChat(actor, "user-ambiguous", "onboarding"),
    ).resolves.toEqual({ leadId: null, created: false });

    const allSql = clientQuery.mock.calls
      .map((call: unknown[]) => String(call[0]))
      .join("\n");
    expect(allSql).not.toContain("insert into app.user_crm_links");
    expect(allSql).not.toContain("insert into app.leads");
    expect(audit.record).not.toHaveBeenCalled();
    expect(realtime.emitCrmChanged).not.toHaveBeenCalled();
  });

  it("autoCreateLeadFromChat links one matching lead instead of creating a duplicate", async () => {
    const clientQuery = jest
      .fn()
      .mockResolvedValueOnce({ rows: [] }) // user lock
      .mockResolvedValueOnce({
        rows: [{
          profile_id: "profile-1",
          first_name: "Иван",
          last_name: "Петров",
          phone: "+79991234567",
        }],
      })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] }) // phone lock
      .mockResolvedValueOnce({ rows: [{ id: null, count: "0" }] })
      .mockResolvedValueOnce({ rows: [{ id: "lead-phone", count: "1" }] })
      .mockResolvedValueOnce({
        rows: [{ id: null, count: "0", unavailable_count: "0" }],
      })
      .mockResolvedValueOnce({ rows: [{ entity_id: "lead-phone" }] });
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: clientQuery }),
    );
    const { service, audit } = makeLeads({ transaction });

    await expect(
      service.autoCreateLeadFromChat(actor, "user-lead", "onboarding"),
    ).resolves.toEqual({ leadId: "lead-phone", created: false });

    const allSql = clientQuery.mock.calls
      .map((call: unknown[]) => String(call[0]))
      .join("\n");
    expect(allSql).not.toContain("insert into app.leads");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.client_user_linked",
        entityType: "lead",
        entityId: "lead-phone",
      }),
    );
  });

  it("links a unique converted Student instead of its matching Lead", async () => {
    const { service, query, audit, realtime } = createServiceWithQueryResults([
      ...convertedLeadRows("1", "0", "student-converted"),
      { rows: [{ entity_id: "student-converted" }] },
      { rows: [{ id: "student-converted" }] },
    ]);
    await expect(
      service.autoCreateLeadFromChat(actor, "user-converted", "onboarding"),
    ).resolves.toEqual({ leadId: null, created: false });
    const studentLink = query.mock.calls.find((call: unknown[]) =>
      String(call[0]).includes("values ($1, 'student'"),
    );
    expect(studentLink?.[1]).toEqual(["user-converted", "student-converted", "+79991234567", "manager-a"]);
    expect(query.mock.calls.some((call: unknown[]) => String(call[0]).includes("update app.students"))).toBe(true);
    expect(
      query.mock.calls.some((call: unknown[]) => String(call[0]).includes("values ($1, 'lead'")),
    ).toBe(false);
    expect(audit.record).toHaveBeenCalledWith({
      actor,
      action: "crm.client_user_linked",
      entityType: "student",
      entityId: "student-converted",
      metadata: { fromApp: true, userId: "user-converted", intakeTrigger: "onboarding" },
    });
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith({
      entity: "student", action: "updated", id: "student-converted",
    });
  });

  it.each([
    ["leaves an ambiguous converted Student set for manual review", "2", "0", { leadId: null, created: false }],
    ["leaves an unavailable converted Student identity for manual review", "1", "1", { leadId: null, created: false }],
  ])("%s", async (_name, count, unavailableCount, expected) => {
    const { service, query, audit, realtime } = createServiceWithQueryResults(
      convertedLeadRows(count as string, unavailableCount as string, "student-converted"),
    );
    await expect(
      service.autoCreateLeadFromChat(actor, "user-review"),
    ).resolves.toEqual(expected);
    expect(query.mock.calls.some((call: unknown[]) => String(call[0]).includes("insert into"))).toBe(false);
    expect(audit.record).not.toHaveBeenCalled();
    expect(realtime.emitCrmChanged).not.toHaveBeenCalled();
  });

  it("treats a concurrent Student link claim as manual review", async () => {
    const { service, query, audit, realtime } = createServiceWithQueryResults([
      ...automaticProfileRows("+79991234567"),
      { rows: [] },
      { rows: [{ id: "student-phone", count: "1" }] },
      { rows: [] },
    ]);
    await expect(
      service.autoCreateLeadFromChat(actor, "user-race"),
    ).resolves.toEqual({ leadId: null, created: false });
    const sql = query.mock.calls.map((call: unknown[]) => String(call[0]));
    expect(sql.some((text: string) => text.includes("update app.students"))).toBe(false);
    expect(
      sql.some((text: string) => text.includes("with candidates as") && text.includes("from app.leads lead")),
    ).toBe(false);
    expect(audit.record).not.toHaveBeenCalled();
    expect(realtime.emitCrmChanged).not.toHaveBeenCalled();
  });

  it("throws the exact conflict when Student profile assignment loses its race", async () => {
    const { service, audit, realtime } = createServiceWithQueryResults([
      ...automaticProfileRows("+79991234567"),
      { rows: [] },
      { rows: [{ id: "student-phone", count: "1" }] },
      { rows: [{ entity_id: "student-phone" }] },
      { rows: [] },
    ]);
    await expect(
      service.autoCreateLeadFromChat(actor, "user-conflict"),
    ).rejects.toMatchObject({
      name: "ConflictException",
      message: "Карточка ученика изменилась во время привязки. Повторите попытку.",
    });
    expect(audit.record).not.toHaveBeenCalled();
    expect(realtime.emitCrmChanged).not.toHaveBeenCalled();
  });

  it("creates an app Lead without taking a phone lock when the profile has no phone", async () => {
    const { service, query, audit, realtime } = createServiceWithQueryResults(noPhoneLeadRows());
    await expect(
      service.autoCreateLeadFromChat(actor, "user-no-phone"),
    ).resolves.toEqual({ leadId: "lead-new", created: true });
    expect(
      query.mock.calls.some((call: unknown[]) =>
        String((call[1] as unknown[] | undefined)?.[0]).startsWith("lead-phone:"),
      ),
    ).toBe(false);
    const sql = query.mock.calls.map((call: unknown[]) => String(call[0]));
    expect(sql.some((text: string) => text.includes("with candidates as"))).toBe(false);
    const link = query.mock.calls.find((call: unknown[]) =>
      String(call[0]).includes("insert into app.user_crm_links"),
    );
    expect(link?.[1]).toEqual(["user-no-phone", "lead-new", null, "manager-a"]);
    expect(audit.record).toHaveBeenCalledWith({
      actor,
      action: "crm.lead_created",
      entityType: "lead",
      entityId: "lead-new",
      metadata: { fromApp: true, userId: "user-no-phone", intakeTrigger: "chat" },
    });
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith({ entity: "lead", action: "created", id: "lead-new" });
  });

  it("commits identity before awaiting audit and delays realtime until audit settles", async () => {
    const events: string[] = [];
    const { service, query, transaction, audit, realtime } =
      createServiceWithQueryResults(noPhoneLeadRows());
    transaction.mockImplementation(async (work) => {
      events.push("transaction:start");
      const result = await work({ query });
      events.push("transaction:commit");
      return result;
    });
    let resolveAudit!: () => void;
    let signalAudit!: () => void;
    const auditStarted = new Promise<void>((resolve) => (signalAudit = resolve));
    const deferredAudit = new Promise<void>((resolve) => (resolveAudit = resolve));
    audit.record.mockImplementation(() => {
      events.push("audit:start");
      signalAudit();
      return deferredAudit;
    });
    realtime.emitCrmChanged.mockImplementation(() =>
      events.push("realtime:lead:created"),
    );
    const pending = service.autoCreateLeadFromChat(actor, "user-deferred");
    await auditStarted;
    expect(events).toEqual(["transaction:start", "transaction:commit", "audit:start"]);
    expect(realtime.emitCrmChanged).not.toHaveBeenCalled();
    resolveAudit();
    await expect(pending).resolves.toEqual({ leadId: "lead-new", created: true });
    expect(events).toEqual(["transaction:start", "transaction:commit", "audit:start", "realtime:lead:created"]);
  });

  it("continues realtime publication when post-commit audit fails", async () => {
    const { service, audit, realtime } = createServiceWithQueryResults(noPhoneLeadRows());
    audit.record.mockRejectedValueOnce(new Error("audit unavailable"));
    await expect(
      service.autoCreateLeadFromChat(actor, "user-audit-failure"),
    ).resolves.toEqual({ leadId: "lead-new", created: true });
    expect(audit.record).toHaveBeenCalledTimes(1);
    expect(audit.record).toHaveBeenCalledWith({
      actor,
      action: "crm.lead_created",
      entityType: "lead",
      entityId: "lead-new",
      metadata: { fromApp: true, userId: "user-audit-failure", intakeTrigger: "chat" },
    });
    expect(realtime.emitCrmChanged).toHaveBeenCalledWith({ entity: "lead", action: "created", id: "lead-new" });
  });

  it("counts app-sourced leads", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      { rows: [{ count: "7" }] },
    ]);
    const result = await service.countAppLeads(actor);
    expect(result).toEqual({ count: 7 });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("canonical_name");
  });

});
