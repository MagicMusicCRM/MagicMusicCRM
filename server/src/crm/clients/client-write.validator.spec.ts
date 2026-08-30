import { UnprocessableEntityException } from "@nestjs/common";
import { ClientCustomValueType } from "../dto/client-config.dto";
import {
  ClientConfigRepository,
  ClientCustomFieldDefinitionRow,
} from "./client-config.repository";
import {
  ClientWriteValidator,
  ValidatedCustomFields,
} from "./client-write.validator";

interface ValidationErrorPayload {
  code: string;
  field: string;
  message: string;
}

describe("ClientWriteValidator.validateCustomFields", () => {
  const repository: jest.Mocked<
    Pick<
      ClientConfigRepository,
      "findDefinitionsByIds" | "listRequiredCustomDefinitions"
    >
  > = {
    findDefinitionsByIds: jest.fn(),
    listRequiredCustomDefinitions: jest.fn(),
  };
  const validator = new ClientWriteValidator(
    repository as unknown as ClientConfigRepository,
  );

  const definition = (
    valueType: ClientCustomValueType,
    options: unknown = [],
    overrides: Partial<ClientCustomFieldDefinitionRow> = {},
  ): ClientCustomFieldDefinitionRow => ({
    id: "field-1",
    field_key: "instrument",
    label: "Инструмент",
    value_type: valueType,
    is_required: false,
    is_active: true,
    is_system: false,
    options,
    version: 1,
    created_at: new Date("2026-01-01T00:00:00.000Z"),
    updated_at: new Date("2026-01-01T00:00:00.000Z"),
    deleted_at: null,
    visible_on_lead: true,
    visible_on_student: false,
    ...overrides,
  });

  async function convert(
    valueType: ClientCustomValueType,
    value: unknown,
    options: unknown = [],
  ): Promise<ValidatedCustomFields> {
    repository.findDefinitionsByIds.mockResolvedValue([
      definition(valueType, options),
    ]);
    return validator.validateCustomFields("lead", [
      { definitionId: "field-1", value },
    ]);
  }

  async function expectValidationError(
    promise: Promise<unknown>,
    expected: ValidationErrorPayload,
  ): Promise<void> {
    let caught: unknown;
    try {
      await promise;
    } catch (error) {
      caught = error;
    }
    expect(caught).toBeInstanceOf(UnprocessableEntityException);
    const exception = caught as UnprocessableEntityException;
    expect(exception.getStatus()).toBe(422);
    expect(exception.getResponse()).toEqual(expected);
  }

  beforeEach(() => {
    repository.findDefinitionsByIds.mockReset();
    repository.listRequiredCustomDefinitions.mockReset();
    repository.listRequiredCustomDefinitions.mockResolvedValue([]);
  });

  it("ignores the legacy typed discipline copy owned by the direction editor", async () => {
    repository.findDefinitionsByIds.mockResolvedValue([
      definition("select", ["Вокал"], {
        field_key: "discipline",
        label: "Направление",
        is_system: false,
      }),
    ]);

    await expect(
      validator.validateCustomFields("lead", [
        { definitionId: "field-1", value: "Сольфеджио" },
      ]),
    ).resolves.toEqual({ values: [], warnings: [] });
  });

  const successfulConversions: Array<{
    name: string;
    valueType: ClientCustomValueType;
    value: unknown;
    options?: unknown;
    expected: ValidatedCustomFields;
  }> = [
    {
      name: "number",
      valueType: "number",
      value: 12.5,
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: null,
            valueNumber: 12.5,
            valueBoolean: null,
            valueDate: null,
            valueJson: null,
          },
        ],
        warnings: [],
      },
    },
    {
      name: "money with zero",
      valueType: "money",
      value: 0,
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: null,
            valueNumber: 0,
            valueBoolean: null,
            valueDate: null,
            valueJson: null,
          },
        ],
        warnings: [],
      },
    },
    {
      name: "duration with a negative value",
      valueType: "duration",
      value: -5,
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: null,
            valueNumber: -5,
            valueBoolean: null,
            valueDate: null,
            valueJson: null,
          },
        ],
        warnings: [],
      },
    },
    {
      name: "boolean false",
      valueType: "boolean",
      value: false,
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: null,
            valueNumber: null,
            valueBoolean: false,
            valueDate: null,
            valueJson: null,
          },
        ],
        warnings: [],
      },
    },
    {
      name: "toggle",
      valueType: "toggle",
      value: true,
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: null,
            valueNumber: null,
            valueBoolean: true,
            valueDate: null,
            valueJson: null,
          },
        ],
        warnings: [],
      },
    },
    {
      name: "text",
      valueType: "text",
      value: "  Вокал  ",
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: "Вокал",
            valueNumber: null,
            valueBoolean: null,
            valueDate: null,
            valueJson: null,
          },
        ],
        warnings: [],
      },
    },
    {
      name: "textarea",
      valueType: "textarea",
      value: "  Вокал  ",
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: "Вокал",
            valueNumber: null,
            valueBoolean: null,
            valueDate: null,
            valueJson: null,
          },
        ],
        warnings: [],
      },
    },
    {
      name: "date",
      valueType: "date",
      value: "  2024-02-29  ",
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: null,
            valueNumber: null,
            valueBoolean: null,
            valueDate: "2024-02-29",
            valueJson: null,
          },
        ],
        warnings: [],
      },
    },
    {
      name: "datetime",
      valueType: "datetime",
      value: "  2026-08-28T12:30:00.000Z  ",
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: "2026-08-28T12:30:00.000Z",
            valueNumber: null,
            valueBoolean: null,
            valueDate: null,
            valueJson: null,
          },
        ],
        warnings: [],
      },
    },
    {
      name: "select",
      valueType: "select",
      value: "  Вокал  ",
      options: ["Вокал"],
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: "Вокал",
            valueNumber: null,
            valueBoolean: null,
            valueDate: null,
            valueJson: null,
          },
        ],
        warnings: [],
      },
    },
    {
      name: "radio",
      valueType: "radio",
      value: "  Вокал  ",
      options: ["Вокал"],
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: "Вокал",
            valueNumber: null,
            valueBoolean: null,
            valueDate: null,
            valueJson: null,
          },
        ],
        warnings: [],
      },
    },
    {
      name: "multi-select",
      valueType: "multi_select",
      value: ["Вокал", "Вокал", "Гитара"],
      options: ["Вокал", "Гитара"],
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: null,
            valueNumber: null,
            valueBoolean: null,
            valueDate: null,
            valueJson: ["Вокал", "Гитара"],
          },
        ],
        warnings: [],
      },
    },
    {
      name: "checkbox group",
      valueType: "checkbox_group",
      value: ["Гитара", "Вокал", "Гитара"],
      options: ["Вокал", "Гитара"],
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: null,
            valueNumber: null,
            valueBoolean: null,
            valueDate: null,
            valueJson: ["Гитара", "Вокал"],
          },
        ],
        warnings: [],
      },
    },
    {
      name: "email",
      valueType: "email",
      value: "  a@example.test  ",
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: "a@example.test",
            valueNumber: null,
            valueBoolean: null,
            valueDate: null,
            valueJson: null,
          },
        ],
        warnings: [],
      },
    },
    {
      name: "phone",
      valueType: "phone",
      value: "8 (999) 000-00-00",
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: "+79990000000",
            valueNumber: null,
            valueBoolean: null,
            valueDate: null,
            valueJson: null,
          },
        ],
        warnings: [
          {
            field: "customFields.instrument",
            code: "PHONE_NORMALIZED",
            normalizedValue: "+79990000000",
          },
        ],
      },
    },
    {
      name: "URL",
      valueType: "url",
      value: "  https://example.test/a  ",
      expected: {
        values: [
          {
            definitionId: "field-1",
            valueText: "https://example.test/a",
            valueNumber: null,
            valueBoolean: null,
            valueDate: null,
            valueJson: null,
          },
        ],
        warnings: [],
      },
    },
  ];

  it.each(successfulConversions)(
    "converts $name into exactly one typed slot",
    async ({ valueType, value, options, expected }) => {
      await expect(convert(valueType, value, options)).resolves.toEqual(
        expected,
      );
    },
  );

  it("preserves input order and definition IDs when repository order differs", async () => {
    repository.findDefinitionsByIds.mockResolvedValue([
      definition("phone", [], {
        id: "field-phone",
        field_key: "phone",
        label: "Телефон",
      }),
      definition("number", [], {
        id: "field-number",
        field_key: "age",
        label: "Возраст",
      }),
    ]);

    await expect(
      validator.validateCustomFields("lead", [
        { definitionId: "field-number", value: 12 },
        { definitionId: "field-phone", value: "8 (999) 000-00-00" },
      ]),
    ).resolves.toEqual({
      values: [
        {
          definitionId: "field-number",
          valueText: null,
          valueNumber: 12,
          valueBoolean: null,
          valueDate: null,
          valueJson: null,
        },
        {
          definitionId: "field-phone",
          valueText: "+79990000000",
          valueNumber: null,
          valueBoolean: null,
          valueDate: null,
          valueJson: null,
        },
      ],
      warnings: [
        {
          field: "customFields.phone",
          code: "PHONE_NORMALIZED",
          normalizedValue: "+79990000000",
        },
      ],
    });
  });

  it.each<ClientCustomValueType>(["number", "money", "duration"])(
    "rejects non-finite %s values",
    async (valueType) => {
      await expectValidationError(convert(valueType, Infinity), {
        code: "INVALID_FIELD_TYPE",
        field: "customFields.instrument",
        message: `Значение не соответствует типу ${valueType}.`,
      });
    },
  );

  it.each<ClientCustomValueType>(["boolean", "toggle"])(
    "rejects string values for %s before conversion",
    async (valueType) => {
      await expectValidationError(convert(valueType, "false"), {
        code: "INVALID_FIELD_TYPE",
        field: "customFields.instrument",
        message: `Значение не соответствует типу ${valueType}.`,
      });
    },
  );

  it.each<ClientCustomValueType>(["text", "textarea"])(
    "rejects blank %s values",
    async (valueType) => {
      await expectValidationError(convert(valueType, "   "), {
        code: "INVALID_FIELD_TYPE",
        field: "customFields.instrument",
        message: `Значение не соответствует типу ${valueType}.`,
      });
    },
  );

  it.each([
    {
      name: "impossible calendar date",
      valueType: "date" as const,
      value: "2024-02-31",
    },
    {
      name: "invalid datetime",
      valueType: "datetime" as const,
      value: "not-a-datetime",
    },
    {
      name: "invalid email",
      valueType: "email" as const,
      value: "not-an-email",
    },
    {
      name: "non-HTTP URL",
      valueType: "url" as const,
      value: "ftp://example.test",
    },
    {
      name: "malformed URL",
      valueType: "url" as const,
      value: "not a url",
    },
  ])("rejects $name with its exact type error", async ({ valueType, value }) => {
    await expectValidationError(convert(valueType, value), {
      code: "INVALID_FIELD_TYPE",
      field: "customFields.instrument",
      message: `Значение не соответствует типу ${valueType}.`,
    });
  });

  it("accepts HTTP as well as HTTPS URLs", async () => {
    await expect(convert("url", "http://example.test/a")).resolves.toEqual({
      values: [
        {
          definitionId: "field-1",
          valueText: "http://example.test/a",
          valueNumber: null,
          valueBoolean: null,
          valueDate: null,
          valueJson: null,
        },
      ],
      warnings: [],
    });
  });

  it.each<ClientCustomValueType>(["select", "radio"])(
    "rejects a wrong-shaped %s before option membership",
    async (valueType) => {
      await expectValidationError(convert(valueType, 1, [1, "Вокал"]), {
        code: "INVALID_FIELD_TYPE",
        field: "customFields.instrument",
        message: `Значение не соответствует типу ${valueType}.`,
      });
    },
  );

  it("treats non-array select options as empty", async () => {
    await expectValidationError(
      convert("select", "Вокал", { 0: "Вокал" }),
      {
        code: "OPTION_INACTIVE",
        field: "customFields.instrument",
        message: "Значение поля «Инструмент» отсутствует в справочнике.",
      },
    );
  });

  it.each<ClientCustomValueType>(["select", "radio"])(
    "rejects a stale %s option with the exact option error",
    async (valueType) => {
      await expectValidationError(convert(valueType, "Гитара", ["Вокал"]), {
        code: "OPTION_INACTIVE",
        field: "customFields.instrument",
        message: "Значение поля «Инструмент» отсутствует в справочнике.",
      });
    },
  );

  it("ignores non-string single-choice definition options", async () => {
    await expect(
      convert("select", "Вокал", [1, null, "Вокал"]),
    ).resolves.toEqual({
      values: [
        {
          definitionId: "field-1",
          valueText: "Вокал",
          valueNumber: null,
          valueBoolean: null,
          valueDate: null,
          valueJson: null,
        },
      ],
      warnings: [],
    });
    await expectValidationError(convert("select", "1", [1, "Вокал"]), {
      code: "OPTION_INACTIVE",
      field: "customFields.instrument",
      message: "Значение поля «Инструмент» отсутствует в справочнике.",
    });
  });

  it.each<ClientCustomValueType>(["multi_select", "checkbox_group"])(
    "rejects a scalar %s before option membership",
    async (valueType) => {
      await expectValidationError(convert(valueType, "Вокал", ["Вокал"]), {
        code: "INVALID_FIELD_TYPE",
        field: "customFields.instrument",
        message: `Значение не соответствует типу ${valueType}.`,
      });
    },
  );

  it("ignores non-string list definition options", async () => {
    await expect(
      convert("multi_select", ["Вокал"], [1, null, "Вокал"]),
    ).resolves.toEqual({
      values: [
        {
          definitionId: "field-1",
          valueText: null,
          valueNumber: null,
          valueBoolean: null,
          valueDate: null,
          valueJson: ["Вокал"],
        },
      ],
      warnings: [],
    });
    await expectValidationError(
      convert("multi_select", ["1"], [1, "Вокал"]),
      {
        code: "OPTION_INACTIVE",
        field: "customFields.instrument",
        message: "Значение поля «Инструмент» отсутствует в справочнике.",
      },
    );
  });

  it.each<ClientCustomValueType>(["multi_select", "checkbox_group"])(
    "rejects a mixed %s array before stale-option membership",
    async (valueType) => {
      await expectValidationError(
        convert(valueType, ["Гитара", 1], ["Вокал"]),
        {
          code: "INVALID_FIELD_TYPE",
          field: "customFields.instrument",
          message: `Значение не соответствует типу ${valueType}.`,
        },
      );
    },
  );

  it.each<ClientCustomValueType>(["multi_select", "checkbox_group"])(
    "rejects a stale %s list option",
    async (valueType) => {
      await expectValidationError(
        convert(valueType, ["Гитара"], ["Вокал"]),
        {
          code: "OPTION_INACTIVE",
          field: "customFields.instrument",
          message: "Значение поля «Инструмент» отсутствует в справочнике.",
        },
      );
    },
  );

  it.each<ClientCustomValueType>(["multi_select", "checkbox_group"])(
    "does not trim %s items",
    async (valueType) => {
      await expect(
        convert(valueType, [" Вокал ", " Вокал "], [" Вокал "]),
      ).resolves.toEqual({
        values: [
          {
            definitionId: "field-1",
            valueText: null,
            valueNumber: null,
            valueBoolean: null,
            valueDate: null,
            valueJson: [" Вокал "],
          },
        ],
        warnings: [],
      });
      await expectValidationError(
        convert(valueType, [" Вокал "], ["Вокал"]),
        {
          code: "OPTION_INACTIVE",
          field: "customFields.instrument",
          message: "Значение поля «Инструмент» отсутствует в справочнике.",
        },
      );
    },
  );

  it("returns no warning for an already canonical phone", async () => {
    await expect(convert("phone", "+79990000000")).resolves.toEqual({
      values: [
        {
          definitionId: "field-1",
          valueText: "+79990000000",
          valueNumber: null,
          valueBoolean: null,
          valueDate: null,
          valueJson: null,
        },
      ],
      warnings: [],
    });
  });

  it("keeps the exact invalid-phone error", async () => {
    await expectValidationError(convert("phone", "123"), {
      code: "INVALID_PHONE",
      field: "customFields.instrument",
      message: "Укажите корректный российский номер телефона.",
    });
  });

  it("rejects duplicate IDs before either repository lookup", async () => {
    await expectValidationError(
      validator.validateCustomFields("lead", [
        { definitionId: "field-1", value: "Вокал" },
        { definitionId: "field-1", value: "Гитара" },
      ]),
      {
        code: "DUPLICATE_FIELD",
        field: "customFields",
        message: "Дополнительное поле передано больше одного раза.",
      },
    );
    expect(repository.findDefinitionsByIds).not.toHaveBeenCalled();
    expect(repository.listRequiredCustomDefinitions).not.toHaveBeenCalled();
  });

  it("rejects a required omission before converting a malformed supplied value", async () => {
    repository.findDefinitionsByIds.mockResolvedValue([definition("number")]);
    repository.listRequiredCustomDefinitions.mockResolvedValue([
      definition("text", [], {
        id: "field-required",
        field_key: "required",
        label: "Обязательное поле",
        is_required: true,
      }),
    ]);

    await expectValidationError(
      validator.validateCustomFields("lead", [
        { definitionId: "field-1", value: Infinity },
      ]),
      {
        code: "REQUIRED_CUSTOM_FIELD",
        field: "customFields.required",
        message: "Поле «Обязательное поле» обязательно.",
      },
    );
  });

  it.each([
    { name: "missing", rows: [] as ClientCustomFieldDefinitionRow[] },
    {
      name: "system",
      rows: [definition("text", [], { is_system: true })],
    },
    {
      name: "inactive",
      rows: [definition("text", [], { is_active: false })],
    },
    {
      name: "deleted",
      rows: [
        definition("text", [], {
          deleted_at: new Date("2026-08-01T00:00:00.000Z"),
        }),
      ],
    },
  ])("keeps the exact failure for a $name definition", async ({ rows }) => {
    repository.findDefinitionsByIds.mockResolvedValue(rows);
    await expectValidationError(
      validator.validateCustomFields("lead", [
        { definitionId: "field-1", value: "Вокал" },
      ]),
      {
        code: "FIELD_INACTIVE",
        field: "customFields",
        message: "Дополнительное поле не найдено или архивировано.",
      },
    );
  });
});
