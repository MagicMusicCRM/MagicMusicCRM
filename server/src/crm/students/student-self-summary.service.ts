import { Injectable } from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { ScheduleReadService } from "../schedule/schedule-read.service";
import { StudentRow } from "../student-read";
import { SharedTaskService } from "../tasks/shared-task.service";
import { toStudentDto } from "./student-presenter";

@Injectable()
export class StudentSelfSummaryService {
  constructor(
    private readonly database: DatabaseService,
    private readonly tasks: SharedTaskService,
    private readonly scheduleRead: ScheduleReadService,
  ) {}

  async getMySummary(actor: ActorContext) {
    const ownStudents = await this.listClientStudents(actor.userId);
    const familyStudents = await this.listFamilyLinkedStudents(actor.userId);
    const linkedStudents = await this.listManuallyLinkedStudents(actor.userId);
    const byId = new Map<string, StudentRow>();
    for (const row of ownStudents) byId.set(row.id, row);
    for (const row of familyStudents) {
      if (!byId.has(row.id)) byId.set(row.id, row);
    }
    for (const row of linkedStudents) {
      if (!byId.has(row.id)) byId.set(row.id, row);
    }

    const students = Array.from(byId.values());
    const studentIds = students.map((student) => student.id);
    let upcomingLessons: unknown[] = [];
    let openTasks: unknown[] = [];
    if (studentIds.length) {
      [upcomingLessons, openTasks] = await Promise.all([
        this.scheduleRead
          .listUpcomingLessonsForStudents(studentIds)
          .catch(() => []),
        Promise.all(
          studentIds.map((studentId) =>
            this.tasks.list(actor, {
              state: "open",
              linkedEntityType: "student",
              linkedEntityId: studentId,
              limit: 20,
            }),
          ),
        )
          .then((results) => results.flatMap((result) => result.items))
          .catch(() => []),
      ]);
    }

    return {
      students: students.map((row) => toStudentDto(row)),
      upcomingLessons,
      tasks: openTasks,
    };
  }

  private async listClientStudents(userId: string): Promise<StudentRow[]> {
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.version, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, s.blacklisted, s.blacklist_reason, p.first_name, p.last_name, u.email, p.phone, s.created_at,
          '{}'::uuid[] as teacher_user_ids
        from app.students s
        join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        where s.deleted_at is null and p.user_id = $1
        order by s.created_at desc
      `,
      [userId],
    );
    return result.rows;
  }

  private async listFamilyLinkedStudents(
    userId: string,
  ): Promise<StudentRow[]> {
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.version, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, s.blacklisted, s.blacklist_reason, p.first_name, p.last_name, u.email, p.phone, s.created_at,
          '{}'::uuid[] as teacher_user_ids
        from app.profiles acct
        join app.family_members parent_m
          on parent_m.entity_type = 'profile'
          and parent_m.entity_id = acct.id
          and parent_m.role in ('parent', 'payer')
          and parent_m.deleted_at is null
        join app.families f
          on f.id = parent_m.family_id and f.deleted_at is null
        join app.family_members child_m
          on child_m.family_id = f.id
          and child_m.entity_type = 'student'
          and child_m.deleted_at is null
        join app.students s
          on s.id = child_m.entity_id and s.deleted_at is null
        join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        where acct.user_id = $1 and acct.deleted_at is null
        order by s.created_at desc
      `,
      [userId],
    );
    return result.rows;
  }

  private async listManuallyLinkedStudents(
    userId: string,
  ): Promise<StudentRow[]> {
    const result = await this.database.query<StudentRow>(
      `
        select s.id, s.version, s.status, s.profile_id, p.user_id as profile_user_id,
          s.lead_id, s.custom_data, s.blacklisted, s.blacklist_reason, p.first_name, p.last_name, u.email, p.phone, s.created_at,
          '{}'::uuid[] as teacher_user_ids
        from app.user_crm_links link
        join app.students s
          on s.id = link.entity_id and s.deleted_at is null
        left join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        left join app.users u on u.id = p.user_id and u.deleted_at is null
        where link.user_id = $1
          and link.entity_type = 'student'
          and link.deleted_at is null
        order by s.created_at desc
      `,
      [userId],
    );
    return result.rows;
  }
}
