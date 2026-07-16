import { Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { SetBlacklistDto } from "./dto/set-blacklist.dto";

interface BlacklistRow {
  id: string;
  blacklisted: boolean;
  blacklisted_at: Date | string | null;
  blacklisted_by: string | null;
  blacklist_reason: string | null;
}

/**
 * Чёрный список клиента — бан (✔ решение владельца 17.07).
 *
 * Отдельный сервис и отдельный эндпоинт, а не поле в `updateStudent`, по двум
 * причинам:
 *  - бан — модерационное действие: у него есть автор, время и причина, и он
 *    обязан попасть в аудит именно как бан, а не раствориться в общем diff'е
 *    «поменяли карточку»;
 *  - он снимает человеку доступ к чатам. Такое не должно уезжать вместе с
 *    патчем произвольных полей карточки — в том числе случайно.
 *
 * Ставится на обе половины карточки (лид и ученик), потому что клиентский
 * аккаунт цепляется к любой из них — см. `blacklist.ts`.
 */
@Injectable()
export class BlacklistService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
  ) {}

  async setStudentBlacklist(
    actor: ActorContext,
    studentId: string,
    dto: SetBlacklistDto,
  ) {
    return this.setBlacklist(actor, "student", studentId, dto);
  }

  async setLeadBlacklist(
    actor: ActorContext,
    leadId: string,
    dto: SetBlacklistDto,
  ) {
    return this.setBlacklist(actor, "lead", leadId, dto);
  }

  private async setBlacklist(
    actor: ActorContext,
    entity: "student" | "lead",
    id: string,
    dto: SetBlacklistDto,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const table = entity === "student" ? "app.students" : "app.leads";
    const reason = dto.reason?.trim() || null;

    const result = await this.database.query<BlacklistRow>(
      `
        update ${table}
        set blacklisted = $2,
            -- Снятие стирает и автора, и причину: «снят, но причина всё ещё
            -- висит» читалось бы как «всё ещё в списке».
            blacklisted_at = case when $2 then now() else null end,
            blacklisted_by = case when $2 then $3::uuid else null end,
            blacklist_reason = case when $2 then $4 else null end,
            updated_at = now()
        where id = $1 and deleted_at is null
        returning id, blacklisted, blacklisted_at, blacklisted_by,
          blacklist_reason
      `,
      [id, dto.blacklisted, actor.userId, reason],
    );
    const row = result.rows[0];
    if (!row) {
      throw new NotFoundException(
        entity === "student" ? "Ученик не найден." : "Лид не найден.",
      );
    }

    await this.audit.record({
      actor,
      action: dto.blacklisted
        ? "crm.client_blacklisted"
        : "crm.client_unblacklisted",
      entityType: entity,
      entityId: id,
      metadata: { reason },
    });
    this.realtime.emitCrmChanged({
      entity,
      action: "updated",
      id,
    });

    return {
      id: row.id,
      blacklisted: row.blacklisted,
      blacklistedAt: row.blacklisted_at,
      blacklistedBy: row.blacklisted_by,
      blacklistReason: row.blacklist_reason,
    };
  }
}
