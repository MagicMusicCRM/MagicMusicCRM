import type { PoolClient } from "pg";
import type { DatabaseService } from "../../db/database.service";
import type { StudentFunnelService } from "../student-funnel.service";
import { StudentMutationExecutor } from "./student-mutation.executor";
import type {
  PreparedStudentCreate,
  PreparedStudentUpdate,
} from "./student-mutation.types";

describe("StudentMutationExecutor", () => {
  const responsibleId = "11111111-1111-4111-8111-111111111111";
  const branchId = "22222222-2222-4222-8222-222222222222";
  const sourceId = "33333333-3333-4333-8333-333333333333";
  const studentId = "44444444-4444-4444-8444-444444444444";
  const definitionId = "55555555-5555-4555-8555-555555555555";
  const student = {
    id: studentId,
    status: "trial",
    profile_id: "66666666-6666-4666-8666-666666666666",
    profile_user_id: "77777777-7777-4777-8777-777777777777",
    lead_id: "88888888-8888-4888-8888-888888888888",
    source_id: sourceId,
    source_name: "Рекомендация",
    custom_data: {
      responsibleUserId: responsibleId,
      responsible: "Иван Петров",
    },
    blacklisted: false,
    blacklist_reason: null,
    first_name: "Алина",
    last_name: "Иванова",
    email: "alina@example.com",
    phone: "+79990000000",
    created_at: "2026-08-26T10:00:00.000Z",
    teacher_user_ids: [],
  };

  it("keeps create validation, lead lock, insert, and typed values in one transaction", async () => {
    const events: string[] = [];
    let transactionClient: PoolClient;
    const query = jest.fn(async (text: string, params?: unknown[]) => {
      const sql = String(text);
      if (sql.includes("pg_advisory_xact_lock")) {
        events.push("lead-lock");
        return { rows: [] };
      }
      if (sql.includes("from app.students where lead_id")) {
        events.push("duplicate-recheck");
        return { rows: [] };
      }
      if (sql.includes("from app.users u") && sql.includes("for share")) {
        events.push("responsible-lock");
        return {
          rows: [
            {
              user_id: responsibleId,
              role: "manager",
              staff_member_id: "99999999-9999-4999-8999-999999999999",
              staff_status: "working",
              display_name: "Иван Петров",
            },
          ],
        };
      }
      if (sql.includes("with identity as")) {
        events.push("insert-student");
        expect(params).toEqual([
          "Алина",
          "Иванова",
          "alina@example.com",
          "Алина Иванова",
          "+79990000000",
          "trial",
          student.lead_id,
          JSON.stringify({
            responsibleUserId: responsibleId,
            responsible: "Иван Петров",
          }),
          branchId,
          sourceId,
        ]);
        return { rows: [student] };
      }
      if (
        sql.includes("from app.client_custom_field_definitions") &&
        sql.includes("for update")
      ) {
        events.push("definition-lock");
        expect(params).toEqual(["student", [definitionId]]);
        return {
          rows: [{
            id: definitionId,
            field_key: "priority",
            label: "Приоритет",
            value_type: "text",
            is_required: false,
            is_active: true,
            is_system: false,
            options: [],
            version: 1,
            created_at: "2026-01-01T00:00:00.000Z",
            updated_at: "2026-01-01T00:00:00.000Z",
            deleted_at: null,
            visible_on_lead: true,
            visible_on_student: true,
          }],
        };
      }
      if (sql.includes("app.resolve_client_id")) {
        events.push("typed-resolve");
        return { rows: [{ client_id: "client-a" }] };
      }
      if (sql.includes("insert into app.client_custom_field_values")) {
        events.push("typed-save");
        expect(params).toEqual([
          definitionId,
          "client-a",
          "student",
          studentId,
          "VIP",
          null,
          null,
          null,
          null,
        ]);
        return { rows: [] };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });
    const client = { query } as unknown as PoolClient;
    transactionClient = client;
    const database = {
      transaction: jest.fn(async <T>(work: (client: PoolClient) => Promise<T>) => {
        events.push("transaction-start");
        const result = await work(client);
        events.push("transaction-end");
        return result;
      }),
    } as unknown as DatabaseService;
    const funnel = {
      assertCreateStatus: jest.fn(
        async (receivedClient: PoolClient, receivedBranch: string, status: string) => {
          expect(receivedClient).toBe(transactionClient);
          expect([receivedBranch, status]).toEqual([branchId, "trial"]);
          events.push("funnel-create");
        },
      ),
    } as unknown as StudentFunnelService;
    const executor = new StudentMutationExecutor(database, funnel);
    const command: PreparedStudentCreate = {
      firstName: "Алина",
      lastName: "Иванова",
      email: "alina@example.com",
      fullName: "Алина Иванова",
      phone: "+79990000000",
      status: "trial",
      leadId: student.lead_id,
      customDataPatch: { responsibleUserId: responsibleId },
      requestedResponsibleId: responsibleId,
      branchId,
      sourceId,
      customFields: [
        {
          definitionId,
          definitionVersion: 1,
          fieldKey: "priority",
          label: "Приоритет",
          valueType: "text",
          valueText: "VIP",
          valueNumber: null,
          valueBoolean: null,
          valueDate: null,
          valueJson: null,
        },
      ],
    };

    await expect(executor.create(command)).resolves.toEqual(student);

    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(events).toEqual([
      "transaction-start",
      "funnel-create",
      "lead-lock",
      "duplicate-recheck",
      "responsible-lock",
      "insert-student",
      "definition-lock",
      "typed-resolve",
      "typed-save",
      "transaction-end",
    ]);
  });

  it("keeps update snapshot, validation, replacement, and history in one transaction", async () => {
    const events: string[] = [];
    const beforeStudent = {
      version: 1,
      status: "active",
      branch_id: branchId,
      first_name: "Анна",
      last_name: "Иванова",
      phone: "+78880000000",
      email: "anna@example.com",
      custom_data: {},
    };
    let transactionClient: PoolClient;
    const query = jest.fn(async (text: string, params?: unknown[]) => {
      const sql = String(text);
      if (sql.includes("for update of s")) {
        events.push("snapshot-lock");
        return { rows: [beforeStudent] };
      }
      if (sql.includes("from app.lead_sources")) {
        events.push("source-check");
        return { rows: [{ display_name: "Рекомендация" }] };
      }
      if (sql.includes("from app.users u") && sql.includes("for share")) {
        events.push("responsible-lock");
        return {
          rows: [
            {
              user_id: responsibleId,
              role: "manager",
              staff_member_id: "99999999-9999-4999-8999-999999999999",
              staff_status: "working",
              display_name: "Иван Петров",
            },
          ],
        };
      }
      if (sql.includes("with target as")) {
        events.push("update-student");
        expect(params).toEqual([
          studentId,
          "Алина",
          "Иванова",
          "+79990000000",
          "alina@example.com",
          "trial",
          JSON.stringify({
            responsibleUserId: responsibleId,
            responsible: "Иван Петров",
          }),
          branchId,
          false,
          sourceId,
          false,
        ]);
        return { rows: [student] };
      }
      if (sql.includes("app.resolve_client_id")) {
        events.push("typed-resolve");
        return { rows: [{ client_id: "client-a" }] };
      }
      if (
        sql.includes("from app.client_custom_field_definitions") &&
        sql.includes("for update")
      ) {
        events.push("definition-lock");
        expect(params).toEqual(["student", [definitionId]]);
        return {
          rows: [{
            id: definitionId,
            field_key: "instrument",
            label: "Любимый инструмент",
            value_type: "select",
            is_required: false,
            is_active: true,
            is_system: false,
            options: ["PIANO"],
            version: 1,
            created_at: "2026-01-01T00:00:00.000Z",
            updated_at: "2026-01-01T00:00:00.000Z",
            deleted_at: null,
            visible_on_lead: true,
            visible_on_student: true,
          }],
        };
      }
      if (sql.includes("from app.client_custom_field_values value")
        && sql.includes("join app.client_custom_field_definitions")) {
        events.push("typed-snapshot");
        return {
          rows: [{
            definition_id: definitionId,
            field_key: "instrument",
            label: "Любимый инструмент",
            value_type: "select",
            value_text: "PIANO",
            value_number: null,
            value_boolean: null,
            value_date: null,
            value_json: null,
          }],
        };
      }
      if (sql.includes("delete from app.client_custom_field_values")) {
        events.push("typed-delete");
        expect(params).toEqual(["client-a", [definitionId]]);
        return { rows: [] };
      }
      if (sql.includes("insert into app.client_custom_field_values")) {
        events.push("typed-save");
        return { rows: [] };
      }
      if (sql.includes("insert into app.student_status_history")) {
        events.push("status-history");
        expect(params).toEqual([studentId, "trial", branchId]);
        return { rows: [] };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });
    const client = { query } as unknown as PoolClient;
    transactionClient = client;
    const database = {
      transaction: jest.fn(async <T>(work: (client: PoolClient) => Promise<T>) => {
        events.push("transaction-start");
        const result = await work(client);
        events.push("transaction-end");
        return result;
      }),
    } as unknown as DatabaseService;
    const funnel = {
      assertTransition: jest.fn(
        async (
          receivedClient: PoolClient,
          receivedBranch: string,
          previousStatus: string,
          nextStatus: string,
        ) => {
          expect(receivedClient).toBe(transactionClient);
          expect([receivedBranch, previousStatus, nextStatus]).toEqual([
            branchId,
            "active",
            "trial",
          ]);
          events.push("funnel-transition");
        },
      ),
    } as unknown as StudentFunnelService;
    const executor = new StudentMutationExecutor(database, funnel);
    const command: PreparedStudentUpdate = {
      studentId,
      expectedVersion: 1,
      firstName: "Алина",
      lastName: "Иванова",
      phone: "+79990000000",
      email: "alina@example.com",
      status: "trial",
      customDataPatch: { responsibleUserId: responsibleId },
      requestedResponsibleId: responsibleId,
      branchId,
      clearResponsible: false,
      sourceId,
      customFields: [
        {
          definitionId,
          definitionVersion: 1,
          fieldKey: "instrument",
          label: "Любимый инструмент",
          valueType: "select",
          valueText: "DRUMS",
          valueNumber: null,
          valueBoolean: null,
          valueDate: null,
          valueJson: null,
        },
      ],
    };

    await expect(executor.update(command)).resolves.toEqual({
      beforeStudent,
      student,
      customFieldChanges: [{
        field: "customFields.instrument",
        label: "Любимый инструмент",
        valueType: "text",
        displayMode: "values",
        from: "PIANO",
        to: "DRUMS",
      }],
    });

    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(events).toEqual([
      "transaction-start",
      "snapshot-lock",
      "funnel-transition",
      "source-check",
      "responsible-lock",
      "update-student",
      "typed-resolve",
      "definition-lock",
      "typed-snapshot",
      "typed-delete",
      "typed-resolve",
      "typed-save",
      "status-history",
      "transaction-end",
    ]);
  });

  it("does not touch typed values or append history when both are unchanged", async () => {
    const queries: string[] = [];
    const beforeStudent = {
      version: 1,
      status: "active",
      branch_id: branchId,
      first_name: "Алина",
      last_name: "Иванова",
      phone: "+79990000000",
      email: "alina@example.com",
      custom_data: {},
    };
    const unchangedStudent = { ...student, status: "active" };
    const query = jest.fn(async (text: string) => {
      const sql = String(text);
      queries.push(sql);
      if (sql.includes("for update of s")) return { rows: [beforeStudent] };
      if (sql.includes("with target as")) return { rows: [unchangedStudent] };
      throw new Error(`Unexpected SQL: ${sql}`);
    });
    const client = { query } as unknown as PoolClient;
    const database = {
      transaction: jest.fn(async <T>(work: (client: PoolClient) => Promise<T>) =>
        work(client),
      ),
    } as unknown as DatabaseService;
    const executor = new StudentMutationExecutor(database, {
      assertCreateStatus: jest.fn(),
      assertTransition: jest.fn(),
    } as unknown as StudentFunnelService);
    const command: PreparedStudentUpdate = {
      studentId,
      expectedVersion: 1,
      firstName: null,
      lastName: null,
      phone: null,
      email: null,
      status: null,
      customDataPatch: {},
      requestedResponsibleId: undefined,
      branchId: null,
      clearResponsible: false,
      sourceId: null,
    };

    await expect(executor.update(command)).resolves.toEqual({
      beforeStudent,
      student: unchangedStudent,
      customFieldChanges: [],
    });

    expect(queries.some((sql) => sql.includes("resolve_client_id"))).toBe(false);
    expect(
      queries.some((sql) => sql.includes("student_status_history")),
    ).toBe(false);
    expect(queries.find((sql) => sql.includes("with target as"))).toContain(
      "jsonb_strip_nulls",
    );
  });

  it("rejects a stale autosave before changing the student profile", async () => {
    const query = jest.fn(async (text: string) => {
      const sql = String(text);
      if (sql.includes("for update of s")) {
        return {
          rows: [
            {
              version: 5,
              status: "active",
              branch_id: branchId,
              first_name: "Анна",
              last_name: "Иванова",
              phone: "+79990000000",
              email: "anna@example.com",
              custom_data: {},
            },
          ],
        };
      }
      throw new Error(`Unexpected SQL after stale snapshot: ${sql}`);
    });
    const client = { query } as unknown as PoolClient;
    const database = {
      transaction: jest.fn(async <T>(work: (value: PoolClient) => Promise<T>) =>
        work(client),
      ),
    } as unknown as DatabaseService;
    const executor = new StudentMutationExecutor(database, {
      assertCreateStatus: jest.fn(),
      assertTransition: jest.fn(),
    } as unknown as StudentFunnelService);
    const command: PreparedStudentUpdate = {
      studentId,
      expectedVersion: 4,
      firstName: "Мария",
      lastName: null,
      phone: null,
      email: null,
      status: null,
      customDataPatch: {},
      requestedResponsibleId: undefined,
      branchId: null,
      clearResponsible: false,
      sourceId: null,
    };

    await expect(executor.update(command)).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "CLIENT_VERSION_CONFLICT",
        entityType: "student",
        expectedVersion: 4,
        currentVersion: 5,
      }),
    });
    expect(query).toHaveBeenCalledTimes(1);
  });

  it("keeps released clients compatible when expectedVersion is omitted", async () => {
    const beforeStudent = {
      version: 5,
      status: "active",
      branch_id: branchId,
      first_name: "Анна",
      last_name: "Иванова",
      phone: "+79990000000",
      email: "anna@example.com",
      custom_data: {},
    };
    const updatedStudent = { ...student, version: 6, status: "active" };
    const query = jest.fn(async (text: string) => {
      const sql = String(text);
      if (sql.includes("for update of s")) return { rows: [beforeStudent] };
      if (sql.includes("with target as")) return { rows: [updatedStudent] };
      throw new Error(`Unexpected SQL: ${sql}`);
    });
    const client = { query } as unknown as PoolClient;
    const database = {
      transaction: jest.fn(async <T>(work: (value: PoolClient) => Promise<T>) =>
        work(client),
      ),
    } as unknown as DatabaseService;
    const executor = new StudentMutationExecutor(database, {
      assertCreateStatus: jest.fn(),
      assertTransition: jest.fn(),
    } as unknown as StudentFunnelService);
    const command: PreparedStudentUpdate = {
      studentId,
      firstName: "Мария",
      lastName: null,
      phone: null,
      email: null,
      status: null,
      customDataPatch: {},
      requestedResponsibleId: undefined,
      branchId: null,
      clearResponsible: false,
      sourceId: null,
    };

    await expect(executor.update(command)).resolves.toEqual({
      beforeStudent,
      student: updatedStudent,
      customFieldChanges: [],
    });
    expect(query).toHaveBeenCalledTimes(2);
    expect(String(query.mock.calls[1]?.[0])).toContain("version = s.version + 1");
  });
});
