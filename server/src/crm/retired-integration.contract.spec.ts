import { PATH_METADATA } from "@nestjs/common/constants";
import { CrmReferenceDataController } from "./crm-reference-data.controller";

describe("CRM reference routes", () => {
  it("does not expose the retired external metadata proxy", () => {
    const prototype = CrmReferenceDataController.prototype;
    const paths = Object.getOwnPropertyNames(prototype)
      .filter((name) => name !== "constructor")
      .map((name) => Reflect.getMetadata(
        PATH_METADATA,
        Object.getOwnPropertyDescriptor(prototype, name)!.value,
      ));

    expect(paths).toContain("disciplines");
    expect(paths.filter((path) => String(path).includes("hollihop"))).toEqual([]);
  });
});
