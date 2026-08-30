import { ActorContext } from "../../common/security/actor-context";
import { StudentSearchQuery } from "../dto/student-search.query";
import { buildStudentSearchFilter } from "./student-search-filter";

describe("buildStudentSearchFilter", () => {
  const manager: ActorContext = { userId: "manager-a", role: "manager" };
  const teacher: ActorContext = { userId: "teacher-a", role: "teacher" };

  it.each([
    ["q", { q: "  Анна  " }, ["manager", "manager-a", "анна", null], "btrim(s.contact_email)"],
    ["status", { status: " active " }, ["manager", "manager-a", "active"], "s.status = $3::text"],
    ["branch", { branchId: "branch-a" }, ["manager", "manager-a", "branch-a"], "coalesce(s.branch_id::text"],
    ["no branch", { noBranch: true }, ["manager", "manager-a"], "coalesce(s.branch_id::text, s.custom_data->>'branchId', s.custom_data->>'branch_id') is null"],
    ["group", { groupId: "group-a" }, ["manager", "manager-a", "group-a"], "group_filter.group_id = $3::uuid"],
    ["discipline", { discipline: " Вокал " }, ["manager", "manager-a", "Вокал"], "lower(coalesce(s.custom_data->>'discipline'"],
    ["level", { level: "Начальный" }, ["manager", "manager-a", "Начальный"], "s.custom_data->>'levelName'"],
    ["category", { category: "Дети" }, ["manager", "manager-a", "Дети"], "s.custom_data->>'maturity'"],
    ["date bounds", { from: "2026-01-01", to: "2026-02-01" }, ["manager", "manager-a", "2026-01-01", "2026-02-01"], "s.created_at < $4::timestamptz"],
    ["linked user", { linkedUser: true }, ["manager", "manager-a"], "or u.is_app_account = true"],
    ["not linked", { linkedUser: false }, ["manager", "manager-a"], "not (exists (select 1 from app.user_crm_links"],
    ["no email", { noEmail: true }, ["manager", "manager-a"], "when lower(u.email) like '%@local.magicmusiccrm.invalid' then null"],
    ["no open tasks", { noOpenTasks: true }, ["manager", "manager-a"], "from app.canonical_tasks task_filter"],
    ["valid cursor", { cursor: "2026-08-01T10:00:00.000Z|11111111-1111-4111-8111-111111111111" }, ["manager", "manager-a", "2026-08-01T10:00:00.000Z", "11111111-1111-4111-8111-111111111111"], "(s.created_at, s.id) < ($3::timestamptz, $4::uuid)"],
    ["malformed cursor", { cursor: "malformed" }, ["manager", "manager-a"], "s.deleted_at is null"],
  ] satisfies ReadonlyArray<[string, Partial<StudentSearchQuery>, unknown[], string]>)
    ("keeps SQL fragment and parameter order for %s", (_name, query, params, fragment) => {
      const filter = buildStudentSearchFilter(manager, query as StudentSearchQuery);
      expect(filter.params).toEqual(params);
      expect(filter.where).toContain(fragment);
    });

  it("adds teacher scope using role and user parameters before filters", () => {
    const filter = buildStudentSearchFilter(teacher, { status: "active" });
    expect(filter.params).toEqual(["teacher", "teacher-a", "active"]);
    expect(filter.where).toContain("$1::text = 'teacher' and tp.user_id = $2");
  });

  it("keeps manager branch scope and exact combined parameter order", () => {
    const filter = buildStudentSearchFilter(manager, {
      q: "Анна",
      status: "active",
      branchId: "branch-a",
      groupId: "group-a",
      discipline: "Вокал",
      level: "Начальный",
      category: "Дети",
      from: "2026-01-01",
      to: "2026-02-01",
      linkedUser: false,
      noEmail: true,
      noOpenTasks: true,
      cursor: "2026-08-01T10:00:00.000Z|11111111-1111-4111-8111-111111111111",
    });

    expect(filter.params).toEqual([
      "manager", "manager-a", "анна", null, "active", "branch-a", "group-a",
      "Вокал", "Начальный", "Дети", "2026-01-01", "2026-02-01",
      "2026-08-01T10:00:00.000Z", "11111111-1111-4111-8111-111111111111",
    ]);
    expect(filter.where).toContain("scope_assignment.branch_id::text");
    expect(filter.searchRank).toContain("case");
  });
});
