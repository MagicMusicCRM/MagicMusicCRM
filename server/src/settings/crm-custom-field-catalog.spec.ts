import {
  DEFAULT_CRM_CUSTOM_FIELDS,
  findDefaultCrmField,
} from "./crm-custom-field-catalog";

describe("CRM custom field catalog", () => {
  it("owns unique Russian labels for the current standard fields", () => {
    const identities = DEFAULT_CRM_CUSTOM_FIELDS.map(
      (field) => `${field.entity}:${field.key}`,
    );
    expect(new Set(identities).size).toBe(identities.length);
    expect(findDefaultCrmField("birthday", "students")?.label).toBe(
      "Дата рождения",
    );
    expect(findDefaultCrmField("discipline", "leads")?.label).toBe(
      "Интересующее направление",
    );
    expect(findDefaultCrmField("additionalParams", "teachers")?.label).toBe(
      "Дополнительные параметры",
    );
  });
});
