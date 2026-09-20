import { ProfileRecordRepository } from "./profile-record.repository";

describe("ProfileRecordRepository", () => {
  it("projects a PostgreSQL date as a date-only value", () => {
    const repository = new ProfileRecordRepository({} as any);
    const localMidnight = new Date(1994, 4, 17);

    expect(
      repository.toProfileDto({
        id: "profile-a",
        user_id: "user-a",
        email: "anna@example.com",
        role: "client",
        first_name: "Анна",
        last_name: null,
        phone: null,
        dob: localMidnight,
        avatar_file_id: null,
        email_otp_2fa_enabled: false,
        created_at: new Date("2026-01-01T00:00:00Z"),
        updated_at: new Date("2026-01-01T00:00:00Z"),
      }).dob,
    ).toBe("1994-05-17");
  });
});
