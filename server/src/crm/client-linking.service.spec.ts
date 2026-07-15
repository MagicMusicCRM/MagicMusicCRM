import { BadRequestException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { ClientLinkingService } from "./client-linking.service";

describe("ClientLinkingService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const buildDeps = () => {
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
    };
    return { audit, policy };
  };

  const construct = (query: jest.Mock, deps: ReturnType<typeof buildDeps>) =>
    new ClientLinkingService(
      { query } as unknown as DatabaseService,
      deps.policy as unknown as CrmPolicy,
      deps.audit as unknown as AuditService,
    );

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const deps = buildDeps();
    return { service: construct(query, deps), query, ...deps };
  };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const deps = buildDeps();
    return { service: construct(query, deps), query, ...deps };
  };

  it("getClientLinkedUsers returns linked app users for a lead", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      {
        rows: [
          {
            user_id: "user-1",
            name: "Анна Иванова",
            phone: "+79991234567",
            link_source: "manual_phone",
          },
        ],
      },
    ]);

    await expect(
      service.getClientLinkedUsers(actor, "lead", "lead-a"),
    ).resolves.toEqual({
      items: [
        {
          userId: "user-1",
          name: "Анна Иванова",
          phone: "+79991234567",
          linkSource: "manual_phone",
        },
      ],
    });

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("app.user_crm_links");
    expect(sql).toContain("is_app_account");
    expect(query.mock.calls[0][1]).toEqual(["lead", "lead-a"]);
  });

  it("getClientLinkedUsers merges the student's own app account", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      // linked-users query: one explicit link
      {
        rows: [
          {
            user_id: "user-link",
            name: "Папа",
            phone: "+79990000001",
            link_source: "manual_phone",
          },
        ],
      },
      // student's own account query
      {
        rows: [
          {
            user_id: "user-self",
            name: "Сын",
            phone: "+79990000002",
          },
        ],
      },
    ]);

    const result = await service.getClientLinkedUsers(
      actor,
      "student",
      "student-a",
    );

    expect(result.items).toHaveLength(2);
    expect(result.items).toContainEqual({
      userId: "user-link",
      name: "Папа",
      phone: "+79990000001",
      linkSource: "manual_phone",
    });
    expect(result.items).toContainEqual({
      userId: "user-self",
      name: "Сын",
      phone: "+79990000002",
      linkSource: "self",
    });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    // second query resolves the student's own profile account
    const selfSql = String(query.mock.calls[1][0]);
    expect(selfSql).toContain("app.students");
    expect(selfSql).toContain("profile_id");
    expect(query.mock.calls[1][1]).toEqual(["student-a"]);
  });

  it("getClientLinkedUsers does not duplicate the self account when already linked", async () => {
    const { service } = createServiceWithQueryResults([
      {
        rows: [
          {
            user_id: "user-self",
            name: "Сын",
            phone: "+79990000002",
            link_source: "auto_phone",
          },
        ],
      },
      {
        rows: [
          {
            user_id: "user-self",
            name: "Сын",
            phone: "+79990000002",
          },
        ],
      },
    ]);

    const result = await service.getClientLinkedUsers(
      actor,
      "student",
      "student-a",
    );
    expect(result.items).toHaveLength(1);
    expect(result.items[0]).toEqual({
      userId: "user-self",
      name: "Сын",
      phone: "+79990000002",
      linkSource: "auto_phone",
    });
  });

  it("getClientLinkedUsers rejects an invalid entityType", async () => {
    const { service } = createService([]);
    await expect(
      service.getClientLinkedUsers(actor, "teacher", "x"),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("listClientUserCandidates matches app users by normalized phone", async () => {
    const { service, query, policy } = createServiceWithQueryResults([
      // client phone lookup
      { rows: [{ phone: "8 (999) 123-45-67" }] },
      // candidate users
      {
        rows: [
          {
            user_id: "user-2",
            name: "Пётр Петров",
            phone: "+79991234567",
            email: "petr@example.com",
          },
        ],
      },
    ]);

    await expect(
      service.listClientUserCandidates(actor, "lead", "lead-a"),
    ).resolves.toEqual({
      items: [
        {
          userId: "user-2",
          name: "Пётр Петров",
          phone: "+79991234567",
          email: "petr@example.com",
        },
      ],
    });

    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    const candidatesSql = String(query.mock.calls[1][0]);
    expect(candidatesSql).toContain("is_app_account = true");
    expect(candidatesSql).toContain("limit 50");
    expect(candidatesSql).toContain("not exists");
    // matched against the client's normalized +7 phone, excluding this entity
    expect(query.mock.calls[1][1]).toEqual([
      "+79991234567",
      "lead",
      "lead-a",
    ]);
  });

  it("listClientUserCandidates returns empty when client phone is not normalizable", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ phone: "не телефон" }] },
    ]);

    await expect(
      service.listClientUserCandidates(actor, "lead", "lead-a"),
    ).resolves.toEqual({ items: [] });
    // only the phone lookup ran; no candidate query
    expect(query).toHaveBeenCalledTimes(1);
  });

  it("listClientUserCandidates rejects an invalid entityType", async () => {
    const { service } = createService([]);
    await expect(
      service.listClientUserCandidates(actor, "staff", "x"),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("linkUserToClient inserts a manual link, audits, and returns linked users", async () => {
    const { service, query, audit, policy } = createServiceWithQueryResults([
      // validate user exists + is app account
      { rows: [{ id: "user-3" }] },
      // client phone lookup
      { rows: [{ phone: "+7 999 123 45 67" }] },
      // insert into user_crm_links
      { rows: [] },
      // getClientLinkedUsers → linked users query
      {
        rows: [
          {
            user_id: "user-3",
            name: "Новый Клиент",
            phone: "+79991234567",
            link_source: "manual_phone",
          },
        ],
      },
    ]);

    await expect(
      service.linkUserToClient(actor, "lead", "lead-a", "user-3"),
    ).resolves.toEqual({
      items: [
        {
          userId: "user-3",
          name: "Новый Клиент",
          phone: "+79991234567",
          linkSource: "manual_phone",
        },
      ],
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);

    const insertSql = String(query.mock.calls[2][0]);
    expect(insertSql).toContain("insert into app.user_crm_links");
    expect(insertSql).toContain(
      "on conflict (entity_type, entity_id) where deleted_at is null",
    );
    expect(insertSql).toContain("do update set");
    expect(insertSql).toContain("user_id = excluded.user_id");
    expect(insertSql).toContain("link_source = 'manual_phone'");
    expect(insertSql).toContain("deleted_at = null");
    expect(query.mock.calls[2][1]).toEqual([
      "user-3",
      "lead",
      "lead-a",
      "+79991234567",
      "manager-a",
    ]);

    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.client_user_linked",
        entityType: "lead",
        entityId: "lead-a",
        metadata: { userId: "user-3" },
      }),
    );
  });

  it("linkUserToClient rejects when the user is not an app account", async () => {
    const { service, query } = createServiceWithQueryResults([{ rows: [] }]);
    await expect(
      service.linkUserToClient(actor, "lead", "lead-a", "ghost"),
    ).rejects.toBeInstanceOf(BadRequestException);
    // validation query ran; no insert
    expect(query).toHaveBeenCalledTimes(1);
  });

  it("linkUserToClient rejects an invalid entityType", async () => {
    const { service } = createService([]);
    await expect(
      service.linkUserToClient(actor, "teacher", "x", "user-3"),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
