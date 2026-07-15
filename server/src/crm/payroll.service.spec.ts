import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { CrmPolicy } from "./crm.policy";
import { PayrollService } from "./payroll.service";

describe("PayrollService (KVA-238 teacher payroll)", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
  ) => {
    const query = jest.fn();
    for (const result of results) query.mockResolvedValueOnce(result);
    const database = { query };
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const policy = { assertCanReadPayroll: jest.fn() };
    const service = new PayrollService(
      database as unknown as DatabaseService,
      audit as unknown as AuditService,
      policy as unknown as CrmPolicy,
    );
    return { service, query, audit, policy };
  };

  const lessonRow = (over: Record<string, unknown> = {}) => ({
    id: "l-1",
    teacher_id: "t-1",
    student_id: null,
    group_id: null,
    group_name: null,
    student_name: null,
    scheduled_at: "2026-07-05T10:00:00.000Z",
    duration_minutes: 60,
    is_trial: false,
    group_rate: null,
    attendance_kind: null,
    charge_share: null,
    ...over,
  });

  it("getTeacherPayroll выбирает ставку по дате занятия из истории", async () => {
    const { service } = createServiceWithQueryResults([
      // Занятие до смены ставки (600) и после (900).
      {
        rows: [
          lessonRow({
            id: "l-1",
            student_id: "s-1",
            scheduled_at: "2026-06-10T10:00:00.000Z",
          }),
          lessonRow({
            id: "l-2",
            student_id: "s-1",
            scheduled_at: "2026-07-05T10:00:00.000Z",
          }),
        ],
      },
      {
        rows: [
          { teacher_id: "t-1", rate: "600", effective_from: "2026-01-01" },
          { teacher_id: "t-1", rate: "900", effective_from: "2026-07-01" },
        ],
      },
      { rows: [] }, // выплат нет
    ]);

    const payroll = await service.getTeacherPayroll(actor, "t-1");

    expect(payroll.accruedTotal).toBe(1500); // 600 + 900
    expect(payroll.hoursTotal).toBe(2);
    expect(payroll.currentRate).toBe(900);
    expect(payroll.debt).toBe(1500);
  });

  it("применяет коэффициенты статусов и переопределение ставки группы", async () => {
    const { service } = createServiceWithQueryResults([
      {
        rows: [
          // Неоплачиваемый пропуск → 0.
          lessonRow({ id: "l-1", student_id: "s-1", attendance_kind: "unpaid_miss" }),
          // Частично оплачиваемый → доля charge_share (0.5 × 600 = 300).
          lessonRow({
            id: "l-2",
            student_id: "s-1",
            attendance_kind: "partially_paid",
            charge_share: "0.5",
          }),
          // Обычное посещение → 1 (600).
          lessonRow({ id: "l-3", student_id: "s-1", attendance_kind: "attended" }),
          // Групповое занятие без participation → 1, ставка группы 750.
          lessonRow({ id: "l-4", group_id: "g-1", group_rate: "750" }),
          // Индивидуальное 90 минут без participation → 1.5 астр.ч. × 600.
          lessonRow({ id: "l-5", student_id: "s-1", duration_minutes: 90 }),
        ],
      },
      {
        rows: [
          { teacher_id: "t-1", rate: "600", effective_from: "2026-01-01" },
        ],
      },
      { rows: [] },
    ]);

    const payroll = await service.getTeacherPayroll(actor, "t-1");

    expect(payroll.accruedTotal).toBe(0 + 300 + 600 + 750 + 900);
    expect(payroll.hoursTotal).toBe(5.5);
  });

  it("считает задолженность = начислено + доплаты − вычеты − выплаты", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [lessonRow({ student_id: "s-1", attendance_kind: "attended" })] },
      {
        rows: [
          { teacher_id: "t-1", rate: "600", effective_from: "2026-01-01" },
        ],
      },
      {
        rows: [
          {
            id: "p-1",
            teacher_id: "t-1",
            amount: "300",
            kind: "payout",
            comment: null,
            paid_at: "2026-07-01T10:00:00.000Z",
          },
          {
            id: "p-2",
            teacher_id: "t-1",
            amount: "100",
            kind: "bonus",
            comment: "Премия",
            paid_at: "2026-07-02T10:00:00.000Z",
          },
          {
            id: "p-3",
            teacher_id: "t-1",
            amount: "50",
            kind: "deduction",
            comment: null,
            paid_at: "2026-07-03T10:00:00.000Z",
          },
        ],
      },
    ]);

    const payroll = await service.getTeacherPayroll(actor, "t-1");

    expect(payroll.accruedTotal).toBe(600);
    expect(payroll.paidTotal).toBe(300);
    expect(payroll.bonusTotal).toBe(100);
    expect(payroll.deductionTotal).toBe(50);
    expect(payroll.debt).toBe(600 + 100 - 50 - 300);
    expect(payroll.payouts).toHaveLength(3);
  });

  it("teacher-stats группирует учебные единицы, дни и итоги", async () => {
    const { service } = createServiceWithQueryResults([
      {
        rows: [
          lessonRow({
            id: "l-1",
            group_id: "g-1",
            group_name: "Вокал (группа)",
            scheduled_at: "2026-07-01T10:00:00.000Z",
          }),
          lessonRow({
            id: "l-2",
            group_id: "g-1",
            group_name: "Вокал (группа)",
            scheduled_at: "2026-07-02T10:00:00.000Z",
          }),
          lessonRow({
            id: "l-3",
            student_id: "s-1",
            student_name: "Мария Иванова",
            scheduled_at: "2026-07-02T12:00:00.000Z",
          }),
        ],
      },
      {
        rows: [
          { teacher_id: "t-1", rate: "700", effective_from: "2026-01-01" },
        ],
      },
      { rows: [{ id: "t-1", name: "Иван Петров" }] },
      { rows: [{ teacher_id: "t-1", paid_total: "500" }] },
    ]);

    const report = await service.getTeacherStatsReport(actor, {
      from: "2026-07-01T00:00:00.000Z",
    });

    expect(report.items).toHaveLength(1);
    const item = report.items[0];
    expect(item.teacherName).toBe("Иван Петров");
    expect(item.hoursTotal).toBe(3);
    expect(item.accruedTotal).toBe(2100);
    expect(item.paidTotal).toBe(500);
    expect(item.units).toHaveLength(2);
    const groupUnit = item.units.find((unit) => unit.unitType === "group");
    expect(groupUnit?.unitName).toBe("Вокал (группа)");
    expect(groupUnit?.groupId).toBe("g-1");
    expect(groupUnit?.rate).toBe(700);
    expect(groupUnit?.days).toEqual([
      { date: "2026-07-01", hours: 1 },
      { date: "2026-07-02", hours: 1 },
    ]);
    const individualUnit = item.units.find(
      (unit) => unit.unitType === "individual",
    );
    expect(individualUnit?.unitName).toBe("Мария Иванова");
    expect(report.totals).toEqual({
      hoursTotal: 3,
      accruedTotal: 2100,
      paidTotal: 500,
    });
  });

  it("teacher-stats фильтрует пробные занятия по unitType=trial", async () => {
    const { service } = createServiceWithQueryResults([
      {
        rows: [
          lessonRow({ id: "l-1", student_id: "s-1", is_trial: true }),
          lessonRow({ id: "l-2", student_id: "s-2", is_trial: false }),
        ],
      },
      {
        rows: [
          { teacher_id: "t-1", rate: "600", effective_from: "2026-01-01" },
        ],
      },
      { rows: [{ id: "t-1", name: "Иван Петров" }] },
      { rows: [] },
    ]);

    const report = await service.getTeacherStatsReport(actor, {
      from: "2026-07-01T00:00:00.000Z",
      unitType: "trial",
    });

    expect(report.items).toHaveLength(1);
    expect(report.items[0].units).toHaveLength(1);
    expect(report.items[0].units[0].unitType).toBe("trial");
    expect(report.totals.accruedTotal).toBe(600);
  });

  it("createTeacherPayout сохраняет выплату и пишет аудит", async () => {
    const { service, query, audit } = createServiceWithQueryResults([
      { rows: [{ id: "t-1" }] },
      {
        rows: [
          {
            id: "p-1",
            teacher_id: "t-1",
            amount: "1500",
            kind: "payout",
            comment: "За июнь",
            paid_at: "2026-07-10T10:00:00.000Z",
          },
        ],
      },
    ]);

    const payout = await service.createTeacherPayout(actor, "t-1", {
      kind: "payout",
      amount: 1500,
      comment: "За июнь",
    });

    expect(payout.amount).toBe(1500);
    expect(payout.kind).toBe("payout");
    expect(query).toHaveBeenCalledTimes(2);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.teacher_payout_created" }),
    );
  });

  it("setTeacherRate добавляет запись истории ставок", async () => {
    const { service, audit } = createServiceWithQueryResults([
      { rows: [{ id: "t-1" }] },
      {
        rows: [
          {
            id: "r-1",
            teacher_id: "t-1",
            rate: "750",
            effective_from: "2026-08-01",
          },
        ],
      },
    ]);

    const rate = await service.setTeacherRate(actor, "t-1", {
      rate: 750,
      effectiveFrom: "2026-08-01",
    });

    expect(rate.rate).toBe(750);
    expect(rate.effectiveFrom).toBe("2026-08-01");
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({ action: "crm.teacher_rate_set" }),
    );
  });
});
