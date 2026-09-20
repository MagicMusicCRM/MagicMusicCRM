import { Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import {
  branchIdExpr,
  currentActorRoleSql,
  managerBranchScopeSql,
} from "./branch-scope";
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
      `insert into app.families (name, branch_id)
       select $1, $2::uuid
       where ${managerBranchScopeSql({
         roleExpression: currentActorRoleSql("$3"),
         userIdExpression: "$3",
         branchExpression: "$2::text",
       })}
       returning id, name, branch_id`,
      [dto.name ?? null, dto.branchId ?? null, actor.userId],
    );
    const row = result.rows[0];
    if (!row) throw new NotFoundException("Филиал недоступен.");
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
       select family.id, $2, $3, $4, $5
       from app.families family
       where family.id = $1 and family.deleted_at is null
         and ${managerBranchScopeSql({
           roleExpression: currentActorRoleSql("$6"),
           userIdExpression: "$6",
           branchExpression: "family.branch_id::text",
         })}
         and (
           ($2 = 'lead' and exists (
             select 1 from app.leads target
             where target.id = $3 and target.deleted_at is null
               and ${branchIdExpr("target")} = family.branch_id::text
           ))
           or ($2 = 'student' and exists (
             select 1 from app.students target
             where target.id = $3 and target.deleted_at is null
               and ${branchIdExpr("target")} = family.branch_id::text
           ))
           or ($2 = 'profile' and exists (
             select 1 from app.profiles target
             where target.id = $3 and target.deleted_at is null
               and (
                 ${currentActorRoleSql("$6")}::text <> all(array['admin', 'manager']::text[])
                 or exists (
                   select 1 from app.students target_student
                   where target_student.profile_id = target.id
                     and target_student.deleted_at is null
                     and ${branchIdExpr("target_student")} = family.branch_id::text
                 )
               )
           ))
         )
       on conflict (family_id, entity_type, entity_id)
       do update set role = excluded.role, is_primary_contact = excluded.is_primary_contact, deleted_at = null
       returning id, family_id, entity_type, entity_id, role`,
      [familyId, dto.entityType, dto.entityId, dto.role, dto.isPrimaryContact ?? false, actor.userId],
    );
    const row = result.rows[0];
    if (!row) {
      throw new NotFoundException(
        "Семья или участник не найдены в доступном филиале.",
      );
    }
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
          and ${managerBranchScopeSql({
            roleExpression: currentActorRoleSql("$3"),
            userIdExpression: "$3",
            branchExpression: "f.branch_id::text",
          })}
        limit 1`,
      [entityType, entityId, actor.userId],
    );
    const fam = famRes.rows[0];
    if (!fam) {
      const hiddenFamily = await this.database.query<{ exists: boolean }>(
        `select exists (
           select 1
           from app.family_members member
           join app.families family
             on family.id = member.family_id and family.deleted_at is null
           where member.entity_type = $1
             and member.entity_id = $2
             and member.deleted_at is null
         ) as exists`,
        [entityType, entityId],
      );
      if (hiddenFamily.rows[0]?.exists) {
        throw new NotFoundException('Семья не найдена.');
      }
      return { family: null, members: [] };
    }
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
          and exists (
            select 1 from app.families scoped_family
            where scoped_family.id = m.family_id
              and scoped_family.deleted_at is null
              and ${managerBranchScopeSql({
                roleExpression: currentActorRoleSql("$2"),
                userIdExpression: "$2",
                branchExpression: "scoped_family.branch_id::text",
              })}
          )
        order by m.role, member_name`,
      [fam.family_id, actor.userId],
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
    const result = await this.database.query<{
      member_id: string;
      is_primary_payer: boolean;
      removed_id: string | null;
    }>(
      `with candidate as (
         select member.id as member_id,
                coalesce(family.primary_payer_member_id = member.id, false) as is_primary_payer
         from app.family_members member
         join app.families family on family.id = member.family_id
         where member.id = $1
           and member.deleted_at is null
           and family.deleted_at is null
           and ${managerBranchScopeSql({
             roleExpression: currentActorRoleSql("$2"),
             userIdExpression: "$2",
             branchExpression: "family.branch_id::text",
           })}
       ), cleared_primary as (
         update app.families family
         set primary_payer_member_id = null,
             updated_at = now()
         from candidate
         where family.primary_payer_member_id = candidate.member_id
         returning family.id
       ), removed as (
         update app.family_members member
         set deleted_at = now()
         from candidate
         where member.id = candidate.member_id
           and (
             not candidate.is_primary_payer
             or exists (select 1 from cleared_primary)
           )
         returning member.id
       )
       select candidate.member_id, candidate.is_primary_payer,
              removed.id as removed_id
       from candidate
       left join removed on removed.id = candidate.member_id`,
      [memberId, actor.userId],
    );
    const status = result.rows[0];
    if (!status) {
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
      `update app.families family
          set primary_payer_member_id = $2, updated_at = now()
        where family.id = $1 and family.deleted_at is null
          and ${managerBranchScopeSql({
            roleExpression: currentActorRoleSql("$3"),
            userIdExpression: "$3",
            branchExpression: "family.branch_id::text",
          })}
          and exists (
            select 1 from app.family_members m
            where m.id = $2 and m.family_id = $1 and m.deleted_at is null
          )`,
      [familyId, memberId, actor.userId],
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
