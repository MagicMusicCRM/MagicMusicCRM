import { NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { BlacklistService } from "./blacklist.service";
import { isUserBlacklisted } from "./blacklist";
import { CrmPolicy } from "./crm.policy";

describe("BlacklistService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const database = { query };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = { assertCanWriteCrm: jest.fn() };
    const realtime = { emitCrmChanged: jest.fn() };
    const service = new BlacklistService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
      realtime as unknown as RealtimeBus,
    );
    return { service, query, audit, policy, realtime };
  };

  const banned = {
    id: "student-a",
    blacklisted: true,
    blacklisted_at: "2026-07-17T10:00:00.000Z",
    blacklisted_by: "manager-a",
    blacklist_reason: "Оскорблял администратора в чате",
  };

  it("bans a student with an author, a time and a reason", async () => {
    // ✔ Решение владельца 17.07: чёрный список — это бан, а не галочка.
    const { service, query, policy } = createService([banned]);

    await expect(
      service.setStudentBlacklist(actor, "student-a", {
        blacklisted: true,
        reason: " Оскорблял администратора в чате ",
      }),
    ).resolves.toEqual({
      id: "student-a",
      blacklisted: true,
      blacklistedAt: "2026-07-17T10:00:00.000Z",
      blacklistedBy: "manager-a",
      blacklistReason: "Оскорблял администратора в чате",
    });

    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][1]).toEqual([
      "student-a",
      true,
      "manager-a",
      // Причина обрезана: пробелы по краям — не причина.
      "Оскорблял администратора в чате",
    ]);
    expect(String(query.mock.calls[0][0])).toContain("update app.students");
  });

  it("records the ban in the audit as a ban, not as a card edit", async () => {
    // Модерационное действие обязано быть узнаваемо в аудите: иначе «кто его
    // забанил» пришлось бы искать diff'ом по полям карточки.
    const { service, audit } = createService([banned]);

    await service.setStudentBlacklist(actor, "student-a", {
      blacklisted: true,
      reason: "спам",
    });

    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.client_blacklisted",
        entityType: "student",
        entityId: "student-a",
        metadata: { reason: "спам" },
      }),
    );
  });

  it("clears the author and the reason when the ban is lifted", async () => {
    // «Снят, но причина всё ещё висит» читалось бы как «всё ещё в списке».
    const { service, query, audit } = createService([
      {
        id: "student-a",
        blacklisted: false,
        blacklisted_at: null,
        blacklisted_by: null,
        blacklist_reason: null,
      },
    ]);

    await expect(
      service.setStudentBlacklist(actor, "student-a", { blacklisted: false }),
    ).resolves.toEqual({
      id: "student-a",
      blacklisted: false,
      blacklistedAt: null,
      blacklistedBy: null,
      blacklistReason: null,
    });

    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("blacklisted_at = case when $2 then now() else null end");
    expect(sql).toContain("blacklist_reason = case when $2 then $4 else null end");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.client_unblacklisted" }),
    );
  });

  it("bans a lead too — the app account may hang off either half", async () => {
    const { service, query } = createService([{ ...banned, id: "lead-a" }]);

    await service.setLeadBlacklist(actor, "lead-a", { blacklisted: true });

    expect(String(query.mock.calls[0][0])).toContain("update app.leads");
  });

  it("does not report success for a record that is not there", async () => {
    const { service, audit } = createService([]);

    await expect(
      service.setStudentBlacklist(actor, "ghost", { blacklisted: true }),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(audit.record).not.toHaveBeenCalled();
  });
});

describe("isUserBlacklisted", () => {
  const withRows = (rows: Record<string, unknown>[]) => {
    const query = jest.fn().mockResolvedValue({ rows });
    return { database: { query } as unknown as DatabaseService, query };
  };

  it("says yes when any linked record is blacklisted", async () => {
    const { database } = withRows([{ blacklisted: true }]);
    await expect(isUserBlacklisted(database, "client-a")).resolves.toBe(true);
  });

  it("says no for a client with nothing against them", async () => {
    const { database } = withRows([{ blacklisted: false }]);
    await expect(isUserBlacklisted(database, "client-a")).resolves.toBe(false);
  });

  it("looks at every way an account attaches to a client record", async () => {
    // Строки здесь замоканы, SQL не исполняется — поэтому сам запрос
    // проверяем текстом. Пропусти любой из трёх путей, и бан обходился бы
    // сменой половины карточки.
    const { database, query } = withRows([{ blacklisted: false }]);
    await isUserBlacklisted(database, "client-a");
    const sql = String(query.mock.calls[0][0]);

    // 1. Ученик со своим профилем.
    expect(sql).toContain("join app.profiles p on p.id = s.profile_id");
    // 2. Ручная/телефонная привязка к ученику.
    expect(sql).toContain("link.entity_type = 'student'");
    // 3. Та же привязка, но к лиду.
    expect(sql).toContain("link.entity_type = 'lead'");
    expect(sql).toContain("l.blacklisted = true");
    // Удалённая запись никого не банит.
    expect(sql).toContain("link.deleted_at is null");
  });
});
