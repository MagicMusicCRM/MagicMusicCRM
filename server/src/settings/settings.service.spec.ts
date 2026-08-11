import { BadRequestException, ForbiddenException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import { CrmCustomFieldDefinitionDto } from "./dto/update-crm-custom-fields.dto";
import { SettingsService } from "./settings.service";

describe("SettingsService", () => {
  const admin = { userId: "admin-a", role: "admin" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const audit = { record: jest.fn().mockResolvedValue(undefined) };
    const realtime = {
      emitSettingChanged: jest.fn(),
      emitCrmChanged: jest.fn(),
    };
    const service = new SettingsService(
      { query } as unknown as DatabaseService,
      audit as unknown as AuditService,
      realtime as unknown as RealtimeBus,
    );
    return { service, query, audit, realtime };
  };

  it("returns admin chat avatar setting for authenticated users", async () => {
    const { service, query } = createService([
      {
        key: "admin_chat_avatar_url",
        value_text: "storage://avatars/admin/avatar.png",
        updated_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.getAdminChatAvatar({ userId: "client-a", role: "client" }),
    ).resolves.toEqual({
      key: "admin_chat_avatar_url",
      value: "storage://avatars/admin/avatar.png",
      updatedAt: "2026-06-12T00:00:00.000Z",
    });
    expect(query.mock.calls[0][1]).toEqual(["admin_chat_avatar_url"]);
  });

  it("updates admin chat avatar only for admins and records audit", async () => {
    const { service, query, audit, realtime } = createService([
      {
        key: "admin_chat_avatar_url",
        value_text: "https://cdn.example.com/avatar.png",
        updated_at: "2026-06-12T00:00:00.000Z",
      },
    ]);

    await expect(
      service.updateAdminChatAvatar(
        admin,
        " https://cdn.example.com/avatar.png ",
      ),
    ).resolves.toEqual({
      key: "admin_chat_avatar_url",
      value: "https://cdn.example.com/avatar.png",
      updatedAt: "2026-06-12T00:00:00.000Z",
    });

    expect(query.mock.calls[0][1]).toEqual([
      "admin_chat_avatar_url",
      JSON.stringify("https://cdn.example.com/avatar.png"),
      "admin-a",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "settings.admin_chat_avatar_updated",
        entityType: "setting",
        entityId: "admin_chat_avatar_url",
        metadata: { cleared: false },
      }),
    );
    expect(realtime.emitSettingChanged).toHaveBeenCalledWith(
      "admin_chat_avatar_url",
    );
  });

  it("rejects manager writes and unsafe avatar schemes", async () => {
    const { service } = createService();

    await expect(
      service.updateAdminChatAvatar(
        { userId: "manager-a", role: "manager" },
        "https://cdn.example.com/avatar.png",
      ),
    ).rejects.toThrow(ForbiddenException);
    await expect(
      service.updateAdminChatAvatar(admin, "javascript:alert(1)"),
    ).rejects.toThrow(BadRequestException);
  });

  it("returns default CRM custom field schema when no saved setting exists", async () => {
    const { service, query } = createService();

    const result = await service.getCrmCustomFields({
      userId: "manager-a",
      role: "manager",
    });

    expect(query.mock.calls[0][1]).toEqual(["crm_custom_fields"]);
    expect(result.key).toBe("crm_custom_fields");
    expect(result.fields).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          entity: "students",
          key: "hollihopId",
          label: "ID в HolliHop",
        }),
        expect.objectContaining({
          entity: "students",
          key: "adSource",
          label: "Рекламный источник",
          type: "select",
          options: expect.any(Array),
        }),
      ]),
    );
    expect(
      result.fields.filter(
        (field) =>
          field.key === "source" &&
          (field.entity === "students" || field.entity === "leads"),
      ),
    ).toEqual([]);
    expect(
      result.fields.filter((field) =>
        ["workplace", "position", "individualPrice"].includes(field.key),
      ),
    ).toEqual([]);
  });

  it("filters owner-rejected fields from a persisted CRM schema", async () => {
    const persistedFields = [
      {
        entity: "students",
        key: "workplace",
        label: "Место работы/учёбы",
        type: "text",
      },
      {
        entity: "students",
        key: "position",
        label: "Должность/класс",
        type: "text",
      },
      {
        entity: "students",
        key: "individualPrice",
        label: "Индивидуальная цена",
        type: "number",
      },
      {
        entity: "students",
        key: "learningGoal",
        label: "Цель обучения",
        type: "text",
      },
    ];
    const { service } = createService([
      {
        key: "crm_custom_fields",
        value: persistedFields,
        updated_at: "2026-07-19T00:00:00.000Z",
      },
    ]);

    const result = await service.getCrmCustomFields(admin);

    expect(result.fields.map((field) => field.key)).toEqual(["learningGoal"]);
  });

  it("reuses canonical CRM level and category options for teacher fields", async () => {
    const { service } = createService([
      {
        key: "crm_custom_fields",
        value: [
          {
            entity: "teachers",
            key: "levels",
            label: "Уровни обучения",
            type: "select",
            options: [],
          },
          {
            entity: "teachers",
            key: "categories",
            label: "Категории",
            type: "select",
            options: [],
          },
        ],
        updated_at: "2026-08-11T00:00:00.000Z",
        configuration_snapshot: {
          fields: [
            {
              entityType: "lead",
              key: "level",
              valueType: "select",
              options: ["Без опыта", "Начальный", "Средний"],
              active: true,
            },
            {
              entityType: "student",
              key: "category",
              valueType: "multi_select",
              optionSetKey: "student_categories",
              active: true,
            },
          ],
          optionSets: [
            {
              key: "student_categories",
              options: [
                { key: "adult", label: "Взрослые", active: true },
                { key: "child", label: "Дети", active: true },
                { key: "old", label: "Архив", active: false },
              ],
            },
          ],
        },
      },
    ]);

    const result = await service.getCrmCustomFields(admin);
    const levels = result.fields.find(
      (field) => field.entity === "teachers" && field.key === "levels",
    );
    const categories = result.fields.find(
      (field) => field.entity === "teachers" && field.key === "categories",
    );

    expect(levels?.options).toEqual(["Без опыта", "Начальный", "Средний"]);
    expect(categories?.options).toEqual(["Взрослые", "Дети"]);
  });

  it("updates CRM custom field schema only for admins and records audit", async () => {
    const savedFields: CrmCustomFieldDefinitionDto[] = [
      {
        entity: "students",
        key: "parentName",
        label: "Имя родителя",
        type: "text",
        required: true,
        hint: "Контакт для связи",
      },
      {
        entity: "leads",
        key: "preferredDiscipline",
        label: "Интересующее направление",
        type: "select",
        required: false,
        options: ["Вокал", "Гитара"],
      },
    ];
    const { service, query, audit } = createService([
      {
        key: "crm_custom_fields",
        value: savedFields,
        updated_at: "2026-06-13T00:00:00.000Z",
      },
    ]);

    await expect(
      service.updateCrmCustomFields(admin, savedFields),
    ).resolves.toEqual({
      key: "crm_custom_fields",
      fields: savedFields,
      updatedAt: "2026-06-13T00:00:00.000Z",
    });
    expect(query.mock.calls[0][1]).toEqual([
      "crm_custom_fields",
      JSON.stringify(savedFields),
      "admin-a",
    ]);
    expect(audit.record).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "settings.crm_custom_fields_updated",
        entityType: "setting",
        entityId: "crm_custom_fields",
        metadata: { fieldCount: 2 },
      }),
    );
  });

  it("rejects non-admin CRM schema writes and duplicate field keys", async () => {
    const { service } = createService();

    await expect(
      service.updateCrmCustomFields({ userId: "manager-a", role: "manager" }, [
        {
          entity: "students",
          key: "parentName",
          label: "Имя родителя",
          type: "text",
        },
      ]),
    ).rejects.toThrow(ForbiddenException);

    await expect(
      service.updateCrmCustomFields(admin, [
        {
          entity: "students",
          key: "parentName",
          label: "Имя родителя",
          type: "text",
        },
        {
          entity: "students",
          key: "parentName",
          label: "Дублирующее поле",
          type: "text",
        },
      ]),
    ).rejects.toThrow(BadRequestException);
  });
});
