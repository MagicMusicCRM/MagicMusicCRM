import { BadRequestException } from "@nestjs/common";
import { sanitizeJsonObject } from "./crm-util";

describe("crm-util sanitizeJsonObject", () => {
  it("rejects customData nested beyond the depth limit", () => {
    let deep: unknown = "x";
    for (let i = 0; i < 9; i++) deep = { nested: deep };
    expect(() => sanitizeJsonObject(deep)).toThrow(BadRequestException);
  });

  it("rejects customData with too many keys", () => {
    const big: Record<string, unknown> = {};
    for (let i = 0; i < 200; i++) big["k" + i] = i;
    expect(() => sanitizeJsonObject(big)).toThrow(BadRequestException);
  });

  it("accepts reasonable customData", () => {
    expect(sanitizeJsonObject({ a: 1, b: { c: "ok" } })).toEqual({
      a: 1,
      b: { c: "ok" },
    });
  });
});
