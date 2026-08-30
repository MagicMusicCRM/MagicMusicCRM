import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { RoomsService } from "./rooms.service";

describe("RoomsService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };
  const director = { userId: "director-a", role: "director" as const };

  const build = (query: jest.Mock) => {
    const database = { query };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = {
      assertCanReadOperationalData: jest.fn(),
      assertManagerOnly: jest.fn(),
      assertCanWriteCrm: jest.fn(),
      assertCanManageSystemSettings: jest.fn(),
    };
    const service = new RoomsService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, audit, policy };
  };

  const createService = (rows: Record<string, unknown>[] = []) =>
    build(jest.fn().mockResolvedValue({ rows }));

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) query.mockResolvedValueOnce(result);
    return build(query);
  };

  it("filters rooms by branch id", async () => {
    const { service, query } = createService([
      {
        id: "room-a",
        branch_id: "branch-a",
        branch_name: "Центр",
        name: "101",
        capacity: 4,
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.listRooms(actor, { branchId: "branch-a", limit: 5 }),
    ).resolves.toEqual({
      items: [
        {
          id: "room-a",
          branchId: "branch-a",
          branchName: "Центр",
          name: "101",
          capacity: 4,
          lifecycleState: "active",
          version: 1,
          archivedAt: null,
          archiveReason: null,
          archiveEffectiveDate: null,
          createdAt: "2026-06-12T00:00:00.000Z",
        },
      ],
    });

    expect(query.mock.calls[0][1]).toEqual([
      "branch-a",
      null,
      5,
      "manager-a",
      false,
    ]);
    expect(String(query.mock.calls[0][0])).toContain(
      "from app.users scope_actor",
    );
    expect(String(query.mock.calls[0][0])).toContain(
      "scope_assignment.branch_id::text = r.branch_id::text",
    );
  });

  it("returns room availability with slot conflicts", async () => {
    const { service, query, policy } = createService([
      {
        room_id: "room-a",
        branch_id: "branch-a",
        branch_name: "Центр",
        room_name: "101",
        capacity: 4,
        lessons: [
          {
            id: "lesson-a",
            teacherId: "teacher-a",
            teacherName: "Мария Петрова",
            scheduledAt: "2026-06-15T09:00:00.000Z",
            durationMinutes: 60,
            status: "scheduled",
            isTrial: false,
          },
        ],
        is_available: false,
        conflict_types: ["room_overlap"],
      },
    ]);

    await expect(
      service.listRoomAvailability(actor, {
        branchId: "branch-a",
        roomId: "room-a",
        teacherId: "teacher-a",
        date: "2026-06-15",
        dayFrom: "2026-06-14T21:00:00.000Z",
        dayTo: "2026-06-15T21:00:00.000Z",
        from: "2026-06-15T09:00:00.000Z",
        to: "2026-06-15T10:00:00.000Z",
        durationMinutes: 60,
        limit: 20,
      }),
    ).resolves.toEqual({
      dateFrom: "2026-06-14T21:00:00.000Z",
      dateTo: "2026-06-15T21:00:00.000Z",
      slotFrom: "2026-06-15T09:00:00.000Z",
      slotTo: "2026-06-15T10:00:00.000Z",
      items: [
        {
          roomId: "room-a",
          branchId: "branch-a",
          branchName: "Центр",
          roomName: "101",
          capacity: 4,
          lessons: [
            {
              id: "lesson-a",
              teacherId: "teacher-a",
              teacherName: "Мария Петрова",
              scheduledAt: "2026-06-15T09:00:00.000Z",
              durationMinutes: 60,
              status: "scheduled",
              isTrial: false,
            },
          ],
          isAvailable: false,
          conflictTypes: ["room_overlap"],
        },
      ],
    });

    expect(policy.assertManagerOnly).toHaveBeenCalledWith(actor);
    expect(String(query.mock.calls[0][0])).toContain(
      "from app.users scope_actor",
    );
    expect(String(query.mock.calls[0][0])).toContain(
      "scope_assignment.branch_id::text = r.branch_id::text",
    );
    expect(query.mock.calls[0][1]).toEqual([
      "branch-a",
      "room-a",
      "2026-06-14T21:00:00.000Z",
      "2026-06-15T21:00:00.000Z",
      "2026-06-15T09:00:00.000Z",
      "2026-06-15T10:00:00.000Z",
      "teacher-a",
      20,
      "manager-a",
    ]);
  });

  it("rejects teacher access to lesson identities in room availability", async () => {
    const { service, policy, query } = createService();
    policy.assertManagerOnly.mockImplementationOnce(() => {
      throw new Error("denied");
    });

    await expect(
      service.listRoomAvailability(
        { userId: "teacher-a", role: "teacher" },
        { branchId: "branch-a" },
      ),
    ).rejects.toThrow("denied");
    expect(query).not.toHaveBeenCalled();
  });

  it("creates rooms through CRM write policy and audit", async () => {
    const { service, query, audit, policy } = createService([
      {
        id: "room-b",
        branch_id: "branch-a",
        branch_name: "Центр",
        name: "102",
        capacity: 6,
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createRoom(director, {
        branchId: "branch-a",
        name: " 102 ",
        capacity: 6,
      }),
    ).resolves.toEqual({
      id: "room-b",
      branchId: "branch-a",
      branchName: "Центр",
      name: "102",
      capacity: 6,
      lifecycleState: "active",
      version: 1,
      archivedAt: null,
      archiveReason: null,
      archiveEffectiveDate: null,
      createdAt: "2026-06-12T00:00:00.000Z",
    });

    expect(policy.assertCanManageSystemSettings).toHaveBeenCalledWith(director);
    expect(query.mock.calls[0][1]).toEqual(["branch-a", "102", 6]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.room_created",
        entityType: "room",
        entityId: "room-b",
      }),
    );
  });

  it("creates a room without capacity", async () => {
    const { service, query } = createService([
      {
        id: "room-no-capacity",
        branch_id: "branch-a",
        branch_name: "Центр",
        name: "Репетиционная",
        capacity: null,
        created_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.createRoom(director, {
        branchId: "branch-a",
        name: "Репетиционная",
      }),
    ).resolves.toMatchObject({ capacity: null });
    expect(query.mock.calls[0][1]).toEqual(["branch-a", "Репетиционная", null]);
  });

  it("updates rooms but makes the legacy delete path fail closed", async () => {
    const { service, query, audit, policy } = createServiceWithQueryResults([
      { rows: [{ branch_id: "branch-b" }] },
      {
        rows: [
          {
            id: "room-a",
            branch_id: "branch-b",
            branch_name: "Север",
            name: "201",
            capacity: 8,
            created_at: "2026-06-12T00:00:00.000Z",
          },
        ],
      },
    ]);

    await expect(
      service.updateRoom(director, "room-a", {
        branchId: "branch-b",
        name: " 201 ",
        capacity: 8,
      }),
    ).resolves.toMatchObject({
      id: "room-a",
      branchId: "branch-b",
      branchName: "Север",
      name: "201",
      capacity: 8,
    });
    await expect(service.deleteRoom(director, "room-a")).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "ROOM_ARCHIVE_PREVIEW_REQUIRED",
      }),
    });

    expect(policy.assertCanManageSystemSettings).toHaveBeenCalledTimes(2);
    expect(query.mock.calls[0][1]).toEqual(["room-a"]);
    expect(query.mock.calls[1][1]).toEqual([
      "room-a",
      "branch-b",
      "201",
      true,
      8,
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "crm.room_updated",
        entityType: "room",
        entityId: "room-a",
      }),
    );
    expect(audit.record).toHaveBeenCalledTimes(1);
  });

  it("does not transfer an active room between branches through ordinary edit", async () => {
    const { service, query } = createServiceWithQueryResults([
      { rows: [{ branch_id: "branch-a" }] },
    ]);

    await expect(
      service.updateRoom(director, "room-a", { branchId: "branch-b" }),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "ROOM_BRANCH_TRANSFER_REQUIRES_REMEDIATION",
      }),
    });
    expect(query).toHaveBeenCalledTimes(1);
  });
});
