import { branchIdExpr } from "./branch-scope";
import { LeadBoardQuery } from "./dto/lead-board.query";
import { leadStudentMatchSql } from "./lead-student-link";
import { buildTextSearch } from "./search-text";

interface FilterBuilder {
  filters: string[];
  params: unknown[];
  add: (value: unknown) => string;
}

function createFilterBuilder(): FilterBuilder {
  const params: unknown[] = [];
  return {
    filters: ["l.deleted_at is null"],
    params,
    add: (value) => {
      params.push(value);
      return `$${params.length}`;
    },
  };
}

function addTextFilter(
  builder: FilterBuilder,
  expression: string,
  value: string | undefined,
  fuzzy = false,
) {
  const trimmed = value?.trim();
  if (!trimmed) return;
  const parameter = builder.add(trimmed);
  builder.filters.push(
    fuzzy
      ? `lower(${expression}) like lower('%' || ${parameter}::text || '%')`
      : `lower(${expression}) = lower(${parameter}::text)`,
  );
}

function addSearchFilter(builder: FilterBuilder, query: LeadBoardQuery) {
  const q = query.q?.trim();
  if (!q) return;
  builder.filters.push(
    buildTextSearch({
      q,
      columns: [
        "l.first_name",
        "l.last_name",
        "l.email",
        "l.phone",
        "l.source",
        "l.notes",
      ],
      phoneColumn: "l.phone",
      customDataColumn: "l.custom_data",
      add: builder.add,
    }).where,
  );
}

function addIdentityFilters(builder: FilterBuilder, query: LeadBoardQuery) {
  if (query.statusId) {
    builder.filters.push(`l.status_id = ${builder.add(query.statusId)}::uuid`);
  } else if (query.unassigned === true) {
    builder.filters.push("l.status_id is null");
  }
  if (query.assignedTo) {
    builder.filters.push(
      `l.assigned_to = ${builder.add(query.assignedTo)}::uuid`,
    );
  }
  if (query.branchId) {
    const parameter = builder.add(query.branchId);
    builder.filters.push(`${branchIdExpr("l")} = ${parameter}::text`);
  }
}

function addConfiguredFieldFilters(
  builder: FilterBuilder,
  query: LeadBoardQuery,
) {
  addTextFilter(builder, "l.source", query.source);
  const configured: Array<[string, string | undefined, boolean?]> = [
    [
      "coalesce(l.custom_data->>'discipline', l.custom_data->>'disciplineName', l.custom_data->>'discipline_name')",
      query.discipline,
    ],
    [
      "coalesce(l.custom_data->>'level', l.custom_data->>'levelName', l.custom_data->>'level_name')",
      query.level,
    ],
    [
      "coalesce(l.custom_data->>'category', l.custom_data->>'categoryName', l.custom_data->>'category_name', l.custom_data->>'maturity')",
      query.category,
    ],
    [
      "coalesce(l.custom_data->>'requestType', l.custom_data->>'request_type', l.custom_data->>'type')",
      query.requestType,
    ],
    [
      "coalesce(l.custom_data->>'goal', l.custom_data->>'learningGoal', l.custom_data->>'learning_goal')",
      query.goal,
    ],
    ["coalesce(l.custom_data->>'gender', l.custom_data->>'sex')", query.gender],
    [
      "coalesce(l.custom_data->>'preferredSchedule', l.custom_data->>'preferred_schedule')",
      query.preferredSchedule,
      true,
    ],
  ];
  for (const [expression, value, fuzzy] of configured) {
    addTextFilter(builder, expression, value, fuzzy);
  }
}

function addRangeFilters(builder: FilterBuilder, query: LeadBoardQuery) {
  if (query.from) {
    builder.filters.push(
      `l.created_at >= ${builder.add(query.from)}::timestamptz`,
    );
  }
  if (query.to) {
    builder.filters.push(
      `l.created_at < ${builder.add(query.to)}::timestamptz`,
    );
  }
}

function addTaskFilter(
  builder: FilterBuilder,
  query: LeadBoardQuery,
  actorUserId: string,
) {
  if (query.openTasks !== true) return;
  builder.filters.push(`
    exists (
      select 1
      from app.canonical_tasks open_task
      where open_task.deleted_at is null
        and open_task.entity_type = 'lead'
        and open_task.entity_id = l.id
        and open_task.status in ('open', 'in_progress')
        and exists (
          select 1 from app.shared_task_visibility visibility
          where visibility.task_id = open_task.id
            and visibility.user_id = ${builder.add(actorUserId)}::uuid
        )
    )
  `);
}

function addConvertedFilter(builder: FilterBuilder, query: LeadBoardQuery) {
  if (query.hideConverted !== true) return;
  builder.filters.push(`
    not exists (
      select 1
      from app.students linked_conv
      left join app.profiles p_conv
        on p_conv.id = linked_conv.profile_id
       and p_conv.deleted_at is null
      where linked_conv.deleted_at is null
        and linked_conv.status = 'active'
        and (
          linked_conv.lead_id = l.id
          or (${leadStudentMatchSql("l", "p_conv")})
        )
    )
  `);
}

export function decodeLeadCursor(cursor: string | undefined) {
  if (!cursor) return null;
  const [createdAt, id] = cursor.split("|");
  if (!createdAt || !id || Number.isNaN(Date.parse(createdAt))) return null;
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      id,
    )
  ) {
    return null;
  }
  return { createdAt, id };
}

function addCursorFilter(builder: FilterBuilder, query: LeadBoardQuery) {
  const cursor = decodeLeadCursor(query.cursor);
  if (!cursor) return;
  const createdAt = builder.add(cursor.createdAt);
  const id = builder.add(cursor.id);
  const comparator = query.sort === "oldest" ? ">" : "<";
  builder.filters.push(
    `(l.created_at, l.id) ${comparator} (${createdAt}::timestamptz, ${id}::uuid)`,
  );
}

function addQuickFilter(builder: FilterBuilder, query: LeadBoardQuery) {
  const quick = query.quick ?? "all";
  if (quick === "all") return;
  const group =
    "lower(coalesce(l.custom_data->>'statusGroup', l.custom_data->>'status_group', ''))";
  const status = "lower(coalesce(ls.name, ''))";
  const processed = `${group} = 'processed' or ${status} like '%обработ%' or ${status} like '%закрыт%' or ${status} like '%отказ%' or ${status} like '%processed%'`;
  const deferred = `${group} = 'deferred' or ${status} like '%отлож%' or ${status} like '%перезвон%' or ${status} like '%defer%'`;
  if (quick === "processed") {
    builder.filters.push(`(${processed})`);
  } else if (quick === "deferred") {
    builder.filters.push(`(${deferred})`);
  } else if (quick === "new") {
    builder.filters.push(`(l.status_id is null or ${status} in ('new', 'новый'))`);
  } else {
    builder.filters.push(`not (${processed}) and not (${deferred})`);
  }
}

export function buildLeadBoardFilter(
  query: LeadBoardQuery,
  actorUserId: string,
) {
  const builder = createFilterBuilder();
  addSearchFilter(builder, query);
  addIdentityFilters(builder, query);
  addConfiguredFieldFilters(builder, query);
  addRangeFilters(builder, query);
  addTaskFilter(builder, query, actorUserId);
  addConvertedFilter(builder, query);
  addCursorFilter(builder, query);
  addQuickFilter(builder, query);
  return {
    where: builder.filters.join("\n          and "),
    params: builder.params,
  };
}
