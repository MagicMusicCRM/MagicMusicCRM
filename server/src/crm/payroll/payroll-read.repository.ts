import { Injectable } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import {
  completeTeacherPayrollScopeSql,
  currentActorRoleSql,
  managerBranchScopeSql,
} from "../branch-scope";
import { PayrollAccrualCalculator } from "./payroll-accrual-calculator";
import {
  PayrollLessonFilters,
  PayrollLessonRow,
  TeacherPayrollHeader,
  TeacherPayoutRow,
  TeacherRateEntry,
  TeacherRateRow,
  TeacherReportReadInput,
  TeacherReportRow,
} from "./payroll.types";

@Injectable()
export class PayrollReadRepository {
  private readonly calculator = new PayrollAccrualCalculator();

  constructor(private readonly database: DatabaseService) {}

  async loadPayrollLessons(
    filters: PayrollLessonFilters,
  ): Promise<PayrollLessonRow[]> {
    const result = await this.database.query<PayrollLessonRow>(
      `
        select l.id, l.teacher_id, l.student_id, l.lead_id, l.group_id,
          coalesce((select version from app.aggregate_versions
            where aggregate_type = 'schedule:teacher-rate-bulk'
              and aggregate_id = 'global'), 0) as rate_mutation_version,
          l.scheduled_at, l.duration_minutes, l.is_trial,
          l.teacher_rate, g.teacher_rate as group_rate, g.name as group_name,
          trim(coalesce(sp.first_name, '') || ' ' || coalesce(sp.last_name, '')) as student_name,
          trim(coalesce(ld.first_name, '') || ' ' || coalesce(ld.last_name, '')) as lead_name,
          lp.attendance_kind, lp.charge_share,
          compensation.id as settlement_fact_id,
          compensation.amount_minor as settled_amount_minor,
          compensation.compensation_type,
          compensation.compensation_rule_key,
          compensation.compensation_rule_label,
          compensation.compensation_actual_value,
          compensation.snapshot_rate as teacher_snapshot_rate,
          compensation.compensation_override_reason
        from app.lessons l
        left join app.groups g on g.id = l.group_id and g.deleted_at is null
        left join app.students s on s.id = l.student_id and s.deleted_at is null
        left join app.profiles sp on sp.id = s.profile_id and sp.deleted_at is null
        left join app.leads ld on ld.id = l.lead_id and ld.deleted_at is null
        left join app.lesson_participation lp
          on lp.lesson_id = l.id and lp.student_id = l.student_id
        left join app.lesson_teacher_compensation_facts_effective compensation
          on compensation.lesson_id = l.id
        where l.deleted_at is null
          and l.teacher_id is not null
          and l.status in ('completed', 'done')
          and ($1::uuid is null or l.teacher_id = $1)
          and ($2::uuid is null or l.branch_id = $2)
          and ($3::timestamptz is null or l.scheduled_at >= $3::timestamptz)
          and ($4::timestamptz is null or l.scheduled_at < $4::timestamptz)
          and ${managerBranchScopeSql({
            roleExpression: currentActorRoleSql("$5"),
            userIdExpression: "$5",
            branchExpression: "l.branch_id::text",
          })}
        order by l.scheduled_at asc, l.id asc
      `,
      [
        filters.teacherId ?? null,
        filters.branchId ?? null,
        filters.from ?? null,
        filters.to ?? null,
        filters.actor.userId,
      ],
    );
    return result.rows;
  }

  async loadTeacherRates(
    teacherIds: string[],
    detailActor?: ActorContext,
  ): Promise<Map<string, TeacherRateEntry[]>> {
    const map = new Map<string, TeacherRateEntry[]>();
    if (!teacherIds.length) return map;
    const result = await this.database.query<TeacherRateRow>(
      `
        select tr.id, tr.teacher_id, tr.rate, tr.effective_from, tr.created_at,
          author.first_name as author_first_name,
          author.last_name as author_last_name
        from app.teacher_rates tr
        left join app.users u on u.id = tr.created_by and u.deleted_at is null
        left join app.profiles author
          on author.user_id = u.id and author.deleted_at is null
        where tr.teacher_id = any($1::uuid[])
          and tr.deleted_at is null
          and (
            $2::uuid is null
            or ${completeTeacherPayrollScopeSql({
              roleExpression: currentActorRoleSql("$2"),
              userIdExpression: "$2",
              teacherExpression: "tr.teacher_id",
            })}
          )
        order by tr.teacher_id, tr.effective_from asc, tr.created_at asc, tr.id asc
      `,
      [teacherIds, detailActor?.userId ?? null],
    );
    for (const row of result.rows) this.addRate(map, row);
    return map;
  }

