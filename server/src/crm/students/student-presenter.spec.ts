import {
  toNumericStat,
  toStudentDto,
  toStudentGroupDto,
  toStudentSearchDto,
} from "./student-presenter";

describe("student presenter", () => {
  const studentRow = {
    id: "student-a",
    lead_id: "lead-a",
    source_id: "source-a",
    source_name: "Рекомендация",
    status: "active",
    custom_data: { appealAt: "2024-02-03", addressDate: "2023-01-02", age: 12 },
    profile_id: "profile-a",
    profile_user_id: "user-a",
    first_name: "Алина",
    last_name: "Иванова",
    email: "alina@example.com",
    phone: "+79990000000",
    teacher_user_ids: ["teacher-a"],
    created_at: "2026-08-01T10:00:00.000Z",
    blacklisted: true,
    blacklist_reason: "Нарушение правил",
  };

  it("preserves appeal and manual-age precedence in the canonical DTO", () => {
    expect(toStudentDto(studentRow)).toEqual(
      expect.objectContaining({
        appealAt: "2024-02-03T00:00:00.000Z",
        appealAtSource: "manual",
        age: 12,
        ageMonths: null,
        ageSource: "manual",
        blacklisted: true,
        blacklistReason: "Нарушение правил",
      }),
    );
  });

  it("uses birthday over manually entered age", () => {
    const dto = toStudentDto({
      ...studentRow,
      custom_data: { birthday: "2010-01-01", age: 3 },
    });

    expect(dto).toEqual(
      expect.objectContaining({ ageSource: "birthday", ageMonths: expect.any(Number) }),
    );
    expect(dto.age).not.toBe(3);
  });

  it("hides placeholder email and supplies null and empty defaults", () => {
    expect(
      toStudentDto({
        ...studentRow,
        source_id: null,
        source_name: null,
        custom_data: null,
        profile_id: null,
        profile_user_id: null,
        email: "student@migration.invalid",
        teacher_user_ids: null,
        blacklisted: null,
        blacklist_reason: null,
      }),
    ).toEqual(
      expect.objectContaining({
        sourceId: null,
        sourceName: null,
        customData: {},
        email: null,
        teacherUserIds: [],
        blacklisted: false,
        blacklistReason: null,
      }),
    );
  });

  it("maps search counters, disciplines, account data, and table fields", () => {
    expect(
      toStudentSearchDto({
        ...studentRow,
        total_count: "9",
        branch_id: "branch-a",
        branch_name: "Центр",
        groups_count: "2",
        open_tasks_count: 0,
        lessons_count: "8",
        payments_total: "12000.50",
        linked_user_id: "linked-a",
        linked_user_email: "linked@example.com",
        is_app_account: true,
        disciplines: [{ id: "discipline-a", name: "Вокал" }],
        table_custom_fields: [{ key: "age", value: 12 }],
      }),
    ).toEqual(
      expect.objectContaining({
        groupsCount: 2,
        openTasksCount: 0,
        lessonsCount: 8,
        paymentsTotal: 12000.5,
        linkedUserId: "linked-a",
        linkedUserEmail: "linked@example.com",
        isAppAccount: true,
        disciplines: [{ id: "discipline-a", name: "Вокал" }],
        tableFields: [{ key: "age", value: 12 }],
      }),
    );
  });

  it("uses zero defaults for absent search metrics and arrays", () => {
    expect(
      toStudentSearchDto({
        ...studentRow,
        total_count: "1",
        branch_id: null,
        branch_name: null,
        groups_count: null as unknown as string,
        open_tasks_count: undefined as unknown as string,
        lessons_count: "not-a-number",
        payments_total: null,
        linked_user_id: null,
        linked_user_email: null,
        is_app_account: null,
        disciplines: null,
        table_custom_fields: null,
      }),
    ).toEqual(
      expect.objectContaining({
        groupsCount: 0,
        openTasksCount: 0,
        lessonsCount: 0,
        paymentsTotal: 0,
        isAppAccount: false,
        disciplines: [],
        tableFields: [],
      }),
    );
  });

  it.each([
    [null, null],
    ["0", 0],
    ["450.5", 450.5],
  ])("preserves teacherRate %p as %p", (teacher_rate, expected) => {
    expect(
      toStudentGroupDto({
        id: "group-a",
        teacher_id: "teacher-a",
        branch_id: "branch-a",
        room_id: "room-a",
        name: "Вокал",
        price_per_lesson: "1000",
        teacher_rate,
        teacher_name: "Иван Преподаватель",
        branch_name: "Центр",
        room_name: "Зал 1",
        created_at: "2026-08-01T10:00:00.000Z",
      }).teacherRate,
    ).toBe(expected);
  });

  it.each([
    [null, 0],
    [undefined, 0],
    ["0", 0],
    ["2.5", 2.5],
    ["bad", 0],
  ])("normalizes numeric stat %p to %p", (value, expected) => {
    expect(toNumericStat(value)).toBe(expected);
  });
});
