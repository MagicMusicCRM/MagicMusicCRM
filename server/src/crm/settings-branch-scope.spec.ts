import { DatabaseService } from "../db/database.service";
import {
  assertSettingsBranchScope,
  settingsBranchIdsForActor,
} from "./settings-branch-scope";

describe("settings branch scope", () => {
  const manager = { userId: "manager-a", role: "manager" as const };

  it("limits delegated managers to assigned branches", async () => {
    const query = jest.fn().mockResolvedValue({
      rows: [{ branch_id: "branch-a" }, { branch_id: "branch-b" }],
    });
    const database = { query } as unknown as DatabaseService;

    await expect(settingsBranchIdsForActor(database, manager)).resolves.toEqual(
      ["branch-a", "branch-b"],
    );
    await expect(
      assertSettingsBranchScope(database, manager, "branch-a"),
    ).resolves.toBeUndefined();
    await expect(
      assertSettingsBranchScope(database, manager, "branch-c"),
    ).rejects.toThrow("Филиал не входит в область доступа.");
  });

  it("keeps Director school-wide without a scope query", async () => {
    const query = jest.fn();
    const database = { query } as unknown as DatabaseService;
    await expect(
      settingsBranchIdsForActor(database, {
        userId: "director-a",
        role: "director",
      }),
    ).resolves.toBeNull();
    expect(query).not.toHaveBeenCalled();
  });
});
