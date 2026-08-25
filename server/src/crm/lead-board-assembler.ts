import { ClientPipelineStageDto } from "./dto/student-funnel.dto";
import {
  encodeLeadCursor,
  LeadBoardColumnDto,
  LeadBoardCountRow,
  LeadBoardRow,
  LeadStatusRow,
  toLeadBoardItemDto,
  toLeadStatusDto,
  toNumericStat,
} from "./lead-model";

export interface LeadBoardAssemblyInput {
  statuses: LeadStatusRow[];
  counts: LeadBoardCountRow[];
  rows: LeadBoardRow[];
  stages: ClientPipelineStageDto[];
  limit: number;
  requestedColumnId: string | null;
  unassignedSort: number | null;
}

function countByStatus(rows: LeadBoardCountRow[]) {
  return new Map(
    rows.map((row) => [row.status_id ?? "unassigned", toNumericStat(row.count)]),
  );
}

function selectStatuses(
  statuses: LeadStatusRow[],
  stages: ClientPipelineStageDto[],
  counts: Map<string, number>,
  requestedColumnId: string | null,
) {
  if (stages.length === 0) return statuses;
  const byKey = new Map(statuses.map((status) => [status.stage_key, status]));
  return stages.flatMap((stage, sortOrder) => {
    const status = byKey.get(stage.key);
    if (!status) return [];
    if (
      !stage.active &&
      (counts.get(status.id) ?? 0) === 0 &&
      requestedColumnId !== status.id
    ) {
      return [];
    }
    return [
      {
        ...status,
        name: stage.label,
        color: stage.style,
        sort_order: sortOrder,
        requires_reason: stage.requiresReason,
        is_terminal: stage.terminal,
      },
    ];
  });
}

function createColumns(
  statuses: LeadStatusRow[],
  counts: Map<string, number>,
  requestedColumnId: string | null,
) {
  return statuses
    .filter(
      (status) =>
        requestedColumnId === null || requestedColumnId === status.id,
    )
    .map<LeadBoardColumnDto>((status) => ({
      ...toLeadStatusDto(status),
      totalCount: counts.get(status.id) ?? 0,
      items: [],
      nextCursor: null,
    }));
}

function collectRows(
  rows: LeadBoardRow[],
  columns: LeadBoardColumnDto[],
  counts: Map<string, number>,
  unassignedSort: number | null,
) {
  const byStatus = new Map(columns.map((column) => [column.id, column]));
  const rowsByStatus = new Map<string, LeadBoardRow[]>();
  for (const row of rows) {
    const statusKey = row.status_id ?? "unassigned";
    const statusRows = rowsByStatus.get(statusKey) ?? [];
    statusRows.push(row);
    rowsByStatus.set(statusKey, statusRows);
    if (byStatus.has(statusKey)) continue;
    const column: LeadBoardColumnDto = {
      id: statusKey,
      stageKey: row.status_key ?? statusKey,
      name: row.status_name ?? "Без статуса",
      color: row.status_color ?? null,
      sortOrder:
        statusKey === "unassigned"
          ? (unassignedSort ?? 9999)
          : (row.status_sort_order ?? 9999),
      createdAt: row.created_at,
      requiresReason: false,
      isTerminal: false,
      totalCount: counts.get(statusKey) ?? 0,
      items: [],
      nextCursor: null,
    };
    byStatus.set(statusKey, column);
    columns.push(column);
  }
  return { byStatus, rowsByStatus };
}

function ensureRequestedUnassigned(
  requestedColumnId: string | null,
  unassignedSort: number | null,
  counts: Map<string, number>,
  columns: LeadBoardColumnDto[],
  byStatus: Map<string, LeadBoardColumnDto>,
) {
  if (requestedColumnId !== "unassigned" || byStatus.has("unassigned")) return;
  const column: LeadBoardColumnDto = {
    id: "unassigned",
    stageKey: "unassigned",
    name: "Без статуса",
    color: null,
    sortOrder: unassignedSort ?? 9999,
    createdAt: null,
    requiresReason: false,
    isTerminal: false,
    totalCount: counts.get("unassigned") ?? 0,
    items: [],
    nextCursor: null,
  };
  byStatus.set(column.id, column);
  columns.push(column);
}

function populatePages(
  rowsByStatus: Map<string, LeadBoardRow[]>,
  byStatus: Map<string, LeadBoardColumnDto>,
  limit: number,
) {
  const returnedLeadIds = new Set<string>();
  for (const [statusKey, rows] of rowsByStatus) {
    const column = byStatus.get(statusKey);
    if (!column) continue;
    const returnedRows = rows.slice(0, limit);
    for (const row of returnedRows) returnedLeadIds.add(row.id);
    column.items.push(...returnedRows.map(toLeadBoardItemDto));
    column.nextCursor =
      rows.length > limit && returnedRows.length > 0
        ? encodeLeadCursor(returnedRows[returnedRows.length - 1])
        : null;
  }
  return returnedLeadIds;
}

function sortColumns(columns: LeadBoardColumnDto[]) {
  columns.sort((left, right) => {
    const order = (left.sortOrder ?? 9999) - (right.sortOrder ?? 9999);
    return order !== 0
      ? order
      : String(left.name).localeCompare(String(right.name), "ru");
  });
}

function legacyCursor(
  rows: LeadBoardRow[],
  columns: LeadBoardColumnDto[],
  returnedLeadIds: Set<string>,
  requestedColumnId: string | null,
) {
  if (requestedColumnId !== null) return null;
  if (!columns.some((column) => column.nextCursor !== null)) return null;
  const boundary = [...rows].reverse().find((row) => returnedLeadIds.has(row.id));
  return boundary ? encodeLeadCursor(boundary) : null;
}

export function assembleLeadBoard(input: LeadBoardAssemblyInput) {
  const counts = countByStatus(input.counts);
  const statuses = selectStatuses(
    input.statuses,
    input.stages,
    counts,
    input.requestedColumnId,
  );
  const columns = createColumns(statuses, counts, input.requestedColumnId);
  const { byStatus, rowsByStatus } = collectRows(
    input.rows,
    columns,
    counts,
    input.unassignedSort,
  );
  ensureRequestedUnassigned(
    input.requestedColumnId,
    input.unassignedSort,
    counts,
    columns,
    byStatus,
  );
  const returnedLeadIds = populatePages(rowsByStatus, byStatus, input.limit);
  sortColumns(columns);
  return {
    columns,
    totalCount: Array.from(counts.values()).reduce(
      (sum, count) => sum + count,
      0,
    ),
    nextCursor: legacyCursor(
      input.rows,
      columns,
      returnedLeadIds,
      input.requestedColumnId,
    ),
  };
}
