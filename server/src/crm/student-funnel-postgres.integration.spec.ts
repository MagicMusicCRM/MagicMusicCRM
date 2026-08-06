import {
  ForbiddenException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Pool, PoolClient } from "pg";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { MigrationRunner } from "../db/migration-runner";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmPolicy } from "./crm.policy";
import { StudentFunnelStageDto } from "./dto/student-funnel.dto";
import { StudentFunnelService } from "./student-funnel.service";

const databaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ??
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
if (!new Set(["127.0.0.1", "localhost", "[::1]"]).has(new URL(databaseUrl).hostname)) {
  throw new Error("Student funnel tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Student funnel effective configuration (PostgreSQL)", () => {
  let pool: Pool;
  let client: PoolClient;
  let service: StudentFunnelService;
  let branchId: string;
  let otherBranchId: string;
  let studentId: string;
  let director: ActorContext;

  beforeAll(async () => {
    pool = new Pool({ connectionString: databaseUrl });
    await new MigrationRunner(pool).up();
    client = await pool.connect();
    await client.query("begin");
    const directorId = randomUUID();
    const managerId = randomUUID();
    const clientId = randomUUID();
    branchId = randomUUID();
    otherBranchId = randomUUID();
    studentId = randomUUID();
    const profileId = randomUUID();
    await client.query(
      `
        insert into app.users (id, email, role, profile_completed)
        values
          ($1, $2, 'director', true),
          ($3, $4, 'manager', true),
          ($5, $6, 'client', true)
      `,
      [
        directorId,
        `${directorId}@test.local`,
        managerId,
        `${managerId}@test.local`,
        clientId,
        `${clientId}@test.local`,
      ],
    );
    await client.query(
      `insert into app.branches (id, name) values ($1, 'Сокол'), ($2, 'Центр')`,
      [branchId, otherBranchId],
    );
    await client.query(
      `
        insert into app.profiles (id, user_id, first_name, last_name)
        values ($1, $2, 'Тест', 'Ученик')
      `,
      [profileId, clientId],
    );
    await client.query(
      `
        insert into app.students (id, profile_id, branch_id, status)
        values ($1, $2, $3, 'active')
      `,
      [studentId, profileId, branchId],
    );

    const database = {
      query: (text: string, params?: unknown[]) => client.query(text, params),
      transaction: <T>(work: (transactionClient: PoolClient) => Promise<T>) =>
        work(client),
    } as unknown as DatabaseService;
    service = new StudentFunnelService(
      database,
      { record: jest.fn().mockResolvedValue(undefined) } as unknown as AuditService,
      new CrmPolicy(),
      { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
    );
    director = { userId: directorId, role: "director" };
  });

  afterAll(async () => {
    await client.query("rollback");
    client.release();
    await pool.end();
  });

  it("publishes school defaults and a sparse branch override", async () => {
    const school = await service.getEffective(director);
    expect(school).toMatchObject({ source: "school", schoolVersion: 1 });

    const schoolStages = renameStage(school.stages, "paused", "На паузе");
    const schoolRevision = await service.publish(director, {
      expectedVersion: 1,
      reason: "Уточнили школьный термин",
      stages: schoolStages,
    });
    expect(schoolRevision.version).toBe(2);

    const desired = moveFirst(
      renameStage(schoolStages, "paused", "Пауза филиала"),
      "active",
    );
    const branchRevision = await service.publish(director, {
      branchId,
      expectedVersion: 0,
      reason: "Порядок Сокола",
      stages: desired,
    });
    expect(branchRevision.patch).toMatchObject({
      order: expect.any(Array),
      stages: { paused: { label: "Пауза филиала" } },
    });
    expect(Object.keys((branchRevision.patch as { stages: object }).stages)).toEqual([
      "paused",
    ]);

    const effective = await service.getEffective(director, branchId);
    const other = await service.getEffective(director, otherBranchId);
    expect(effective).toMatchObject({ source: "branch_override", branchVersion: 1 });
    expect(effective.stages[0]?.key).toBe("active");
    expect(stageLabel(effective.stages, "paused")).toBe("Пауза филиала");
    expect(stageLabel(other.stages, "paused")).toBe("На паузе");
  });

  it("configures Lead and Student pipelines through the same version contract", async () => {
    const school = await service.getEffective(director, undefined, "lead");
    expect(school.clientType).toBe("lead");
    expect(school.stages.length).toBeGreaterThan(0);

    const first = school.stages[0]!;
    const renamed = [
      ...school.stages.map((stage) =>
        stage.key === first.key
          ? { ...stage, label: "Первичный контакт" }
          : stage,
      ),
      {
        key: "follow_up",
        label: "Повторный контакт",
        style: "amber",
        active: true,
        terminal: false,
        requiresReason: false,
        allowedTransitions: [first.key],
      },
    ];
    const preview = await service.preview(director, {
      clientType: "lead",
      expectedVersion: school.schoolVersion,
      stages: renamed,
    });
    expect(preview).toMatchObject({
      valid: true,
      changes: { created: 1, updated: 1 },
    });
    const published = await service.publish(director, {
      clientType: "lead",
      expectedVersion: school.schoolVersion,
      reason: "Единый редактор лидов",
      stages: renamed,
    });
    expect(published).toMatchObject({
      clientType: "lead",
      version: school.schoolVersion + 1,
    });
    const synced = await client.query<{ name: string }>(
      "select name from app.lead_statuses where stage_key = $1",
      [first.key],
    );
    expect(synced.rows[0]?.name).toBe("Первичный контакт");

    const swapped = renamed.map((stage) =>
      stage.key === first.key
        ? { ...stage, label: "Повторный контакт" }
        : stage.key === "follow_up"
          ? { ...stage, label: "Первичный контакт" }
          : stage,
    );
    const swappedRevision = await service.publish(director, {
      clientType: "lead",
      expectedVersion: published.version,
      reason: "Обмен названиями стадий",
      stages: swapped,
    });
    expect(swappedRevision.version).toBe(published.version + 1);
    await expect(
      service.preview(director, {
        clientType: "lead",
        expectedVersion: swappedRevision.version,
        stages: swapped.map((stage) => ({
          ...stage,
          label: "Одинаковая стадия",
        })),
      }),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);

    const branchStages = swapped.map((stage) =>
      stage.key === first.key ? { ...stage, label: "Контакт филиала" } : stage,
    );
    await service.publish(director, {
      clientType: "lead",
      branchId,
      expectedVersion: 0,
      reason: "Термин филиала",
      stages: branchStages,
    });
    const effective = await service.getEffective(director, branchId, "lead");
    expect(effective).toMatchObject({
      clientType: "lead",
      source: "branch_override",
      branchVersion: 1,
    });
    expect(stageLabel(effective.stages, first.key)).toBe("Контакт филиала");

    const blocked = await service.preview(director, {
      clientType: "lead",
      branchId,
      expectedVersion: 1,
      stages: effective.stages.slice(1).map((stage) => ({
        ...stage,
        allowedTransitions: [],
      })),
    });
    expect(blocked).toMatchObject({
      valid: false,
      blockingIssues: [{ stageKey: first.key }],
    });
    const rollback = await service.rollback(director, {
      clientType: "lead",
      branchId,
      expectedVersion: 1,
      targetVersion: 1,
      reason: "Проверка отката",
    });
    expect(rollback).toMatchObject({
      clientType: "lead",
      version: 2,
      rollbackFromVersion: 1,
    });
  });

  it("enforces configured transitions and rolls back by publishing a revision", async () => {
    const current = await service.getEffective(director, branchId);
    const restricted = current.stages.map((stage) =>
      stage.key === "active"
        ? { ...stage, allowedTransitions: ["inactive"] }
        : stage,
    );
    await service.publish(director, {
      branchId,
      expectedVersion: 1,
      reason: "Ограничили переход",
      stages: restricted,
    });
    await expect(
      service.assertTransition(client, branchId, "active", "paused"),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    await service.assertTransition(client, branchId, "active", "inactive");

    const rollback = await service.rollback(director, {
      branchId,
      expectedVersion: 2,
      targetVersion: 1,
      reason: "Вернули согласованный вариант",
    });
    expect(rollback).toMatchObject({ version: 3, rollbackFromVersion: 1 });
    await service.assertTransition(client, branchId, "active", "paused");
  });

  it("keeps configuration director-only and revisions immutable", async () => {
    const manager: ActorContext = { userId: randomUUID(), role: "manager" };
    const current = await service.getEffective(director, branchId);
    await expect(
      service.publish(manager, {
        branchId,
        expectedVersion: current.branchVersion,
        reason: "Недопустимое изменение",
        stages: current.stages,
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await client.query("savepoint immutable_revision_check");
    await expect(
      client.query(
        "update app.student_funnel_revisions set reason = 'rewrite' where branch_id = $1",
        [branchId],
      ),
    ).rejects.toMatchObject({ code: "23514" });
    await client.query("rollback to savepoint immutable_revision_check");
  });

  it("does not expose school remediation counts to a teacher", async () => {
    await client.query("update app.students set status = 'legacy_unknown' where id = $1", [
      studentId,
    ]);
    const staffView = await service.getEffective(director, branchId);
    expect(staffView.remediationStatuses).toContainEqual({
      key: "legacy_unknown",
      count: 1,
    });
    const teacherView = await service.getEffective(
      { userId: randomUUID(), role: "teacher" },
      branchId,
    );
    expect(teacherView.remediationStatuses).toEqual([]);
    await client.query("update app.students set status = 'active' where id = $1", [
      studentId,
    ]);
  });

  it("keeps school inheritance sparse and branch-created keys immutable", async () => {
    const school = await service.getEffective(director);
    const schoolStages = [
      ...school.stages,
      {
        key: "waiting_list",
        label: "Лист ожидания",
        style: "slate" as const,
        active: false,
        allowedTransitions: [],
      },
    ];
    await service.publish(director, {
      expectedVersion: school.schoolVersion,
      reason: "Добавили архивный школьный этап",
      stages: schoolStages,
    });

    const inherited = await service.getEffective(director, branchId);
    expect(inherited.stages.some((stage) => stage.key === "waiting_list")).toBe(
      true,
    );
    await expect(
      service.assertCreateStatus(client, branchId, "waiting_list"),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
    await expect(
      service.assertTransition(
        client,
        branchId,
        "waiting_list",
        "waiting_list",
      ),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);

    const custom = {
      key: "branch_follow_up",
      label: "Контрольный звонок",
      style: "cyan" as const,
      active: true,
      allowedTransitions: ["active"],
    };
    await service.publish(director, {
      branchId,
      expectedVersion: inherited.branchVersion,
      reason: "Добавили этап филиала",
      stages: [...inherited.stages, custom],
    });
    await expect(
      service.publish(director, {
        branchId,
        expectedVersion: inherited.branchVersion + 1,
        reason: "Попытка удаления",
        stages: inherited.stages,
      }),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);

    await service.rollback(director, {
      branchId,
      expectedVersion: inherited.branchVersion + 1,
      targetVersion: 1,
      reason: "Откат филиала",
    });
    const rolledBack = await service.getEffective(director, branchId);
    expect(rolledBack.stages.some((stage) => stage.key === "waiting_list")).toBe(
      true,
    );
    expect(
      rolledBack.stages.find((stage) => stage.key === "branch_follow_up")
        ?.active,
    ).toBe(false);
  });
});

function renameStage(
  stages: StudentFunnelStageDto[],
  key: string,
  label: string,
) {
  return stages.map((stage) => (stage.key === key ? { ...stage, label } : stage));
}

function moveFirst(stages: StudentFunnelStageDto[], key: string) {
  return [
    ...stages.filter((stage) => stage.key === key),
    ...stages.filter((stage) => stage.key !== key),
  ];
}

function stageLabel(stages: StudentFunnelStageDto[], key: string) {
  return stages.find((stage) => stage.key === key)?.label;
}
