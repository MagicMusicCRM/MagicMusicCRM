import { BranchesService } from "./branches.service";
import { BranchLifecycleService } from "./branch-lifecycle.service";
import { CrmFacilitiesController } from "./crm-facilities.controller";
import { CrmService } from "./crm.service";
import { GroupLifecycleService } from "./group-lifecycle.service";
import { GroupsService } from "./groups.service";
import { RoomLifecycleService } from "./room-lifecycle.service";
import { RoomsService } from "./rooms.service";

describe("CrmFacilitiesController", () => {
  it("delegates group-student reads to the CRM boundary without copying arguments", async () => {
    const response = { items: [{ id: "student-a" }] };
    const crm = {
      listGroupStudents: jest.fn().mockResolvedValue(response),
    };
    const controller = new CrmFacilitiesController(
      {} as BranchesService,
      {} as BranchLifecycleService,
      crm as unknown as CrmService,
      {} as GroupsService,
      {} as GroupLifecycleService,
      {} as RoomsService,
      {} as RoomLifecycleService,
    );
    const actor = { userId: "admin-a", role: "admin" as const };
    const groupId = "group-a";
    const query = { limit: 20 };

    await expect(
      controller.listGroupStudents(actor, groupId, query),
    ).resolves.toBe(response);
    expect(crm.listGroupStudents).toHaveBeenCalledWith(actor, groupId, query);
  });
});
