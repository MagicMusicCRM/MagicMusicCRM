import { ActorContext } from "../../common/security/actor-context";
import { managerAdminRolesSql } from "../../common/security/role-sql";
import { branchIdExpr, managerBranchScopeSql } from "../branch-scope";
import { StudentSearchQuery } from "../dto/student-search.query";
import { buildTextSearch } from "../search-text";
import { studentContactEmailSql } from "./student-contact-email";

export interface StudentSearchSqlFilter {
  where: string;
  params: unknown[];
  searchRank: string | null;
}

type AddParameter = (value: unknown) => string;

function addActorScope(
  filters: string[],
  add: AddParameter,
  actor: ActorContext,
) {
  const role = add(actor.role);
  const userId = add(actor.userId);
  filters.push(`
      (
        ${managerAdminRolesSql(role)}
        or (${role}::text = 'teacher' and tp.user_id = ${userId})
      )
    `);
  filters.push(
    managerBranchScopeSql({
      roleExpression: role,
      userIdExpression: userId,
      branchExpression: branchIdExpr("s"),
    }),
  );
  return { role, userId };
}

function addTextFilter(
  filters: string[],
  add: AddParameter,
  expression: string,
  value: string | undefined,
) {
  const trimmed = value?.trim();
  if (!trimmed) return;
  const parameter = add(trimmed);
  filters.push(`lower(${expression}) = lower(${parameter}::text)`);
}

function addTextAndScalarFilters(
  filters: string[],
  add: AddParameter,
  query: StudentSearchQuery,
) {
  const q = query.q?.trim();
  let searchRank: string | null = null;
  if (q) {
    const search = buildTextSearch({
      q,
      columns: [
        "p.first_name",
        "p.last_name",
        studentContactEmailSql(),
        "p.phone",
      ],
      phoneColumn: "p.phone",
      customDataColumn: "s.custom_data",
      exactColumn: "concat_ws(' ', p.first_name, p.last_name)",
      add,
    });
    filters.push(search.where);
    searchRank = search.rank;
  }
  if (query.status?.trim()) {
    filters.push(`s.status = ${add(query.status.trim())}::text`);
  }
  if (query.branchId) {
    const parameter = add(query.branchId);
    filters.push(`${branchIdExpr("s")} = ${parameter}::text`);
  }
  if (query.noBranch) {
    filters.push(`${branchIdExpr("s")} is null`);
  }
  if (query.groupId) {
    filters.push(`
        exists (
          select 1
          from app.group_students group_filter
          where group_filter.student_id = s.id
            and group_filter.group_id = ${add(query.groupId)}::uuid
            and group_filter.left_at is null
        )
      `);
  }
  addTextFilter(
    filters,
    add,
    "coalesce(s.custom_data->>'discipline', s.custom_data->>'disciplineName', s.custom_data->>'discipline_name')",
    query.discipline,
  );
  addTextFilter(
    filters,
    add,
    "coalesce(s.custom_data->>'level', s.custom_data->>'levelName', s.custom_data->>'level_name')",
    query.level,
  );
  addTextFilter(
    filters,
    add,
    "coalesce(s.custom_data->>'category', s.custom_data->>'categoryName', s.custom_data->>'category_name', s.custom_data->>'maturity')",
    query.category,
  );
  if (query.from)
    filters.push(`s.created_at >= ${add(query.from)}::timestamptz`);
  if (query.to) filters.push(`s.created_at < ${add(query.to)}::timestamptz`);
  return searchRank;
}

function addActivityAndCursorFilters(
  filters: string[],
  add: AddParameter,
  userId: string,
  query: StudentSearchQuery,
) {
  if (query.linkedUser !== undefined) {
    const condition =
      "(exists (select 1 from app.user_crm_links link_filter where link_filter.entity_type = 'student' and link_filter.entity_id = s.id and link_filter.deleted_at is null) or u.is_app_account = true)";
    filters.push(query.linkedUser ? condition : `not ${condition}`);
  }
  if (query.noEmail === true) {
    filters.push(`coalesce(${studentContactEmailSql()}, '') = ''`);
  }
  if (query.noOpenTasks === true) {
    filters.push(`
        not exists (
          select 1
          from app.canonical_tasks task_filter
          where task_filter.entity_type = 'student'
            and task_filter.entity_id = s.id
            and task_filter.deleted_at is null
            and task_filter.status in ('open', 'in_progress')
            and exists (
              select 1 from app.shared_task_visibility visibility
              where visibility.task_id = task_filter.id
                and visibility.user_id = ${userId}::uuid
            )
        )
      `);
  }
  if (query.cursor) {
    const [createdAt, id] = query.cursor.split("|");
    if (createdAt && id) {
      const created = add(createdAt);
      const studentId = add(id);
      filters.push(
        `(s.created_at, s.id) < (${created}::timestamptz, ${studentId}::uuid)`,
      );
    }
  }
}

export function buildStudentSearchFilter(
  actor: ActorContext,
  query: StudentSearchQuery,
): StudentSearchSqlFilter {
  const params: unknown[] = [];
  const filters = ["s.deleted_at is null"];
  const add: AddParameter = (value) => {
    params.push(value);
    return `$${params.length}`;
  };
  const { userId } = addActorScope(filters, add, actor);
  const searchRank = addTextAndScalarFilters(filters, add, query);
  addActivityAndCursorFilters(filters, add, userId, query);
  return { where: filters.join("\n          and "), params, searchRank };
}
