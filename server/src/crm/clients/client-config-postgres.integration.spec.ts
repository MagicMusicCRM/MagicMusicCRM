import {
  ForbiddenException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { randomUUID } from "crypto";
import { Pool } from "pg";
import { AuditService } from "../../audit/audit.service";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { MigrationRunner } from "../../db/migration-runner";
import { CrmPolicy } from "../crm.policy";
import { ClientConfigRepository } from "./client-config.repository";
import { ClientConfigService } from "./client-config.service";
import { ClientWriteValidator } from "./client-write.validator";

const defaultTestDatabaseUrl =
  "postgresql://magiccrm_owner:magiccrm_owner@127.0.0.1:54329/magiccrm";
const testDatabaseUrl =
  process.env.V4_PLATFORM_TEST_DATABASE_URL ?? defaultTestDatabaseUrl;
const parsedDatabaseUrl = new URL(testDatabaseUrl);
if (
  !new Set(["127.0.0.1", "localhost", "[::1]"]).has(parsedDatabaseUrl.hostname)
) {
  throw new Error("Client config tests require local PostgreSQL.");
}

jest.setTimeout(60_000);

describe("Client configuration and strict validators (PostgreSQL)", () => {
  let database: DatabaseService;
  let repository: ClientConfigRepository;
  let config: ClientConfigService;
  let validator: ClientWriteValidator;
  const audit = { record: jest.fn().mockResolvedValue(undefined) };
  const director: ActorContext = {
    userId: "10000000-0000-4000-8000-000000000001",
    role: "director",
  };
  const systemAdmin: ActorContext = {
    userId: "10000000-0000-4000-8000-000000000002",
    role: "system_admin",
  };
  const manager: ActorContext = {
    userId: "10000000-0000-4000-8000-000000000003",
    role: "manager",
  };
  const admin: ActorContext = {
    userId: "10000000-0000-4000-8000-000000000004",
    role: "admin",
  };
  const sourceIds: string[] = [];
  const definitionIds: string[] = [];
  const entityIds: string[] = [];
  let branchId: string;

  beforeAll(async () => {
    const migrationPool = new Pool({ connectionString: testDatabaseUrl });
    try {
      await new MigrationRunner(migrationPool).up();
    } finally {
      await migrationPool.end();
    }
    database = new DatabaseService({
      getOrThrow: () => testDatabaseUrl,
    } as unknown as ConfigService);
    repository = new ClientConfigRepository(database);
    validator = new ClientWriteValidator(repository);
    config = new ClientConfigService(
      database,
      repository,
      new CrmPolicy(),
      audit as unknown as AuditService,
    );
    const branch = await database.query<{ id: string }>(
      `
        insert into app.branches (name)
        values ($1)
        returning id
      `,
      [`V4 client config ${randomUUID()}`],
    );
    branchId = branch.rows[0]!.id;
  });

  afterEach(() => {
    audit.record.mockClear();
  });

  afterAll(async () => {
    if (entityIds.length > 0) {
      await database.query(
        `
          delete from app.client_custom_field_values
          where entity_id = any($1::uuid[])
        `,
        [entityIds],
      );
      await database.query("delete from app.leads where id = any($1::uuid[])", [
        entityIds,
      ]);
    }
    if (definitionIds.length > 0) {
      await database.query(
        `
          delete from app.client_custom_field_definitions
          where id = any($1::uuid[])
        `,
        [definitionIds],
      );
    }
    if (sourceIds.length > 0) {
      await database.query(
        "delete from app.lead_sources where id = any($1::uuid[])",
        [sourceIds],
      );
    }
    await database.query("delete from app.branches where id = $1", [branchId]);
    await database.onModuleDestroy();
  });

  async function createSource(label = "Integration source") {
    const source = await config.createSource(director, {
      canonicalName: `integration_${randomUUID().replace(/-/g, "")}`,
      displayName: label,
    });
    sourceIds.push(source.id);
    return source;
  }

  async function createField(input?: {
    entityType?: "lead" | "student";
    valueType?: "text" | "number" | "select" | "phone";
    required?: boolean;
    options?: string[];
  }) {
    const field = await config.createField(director, {
      entityType: input?.entityType ?? "lead",
      key: `field_${randomUUID().replace(/-/g, "")}`,
      label: "Проверочное поле",
      valueType: input?.valueType ?? "text",
      required: input?.required ?? false,
      options: input?.options,
    });
    definitionIds.push(field.id);
    return field;
  }

  it("allows only Director/system_admin to mutate sources and fields", async () => {
    await expect(
      config.createSource(manager, {
        canonicalName: "manager_denied",
        displayName: "Manager denied",
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await expect(
      config.createField(admin, {
        entityType: "lead",
        key: "adminDenied",
        label: "Admin denied",
        valueType: "text",
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);

    const directorSource = await createSource("Director source");
    const rootField = await config.createField(systemAdmin, {
      entityType: "student",
      key: `root_${randomUUID().replace(/-/g, "")}`,
      label: "Root field",
      valueType: "number",
    });
    definitionIds.push(rootField.id);

    expect(directorSource).toMatchObject({
      displayName: "Director source",
      isActive: true,
      version: 1,
    });
    expect(rootField).toMatchObject({
      entityType: "student",
      valueType: "number",
      isSystem: false,
      version: 1,
    });
  });

  it("rejects missing core fields, inactive source and invalid phone with 422", async () => {
    const source = await createSource();
    const before = await database.query<{ count: string }>(
      "select count(*)::text as count from app.leads where source_id = $1",
      [source.id],
    );

    await expect(
      validator.validateLeadCreate({
        firstName: " ",
        lastName: "Иванова",
        phone: "+79990000000",
        sourceId: source.id,
      }),
    ).rejects.toMatchObject({
      status: 422,
      response: { field: "firstName", code: "REQUIRED" },
    });
    await expect(
      validator.validateLeadCreate({
        firstName: "Анна",
        lastName: "Иванова",
        phone: "123",
        sourceId: source.id,
      }),
    ).rejects.toMatchObject({
      status: 422,
      response: { field: "phone", code: "INVALID_PHONE" },
    });

    const archived = await config.updateSource(director, source.id, {
      expectedVersion: source.version,
      isActive: false,
    });
    expect(archived).toMatchObject({ isActive: false, version: 2 });
    await expect(
      validator.validateLeadCreate({
        firstName: "Анна",
        lastName: "Иванова",
        phone: "+79990000000",
        sourceId: source.id,
      }),
    ).rejects.toMatchObject({
      status: 422,
      response: { field: "sourceId", code: "SOURCE_INACTIVE" },
    });

    const after = await database.query<{ count: string }>(
      "select count(*)::text as count from app.leads where source_id = $1",
      [source.id],
    );
    expect(after.rows[0]!.count).toBe(before.rows[0]!.count);
  });

  it("normalizes valid phones and validates the Student required minimum", async () => {
    const source = await createSource();
    const lead = await validator.validateLeadCreate({
      firstName: " Анна ",
      lastName: " Иванова ",
      phone: "8 (999) 000-00-00",
      sourceId: source.id,
    });
    expect(lead).toMatchObject({
      firstName: "Анна",
      lastName: "Иванова",
      phone: "+79990000000",
      sourceId: source.id,
      warnings: [
        {
          field: "phone",
          code: "PHONE_NORMALIZED",
          normalizedValue: "+79990000000",
        },
      ],
    });

    await expect(
      validator.validateStudentCreate({
        firstName: "Анна",
        lastName: "Иванова",
        phone: "+79990000000",
        branchId,
        status: " ",
      }),
    ).rejects.toMatchObject({
      status: 422,
      response: { field: "status", code: "REQUIRED" },
    });
    await expect(
      validator.validateStudentCreate({
        firstName: "Анна",
        lastName: "Иванова",
        phone: "+79990000000",
        branchId: randomUUID(),
        status: "active",
      }),
    ).rejects.toMatchObject({
      status: 422,
      response: { field: "branchId", code: "BRANCH_INACTIVE" },
    });
    await expect(
      validator.validateStudentCreate({
        firstName: "Анна",
        lastName: "Иванова",
        phone: "+79990000000",
        branchId,
        status: "active",
      }),
    ).resolves.toMatchObject({
      branchId,
      status: "active",
      warnings: [],
    });
  });

  it("enforces required and typed custom values", async () => {
    const source = await createSource();
    const select = await createField({
      valueType: "select",
      required: true,
      options: ["Вокал", "Гитара"],
    });

    await expect(
      validator.validateLeadCreate({
        firstName: "Анна",
        lastName: "Иванова",
        phone: "+79990000000",
        sourceId: source.id,
      }),
    ).rejects.toMatchObject({
      status: 422,
      response: { code: "REQUIRED_CUSTOM_FIELD" },
    });
    await expect(
      validator.validateLeadCreate({
        firstName: "Анна",
        lastName: "Иванова",
        phone: "+79990000000",
        sourceId: source.id,
        customFields: [
          { definitionId: select.id, value: "Несуществующий вариант" },
        ],
      }),
    ).rejects.toMatchObject({
      status: 422,
      response: { code: "OPTION_INACTIVE" },
    });
    await expect(
      validator.validateLeadCreate({
        firstName: "Анна",
        lastName: "Иванова",
        phone: "+79990000000",
        sourceId: source.id,
        customFields: [{ definitionId: select.id, value: "Вокал" }],
      }),
    ).resolves.toMatchObject({
      customFields: [
        {
          definitionId: select.id,
          valueText: "Вокал",
          valueNumber: null,
          valueBoolean: null,
          valueDate: null,
          valueJson: null,
        },
      ],
    });
    await config.updateField(director, select.id, {
      expectedVersion: select.version,
      required: false,
    });
  });

  it("blocks value type changes with existing values and preserves them on archive", async () => {
    const source = await createSource();
    const field = await createField({ valueType: "text" });
    const lead = await database.query<{ id: string }>(
      `
        insert into app.leads (
          first_name,
          last_name,
          phone,
          source,
          source_id
        )
        values ('Анна', 'Иванова', '+79990000000', $1, $2)
        returning id
      `,
      [source.canonicalName, source.id],
    );
    const leadId = lead.rows[0]!.id;
    entityIds.push(leadId);
    const validated = await validator.validateCustomFields("lead", [
      { definitionId: field.id, value: "Историческое значение" },
    ]);
    await database.transaction((client) =>
      repository.saveValues(client, "lead", leadId, validated.values),
    );

    await expect(
      config.updateField(director, field.id, {
        expectedVersion: field.version,
        valueType: "number",
      }),
    ).rejects.toMatchObject({
      status: 422,
      response: { code: "FIELD_TYPE_MIGRATION_REQUIRED" },
    });

    const archived = await config.updateField(director, field.id, {
      expectedVersion: field.version,
      isActive: false,
    });
    expect(archived).toMatchObject({
      id: field.id,
      valueType: "text",
      isActive: false,
      version: 2,
    });
    const stored = await database.query<{
      value_text: string;
      validation_state: string;
    }>(
      `
        select value_text, validation_state
        from app.client_custom_field_values
        where definition_id = $1 and entity_id = $2
      `,
      [field.id, leadId],
    );
    expect(stored.rows[0]).toEqual({
      value_text: "Историческое значение",
      validation_state: "valid",
    });
    const activeList = await config.listFields(director, {
      entityType: "lead",
    });
    expect(activeList.items.some((item) => item.id === field.id)).toBe(false);
    const allList = await config.listFields(director, {
      entityType: "lead",
      includeArchived: true,
    });
    expect(allList.items.some((item) => item.id === field.id)).toBe(true);
  });

  it("keeps system required fields locked", async () => {
    const fields = await config.listFields(director, {
      entityType: "lead",
      includeArchived: true,
    });
    const firstName = fields.items.find(
      (field) => field.key === "firstName" && field.isSystem,
    );
    expect(firstName).toBeDefined();

    await expect(
      config.updateField(director, firstName!.id, {
        expectedVersion: firstName!.version,
        required: false,
      }),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
  });
});
