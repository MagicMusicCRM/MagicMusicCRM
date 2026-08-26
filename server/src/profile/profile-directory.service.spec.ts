import { NotFoundException } from "@nestjs/common";
import { ProfileDirectoryService } from "./profile-directory.service";

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
