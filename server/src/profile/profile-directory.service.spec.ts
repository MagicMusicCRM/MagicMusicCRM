import { NotFoundException } from "@nestjs/common";
import { ProfileDirectoryService } from "./profile-directory.service";
import { ProfileRecordRepository } from "./profile-record.repository";

const actor = { userId: "manager-a", role: "manager" } as const;
const profileRow = {
  id: "profile-a",
  user_id: "user-a",
  email: "anna@example.com",
  role: "client" as const,
  first_name: "Анна",
  last_name: "Иванова",
  phone: null,
  dob: null,
  avatar_file_id: null,
  email_otp_2fa_enabled: false,
  created_at: new Date("2026-06-13T09:00:00Z"),
  updated_at: new Date("2026-06-13T09:00:00Z"),
};

function createService() {
  const database = { query: jest.fn() };
  const policy = {
    assertCanListProfiles: jest.fn(),
    assertCanReadProfile: jest.fn(),
  };
  const repository = {
    findById: jest.fn(),
    toProfileDto: jest.fn((row) => ({ id: row.id, userId: row.user_id })),
    toProfileSummaryDto: jest.fn((row) => ({ id: row.id })),
  };
  return {
    service: new ProfileDirectoryService(
      database as any,
      policy as any,
      repository as any,
    ),
    database,
    policy,
    repository,
  };
}

describe("ProfileDirectoryService", () => {
  it("caps the directory at 100 and keeps system-admin visibility actor-scoped", async () => {
    const { service, database, policy } = createService();
    database.query.mockResolvedValue({ rows: [] });

    await service.listProfiles(actor, { limit: 500, q: "  Анна  " });

    expect(policy.assertCanListProfiles).toHaveBeenCalledWith(actor);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringMatching(
        /u\.is_app_account = true[\s\S]*u\.role <> 'system_admin'/,
      ),
      [null, "Анна", 100, actor.role],
    );
  });

  it("keeps linked and candidate counts in one grouped directory projection", async () => {
    const database = {
      query: jest.fn().mockResolvedValue({
        rows: [
          {
            ...profileRow,
            is_app_account: true,
            phone_verified_at: null,
            linked_students_count: "2",
            linked_leads_count: "1",
            linked_teachers_count: "3",
            linked_staff_count: "4",
            candidate_students_count: "5",
            candidate_leads_count: "6",
            candidate_teachers_count: "7",
            candidate_staff_count: "8",
            total: "1",
          },
        ],
      }),
    };
    const policy = {
      assertCanListProfiles: jest.fn(),
      assertCanReadProfile: jest.fn(),
    };
    const repository = new ProfileRecordRepository(database as any);
    const service = new ProfileDirectoryService(
      database as any,
      policy as any,
      repository,
    );

    await expect(service.listProfiles(actor, {})).resolves.toEqual({
      items: [
        expect.objectContaining({
          linkedStudents: 2,
          linkedLeads: 1,
          linkedTeachers: 3,
          linkedStaff: 4,
          candidateStudents: 5,
          candidateLeads: 6,
          candidateTeachers: 7,
          candidateStaff: 8,
        }),
      ],
      total: 1,
    });
    expect(database.query).toHaveBeenCalledTimes(1);
    const [sql, parameters] = database.query.mock.calls[0];
    expect(String(sql)).toMatch(
      /count\(\*\) over\(\) as total[\s\S]*group by vp\.user_id[\s\S]*linked_students_count[\s\S]*candidate_staff_count/,
    );
    expect(String(sql)).toContain("occupied.user_id <> vp.user_id");
    expect(parameters).toEqual([null, null, 50, actor.role]);
  });

  it("authorizes getProfile against the profile user id", async () => {
    const { service, policy, repository } = createService();
    repository.findById.mockResolvedValue(profileRow);

    await expect(service.getProfile(actor, "profile-a")).resolves.toEqual({
      id: "profile-a",
      userId: "user-a",
    });
    expect(policy.assertCanReadProfile).toHaveBeenCalledWith(
      actor,
      profileRow.user_id,
    );
  });

  it("fails closed when the requested profile is absent", async () => {
    const { service, repository } = createService();
    repository.findById.mockResolvedValue(undefined);

    await expect(service.getProfile(actor, "missing")).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it("projects only student and lead links, caps at 500, and maps null names", async () => {
    const { service, database, policy, repository } = createService();
    repository.findById.mockResolvedValue(profileRow);
    database.query.mockResolvedValue({
      rows: [
        { entity_type: "student", entity_id: "student-a", name: null },
        { entity_type: "lead", entity_id: "lead-a", name: "Анна" },
      ],
    });

    await expect(service.listProfileLinks(actor, "profile-a")).resolves.toEqual({
      items: [
        { entityType: "student", entityId: "student-a", name: "—" },
        { entityType: "lead", entityId: "lead-a", name: "Анна" },
      ],
    });
    expect(policy.assertCanListProfiles).toHaveBeenCalledWith(actor);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringMatching(
        /select 'student'[\s\S]*union all[\s\S]*select 'lead'[\s\S]*limit 500/,
      ),
      ["profile-a"],
    );
    const sql = String(database.query.mock.calls[0][0]);
    expect(sql).not.toMatch(/select 'teacher'|select 'staff'/);
  });
});
