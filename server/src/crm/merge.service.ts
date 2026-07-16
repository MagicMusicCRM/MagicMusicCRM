import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";

/**
 * Lead merge + undo (app.merge_log). Repoints every lead reference from the
 * loser onto the winner inside a transaction, soft-deletes the loser, and
 * records a reversible merge_log row. Extracted from CrmService (B5) —
 * self-contained (database + policy only).
 */
@Injectable()
export class MergeService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
  ) {}

  async listMergeCandidates(actor: ActorContext, limit = 50) {
    this.policy.assertCanReadOperationalData(actor);
    const safeLimit = Number.isFinite(limit) ? limit : 50;
    const capped = Math.min(Math.max(safeLimit, 1), 200);
    const result = await this.database.query<{
      loser_id: string;
      winner_id: string;
      phone: string | null;
      name: string;
    }>(
      `select l1.id as loser_id, l2.id as winner_id, l2.phone_normalized as phone,
              btrim(concat_ws(' ', l2.first_name, l2.last_name)) as name
         from app.leads l1
         join app.leads l2
           on l1.phone_normalized = l2.phone_normalized
          and lower(btrim(coalesce(l1.first_name, ''))) = lower(btrim(coalesce(l2.first_name, '')))
          and lower(btrim(coalesce(l1.last_name, '')))  = lower(btrim(coalesce(l2.last_name, '')))
          and l1.id < l2.id
        where l1.deleted_at is null and l2.deleted_at is null
          and l1.phone_normalized is not null
        order by l2.phone_normalized
        limit $1`,
      [capped],
    );
    return {
      items: result.rows.map((row) => ({
        loserId: row.loser_id,
        winnerId: row.winner_id,
        phone: row.phone,
        name: row.name,
      })),
    };
  }

  async mergeLeads(actor: ActorContext, loserId: string, winnerId: string) {
    this.policy.assertCanWriteCrm(actor);
    if (loserId === winnerId) {
      throw new BadRequestException("Нельзя объединить лид сам с собой.");
    }
    return this.database.transaction(async (client) => {
      const existing = await client.query<{ id: string }>(
        `select id from app.leads where id in ($1, $2) and deleted_at is null`,
        [loserId, winnerId],
      );
      if (existing.rows.length !== 2) {
        throw new NotFoundException("Один из лидов не найден.");
      }

      const repointed: Record<string, string[]> = {};
      const ids = (rows: { id: string }[]) => rows.map((r) => r.id);

      // Real-FK lead references.
      repointed["students.lead_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.students set lead_id = $2, updated_at = now() where lead_id = $1 and deleted_at is null returning id`,
          [loserId, winnerId],
        )).rows,
      );
      repointed["lessons.lead_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.lessons set lead_id = $2 where lead_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      repointed["lead_status_history.lead_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.lead_status_history set lead_id = $2 where lead_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      // app.lead_comments (migration 0002) is a legacy table the app no longer
      // reads or writes — lead comments live in app.entity_comments (repointed
      // below). Re-pointing it here only muddied where comments live, so the
      // branch is dropped. Historical undo is unaffected: undoMerge is driven by
      // UNDO_REPOINT's keys, so old merge_log rows carrying "lead_comments.lead_id"
      // are simply skipped, and nothing reads that table anyway.
      // Polymorphic (no unique constraint).
      repointed["tasks.entity_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.tasks set entity_id = $2 where entity_type = 'lead' and entity_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      repointed["entity_comments.entity_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.entity_comments set entity_id = $2 where entity_type = 'lead' and entity_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      repointed["chats.lead_id"] = ids(
        (await client.query<{ id: string }>(
          `update app.chats set lead_id = $2 where lead_id = $1 returning id`,
          [loserId, winnerId],
        )).rows,
      );
      // Mark duplicate candidates merged (capture for undo).
      repointed["duplicate_candidates.status"] = ids(
        (await client.query<{ id: string }>(
          `update app.duplicate_candidates set status = 'merged', updated_at = now()
            where status = 'pending'
              and ((entity_type_a = 'lead' and entity_id_a = $1) or (entity_type_b = 'lead' and entity_id_b = $1))
            returning id`,
          [loserId],
        )).rows,
      );

      // Soft-delete the loser (CASCADE never fires — no hard delete).
      await client.query(
        `update app.leads set deleted_at = now(), updated_at = now() where id = $1`,
        [loserId],
      );

      const log = await client.query<{ id: string }>(
        `insert into app.merge_log (entity_type, loser_id, winner_id, repointed, merged_by)
         values ('lead', $1, $2, $3::jsonb, $4) returning id`,
        [loserId, winnerId, JSON.stringify(repointed), actor.userId],
      );
      return { mergeLogId: log.rows[0].id, winnerId };
    });
  }

  // Reverse-op for each known repointed key. Hard-coded — never derives a table
  // name from stored data.
  private static readonly UNDO_REPOINT: Record<string, string> = {
    "students.lead_id": "update app.students set lead_id = $1, updated_at = now() where id = any($2::uuid[])",
    "lessons.lead_id": "update app.lessons set lead_id = $1 where id = any($2::uuid[])",
    "lead_status_history.lead_id": "update app.lead_status_history set lead_id = $1 where id = any($2::uuid[])",
    "tasks.entity_id": "update app.tasks set entity_id = $1 where id = any($2::uuid[])",
    "chats.lead_id": "update app.chats set lead_id = $1 where id = any($2::uuid[])",
    "entity_comments.entity_id": "update app.entity_comments set entity_id = $1 where id = any($2::uuid[])",
    "duplicate_candidates.status": "update app.duplicate_candidates set status = 'pending', updated_at = now() where id = any($2::uuid[])",
  };

  async undoMerge(actor: ActorContext, mergeLogId: string) {
    this.policy.assertCanWriteCrm(actor);
    return this.database.transaction(async (client) => {
      const logRes = await client.query<{
        loser_id: string;
        repointed: Record<string, string[]>;
      }>(
        `select loser_id, repointed from app.merge_log where id = $1 and undone_at is null`,
        [mergeLogId],
      );
      const log = logRes.rows[0];
      if (!log) {
        throw new NotFoundException("Слияние не найдено или уже отменено.");
      }
      for (const [key, sql] of Object.entries(MergeService.UNDO_REPOINT)) {
        const movedIds = log.repointed[key];
        if (!movedIds || movedIds.length === 0) continue;
        const isDupCandidate = key === "duplicate_candidates.status";
        await client.query(sql, isDupCandidate ? [null, movedIds] : [log.loser_id, movedIds]);
      }
      // The duplicate_candidates reverse SQL ignores $1; pass null there.
      await client.query(
        `update app.leads set deleted_at = null, updated_at = now() where id = $1`,
        [log.loser_id],
      );
      await client.query(
        `update app.merge_log set undone_at = now(), undone_by = $2 where id = $1`,
        [mergeLogId, actor.userId],
      );
      return { success: true as const };
    });
  }
}
