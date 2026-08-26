import { BadRequestException, NotFoundException } from "@nestjs/common";
import { ProfileNotesService } from "./profile-notes.service";

const actor = { userId: "manager-a", role: "manager" } as const;
const profileRow = { id: "profile-a", user_id: "user-a" };
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

function createService() {
  const database = { query: jest.fn() };
  const audit = { record: jest.fn() };
  const policy = { assertCanListProfiles: jest.fn() };
  const repository = {
    findById: jest.fn(),
    toProfileNoteDto: jest.fn((row) => ({
      id: row.id,
      profileId: row.profile_id,
      authorId: row.author_id,
      body: row.body,
      createdAt: row.created_at,
      author: row.author_id
        ? {
            id: row.author_id,
            email: row.author_email,
            firstName: row.author_first_name,
            lastName: row.author_last_name,
          }
        : null,
    })),
  };
  return {
    service: new ProfileNotesService(
      database as any,
      audit as any,
      policy as any,
      repository as any,
    ),
    database,
    audit,
    policy,
    repository,
  };
}

describe("ProfileNotesService", () => {
  it("keeps note ordering, author fallback, and audit payload", async () => {
    const { service, database, policy, repository } = createService();
    repository.findById.mockResolvedValue(profileRow);
    database.query.mockResolvedValueOnce({
      rows: [{ ...noteRow, author_id: null }],
    });

    await expect(service.listProfileNotes(actor, "profile-a")).resolves.toEqual({
      items: [expect.objectContaining({ author: null })],
    });
    expect(policy.assertCanListProfiles).toHaveBeenCalledWith(actor);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringMatching(
        /order by n\.created_at desc, n\.id desc[\s\S]*limit 100/,
      ),
      ["profile-a"],
    );
  });

  it("rejects blank notes after trimming without inserting or auditing", async () => {
    const { service, database, audit, repository } = createService();
    repository.findById.mockResolvedValue(profileRow);

    await expect(
      service.createProfileNote(actor, "profile-a", "   "),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(database.query).not.toHaveBeenCalled();
    expect(audit.record).not.toHaveBeenCalled();
  });

  it("inserts a normalized note before profile.note_created with its noteId", async () => {
    const { service, database, audit, repository } = createService();
    repository.findById.mockResolvedValue(profileRow);
    database.query.mockResolvedValueOnce({ rows: [noteRow] });

    await expect(
      service.createProfileNote(
        actor,
        "profile-a",
        "  Позвонить перед занятием  ",
      ),
    ).resolves.toMatchObject({ id: "note-a", body: noteRow.body });

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("insert into app.profile_notes"),
      ["profile-a", actor.userId, noteRow.body],
    );
    expect(audit.record).toHaveBeenCalledWith({
      actor,
      action: "profile.note_created",
      entityType: "profile",
      entityId: "profile-a",
      metadata: { noteId: "note-a" },
    });
    expect(audit.record.mock.invocationCallOrder[0]).toBeGreaterThan(
      database.query.mock.invocationCallOrder[0],
    );
  });

  it("fails closed when the target profile is absent", async () => {
    const { service, database, repository } = createService();
    repository.findById.mockResolvedValue(undefined);

    await expect(
      service.listProfileNotes(actor, "missing"),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(database.query).not.toHaveBeenCalled();
  });
});
