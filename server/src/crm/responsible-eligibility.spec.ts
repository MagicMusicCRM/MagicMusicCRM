import { BadRequestException } from "@nestjs/common";
import {
  ACTIVE_RESPONSIBLE_STAFF_STATUSES,
  applyEligibleResponsibleToCustomData,
  assertEligibleResponsible,
  listEligibleResponsibles,
  RESPONSIBLE_AUTH_ROLES,
  responsibleUserIdFromCustomDataPatch,
} from "./responsible-eligibility";

describe("responsible eligibility", () => {
  it("accepts a linked live localized-status manager and locks all rows", async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [
        {
          user_id: "manager-a",
          role: "manager",
          staff_member_id: "staff-a",
          staff_status: "Работает",
          display_name: "Мария Менеджер",
        },
      ],
    });

    await expect(
      assertEligibleResponsible({ query }, "manager-a", { lock: true }),
    ).resolves.toMatchObject({
      userId: "manager-a",
      role: "manager",
      staffStatus: "Работает",
      displayName: "Мария Менеджер",
    });

    expect(String(query.mock.calls[0][0])).toContain("for share of u, p, sm");
    expect(query.mock.calls[0][1]).toEqual([
      "manager-a",
      [...RESPONSIBLE_AUTH_ROLES],
      [...ACTIVE_RESPONSIBLE_STAFF_STATUSES],
    ]);
  });

  it.each(["client-a", "teacher-a", "random-uuid", "inactive-admin"])(
    "rejects an unlinked, inactive, or ineligible user: %s",
    async (userId) => {
      const query = jest.fn().mockResolvedValue({ rows: [] });
      await expect(
        assertEligibleResponsible({ query }, userId),
      ).rejects.toBeInstanceOf(BadRequestException);
    },
  );

  it("excludes system_admin consistently", () => {
    expect(RESPONSIBLE_AUTH_ROLES).not.toContain("system_admin");
  });

  it("uses the same live staff/role/status boundary for the picker", async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [
        {
          id: "11111111-1111-4111-8111-111111111111",
          display_name: "Мария Менеджер",
          role: "manager",
        },
      ],
    });

    await expect(
      listEligibleResponsibles({ query }, {
        search: "мария",
        roles: "manager,teacher,system_admin",
      }),
    ).resolves.toEqual([
      {
        id: "11111111-1111-4111-8111-111111111111",
        displayName: "Мария Менеджер",
        role: "manager",
      },
    ]);

    const sql = String(query.mock.calls[0][0]);
    expect(sql).toContain("join app.profiles");
    expect(sql).toContain("from app.staff_members");
    expect(sql).toContain("lower(btrim(sm.status)) = any($3::text[])");
    expect(query.mock.calls[0][1]).toEqual([
      ["manager"],
      "мария",
      [...ACTIVE_RESPONSIBLE_STAFF_STATUSES],
    ]);
  });

  it("does not query when a picker requests only forbidden roles", async () => {
    const query = jest.fn();
    await expect(
      listEligibleResponsibles({ query }, { roles: "teacher,system_admin" }),
    ).resolves.toEqual([]);
    expect(query).not.toHaveBeenCalled();
  });

  it("rejects malformed nested student owner ids and canonicalizes display metadata", () => {
    expect(() =>
      responsibleUserIdFromCustomDataPatch({ responsibleUserId: "manager-a" }),
    ).toThrow(BadRequestException);

    expect(
      applyEligibleResponsibleToCustomData(
        { responsibleName: "spoofed", note: "keep" },
        {
          userId: "11111111-1111-4111-8111-111111111111",
          role: "manager",
          staffMemberId: "staff-a",
          staffStatus: "active",
          displayName: "Мария Менеджер",
        },
      ),
    ).toEqual({
      note: "keep",
      responsible: "Мария Менеджер",
      responsibleUserId: "11111111-1111-4111-8111-111111111111",
    });
  });
});