  async findTeacherPayrollHeader(
    teacherId: string,
    actor: ActorContext,
  ): Promise<TeacherPayrollHeader | null> {
    const result = await this.database.query<TeacherPayrollHeader>(
      `
        select t.id, coalesce(aggregate.version, 0) as version
        from app.teachers t
        left join app.aggregate_versions aggregate
          on aggregate.aggregate_type = 'teacher:payroll'
          and aggregate.aggregate_id = t.id::text
        where t.id = $1 and t.deleted_at is null
          and ${completeTeacherPayrollScopeSql({
            roleExpression: currentActorRoleSql("$2"),
            userIdExpression: "$2",
            teacherExpression: "t.id",
          })}
      `,
      [teacherId, actor.userId],
    );
    return result.rows[0] ?? null;
  }

  async listTeacherPayouts(
    teacherId: string,
    actor: ActorContext,
  ): Promise<TeacherPayoutRow[]> {
    const result = await this.database.query<TeacherPayoutRow>(
      `
        select tp.id, tp.teacher_id, tp.amount, tp.kind, tp.comment, tp.paid_at,
          author.first_name as author_first_name,
          author.last_name as author_last_name
        from app.teacher_payouts tp
        left join app.users u on u.id = tp.created_by and u.deleted_at is null
        left join app.profiles author on author.user_id = u.id and author.deleted_at is null
        where tp.deleted_at is null and tp.teacher_id = $1
          and ${completeTeacherPayrollScopeSql({
            roleExpression: currentActorRoleSql("$2"),
            userIdExpression: "$2",
            teacherExpression: "tp.teacher_id",
          })}
        order by tp.paid_at desc, tp.id desc
      `,
      [teacherId, actor.userId],
    );
    return result.rows;
  }

  async listReportTeachers(
    input: TeacherReportReadInput,
  ): Promise<TeacherReportRow[]> {
    const result = await this.database.query<TeacherReportRow>(
      `
        select t.id, t.salary,
          trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')) as name
        from app.teachers t
        left join app.profiles p on p.id = t.profile_id and p.deleted_at is null
        where t.deleted_at is null
          and ($1::uuid is null or t.id = $1)
          and t.id = any($2::uuid[])
          and ($3::text is null or t.status = $3)
          and (
            $4::text is null
            or exists (
              select 1 from app.teacher_disciplines td
              join app.disciplines d
                on d.id = td.discipline_id and d.deleted_at is null
              where td.teacher_id = t.id and lower(d.name) = lower($4)
            )
            or lower(coalesce(t.specialization, '')) like '%' || lower($4) || '%'
          )
          and (
            $5::text is null
            or lower(
              coalesce(t.custom_data->>'categories', t.custom_data->>'category', '')
            ) like '%' || lower($5) || '%'
          )
      `,
      [
        input.teacherId,
        input.lessonTeacherIds,
        input.status,
        input.discipline,
        input.category,
      ],
    );
    return result.rows;
  }

  async findPayout(entryId: string): Promise<TeacherPayoutRow | null> {
    const result = await this.database.query<TeacherPayoutRow>(
      `
        select id, teacher_id, amount, kind, comment, paid_at
        from app.teacher_payouts
        where id = $1 and deleted_at is null
      `,
      [entryId],
    );
    return result.rows[0] ?? null;
  }

  async findRate(entryId: string): Promise<TeacherRateRow | null> {
    const result = await this.database.query<TeacherRateRow>(
      `
        select id, teacher_id, rate, effective_from, created_at
        from app.teacher_rates
        where id = $1
      `,
      [entryId],
    );
    return result.rows[0] ?? null;
  }

  private addRate(
    map: Map<string, TeacherRateEntry[]>,
    row: TeacherRateRow,
  ): void {
    const list = map.get(row.teacher_id) ?? [];
    list.push({
      id: row.id ?? null,
      rate: Number(row.rate),
      effectiveFrom: this.calculator.toDateOnly(row.effective_from),
      createdAt: row.created_at ?? null,
      authorName:
        [row.author_first_name, row.author_last_name]
          .filter(Boolean)
          .join(" ") || null,
    });
    map.set(row.teacher_id, list);
  }
}
