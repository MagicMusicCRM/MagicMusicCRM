import { ForbiddenException } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";

export async function settingsBranchIdsForActor(
  database: DatabaseService,
  actor: ActorContext,
): Promise<string[] | null> {
  if (actor.role !== "manager") return null;
  const result = await database.query<{ branch_id: string }>(
    `select assignment.branch_id
     from app.user_crm_links link
     join app.staff_members staff on staff.id = link.entity_id
       and link.entity_type = 'staff' and link.deleted_at is null
       and staff.deleted_at is null
     join app.staff_branch_assignments assignment
       on assignment.staff_member_id = staff.id
       and assignment.deleted_at is null
     where link.user_id = $1
     order by assignment.branch_id`,
    [actor.userId],
  );
  return result.rows.map((row) => row.branch_id);
}

export async function assertSettingsBranchScope(
  database: DatabaseService,
  actor: ActorContext,
  branchId: string,
): Promise<void> {
  const branchIds = await settingsBranchIdsForActor(database, actor);
  if (branchIds !== null && !branchIds.includes(branchId)) {
    throw new ForbiddenException("Филиал не входит в область доступа.");
  }
}
