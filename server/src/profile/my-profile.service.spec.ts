import { NotFoundException } from "@nestjs/common";
import { MyProfileService } from "./my-profile.service";

const actor = { userId: "manager-a", role: "manager" } as const;

const profileRow = {
  id: "profile-a",
  user_id: "manager-a",
  email: "anna@example.com",
  role: "client" as const,
  first_name: "Анна",
  last_name: "Иванова",
  phone: "+79990000000",
  dob: null,
  avatar_file_id: null,
  email_otp_2fa_enabled: false,
  is_app_account: true,
  phone_verified_at: null,
  created_at: new Date("2026-06-13T09:00:00Z"),
  updated_at: new Date("2026-06-13T09:00:00Z"),
};

function createService() {
  const database = { query: jest.fn() };
  const audit = { record: jest.fn() };
  const linking = { linkProfileByPhone: jest.fn().mockResolvedValue({}) };
  const leadIntake = {
    autoCreateLeadFromChat: jest.fn().mockResolvedValue({
      leadId: null,
      created: false,
    }),
  };
  const repository = {
    ensure: jest.fn().mockResolvedValue(undefined),
    findByUserId: jest.fn(),
    findById: jest.fn(),
    toProfileDto: jest.fn((row) => ({
      id: row.id,
      userId: row.user_id,
      email: row.email,
      role: row.role,
      firstName: row.first_name,
      lastName: row.last_name,
      phone: row.phone,
      dob: row.dob,
      avatarFileId: row.avatar_file_id,
      emailOtp2faEnabled: row.email_otp_2fa_enabled,
      isAppAccount: row.is_app_account ?? true,
      phoneVerifiedAt: row.phone_verified_at ?? null,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    })),
  };
  return {
    service: new MyProfileService(
      database as any,
      audit as any,
      linking as any,
      leadIntake as any,
      repository as any,
    ),
    database,
    audit,
    linking,
    leadIntake,
    repository,
  };
}

describe("MyProfileService", () => {
  it("creates a missing profile once, reloads it, and keeps oldest branch as home", async () => {
    const { service, database, repository } = createService();
    repository.findByUserId
      .mockResolvedValueOnce(undefined)
      .mockResolvedValueOnce(profileRow);
    repository.ensure.mockResolvedValue(undefined);
    database.query.mockResolvedValue({
      rows: [{ branch_id: "branch-2" }, { branch_id: "branch-9" }],
    });

    await expect(service.getMe(actor)).resolves.toMatchObject({
      id: "profile-a",
      branchIds: ["branch-2", "branch-9"],
      homeBranchId: "branch-2",
    });
    expect(repository.ensure).toHaveBeenCalledTimes(1);
    expect(repository.ensure).toHaveBeenCalledWith(actor.userId);
    expect(repository.findByUserId).toHaveBeenCalledTimes(2);
  });

  it("returns no branches and a null home branch without active assignments", async () => {
    const { service, database, repository } = createService();
    repository.findByUserId.mockResolvedValue(profileRow);
    database.query.mockResolvedValue({ rows: [] });

    await expect(service.getMe(actor)).resolves.toMatchObject({
      id: "profile-a",
      branchIds: [],
      homeBranchId: null,
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringMatching(
        /sba\.deleted_at is null[\s\S]*sm\.deleted_at is null[\s\S]*order by sba\.created_at asc, sba\.branch_id asc/,
      ),
      [profileRow.id],
    );
  });

  it("rejects an avatar outside the actor-owned active avatar boundary", async () => {
    const { service, database, audit, repository } = createService();
    repository.ensure.mockResolvedValue(undefined);
    database.query.mockResolvedValueOnce({ rows: [] });

    await expect(
      service.updateMe(actor, { avatarFileId: "avatar-a" }),
    ).rejects.toThrow("Файл аватара не найден.");
    expect(database.query).toHaveBeenCalledWith(
      expect.stringMatching(
        /owner_user_id = \$2[\s\S]*purpose = 'profile_avatar'[\s\S]*deleted_at is null/,
      ),
      ["avatar-a", actor.userId],
    );
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("passes blank profile fields as null beside SQL coalesce", async () => {
    const { service, database } = createService();
    database.query.mockResolvedValueOnce({ rows: [profileRow] });

    await service.updateMe(actor, {
      firstName: "  ",
      lastName: "\t",
      phone: " ",
    });

    expect(database.query).toHaveBeenNthCalledWith(
      1,
      expect.stringMatching(
        /first_name = coalesce\(\$2[\s\S]*last_name = coalesce\(\$3[\s\S]*phone = coalesce\(\$4/,
      ),
      [actor.userId, null, null, null, null, null, null],
    );
  });

  it("completes clients through onboarding intake and records profile.updated last", async () => {
    const { service, database, audit, linking, leadIntake } = createService();
    database.query
      .mockResolvedValueOnce({ rows: [profileRow] })
      .mockResolvedValueOnce({ rows: [] });

    await service.updateMe(actor, { firstName: "Анна" });

    expect(leadIntake.autoCreateLeadFromChat).toHaveBeenCalledTimes(1);
    expect(leadIntake.autoCreateLeadFromChat).toHaveBeenCalledWith(
      actor,
      actor.userId,
      "onboarding",
    );
    expect(linking.linkProfileByPhone).not.toHaveBeenCalled();
    expect(audit.record).toHaveBeenCalledWith({
      actor,
      action: "profile.updated",
      entityType: "profile",
      entityId: "profile-a",
    });
    expect(audit.record.mock.invocationCallOrder[0]).toBeGreaterThan(
      leadIntake.autoCreateLeadFromChat.mock.invocationCallOrder[0],
    );
    expect(audit.record.mock.invocationCallOrder[0]).toBeGreaterThan(
      Math.max(...database.query.mock.invocationCallOrder),
    );
  });

  it("completes non-clients through phone linking only", async () => {
    const { service, database, linking, leadIntake } = createService();
    const staffProfile = { ...profileRow, role: "manager" as const };
    database.query
      .mockResolvedValueOnce({ rows: [staffProfile] })
      .mockResolvedValueOnce({ rows: [] });

    await service.updateMe(actor, { lastName: "Иванова" });

    expect(linking.linkProfileByPhone).toHaveBeenCalledTimes(1);
    expect(linking.linkProfileByPhone).toHaveBeenCalledWith(
      actor,
      staffProfile,
      "auto_phone",
    );
    expect(leadIntake.autoCreateLeadFromChat).not.toHaveBeenCalled();
  });

  it("does not link or create a lead while the profile is incomplete", async () => {
    const { service, database, linking, leadIntake } = createService();
    database.query.mockResolvedValueOnce({
      rows: [{ ...profileRow, phone: null }],
    });

    await service.updateMe(actor, { phone: "" });

    expect(linking.linkProfileByPhone).not.toHaveBeenCalled();
    expect(leadIntake.autoCreateLeadFromChat).not.toHaveBeenCalled();
  });

  it("fails closed when a profile is still absent after ensure", async () => {
    const { service, repository } = createService();
    repository.findByUserId.mockResolvedValue(undefined);

    await expect(service.getMe(actor)).rejects.toBeInstanceOf(NotFoundException);
  });
});
