import {
  DEFAULT_CRM_CUSTOM_FIELDS,
  findDefaultCrmField,
  crmFieldDisplayLabel,
} from "./crm-custom-field-catalog";

describe("CRM custom field catalog", () => {
  it("neutralizes only the imported identifier label", () => {
    expect(crmFieldDisplayLabel("hollihopId", "ID в HolliHop")).toBe("Внешний ID");
    expect(crmFieldDisplayLabel("hollihopId", "ID в Holli Hop")).toBe("Внешний ID");
    expect(crmFieldDisplayLabel("hollihopId", "Номер архива")).toBe("Номер архива");
    expect(crmFieldDisplayLabel("notes", "HolliHop")).toBe("HolliHop");
  });
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
