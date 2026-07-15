import { Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";

/**
 * Family grouping (app.families / app.family_members): create a family, attach
 * lead/student/profile members, resolve the family for an entity, and pick the
 * primary payer. Extracted from CrmService (B5) — self-contained, no
 * back-injection.
 */
@Injectable()
export class FamilyService {
  constructor(
    private readonly database: DatabaseService,
    private readonly policy: CrmPolicy,
    private readonly audit: AuditService,
  ) {}

  async createFamily(actor: ActorContext, dto: { name?: string; branchId?: string }) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{ id: string; name: string | null; branch_id: string | null }>(
      `insert into app.families (name, branch_id) values ($1, $2) returning id, name, branch_id`,
      [dto.name ?? null, dto.branchId ?? null],
    );
    const row = result.rows[0];
    return { id: row.id, name: row.name, branchId: row.branch_id };
  }

  async addFamilyMember(
    actor: ActorContext,
    familyId: string,
    dto: { entityType: string; entityId: string; role: string; isPrimaryContact?: boolean },
  ) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query<{
      id: string;
      family_id: string;
      entity_type: string;
      entity_id: string;
      role: string;
    }>(
      `insert into app.family_members (family_id, entity_type, entity_id, role, is_primary_contact)
       values ($1, $2, $3, $4, $5)
       on conflict (family_id, entity_type, entity_id)
       do update set role = excluded.role, is_primary_contact = excluded.is_primary_contact, deleted_at = null
       returning id, family_id, entity_type, entity_id, role`,
      [familyId, dto.entityType, dto.entityId, dto.role, dto.isPrimaryContact ?? false],
    );
    const row = result.rows[0];
    await this.audit.record({
      actor,
      action: "crm.family_member_added",
      entityType: "family",
      entityId: familyId,
      metadata: {
        memberId: row.id,
        entityType: dto.entityType,
        entityId: dto.entityId,
        role: dto.role,
      },
    });
    return { id: row.id, familyId: row.family_id, entityType: row.entity_type, entityId: row.entity_id, role: row.role };
  }

  async getFamilyForEntity(actor: ActorContext, entityType: string, entityId: string) {
    this.policy.assertCanReadOperationalData(actor);
    const famRes = await this.database.query<{
      family_id: string;
      name: string | null;
      branch_id: string | null;
      primary_payer_member_id: string | null;
    }>(
      `select f.id as family_id, f.name, f.branch_id, f.primary_payer_member_id
         from app.family_members m
         join app.families f on f.id = m.family_id and f.deleted_at is null
        where m.entity_type = $1 and m.entity_id = $2 and m.deleted_at is null
        limit 1`,
      [entityType, entityId],
    );
    const fam = famRes.rows[0];
    if (!fam) return { family: null, members: [] };
    const memRes = await this.database.query<{
      id: string;
      entity_type: string;
      entity_id: string;
      role: string;
      is_primary_contact: boolean;
      member_name: string | null;
    }>(
      `select m.id, m.entity_type, m.entity_id, m.role, m.is_primary_contact,
              coalesce(
                nullif(btrim(concat_ws(' ', l.first_name, l.last_name)), ''),
                nullif(btrim(concat_ws(' ', sp.first_name, sp.last_name)), ''),
                nullif(btrim(concat_ws(' ', pr.first_name, pr.last_name)), '')
              ) as member_name
         from app.family_members m
         left join app.leads l    on m.entity_type = 'lead'    and l.id = m.entity_id and l.deleted_at is null
         left join app.students st on m.entity_type = 'student' and st.id = m.entity_id and st.deleted_at is null
         left join app.profiles sp on sp.id = st.profile_id and sp.deleted_at is null
         left join app.profiles pr on m.entity_type = 'profile' and pr.id = m.entity_id and pr.deleted_at is null
        where m.family_id = $1 and m.deleted_at is null
        order by m.role, member_name`,
      [fam.family_id],
    );
    return {
      family: {
        id: fam.family_id,
        name: fam.name,
        branchId: fam.branch_id,
        primaryPayerMemberId: fam.primary_payer_member_id,
      },
      members: memRes.rows.map((row) => ({
        id: row.id,
        entityType: row.entity_type,
        entityId: row.entity_id,
        role: row.role,
        isPrimaryContact: row.is_primary_contact,
        name: row.member_name,
      })),
    };
  }

  async removeFamilyMember(actor: ActorContext, memberId: string) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query(
      `update app.family_members set deleted_at = now() where id = $1 and deleted_at is null`,
      [memberId],
    );
    if (!result.rowCount) {
      throw new NotFoundException("Участник семьи не найден.");
    }
    await this.audit.record({
      actor,
      action: "crm.family_member_removed",
      entityType: "family_member",
      entityId: memberId,
    });
    return { success: true as const };
  }

  async setPrimaryPayer(actor: ActorContext, familyId: string, memberId: string) {
    this.policy.assertCanWriteCrm(actor);
    const result = await this.database.query(
      `update app.families
          set primary_payer_member_id = $2, updated_at = now()
        where id = $1 and deleted_at is null
          and exists (
            select 1 from app.family_members m
            where m.id = $2 and m.family_id = $1 and m.deleted_at is null
          )`,
      [familyId, memberId],
    );
    if (!result.rowCount) {
      throw new NotFoundException("Семья или участник не найдены.");
    }
    await this.audit.record({
      actor,
      action: "crm.family_primary_payer_set",
      entityType: "family",
      entityId: familyId,
      metadata: { memberId },
    });
    return { success: true as const };
  }
}
