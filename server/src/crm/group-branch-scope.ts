import { ForbiddenException, NotFoundException } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { settingsBranchIdsForActor } from "./settings-branch-scope";

export async function assertGroupBranchScope(
  database: DatabaseService,
  actor: ActorContext,
  groupId: string,
  knownBranchId?: string | null,
): Promise<void> {
  if (actor.role !== "manager") return;
  let branchId = knownBranchId;
  if (branchId === undefined) {
    const group = await database.query<{ branch_id: string | null }>(
      `select branch_id
       from app.groups
       where id = $1 and deleted_at is null
       limit 1`,
      [groupId],
    );
    if (!group.rows[0]) throw new NotFoundException("Группа не найдена.");
    branchId = group.rows[0].branch_id;
  }
  if (!branchId) {
    throw new ForbiddenException("Группа не относится к доступному филиалу.");
  }
  const branchIds = await settingsBranchIdsForActor(database, actor);
  if (branchIds === null || !branchIds.includes(branchId)) {
    throw new ForbiddenException("Группа не входит в область доступа.");
  }
}
