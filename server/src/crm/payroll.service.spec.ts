import { BadRequestException, ForbiddenException } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import * as ExcelJS from "exceljs";
import { PlatformIntegrityService } from "../platform/platform-integrity.service";
import { CrmPolicy } from "./crm.policy";
import { PayrollService } from "./payroll.service";
import { PayrollAccrualCalculator } from "./payroll/payroll-accrual-calculator";
import { PayrollReadRepository } from "./payroll/payroll-read.repository";
import { TeacherPayrollCommandService } from "./payroll/teacher-payroll-command.service";
import { TeacherPayrollQueryService } from "./payroll/teacher-payroll-query.service";
import { TeacherStatsXlsxService } from "./payroll/teacher-stats-xlsx.service";
import { OoxmlWorkbookBuilder } from "../common/ooxml-workbook.builder";
import { TeacherStatsReportService } from "./payroll/teacher-stats-report.service";

describe("PayrollService (KVA-238 teacher payroll)", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  const createServiceWithQueryResults = (
    results: { rows: Record<string, unknown>[] }[],
    suppliedIntegrity?: PlatformIntegrityService,
  ) => {
    const queued = [...results];
    const query = jest.fn().mockImplementation((sql: unknown) => {
      if (
        String(sql).includes("aggregate.aggregate_type = 'teacher:payroll'")
      ) {
        return Promise.resolve({ rows: [{ id: "t-1", version: 0 }] });
      }
      return Promise.resolve(queued.shift());
    });
    const database = { query };
    const policy = {
      assertCanReadPayroll: jest.fn(),
      assertCanManagePayrollHistory: jest.fn(),
    };
    const integrity =
      suppliedIntegrity ??
      ({
        executeVersionedMutation: jest.fn(async (command: any) => ({
          resultRef: await command.mutate(
            { query },
            command.expectedVersion + 1,
          ),
          version: command.expectedVersion + 1,
          replayed: false,
          auditId: "audit-1",
          eventId: "event-1",
        })),
      } as unknown as PlatformIntegrityService);
    const repository = new PayrollReadRepository(
      database as unknown as DatabaseService,
    );
    const calculator = new PayrollAccrualCalculator();
    const queryService = new TeacherPayrollQueryService(
      repository,
      policy as unknown as CrmPolicy,
      calculator,
    );
    const commandService = new TeacherPayrollCommandService(
      repository,
      policy as unknown as CrmPolicy,
      integrity,
      calculator,
    );
    const reportService = new TeacherStatsReportService(
      repository,
      policy as unknown as CrmPolicy,
      calculator,
    );
    const xlsxService = new TeacherStatsXlsxService(
      reportService,
      new OoxmlWorkbookBuilder(),
    );
    const service = new PayrollService(
      queryService,
      commandService,
      reportService,
      xlsxService,
    );
    return { service, query, integrity, policy, commandService };
  };

  const teacherId = "11111111-1111-4111-8111-111111111111";
  const entryId = "22222222-2222-4222-8222-222222222222";
  const directorActor = { userId: "manager-a", role: "director" as const };
  const metadata = {
    idempotencyKey: "payroll-key-001",
    requestId: "request-001",
  };

  const createMutationService = (integrityResult: {
    resultRef: { entryId: string };
    version: number;
    replayed: boolean;
  }) => {
    const repository = {} as PayrollReadRepository;
    const policy = {
      assertCanReadPayroll: jest.fn(),
      assertCanManagePayrollHistory: jest.fn(),
    } as unknown as CrmPolicy;
    const integrity = {
      executeVersionedMutation: jest.fn().mockResolvedValue(integrityResult),
    } as unknown as PlatformIntegrityService;
    const commands = new TeacherPayrollCommandService(
      repository,
      policy,
      integrity,
      new PayrollAccrualCalculator(),
    );
    const service = new PayrollService(
      {} as TeacherPayrollQueryService,
      commands,
      {} as TeacherStatsReportService,
      {} as TeacherStatsXlsxService,
    );
    return { service, integrity, policy };
  };

  const createRateAuthorizationService = () => {
    const repository = {
      findRate: jest.fn().mockResolvedValue({
        id: entryId,
        teacher_id: teacherId,
        rate: "900",
        effective_from: "2026-08-01",
      }),
    } as unknown as PayrollReadRepository;
    const integrity = {
      executeVersionedMutation: jest.fn().mockResolvedValue({
        resultRef: { entryId },
        version: 1,
        replayed: false,
      }),
    } as unknown as PlatformIntegrityService;
    const commands = new TeacherPayrollCommandService(
      repository,
      new CrmPolicy(),
      integrity,
      new PayrollAccrualCalculator(),
    );
    return {
      service: new PayrollService(
        {} as TeacherPayrollQueryService,
        commands,
        {} as TeacherStatsReportService,
        {} as TeacherStatsXlsxService,
      ),
      integrity,
    };
  };

  const lessonRow = (over: Record<string, unknown> = {}) => ({
    id: "l-1",
    teacher_id: "t-1",
    student_id: null,
    lead_id: null,
    group_id: null,
    group_name: null,
    student_name: null,
    lead_name: null,
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
    expect(payroll.completedLessons).toBe(2);
    expect(payroll.payableLessons).toBe(2);
    expect(payroll.noAccrualLessons).toBe(0);
    expect(payroll.currentRate).toBe(900);
    expect(payroll.debt).toBe(1500);
  });

  it("uses the effective immutable settlement fact instead of recalculating payroll", async () => {
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [
          lessonRow({
            student_id: "s-1",
            teacher_rate: "9999",
            settlement_fact_id: "fact-effective",
            settled_amount_minor: "12345",
          }),
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

    expect(payroll.accruedTotal).toBe(123.45);
    expect(payroll.debt).toBe(123.45);
    expect(String(query.mock.calls[1][0])).toContain(
      "app.lesson_teacher_compensation_facts_effective",
    );
  });

  it("применяет коэффициенты статусов и переопределение ставки группы", async () => {
    const { service } = createServiceWithQueryResults([
      {
        rows: [
          // Неоплачиваемый пропуск → 0.
          lessonRow({
            id: "l-1",
            student_id: "s-1",
            attendance_kind: "unpaid_miss",
          }),
          // Частично оплачиваемый → доля charge_share (0.5 × 600 = 300).
          lessonRow({
            id: "l-2",
            student_id: "s-1",
            attendance_kind: "partially_paid",
            charge_share: "0.5",
          }),
          // Обычное посещение → 1 (600).
          lessonRow({
            id: "l-3",
            student_id: "s-1",
            attendance_kind: "attended",
          }),
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
    expect(payroll.completedLessons).toBe(5);
    expect(payroll.payableLessons).toBe(4);
    expect(payroll.noAccrualLessons).toBe(1);
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
      {
        rows: [
          {
            teacher_id: "t-1",
            paid_total: "500",
            bonus_total: "100",
            deduction_total: "50",
          },
        ],
      },
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
    expect(item.completedLessons).toBe(3);
    expect(item.payableLessons).toBe(3);
    expect(item.bonusTotal).toBe(100);
    expect(item.deductionTotal).toBe(50);
    expect(item.periodBalance).toBe(1650);
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
      completedLessons: 3,
      payableLessons: 3,
      noAccrualLessons: 0,
      accruedTotal: 2100,
      bonusTotal: 100,
      deductionTotal: 50,
      paidTotal: 500,
      periodBalance: 1650,
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
    // `trial` — любое пробное; сам разрез теперь называет его точнее.
    expect(report.items[0].units[0].unitType).toBe("individual_trial");
    expect(report.totals.accruedTotal).toBe(600);
  });

  describe("«Индивидуальный пробный» — свой разрез (✔ владелец 17.07)", () => {
    it("не сваливает пробные разных лидов в одну строку", async () => {
      // Ключом единицы был `s:${student_id ?? "trial"}`, а у пробного
      // student_id пуст → ВСЕ пробные педагога за период сходились в одну
      // безымянную строку «Пробное занятие».
      const { service } = createServiceWithQueryResults([
        {
          rows: [
            lessonRow({
              id: "l-1",
              student_id: null,
              lead_id: "lead-1",
              lead_name: "Анна Смирнова",
              is_trial: true,
            }),
            lessonRow({
              id: "l-2",
              student_id: null,
              lead_id: "lead-2",
              lead_name: "Пётр Кузнецов",
              is_trial: true,
            }),
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
      });

      const units = report.items[0].units;
      expect(units).toHaveLength(2);
      expect(units.map((u) => u.unitName).sort()).toEqual([
        "Анна Смирнова",
        "Пётр Кузнецов",
      ]);
      expect(units.every((u) => u.unitType === "individual_trial")).toBe(true);
    });

    it("keeps a student's trial apart from their regular lessons", async () => {
      // Раньше единица с любым обычным занятием целиком считалась
      // «individual» — пробные часы исчезали из своего разреза.
      const { service } = createServiceWithQueryResults([
        {
          rows: [
            lessonRow({
              id: "l-1",
              student_id: "s-1",
              student_name: "Мария Иванова",
              is_trial: true,
            }),
            lessonRow({
              id: "l-2",
              student_id: "s-1",
              student_name: "Мария Иванова",
              is_trial: false,
            }),
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
      });

      const units = report.items[0].units;
      expect(units).toHaveLength(2);
      expect(units.map((u) => u.unitType).sort()).toEqual([
        "individual",
        "individual_trial",
      ]);
    });

    it("считает групповое пробное групповым пробным, а не индивидуальным", async () => {
      // Пробность — отдельная ось от «группа/индивидуально».
      const { service } = createServiceWithQueryResults([
        {
          rows: [
            lessonRow({
              id: "l-1",
              group_id: "g-1",
              group_name: "Вокал (группа)",
              is_trial: true,
            }),
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
      });

      expect(report.items[0].units[0].unitType).toBe("group_trial");
      expect(report.items[0].units[0].unitName).toBe("Вокал (группа)");
    });

    it("filters down to individual trials only", async () => {
      const { service } = createServiceWithQueryResults([
        {
          rows: [
            lessonRow({
              id: "l-1",
              student_id: null,
              lead_id: "lead-1",
              lead_name: "Анна Смирнова",
              is_trial: true,
            }),
            lessonRow({ id: "l-2", group_id: "g-1", is_trial: true }),
            lessonRow({ id: "l-3", student_id: "s-9", is_trial: false }),
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
        unitType: "individual_trial",
      });

      expect(report.items[0].units).toHaveLength(1);
      expect(report.items[0].units[0].unitName).toBe("Анна Смирнова");
    });

    it("reads the lead behind a trial, since a trial has no student", async () => {
      // Строки замоканы, SQL не исполняется — проверяем сам запрос текстом.
      const { service, query } = createServiceWithQueryResults([
        { rows: [] },
        { rows: [] },
      ]);
      await service.getTeacherStatsReport(actor, {
        from: "2026-07-01T00:00:00.000Z",
      });
      const sql = String(query.mock.calls[0][0]);
      expect(sql).toContain("l.lead_id");
      expect(sql).toContain("left join app.leads ld on ld.id = l.lead_id");
    });
  });

  it("отбрасывает педагогов, не прошедших фильтр статуса/дисциплины", async () => {
    const { service, query } = createServiceWithQueryResults([
      {
        rows: [
          lessonRow({ id: "l-1", teacher_id: "t-1", student_id: "s-1" }),
          lessonRow({ id: "l-2", teacher_id: "t-2", student_id: "s-2" }),
        ],
      },
      {
        rows: [
          { teacher_id: "t-1", rate: "600", effective_from: "2026-01-01" },
        ],
      },
      // Only t-1 passes the filter, so t-2's lessons must not reach the report.
      { rows: [{ id: "t-1", name: "Иван Петров" }] },
      { rows: [] },
    ]);

    const report = await service.getTeacherStatsReport(actor, {
      from: "2026-07-01T00:00:00.000Z",
      status: "active",
      discipline: "Гитара",
    });

    expect(report.items.map((item) => item.teacherId)).toEqual(["t-1"]);
    const namesSql = String(query.mock.calls[2][0]);
    expect(namesSql).toContain("t.status = $6");
    expect(namesSql).toContain("app.teacher_disciplines");
    expect(query.mock.calls[2][1]).toEqual([
      null,
      ["t-1", "t-2"],
      true,
      "2026-07-01T00:00:00.000Z",
      "2026-08-01T00:00:00.000Z",
      "active",
      "Гитара",
      null,
    ]);
  });

  it("includes a payout-only teacher so period totals do not disappear", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [] },
      { rows: [{ id: "t-1", name: "Иван Петров", salary: null }] },
      {
        rows: [
          { teacher_id: "t-1", rate: "700", effective_from: "2026-01-01" },
        ],
      },
      {
        rows: [
          {
            teacher_id: "t-1",
            paid_total: "500",
            bonus_total: "0",
            deduction_total: "0",
          },
        ],
      },
    ]);

    const report = await service.getTeacherStatsReport(actor, {
      from: "2026-07-01T00:00:00.000Z",
      to: "2026-08-01T00:00:00.000Z",
    });

    expect(report.items).toHaveLength(1);
    expect(report.items[0]).toMatchObject({
      teacherId: "t-1",
      completedLessons: 0,
      accruedTotal: 0,
      paidTotal: 500,
      periodBalance: -500,
    });
    expect(report.totals.paidTotal).toBe(500);
  });

  it("rejects an inverted report period", async () => {
    const { service, query } = createServiceWithQueryResults([]);

    await expect(
      service.getTeacherStatsReport(actor, {
        from: "2026-08-01T00:00:00.000Z",
        to: "2026-07-01T00:00:00.000Z",
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(query).not.toHaveBeenCalled();
  });

  it("экспортирует месячные начисления в валидный XLSX без выплат", async () => {
    const { service } = createServiceWithQueryResults([
      { rows: [lessonRow({ id: "l-1", student_id: "s-1", is_trial: true })] },
      {
        rows: [{ teacher_id: "t-1", rate: "0", effective_from: "2026-01-01" }],
      },
      { rows: [{ id: "t-1", name: '=Иван "Гитарист"; Петров' }] },
      { rows: [] },
    ]);

    const bytes = Buffer.from(await service.exportTeacherStatsReport(actor, {
      from: "2026-07-01T00:00:00.000Z",
    }));

    expect(bytes.subarray(0, 2).toString("ascii")).toBe("PK");
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(Uint8Array.from(bytes).buffer);
    const sheet = workbook.worksheets[0]!;
    const headers = Array.from(
      sheet.getRow(1).values as ExcelJS.CellValue[],
    ).slice(1);
    expect(headers).toEqual([
      "Преподаватель",
      "Учебная единица",
      "Тип",
      "Дни",
      "Занятий",
      "Оплачиваемых занятий",
      "Часы",
      "Ставка за астр. час",
      "Начислено",
    ]);
    expect(sheet.getCell("A2").value).toBe("'=Иван \"Гитарист\"; Петров");
    expect(sheet.getCell("D2").value).toBe("2026-07-05 (1 астр.ч.)");
    expect(sheet.getCell("H2").value).toBe("Входит в оклад");
    expect(sheet.getCell("I2").value).toBe(0);
    expect(
      headers.map((value) => String(value)),
    ).not.toContain("Оплачено");
    expect(
      headers.map((value) => String(value)),
    ).not.toContain("Доплаты");
    expect(
      headers.map((value) => String(value)),
    ).not.toContain("Вычеты");
    expect(
      headers.map((value) => String(value)),
    ).not.toContain("Сальдо периода");
  });

  it("createTeacherPayout сохраняет выплату атомарно", async () => {
    const { service, query, integrity } = createServiceWithQueryResults([
      { rows: [{ id: "t-1" }] },
      { rows: [{ id: "p-1" }] },
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

    const payout = await service.createTeacherPayout(
      actor,
      "t-1",
      {
        kind: "payout",
        amount: 1500,
        comment: "За июнь",
        expectedVersion: 0,
        reasonText: "Оплата за июнь",
      },
      {
        idempotencyKey: "payout-key",
        requestId: "request-1",
      },
    );

    expect(payout.amount).toBe(1500);
    expect(payout.kind).toBe("payout");
    expect(query).toHaveBeenCalledTimes(3);
    expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: "crm.teacher-payout.create",
        expectedVersion: 0,
        authorization: expect.objectContaining({
          capabilityKey: "commerce.teacher_payroll.write",
        }),
      }),
    );
    expect(payout.version).toBe(1);
  });

  it("setTeacherRate добавляет запись истории ставок", async () => {
    const { service, integrity } = createServiceWithQueryResults([
      { rows: [{ id: "t-1" }] },
      { rows: [{ id: "r-1" }] },
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

    const rate = await service.setTeacherRate(
      actor,
      "t-1",
      {
        rate: 750,
        effectiveFrom: "2026-08-01",
        expectedVersion: 0,
        reasonText: "Новая ставка с августа",
      },
      {
        idempotencyKey: "rate-key",
        requestId: "request-2",
      },
    );

    expect(rate.rate).toBe(750);
    expect(rate.effectiveFrom).toBe("2026-08-01");
    expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: "crm.teacher-rate.create",
        authorization: expect.objectContaining({
          capabilityKey: "config.commerce.manage",
        }),
      }),
    );
  });

  it.each([
    ["client", false],
    ["teacher", false],
    ["admin", false],
    ["manager", false],
    ["director", true],
    ["system_admin", true],
  ] as const)(
    "creates a teacher rate only for the owner roles: %s",
    async (role, allowed) => {
      const { service, integrity } = createRateAuthorizationService();
      const mutation = service.setTeacherRate(
        { userId: `${role}-a`, role },
        teacherId,
        {
          rate: 900,
          effectiveFrom: "2026-08-01",
          expectedVersion: 0,
          reasonText: "Новая ставка",
        },
        metadata,
      );

      if (allowed) {
        await expect(mutation).resolves.toMatchObject({
          teacherId,
          rate: 900,
          version: 1,
        });
        expect(integrity.executeVersionedMutation).toHaveBeenCalledTimes(1);
      } else {
        await expect(mutation).rejects.toBeInstanceOf(ForbiddenException);
        expect(integrity.executeVersionedMutation).not.toHaveBeenCalled();
      }
    },
  );

  it("rejects a payroll mutation without safe request metadata", async () => {
    const { service, integrity } = createServiceWithQueryResults([]);

    await expect(
      service.setTeacherRate(
        actor,
        "t-1",
        {
          rate: 750,
          expectedVersion: 0,
          reasonText: "Новая ставка",
        },
        { idempotencyKey: "", requestId: "" },
      ),
    ).rejects.toThrow("Передайте корректный Idempotency-Key");
    expect(integrity.executeVersionedMutation).not.toHaveBeenCalled();
  });

  it("updateTeacherRate preserves expected-version, correction audit and outbox metadata", async () => {
    const dto = {
      expectedVersion: 7,
      reasonText: "Исправление ставки",
      rate: 1250,
      effectiveFrom: "2026-08-01",
    };
    const { service, integrity, policy } = createMutationService({
      resultRef: { entryId },
      version: 8,
      replayed: false,
    });

    await expect(
      service.updateTeacherRate(
        directorActor,
        teacherId,
        entryId,
        dto,
        metadata,
      ),
    ).resolves.toEqual({
      id: entryId,
      teacherId,
      rate: 1250,
      effectiveFrom: "2026-08-01",
      version: 8,
      replayed: false,
    });
    expect(policy.assertCanManagePayrollHistory).toHaveBeenCalledWith(
      directorActor,
    );
    expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: "crm.teacher-rate.update",
        aggregateType: "teacher:payroll",
        aggregateId: teacherId,
        expectedVersion: 7,
        idempotencyKey: "payroll-key-001",
        requestId: "request-001",
        authorization: {
          actor: directorActor,
          capabilityKey: "config.commerce.manage",
        },
        audit: expect.objectContaining({
          action: "crm.teacher_rate_updated",
          reason: "TEACHER_RATE_CORRECTION",
          reasonText: "Исправление ставки",
          beforeRef: { entryId },
        }),
        outbox: {
          type: "crm.teacher_payroll.changed",
          payload: {
            action: "rate_updated",
            entityId: teacherId,
            entryId,
          },
        },
      }),
    );
  });

  it("updateTeacherPayout preserves expected-version, correction audit and outbox metadata", async () => {
    const dto = {
      expectedVersion: 7,
      reasonText: "Исправление выплаты",
      kind: "bonus" as const,
      amount: 2500,
      comment: "Премия",
      paidAt: "2026-08-20T12:00:00.000Z",
    };
    const { service, integrity, policy } = createMutationService({
      resultRef: { entryId },
      version: 8,
      replayed: false,
    });

    await expect(
      service.updateTeacherPayout(
        directorActor,
        teacherId,
        entryId,
        dto,
        metadata,
      ),
    ).resolves.toEqual({
      id: entryId,
      teacherId,
      kind: "bonus",
      amount: 2500,
      comment: "Премия",
      paidAt: "2026-08-20T12:00:00.000Z",
      version: 8,
      replayed: false,
    });
    expect(policy.assertCanManagePayrollHistory).toHaveBeenCalledWith(
      directorActor,
    );
    expect(integrity.executeVersionedMutation).toHaveBeenCalledWith(
      expect.objectContaining({
        operation: "crm.teacher-payout.update",
        aggregateType: "teacher:payroll",
        aggregateId: teacherId,
        expectedVersion: 7,
        idempotencyKey: "payroll-key-001",
        requestId: "request-001",
        authorization: {
          actor: directorActor,
          capabilityKey: "config.commerce.manage",
        },
        audit: expect.objectContaining({
          action: "crm.teacher_payout_updated",
          reason: "TEACHER_PAYOUT_CORRECTION",
          reasonText: "Исправление выплаты",
          beforeRef: { entryId },
        }),
        outbox: {
          type: "crm.teacher_payroll.changed",
          payload: {
            action: "payout_updated",
            entityId: teacherId,
            entryId,
          },
        },
      }),
    );
  });
});
