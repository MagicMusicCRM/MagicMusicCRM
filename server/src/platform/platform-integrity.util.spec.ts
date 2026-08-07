import {
  computeOutboxBackoffSeconds,
  fingerprintPayload,
  safeAuditReason,
  safeAuditReasonText,
  safeFailureName,
  safeOutboxPayload,
  safeReference,
} from "./platform-integrity.util";

describe("platform integrity utilities", () => {
  it("fingerprints equivalent JSON independently of object key order", () => {
    expect(
      fingerprintPayload({
        nested: { second: 2, first: 1 },
        values: ["a", "b"],
      }),
    ).toBe(
      fingerprintPayload({
        values: ["a", "b"],
        nested: { first: 1, second: 2 },
      }),
    );
    expect(fingerprintPayload({ value: 1 })).not.toBe(
      fingerprintPayload({ value: 2 }),
    );
  });

  it("rejects payloads that do not have a stable JSON representation", () => {
    expect(() => fingerprintPayload(undefined)).toThrow(
      "unsupported undefined",
    );
    expect(() => fingerprintPayload({ value: 1n })).toThrow(
      "unsupported bigint",
    );
    expect(() => fingerprintPayload({ value: Number.NaN })).toThrow(
      "non-finite",
    );
  });

  it("redacts result references and outbox envelopes recursively", () => {
    expect(
      safeReference({
        entityId: "safe-id",
        contactEmail: "person@example.com",
        accessToken: "secret-token",
        amount: 500,
        payerStudentId: "payer-id",
        refundMinor: "100",
      }),
    ).toEqual({
      entityId: "safe-id",
      contactEmail: "[PRIVATE]",
      accessToken: "[REDACTED]",
      amount: "[PRIVATE]",
      payerStudentId: "payer-id",
      refundMinor: "100",
    });
    expect(
      safeOutboxPayload({
        note: "Contact person@example.com",
        nested: { phone: "+79990000000" },
        entityId: "safe-id",
        changedFields: ["status"],
        accessVersion: 2,
      }),
    ).toEqual({
      entityId: "safe-id",
      changedFields: ["status"],
      accessVersion: 2,
    });
    expect(safeAuditReason("schedule.conflict")).toBe("schedule.conflict");
    expect(() => safeAuditReason("free-form private reason")).toThrow(
      "reason code",
    );
    expect(safeAuditReasonText("  Клиент сменил филиал  ")).toBe(
      "Клиент сменил филиал",
    );
    expect(() => safeAuditReasonText("   ")).toThrow("1..500");
    expect(() => safeAuditReasonText("x".repeat(501))).toThrow("1..500");
  });

  it("uses bounded exponential retry and safe error names", () => {
    expect(computeOutboxBackoffSeconds(1, 5, 60)).toBe(5);
    expect(computeOutboxBackoffSeconds(4, 5, 60)).toBe(40);
    expect(computeOutboxBackoffSeconds(9, 5, 60)).toBe(60);
    expect(safeFailureName(new TypeError("contains private detail"))).toBe(
      "TypeError",
    );
  });
});
