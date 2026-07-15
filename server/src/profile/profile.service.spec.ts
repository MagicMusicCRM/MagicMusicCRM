import { BadRequestException } from "@nestjs/common";
import { ProfileService } from "./profile.service";

const actor = { userId: "manager-a", role: "manager" } as const;

function createService(overrides: {
  database?: Record<string, jest.Mock>;
  audit?: Record<string, jest.Mock>;
  policy?: Record<string, jest.Mock>;
  linking?: Record<string, jest.Mock>;
} = {}) {
  const database = {
    query: jest.fn(),
    ...overrides.database,
  };
  const audit = {
    record: jest.fn(),
    ...overrides.audit,
  };
  const policy = {
    assertCanReadProfile: jest.fn(),
    assertCanListProfiles: jest.fn(),
    assertCanUpdateRole: jest.fn(),
    ...overrides.policy,
  };

  const linking = {
    linkProfileByPhone: jest.fn().mockResolvedValue({}),
    ...overrides.linking,
  };

  return {
    service: new ProfileService(
      database as any,
      audit as any,
      policy as any,
      linking as any,
    ),
    database,
    audit,
    policy,
    linking,
  };
}

const profileRow = {
  id: "profile-a",
  user_id: "user-a",
  email: "anna@example.com",
  role: "client",
  first_name: "Анна",
  last_name: "Иванова",
  phone: null,
  dob: null,
  avatar_file_id: null,
  email_otp_2fa_enabled: false,
  created_at: new Date("2026-06-13T09:00:00Z"),
  updated_at: new Date("2026-06-13T09:00:00Z"),
};

const noteRow = {
  id: "note-a",
  profile_id: "profile-a",
  author_id: "manager-a",
  body: "Позвонить перед занятием",
  created_at: new Date("2026-06-13T10:00:00Z"),
  author_email: "manager@example.com",
  author_first_name: "Мария",
  author_last_name: "Петрова",
};

describe("ProfileService profile list performance", () => {
  it("lists profiles with batched link counts and indexed normalized phone", async () => {
    const { service, database, policy } = createService({
      database: {
        query: jest.fn().mockResolvedValueOnce({
          rows: [
            {
              ...profileRow,
              is_app_account: true,
              phone_verified_at: null,
              linked_students_count: "2",
              linked_leads_count: "1",
              linked_teachers_count: "0",
              linked_staff_count: "0",
              candidate_students_count: "1",
              candidate_leads_count: "0",
              candidate_teachers_count: "0",
              candidate_staff_count: "0",
              total: "1",
            },
          ],
        }),
      },
    });

    await expect(service.listProfiles(actor, { limit: 20 })).resolves.toEqual({
      items: [
        expect.objectContaining({
          id: "profile-a",
          linkedStudents: 2,
          candidateStudents: 1,
        }),
      ],
      total: 1,
    });

    const sql = String((database.query as jest.Mock).mock.calls[0][0]);
    expect(policy.assertCanListProfiles).toHaveBeenCalledWith(actor);
    expect(sql).toContain("limited_profiles");
    expect(sql).toContain("p.phone_normalized as normalized_phone");
    expect(sql).toContain("linked_students_count");
    expect(sql).not.toContain("regexp_replace");
  });
});

