import { ClientConfigService } from "./client-config.service";

type UpdateArgs = Parameters<ClientConfigService["updateField"]>;
type Dto = UpdateArgs[2];
const actor: UpdateArgs[0] = { userId: "director-a", role: "director" };
const definitionId = "11111111-1111-4111-8111-111111111111",
  transactionClient = { id: "transaction-client" };
const patchKeys = [
  "expectedVersion",
  "label",
  "valueType",
  "required",
  "isActive",
  "options",
  "visibleOnLead",
  "visibleOnStudent",
];

const row = (overrides: Record<string, unknown> = {}) => ({
  id: definitionId,
  field_key: "instrument",
  label: "Instrument",
  value_type: "text",
  is_required: false,
  is_active: true,
  is_system: false,
  options: [],
  version: "7",
  created_at: "2026-08-28T08:00:00.000Z",
  updated_at: "2026-08-28T08:00:00.000Z",
  deleted_at: null,
  category_key: "details",
  category_label: "Details",
  sort_order: "4",
  width: "half",
  placements: ["edit", "card"],
  visible_on_lead: true,
  visible_on_student: true,
  ...overrides,
});

const patch = (values: Partial<Dto> = {}): Dto => ({
  expectedVersion: 7,
  ...values,
});

const fixture = (
  options: {
    before?: ReturnType<typeof row> | null;
    updated?: ReturnType<typeof row> | null;
    count?: number;
  } = {},
) => {
  const events: string[] = [];
  const before = options.before === undefined ? row() : options.before;
  const updated =
    options.updated === undefined ? row({ version: "8" }) : options.updated;
  const repository = {
    findDefinitionForUpdate: jest.fn(async (_client: object, _id: string) => {
      events.push("find");
      return before;
    }),
    countDefinitionValues: jest.fn(async (_client: object, _id: string) => {
      events.push("count");
      return options.count ?? 0;
    }),
    updateDefinition: jest.fn(
      async (_client: object, _id: string, _patch: Record<string, unknown>) => {
        events.push("update");
        return updated;
      },
    ),
  };
  const database = {
    transaction: jest.fn(
      async (callback: (client: object) => Promise<unknown>) => {
        events.push("transaction:start");
        const result = await callback(transactionClient);
        events.push("transaction:commit");
        return result;
      },
    ),
  };
  const policy = {
    assertCanManageClientConfiguration: jest.fn(() => events.push("policy")),
  };
  const audit = {
    record: jest.fn(
      async (_entry: Record<string, unknown>) => void events.push("audit"),
    ),
  };
  const dependencies = [
    database,
    repository,
    policy,
    audit,
  ] as unknown as ConstructorParameters<typeof ClientConfigService>;
  return {
    service: new ClientConfigService(...dependencies),
    database,
    repository,
    policy,
    audit,
    events,
    updated,
  };
};

const update = (f: ReturnType<typeof fixture>, dto: Dto = patch()) =>
  f.service.updateField(actor, definitionId, dto);

