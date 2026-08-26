import { ProfileService } from "./profile.service";

const actor = { userId: "manager-a", role: "manager" } as const;

describe("ProfileService compatibility facade", () => {
  it("delegates every public operation to its semantic owner", async () => {
    const self = {
      getMe: jest.fn().mockResolvedValue({ id: "profile-a" }),
      updateMe: jest.fn().mockResolvedValue({ id: "profile-a" }),
    };
    const directory = {
      listProfiles: jest.fn().mockResolvedValue({ items: [], total: 0 }),
      getProfile: jest.fn().mockResolvedValue({ id: "profile-a" }),
      listProfileLinks: jest.fn().mockResolvedValue({ items: [] }),
    };
    const notes = {
      listProfileNotes: jest.fn().mockResolvedValue({ items: [] }),
      createProfileNote: jest.fn().mockResolvedValue({ id: "note-a" }),
    };
    const service = new ProfileService(
      self as any,
      directory as any,
      notes as any,
    );
    const update = { firstName: "Анна" };
    const query = { q: "Анна", limit: 20 };

    await service.getMe(actor);
    await service.updateMe(actor, update);
    await service.listProfiles(actor, query);
    await service.getProfile(actor, "profile-a");
    await service.listProfileLinks(actor, "profile-a");
    await service.listProfileNotes(actor, "profile-a");
    await service.createProfileNote(actor, "profile-a", "Заметка");

    expect(self.getMe).toHaveBeenCalledWith(actor);
    expect(self.updateMe).toHaveBeenCalledWith(actor, update);
    expect(directory.listProfiles).toHaveBeenCalledWith(actor, query);
    expect(directory.getProfile).toHaveBeenCalledWith(actor, "profile-a");
    expect(directory.listProfileLinks).toHaveBeenCalledWith(actor, "profile-a");
    expect(notes.listProfileNotes).toHaveBeenCalledWith(actor, "profile-a");
    expect(notes.createProfileNote).toHaveBeenCalledWith(
      actor,
      "profile-a",
      "Заметка",
    );
  });
});
