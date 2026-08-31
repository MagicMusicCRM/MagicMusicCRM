import type { PoolClient } from "pg";
import {
  replaceTypedClientValues,
} from "./clients/client-config.repository";
import type {
  TypedClientCustomFieldWrite,
} from "./clients/client-config.repository";
import type { ClientCustomValueType } from "./dto/client-config.dto";
import { LeadWriteRepository } from "./lead-write.repository";

interface StoredTypedValueRow {
  definition_id: string;
  field_key: string;
  label: string;
  value_type: ClientCustomValueType;
  value_text: string | null;
  value_number: number | null;
  value_boolean: boolean | null;
  value_date: string | null;
  value_json: unknown | null;
}

const typedDefinitionId = "55555555-5555-4555-8555-555555555555";

function typedWrite(
  valueType: ClientCustomValueType,
  values: Partial<TypedClientCustomFieldWrite>,
): TypedClientCustomFieldWrite {
  return {
    definitionId: typedDefinitionId,
    fieldKey: "instrument",
    label: "Любимый инструмент",
    valueType,
    valueText: null,
    valueNumber: null,
    valueBoolean: null,
    valueDate: null,
    valueJson: null,
    ...values,
  };
}

function storedTypedValue(
  valueType: ClientCustomValueType,
  values: Partial<StoredTypedValueRow>,
): StoredTypedValueRow {
  return {
    definition_id: typedDefinitionId,
    field_key: "instrument",
    label: "Любимый инструмент",
    value_type: valueType,
    value_text: null,
    value_number: null,
    value_boolean: null,
    value_date: null,
    value_json: null,
    ...values,
  };
}

describe("replaceTypedClientValues", () => {
  it.each([
    {
      name: "replacement",
      oldRows: [storedTypedValue("select", { value_text: "PIANO" })],
      writes: [typedWrite("select", { valueText: "DRUMS" })],
      expected: [{
        field: "customFields.instrument",
        label: "Любимый инструмент",
        valueType: "text",
        displayMode: "values",
        from: "PIANO",
        to: "DRUMS",
      }],
    },
    {
      name: "removal",
      oldRows: [storedTypedValue("text", {
        value_text: "Авторское направление №1",
      })],
      writes: [],
      expected: [{
        field: "customFields.instrument",
        label: "Любимый инструмент",
        valueType: "text",
        displayMode: "values",
        from: "Авторское направление №1",
        to: null,
      }],
    },
    {
      name: "boolean",
      oldRows: [storedTypedValue("boolean", { value_boolean: false })],
      writes: [typedWrite("boolean", { valueBoolean: true })],
      expected: [{
        field: "customFields.instrument",
        label: "Любимый инструмент",
        valueType: "boolean",
        displayMode: "values",
        from: false,
        to: true,
      }],
    },
    {
      name: "date",
      oldRows: [storedTypedValue("date", { value_date: "2026-08-30" })],
      writes: [typedWrite("date", { valueDate: "2026-08-31" })],
      expected: [{
        field: "customFields.instrument",
        label: "Любимый инструмент",
        valueType: "date",
        displayMode: "values",
        from: "2026-08-30",
        to: "2026-08-31",
      }],
    },
    {
      name: "primitive multi-select",
      oldRows: [storedTypedValue("multi_select", { value_json: ["PIANO"] })],
      writes: [typedWrite("multi_select", {
        valueJson: ["Авторское направление №1", "DrUmS"],
      })],
      expected: [{
        field: "customFields.instrument",
        label: "Любимый инструмент",
        valueType: "list",
        displayMode: "values",
        from: ["PIANO"],
        to: ["Авторское направление №1", "DrUmS"],
      }],
    },
    {
      name: "unchanged value",
      oldRows: [storedTypedValue("select", { value_text: "DrUmS" })],
      writes: [typedWrite("select", { valueText: "DrUmS" })],
      expected: [],
    },
  ])(
    "returns a safe semantic diff for $name",
    async ({ oldRows, writes, expected }) => {
      const query = jest.fn(async (text: string) => {
        const sql = String(text);
        if (sql.includes("app.resolve_client_id")) {
          return { rows: [{ client_id: "client-a" }] };
        }
        if (
          sql.includes("from app.client_custom_field_values value") &&
          sql.includes("join app.client_custom_field_definitions")
        ) {
          return { rows: oldRows };
        }
        if (
          sql.includes("delete from app.client_custom_field_values") ||
          sql.includes("insert into app.client_custom_field_values")
        ) {
          return { rows: [] };
        }
        throw new Error(`Unexpected SQL: ${sql}`);
      });

      await expect(
        replaceTypedClientValues(
          { query } as unknown as PoolClient,
          "lead",
          "lead-a",
          writes,
        ),
      ).resolves.toEqual(expected);
    },
  );
});