describe("ClientConfigService.updateField", () => {
  it("authorizes before starting a transaction", async () => {
    const f = fixture();
    const denied = new Error("policy-denied");
    f.policy.assertCanManageClientConfiguration.mockImplementation(() => {
      throw denied;
    });
    await expect(update(f)).rejects.toBe(denied);
    expect(f.database.transaction).not.toHaveBeenCalled();
  });

  it.each([
    [null, 7, "NotFoundException", 404, "Дополнительное поле не найдено."],
    [
      row({ version: "8" }),
      7,
      "ConflictException",
      409,
      "Дополнительное поле уже изменено в другой вкладке.",
    ],
  ])(
    "rejects missing and stale definitions before later reads",
    async (before, expectedVersion, name, status, message) => {
      const f = fixture({ before });
      await expect(update(f, patch({ expectedVersion }))).rejects.toMatchObject(
        { name, status, message },
      );
      expect(f.repository.countDefinitionValues).not.toHaveBeenCalled();
      expect(f.repository.updateDefinition).not.toHaveBeenCalled();
      expect(f.audit.record).not.toHaveBeenCalled();
    },
  );

  it("propagates unexpected repository errors by identity", async () => {
    const f = fixture(),
      failure = new Error("lookup-failed");
    f.repository.findDefinitionForUpdate.mockRejectedValue(failure);
    await expect(update(f)).rejects.toBe(failure);
    expect(f.repository.updateDefinition).not.toHaveBeenCalled();
    expect(f.audit.record).not.toHaveBeenCalled();
  });

  it.each([
    { required: false },
    { isActive: false },
    { valueType: "number" as const },
    { options: [] },
    { visibleOnLead: false },
    { visibleOnStudent: false },
  ])("preserves every ordered system-field lock: %o", async (change) => {
    const f = fixture({ before: row({ is_system: true }) });
    f.repository.countDefinitionValues.mockRejectedValue(
      new Error("eager-count"),
    );
    await expect(
      update(f, patch({ ...change, label: " " })),
    ).rejects.toMatchObject({
      status: 422,
      response: {
        code: "SYSTEM_FIELD_LOCKED",
        field: "field",
        message:
          "Системное обязательное поле нельзя архивировать, сделать необязательным или изменить его тип.",
      },
    });
    expect(f.repository.countDefinitionValues).not.toHaveBeenCalled();
    expect(f.repository.updateDefinition).not.toHaveBeenCalled();
  });

  it("allows a system relabel and repeated false on an already hidden side", async () => {
    const before = row({ is_system: true, visible_on_student: false }),
      eagerRead = new Error("eager-system-row-read");
    Object.defineProperties(before, {
      value_type: {
        get: () => {
          throw eagerRead;
        },
      },
      visible_on_lead: {
        get: () => {
          throw eagerRead;
        },
      },
    });
    const f = fixture({ before });
    await update(
      f,
      patch({
        label: "  Renamed  ",
        required: true,
        isActive: true,
        visibleOnLead: true,
        visibleOnStudent: false,
      }),
    );
    expect(f.repository.updateDefinition.mock.calls[0]![2]).toMatchObject({
      label: "Renamed",
      required: true,
      isActive: true,
      valueType: undefined,
      visibleOnLead: true,
      visibleOnStudent: false,
    });
  });

  it("does not count stored values for a label-only patch", async () => {
    const f = fixture();
    f.repository.countDefinitionValues.mockRejectedValue(
      new Error("eager-count"),
    );
    const dto = patch({ label: "  New label  " });
    await expect(update(f, dto)).resolves.toMatchObject({
      label: "Instrument",
      version: 8,
    });
    expect(f.repository.findDefinitionForUpdate).toHaveBeenCalledTimes(1);
    expect(f.repository.findDefinitionForUpdate).toHaveBeenCalledWith(
      transactionClient,
      definitionId,
    );
    expect(f.repository.countDefinitionValues).not.toHaveBeenCalled();
    const sent = f.repository.updateDefinition.mock.calls[0]![2];
    expect(Object.keys(sent)).toEqual(patchKeys);
    expect(sent).toEqual({
      expectedVersion: 7,
      label: "New label",
      valueType: undefined,
      required: undefined,
      isActive: undefined,
      options: undefined,
      visibleOnLead: undefined,
      visibleOnStudent: undefined,
    });
    expect(f.repository.updateDefinition).toHaveBeenCalledTimes(1);
    expect(f.repository.updateDefinition).toHaveBeenCalledWith(
      transactionClient,
      definitionId,
      sent,
    );
    expect(dto).toEqual({ expectedVersion: 7, label: "  New label  " });
  });

  it("does not count stored values when the type is unchanged", async () => {
    const f = fixture();
    f.repository.countDefinitionValues.mockRejectedValue(
      new Error("eager-count"),
    );
    await expect(
      update(f, patch({ valueType: "text" })),
    ).resolves.toBeDefined();
    expect(f.repository.countDefinitionValues).not.toHaveBeenCalled();
  });

  it("blocks a populated real type change before later validation", async () => {
    const f = fixture({ count: 2 });
    await expect(
      update(
        f,
        patch({
          valueType: "number",
          isActive: false,
          options: ["bad"],
          visibleOnLead: false,
          visibleOnStudent: false,
          label: " ",
        }),
      ),
    ).rejects.toMatchObject({
      status: 422,
      response: {
        code: "FIELD_TYPE_MIGRATION_REQUIRED",
        field: "valueType",
        message:
          "Тип поля с существующими значениями меняется только отдельной миграцией.",
      },
    });
    expect(f.repository.countDefinitionValues).toHaveBeenCalledTimes(1);
    expect(f.repository.countDefinitionValues).toHaveBeenCalledWith(
      transactionClient,
      definitionId,
    );
  });

  it.each([
    [
      patch({
        valueType: "select",
        options: [" Piano ", "", "Piano", "Guitar"],
      }),
      ["Piano", "Guitar"],
      Number.NaN,
    ],
    [patch({ options: [] }), [], 0],
  ])("normalizes a defined option patch", async (dto, normalized, count) => {
    const f = fixture({ count });
    await update(f, dto);
    expect(f.repository.updateDefinition.mock.calls[0]![2].options).toEqual(
      normalized,
    );
  });

  it.each([
    [
      patch({
        valueType: "select",
        options: [],
        visibleOnLead: false,
        visibleOnStudent: false,
        label: " ",
      }),
      "SELECT_OPTIONS_REQUIRED",
      "options",
      "Для поля типа select нужен хотя бы один вариант.",
    ],
    [
      patch({
        options: ["bad"],
        visibleOnLead: false,
        visibleOnStudent: false,
        label: " ",
      }),
      "OPTIONS_ONLY_FOR_SELECT",
      "options",
      "Варианты допустимы только для поля типа select.",
    ],
    [
      patch({ visibleOnLead: false, visibleOnStudent: false, label: " " }),
      "FIELD_VISIBILITY_REQUIRED",
      "visibility",
      "Активное поле должно быть видно хотя бы в карточке лида или ученика.",
    ],
    [
      patch({ label: " " }),
      "REQUIRED",
      "label",
      "Обязательное поле не заполнено.",
    ],
  ])(
    "preserves validation precedence for %s",
    async (dto, code, field, message) => {
      const f = fixture();
      await expect(update(f, dto)).rejects.toMatchObject({
        status: 422,
        response: { code, field, message },
      });
      expect(f.repository.updateDefinition).not.toHaveBeenCalled();
    },
  );

  it("allows an archived field to be hidden from both cards", async () => {
    const f = fixture({
      updated: row({
        version: 8,
        is_active: false,
        visible_on_lead: false,
        visible_on_student: false,
      }),
    });
    await expect(
      update(
        f,
        patch({
          isActive: false,
          visibleOnLead: false,
          visibleOnStudent: false,
        }),
      ),
    ).resolves.toMatchObject({ isActive: false });
  });

  it("returns the exact conflict when the optimistic update loses", async () => {
    const f = fixture({ updated: null });
    await expect(update(f)).rejects.toMatchObject({
      name: "ConflictException",
      status: 409,
      message: "Дополнительное поле уже изменено в другой вкладке.",
    });
    expect(f.audit.record).not.toHaveBeenCalled();
  });

  it.each([
    [false, null, true, "crm.client_custom_field_archived"],
    [true, "deleted", false, "crm.client_custom_field_updated"],
  ] as const)(
    "selects audit action from persisted active only",
    async (persisted, deletedAt, requested, action) => {
      const f = fixture({
        updated: row({
          version: 8,
          is_active: persisted,
          deleted_at: deletedAt,
        }),
      });
      await update(f, patch({ isActive: requested }));
      expect(f.events).toEqual([
        "policy",
        "transaction:start",
        "find",
        "update",
        "transaction:commit",
        "audit",
      ]);
      expect(f.audit.record.mock.calls[0]![0]).toMatchObject({ action });
    },
  );

  it("waits for post-commit audit before resolving", async () => {
    const f = fixture();
    Object.defineProperty(f.updated!, "label", {
      get: () => {
        f.events.push("dto");
        return "Instrument";
      },
    });
    let release!: () => void;
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });
    f.audit.record.mockImplementation(async () => {
      f.events.push("audit");
      await gate;
    });
    let settled = false;
    const result = update(f).then(() => {
      settled = true;
    });
    await new Promise<void>((resolve) => setImmediate(resolve));
    try {
      expect(f.events.slice(-2)).toEqual(["transaction:commit", "audit"]);
      expect(settled).toBe(false);
    } finally {
      release();
      await result;
    }
    expect(f.events.slice(-3)).toEqual(["transaction:commit", "audit", "dto"]);
  });

  it("propagates an audit failure only after commit", async () => {
    const f = fixture();
    Object.defineProperty(f.updated!, "label", {
      get: () => {
        throw new Error("dto-mapped");
      },
    });
    const failure = new Error("audit-failed");
    f.audit.record.mockImplementation(async () => {
      f.events.push("audit");
      throw failure;
    });
    await expect(update(f)).rejects.toBe(failure);
    expect(f.events.slice(-2)).toEqual(["transaction:commit", "audit"]);
    expect(f.repository.updateDefinition).toHaveBeenCalledTimes(1);
  });

  it("preserves the exact patch, audit payload and rich public DTO", async () => {
    const sourceOptions = [" Piano ", "Guitar"],
      persistedOptions = ["Piano", "Guitar"],
      placements = ["edit", "card"];
    const updated = row({
      label: "New label",
      value_type: "select",
      is_required: true,
      options: persistedOptions,
      placements,
      version: "8",
      visible_on_lead: false,
      visible_on_student: true,
    });
    const f = fixture({ updated });
    const result = await update(
      f,
      patch({
        label: " New label ",
        valueType: "select",
        required: true,
        isActive: true,
        options: sourceOptions,
        visibleOnLead: false,
        visibleOnStudent: true,
      }),
    );
    const repositoryPatch = f.repository.updateDefinition.mock.calls[0]![2];
    expect(Object.keys(repositoryPatch)).toEqual(patchKeys);
    expect(repositoryPatch).toEqual({
      expectedVersion: 7,
      label: "New label",
      valueType: "select",
      required: true,
      isActive: true,
      options: ["Piano", "Guitar"],
      visibleOnLead: false,
      visibleOnStudent: true,
    });
    expect(sourceOptions).toEqual([" Piano ", "Guitar"]);
    expect(repositoryPatch.options).not.toBe(sourceOptions);
    expect(f.audit.record).toHaveBeenCalledWith({
      actor,
      action: "crm.client_custom_field_updated",
      entityType: "client_custom_field",
      entityId: definitionId,
      metadata: {
        beforeVersion: 7,
        afterVersion: 8,
        valueType: "select",
        required: true,
      },
    });
    const auditEntry = f.audit.record.mock.calls[0]![0];
    expect(auditEntry.actor).toBe(actor);
    expect(Object.keys(auditEntry.metadata as object)).toEqual([
      "beforeVersion",
      "afterVersion",
      "valueType",
      "required",
    ]);
    expect(Object.keys(result)).toEqual([
      "id",
      "key",
      "label",
      "valueType",
      "required",
      "isActive",
      "isSystem",
      "options",
      "version",
      "archivedAt",
      "categoryKey",
      "categoryLabel",
      "order",
      "width",
      "placements",
      "visibility",
      "visibleOnLead",
      "visibleOnStudent",
    ]);
    expect(result).toEqual({
      id: definitionId,
      key: "instrument",
      label: "New label",
      valueType: "select",
      required: true,
      isActive: true,
      isSystem: false,
      options: ["Piano", "Guitar"],
      version: 8,
      archivedAt: null,
      categoryKey: "details",
      categoryLabel: "Details",
      order: 4,
      width: "half",
      placements: ["edit", "card"],
      visibility: { lead: false, student: true },
      visibleOnLead: false,
      visibleOnStudent: true,
    });
    expect(result.options).toBe(persistedOptions);
    expect(result.placements).toBe(placements);
  });

  it("preserves fallback DTO defaults and deleted active semantics", async () => {
    const f = fixture({
      updated: row({
        is_active: true,
        deleted_at: "archived",
        options: {},
        version: "9",
        category_key: undefined,
        category_label: undefined,
        sort_order: undefined,
        width: undefined,
        placements: {},
      }),
    });
    await expect(update(f)).resolves.toMatchObject({
      isActive: false,
      archivedAt: "archived",
      options: [],
      version: 9,
      categoryKey: "general",
      categoryLabel: "Основная информация",
      order: 0,
      width: "full",
      placements: ["create", "edit", "card"],
    });
  });
});
