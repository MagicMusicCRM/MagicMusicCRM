import { BadRequestException, NotFoundException } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { MergeService } from "./merge.service";

describe("MergeService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createMergeService = (results: { rows: Record<string, unknown>[] }[]) => {
    const query = jest.fn();
    for (const result of results) {
      query.mockResolvedValueOnce(result);
    }
    const transaction = jest.fn(
      async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query }),
    );
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertCanWriteCrm: jest.fn(),
    };
    const service = new MergeService(
      { query, transaction } as unknown as DatabaseService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, transaction, policy };
  };

  it("keeps the HolliHop data when a phone-dedup merges an import into an app lead", async () => {
    const { service, query } = createMergeService([
      {
        rows: [
          {
            id: "l-lo",
            // Loser came from HolliHop: real appeal date, real ad source.
            custom_data: {
              hollihopId: "42",
              addressDate: "2023-03-01",
              adSource: "Яндекс",
            },
          },
          {
            id: "l-wi",
            // Winner was created in the app from a phone call.
            custom_data: { adSource: "не указан" },
          },
        ],
      },
    ]);
    // Everything after the lookup is re-pointing/logging and is not what this
    // test is about — one blanket answer keeps it focused on the merge itself.
    query.mockResolvedValue({ rows: [{ id: "ml1" }] });

    await service.mergeLeads(actor, "l-lo", "l-wi");

    // ✔ «При дедупе через телефон и тд должны оставаться данные только из
    // HolliHop». Before this, merge only re-pointed references and threw the
    // loser's custom_data away — the appeal date and source vanished silently.
    const update = query.mock.calls.find((call) =>
      String(call[0]).includes("set custom_data = $2::jsonb"),
    );
    expect(update).toBeDefined();
    expect(JSON.parse(String((update![1] as unknown[])[1]))).toEqual({
      hollihopId: "42",
      addressDate: "2023-03-01",
      adSource: "Яндекс",
    });
  });

  it("lists lead merge candidates by phone + name", async () => {
    const { service, query, policy } = createMergeService([
      {
        rows: [{
          loser_id: "l-lo",
          winner_id: "l-wi",
          phone: "+79091234567",
          name: "Иван Иванов",
          loser_created_at: new Date("2026-08-08T09:00:00Z"),
          loser_source: "Звонок",
          loser_status: "Новый",
          loser_branch: "Сокол",
          winner_created_at: new Date("2026-08-09T10:00:00Z"),
          winner_source: "Сайт",
          winner_status: "Успешный",
          winner_branch: "Оборонная",
        }],
      },
    ]);
    const result = await service.listMergeCandidates(actor);
    expect(result.items[0]).toEqual({
      loserId: "l-lo",
      winnerId: "l-wi",
      phone: "+79091234567",
      name: "Иван Иванов",
      first: {
        id: "l-lo",
        createdAt: new Date("2026-08-08T09:00:00Z"),
        source: "Звонок",
        status: "Новый",
        branch: "Сокол",
      },
      second: {
        id: "l-wi",
        createdAt: new Date("2026-08-09T10:00:00Z"),
        source: "Сайт",
        status: "Успешный",
        branch: "Оборонная",
      },
    });
    expect(policy.assertCanReadOperationalData).toHaveBeenCalledWith(actor);
    expect(query.mock.calls[0][0]).toContain("phone_normalized");
    expect(query.mock.calls[0][0]).toContain("left join app.lead_sources");
    expect(query.mock.calls[0][0]).toContain("source1.display_name");
  });

  it("mergeLeads re-points references, soft-deletes the loser, and logs", async () => {
    const { service, query, transaction, policy } = createMergeService([
      { rows: [{ id: "l-lo" }, { id: "l-wi" }] }, // validate both exist
      { rows: [] },                                // merge custom_data into winner
      { rows: [{ id: "s1" }] },                    // students.lead_id
      { rows: [{ id: "le1" }] },                   // lessons.lead_id
      { rows: [{ id: "h1" }] },                    // lead_status_history.lead_id
      { rows: [{ id: "t1" }] },                    // tasks.entity_id
      { rows: [] },                                // entity_comments.entity_id
      { rows: [{ id: "ch1" }] },                   // chats.lead_id
      { rows: [{ id: "dc1" }] },                   // duplicate_candidates -> merged
      { rows: [] },                                // soft-delete loser
      { rows: [{ id: "ml1" }] },                   // insert merge_log
    ]);
    const result = await service.mergeLeads(actor, "l-lo", "l-wi");
    expect(result).toEqual({ mergeLogId: "ml1", winnerId: "l-wi" });
    expect(transaction).toHaveBeenCalledTimes(1);
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("for update");
    expect(sql).toContain("version = version + 1");
    expect(sql).toMatch(/update app\.students\s+set lead_id/);
    expect(sql).toContain("app.allow_lead_status_history_repoint");
    expect(sql).toContain("update app.chats set lead_id");
    expect(sql).toMatch(/update app\.leads\s+set deleted_at = now\(\)/);
    expect(sql).toContain("insert into app.merge_log");
    // merge_log insert carries the captured repointed ids
    const mlInsert = query.mock.calls.find((c) => String(c[0]).includes("insert into app.merge_log"));
    expect(JSON.stringify(mlInsert?.[1])).toContain("students.lead_id");
  });

  it("mergeLeads rejects merging a lead into itself", async () => {
    const { service } = createMergeService([]);
    await expect(service.mergeLeads(actor, "same", "same")).rejects.toThrow(BadRequestException);
  });

  it("undoMerge reverses captured rows, restores the loser, and stamps undone", async () => {
    const repointed = { "students.lead_id": ["s1"], "duplicate_candidates.status": ["dc1"] };
    const { service, query, policy } = createMergeService([
      { rows: [{ loser_id: "l-lo", repointed }] }, // select merge_log
      { rows: [] }, // reverse students.lead_id
      { rows: [] }, // reverse duplicate_candidates.status
      { rows: [] }, // restore loser deleted_at = null
      { rows: [] }, // update merge_log undone_at/undone_by
    ]);
    const result = await service.undoMerge(actor, "ml1");
    expect(result).toEqual({ success: true });
    expect(policy.assertCanWriteCrm).toHaveBeenCalledWith(actor);
    const sql = query.mock.calls.map((c) => String(c[0])).join("\n");
    expect(sql).toContain("update app.students set lead_id = $1");
    expect(sql).toContain("version = version + 1");
    expect(sql).toContain("set deleted_at = null");
    expect(sql).toContain("update app.merge_log set undone_at = now()");
    // duplicate_candidates reverse binds [null, ids]; students reverse binds [loser_id, ids]
    const dupCall = query.mock.calls.find((c) => String(c[0]).includes("app.duplicate_candidates"));
    expect((dupCall?.[1] as unknown[])[0]).toBeNull();
    const studCall = query.mock.calls.find((c) => String(c[0]).includes("update app.students set lead_id"));
    expect((studCall?.[1] as unknown[])[0]).toBe("l-lo");
    expect((studCall?.[1] as unknown[])[1]).toEqual(["s1"]);
  });

  it("undoMerge uses the controlled history-repoint scope", async () => {
    const repointed = { "lead_status_history.lead_id": ["h1"] };
    const { service, query } = createMergeService([
      { rows: [{ loser_id: "l-lo", repointed }] },
      { rows: [] },
      { rows: [] },
      { rows: [] },
    ]);

    await service.undoMerge(actor, "ml1");

    const historyUpdate = query.mock.calls.find((call) =>
      String(call[0]).includes("update app.lead_status_history"),
    );
    expect(String(historyUpdate?.[0])).toContain(
      "app.allow_lead_status_history_repoint",
    );
  });

  it("undoMerge 404s when the merge is missing or already undone", async () => {
    const { service } = createMergeService([{ rows: [] }]); // select merge_log → none
    await expect(service.undoMerge(actor, "missing")).rejects.toThrow(NotFoundException);
  });
});