describe("LeadWriteRepository", () => {
  it("creates the lead inside one transaction without a phantom transition", async () => {
    const inserted = {
      id: "lead-a",
      status_id: null,
      status_name: null,
      first_name: "Анна",
      last_name: null,
      phone: null,
      email: null,
      source: null,
      notes: null,
      assigned_to: null,
      custom_data: {},
      created_by: "manager-a",
      created_at: "2026-08-25T10:00:00.000Z",
      updated_at: "2026-08-25T10:00:00.000Z",
    };
    const client = {
      query: jest.fn().mockResolvedValue({ rows: [inserted] }),
    };
    const database = {
      query: jest.fn(),
      transaction: jest.fn(
        async (work: (value: typeof client) => Promise<unknown>) => work(client),
      ),
    };
    const pipelines = { assertLeadTransition: jest.fn() };
    const repository = new LeadWriteRepository(
      database as never,
      pipelines as never,
    );

    await expect(
      repository.create(
        { userId: "manager-a", role: "manager" },
        { firstName: "Анна" },
      ),
    ).resolves.toEqual({ lead: inserted, branchId: null });
    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(pipelines.assertLeadTransition).not.toHaveBeenCalled();
    expect(client.query.mock.calls[0]?.[0]).toContain("insert into app.leads");
  });

  it("rejects a stale autosave before changing the lead", async () => {
    const locked = {
      id: "lead-a",
      version: 3,
      status_id: null,
      status_name: null,
      first_name: "Анна",
      last_name: null,
      phone: null,
      email: null,
      source: null,
      source_id: null,
      notes: null,
      assigned_to: null,
      custom_data: {},
      created_by: "manager-a",
      created_at: "2026-08-25T10:00:00.000Z",
      updated_at: "2026-08-25T10:00:00.000Z",
      branch_id: null,
    };
    const client = {
      query: jest.fn().mockResolvedValue({ rows: [locked] }),
    };
    const database = {
      query: jest.fn(),
      transaction: jest.fn(
        async (work: (value: typeof client) => Promise<unknown>) => work(client),
      ),
    };
    const repository = new LeadWriteRepository(database as never, {
      assertLeadTransition: jest.fn(),
    } as never);

    await expect(
      repository.update(
        { userId: "manager-a", role: "manager" },
        "lead-a",
        { firstName: "Мария", expectedVersion: 2 },
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: "CLIENT_VERSION_CONFLICT",
        entityType: "lead",
        expectedVersion: 2,
        currentVersion: 3,
      }),
    });
    expect(client.query).toHaveBeenCalledTimes(1);
    expect(String(client.query.mock.calls[0]?.[0])).toContain("for update");
  });

  it("keeps released clients compatible when expectedVersion is omitted", async () => {
    const locked = {
      id: "lead-a",
      version: 3,
      status_id: null,
      status_name: null,
      first_name: "Анна",
      last_name: null,
      phone: null,
      email: null,
      source: null,
      source_id: null,
      notes: null,
      assigned_to: null,
      custom_data: {},
      created_by: "manager-a",
      created_at: "2026-08-25T10:00:00.000Z",
      updated_at: "2026-08-25T10:00:00.000Z",
      branch_id: null,
    };
    const updated = { ...locked, version: 4, first_name: "Мария" };
    const client = {
      query: jest
        .fn()
        .mockResolvedValueOnce({ rows: [locked] })
        .mockResolvedValueOnce({ rows: [updated] }),
    };
    const database = {
      query: jest.fn(),
      transaction: jest.fn(
        async (work: (value: typeof client) => Promise<unknown>) => work(client),
      ),
    };
    const repository = new LeadWriteRepository(database as never, {
      assertLeadTransition: jest.fn(),
    } as never);

    await expect(
      repository.update(
        { userId: "manager-a", role: "manager" },
        "lead-a",
        { firstName: "Мария" },
      ),
    ).resolves.toMatchObject({ lead: updated });
    expect(String(client.query.mock.calls[1]?.[0])).toContain(
      "version = version + 1",
    );
  });
});