describe("ProfileService profile notes", () => {
  it("lists profile notes for manager/admin actors", async () => {
    const { service, database, policy } = createService({
      database: {
        query: jest
          .fn()
          .mockResolvedValueOnce({ rows: [profileRow] })
          .mockResolvedValueOnce({ rows: [noteRow] }),
      },
    });

    const result = await service.listProfileNotes(actor, "profile-a");

    expect(policy.assertCanListProfiles).toHaveBeenCalledWith(actor);
    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining("from app.profile_notes n"),
      ["profile-a"],
    );
    expect(result.items).toEqual([
      {
        id: "note-a",
        profileId: "profile-a",
        authorId: "manager-a",
        body: "Позвонить перед занятием",
        createdAt: noteRow.created_at,
        author: {
          id: "manager-a",
          email: "manager@example.com",
          firstName: "Мария",
          lastName: "Петрова",
        },
      },
    ]);
  });

  it("creates profile note and records audit event", async () => {
    const { service, database, audit } = createService({
      database: {
        query: jest
          .fn()
          .mockResolvedValueOnce({ rows: [profileRow] })
          .mockResolvedValueOnce({ rows: [noteRow] }),
      },
    });

    const result = await service.createProfileNote(
      actor,
      "profile-a",
      "  Позвонить перед занятием  ",
    );

    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining("insert into app.profile_notes"),
      ["profile-a", "manager-a", "Позвонить перед занятием"],
    );
    expect(audit.record).toHaveBeenCalledWith({
      actor,
      action: "profile.note_created",
      entityType: "profile",
      entityId: "profile-a",
      metadata: { noteId: "note-a" },
    });
    expect(result.body).toBe("Позвонить перед занятием");
  });

  it("rejects blank notes after trimming", async () => {
    const { service } = createService({
      database: {
        query: jest.fn().mockResolvedValueOnce({ rows: [profileRow] }),
      },
    });

    await expect(
      service.createProfileNote(actor, "profile-a", "   "),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe("ProfileService profile updates", () => {
  it("marks user profile as completed when first name, last name and phone are present", async () => {
    const { service, database } = createService({
      database: {
        query: jest
          .fn()
          .mockResolvedValueOnce({ rows: [] })
          .mockResolvedValueOnce({
            rows: [
              {
                id: "profile-a",
                user_id: "user-a",
                email: "anna@example.com",
                role: "client",
                first_name: "Анна",
                last_name: "Иванова",
                phone: "+79990000000",
                dob: null,
                avatar_file_id: null,
                email_otp_2fa_enabled: false,
                created_at: new Date("2026-06-13T09:00:00Z"),
                updated_at: new Date("2026-06-13T09:00:00Z"),
              },
            ],
          })
          .mockResolvedValueOnce({ rows: [] })
          .mockResolvedValueOnce({ rows: [] })
          .mockResolvedValueOnce({ rows: [] })
          .mockResolvedValueOnce({ rows: [] })
          .mockResolvedValueOnce({ rows: [] })
          .mockResolvedValueOnce({
            rows: [
              {
                linked_students_count: "0",
                linked_leads_count: "0",
                linked_teachers_count: "0",
                linked_staff_count: "0",
                candidate_students_count: "0",
                candidate_leads_count: "0",
                candidate_teachers_count: "0",
                candidate_staff_count: "0",
              },
            ],
          }),
      },
    });

    await service.updateMe(actor, {
      firstName: "Анна",
      lastName: "Иванова",
      phone: "+79990000000",
    });

    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining("update app.profiles p"),
      expect.arrayContaining(["manager-a", "Анна", "Иванова", "+79990000000"]),
    );
    expect(database.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining("update app.users"),
      ["manager-a"],
    );
  });

  it("does not mark profile as completed when phone is still missing", async () => {
    const { service, database } = createService({
      database: {
        query: jest
          .fn()
          .mockResolvedValueOnce({ rows: [] })
          .mockResolvedValueOnce({
            rows: [
              {
                id: "profile-a",
                user_id: "user-a",
                email: "anna@example.com",
                role: "client",
                first_name: "Анна",
                last_name: "Иванова",
                phone: null,
                dob: null,
                avatar_file_id: null,
                email_otp_2fa_enabled: false,
                created_at: new Date("2026-06-13T09:00:00Z"),
                updated_at: new Date("2026-06-13T09:00:00Z"),
              },
            ],
          }),
      },
    });

    await service.updateMe(actor, {
      firstName: "Анна",
      lastName: "Иванова",
      phone: "",
    });

    expect(database.query).toHaveBeenCalledTimes(2);
  });
});

describe("ProfileService role updates", () => {
  const sysAdminRow = {
    ...profileRow,
    id: "profile-sys",
    user_id: "user-sys",
    role: "system_admin",
  };

  it("blocks demoting the last active system_admin", async () => {
    const { service, database } = createService({
      database: {
        query: jest
          .fn()
          // findById -> the target system_admin
          .mockResolvedValueOnce({ rows: [sysAdminRow] })
          // count of OTHER active system_admins -> none left
          .mockResolvedValueOnce({ rows: [{ count: "0" }] }),
      },
    });

    await expect(
      service.updateRole(actor, "profile-sys", "manager"),
    ).rejects.toBeInstanceOf(BadRequestException);
    // Must not have run the UPDATE.
    expect(database.query).toHaveBeenCalledTimes(2);
  });

  it("allows demoting a system_admin when another one remains", async () => {
    const { service, database } = createService({
      database: {
        query: jest
          .fn()
          .mockResolvedValueOnce({ rows: [sysAdminRow] })
          .mockResolvedValueOnce({ rows: [{ count: "1" }] })
          .mockResolvedValueOnce({ rows: [] })
          .mockResolvedValueOnce({
            rows: [{ ...sysAdminRow, role: "manager" }],
          }),
      },
    });

    const result = await service.updateRole(actor, "profile-sys", "manager");

    expect(result.role).toBe("manager");
    expect(database.query).toHaveBeenCalledTimes(4);
  });
});
