import {
  signSchedulePlanEndPreview,
  signSchedulePlanRowRemovalPreview,
  SubscriptionPreviewTokenError,
  verifySchedulePlanRowRemovalPreview,
} from "./subscription-preview-token";

const SECRET = "schedule-row-preview-secret-at-least-32-bytes";
const payload = {
  kind: "schedule.plan.row.remove" as const,
  actorUserId: "10000000-0000-4000-8000-000000000001",
  planId: "10000000-0000-4000-8000-000000000002",
  seriesId: "10000000-0000-4000-8000-000000000003",
  expectedVersion: 4,
  effectiveFrom: "2026-09-04",
  impactFingerprint:
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  issuedAtSeconds: 1_800_000_000,
  expiresAtSeconds: 1_800_000_300,
};

describe("schedule plan row removal preview token", () => {
  it("round-trips exact row identity and rejects expiration", () => {
    const token = signSchedulePlanRowRemovalPreview(SECRET, payload);

    expect(verifySchedulePlanRowRemovalPreview(SECRET, token, 1_800_000_100)).toEqual(
      payload,
    );
    expect(() =>
      verifySchedulePlanRowRemovalPreview(SECRET, token, 1_800_000_301),
    ).toThrow(expect.objectContaining({ code: "PREVIEW_TOKEN_EXPIRED" }));
  });

  it("rejects missing fields, tampering, and plan-end cross-domain tokens", () => {
    expect(() =>
      signSchedulePlanRowRemovalPreview(SECRET, {
        ...payload,
        seriesId: undefined,
      } as never),
    ).toThrow(expect.objectContaining({ code: "PREVIEW_TOKEN_INVALID" }));

    const token = signSchedulePlanRowRemovalPreview(SECRET, payload);
    const [version, body, signature] = token.split(".");
    const tamperedSignature = `${signature![0] === "A" ? "B" : "A"}${signature!.slice(1)}`;
    const tampered = `${version}.${body}.${tamperedSignature}`;
    expect(() =>
      verifySchedulePlanRowRemovalPreview(SECRET, tampered, 1_800_000_100),
    ).toThrow(SubscriptionPreviewTokenError);

    const endToken = signSchedulePlanEndPreview(SECRET, {
      kind: "schedule.plan.end",
      actorUserId: payload.actorUserId,
      planId: payload.planId,
      expectedVersion: payload.expectedVersion,
      lastDate: payload.effectiveFrom,
      impactFingerprint: payload.impactFingerprint,
      issuedAtSeconds: payload.issuedAtSeconds,
      expiresAtSeconds: payload.expiresAtSeconds,
    });
    expect(() =>
      verifySchedulePlanRowRemovalPreview(SECRET, endToken, 1_800_000_100),
    ).toThrow(expect.objectContaining({ code: "PREVIEW_TOKEN_INVALID" }));
  });
});
