import { BadRequestException, ValidationPipe } from "@nestjs/common";
import {
  UpdateClientCustomFieldDto,
  UpdateLeadSourceDto,
} from "./client-config.dto";

describe("client configuration PATCH validation", () => {
  const pipe = new ValidationPipe({
    transform: true,
    whitelist: true,
    forbidNonWhitelisted: true,
  });

  it.each([
    { metatype: UpdateLeadSourceDto, field: "canonicalName" },
    { metatype: UpdateLeadSourceDto, field: "displayName" },
    { metatype: UpdateClientCustomFieldDto, field: "label" },
  ])("rejects explicit null for $field before the command", async ({ metatype, field }) => {
    await expect(pipe.transform(
      { expectedVersion: 1, [field]: null },
      { type: "body", metatype },
    )).rejects.toBeInstanceOf(BadRequestException);
  });

  it.each([UpdateLeadSourceDto, UpdateClientCustomFieldDto])(
    "allows archiving without resending the name (%p)",
    async (metatype) => {
      await expect(pipe.transform(
        { expectedVersion: 1, isActive: false },
        { type: "body", metatype },
      )).resolves.toMatchObject({ expectedVersion: 1, isActive: false });
    },
  );

  it("accepts valid source and field renames", async () => {
    await expect(pipe.transform(
      { expectedVersion: 1, canonicalName: "referral", displayName: "Рекомендация" },
      { type: "body", metatype: UpdateLeadSourceDto },
    )).resolves.toMatchObject({ canonicalName: "referral", displayName: "Рекомендация" });
    await expect(pipe.transform(
      { expectedVersion: 1, label: "Направление" },
      { type: "body", metatype: UpdateClientCustomFieldDto },
    )).resolves.toMatchObject({ label: "Направление" });
  });
});
