const codec = require("./subscription-preview-token") as Record<
  string,
  (...args: never[]) => unknown
>;

const SECRET = "schedule-history-preview-secret-at-least-32-bytes";
const NOW = 1_800_000_100;
const payload = {
  kind: "schedule.plan.history",
  operation: "update",
  actorUserId: "10000000-0000-4000-8000-000000000001",
  planId: "10000000-0000-4000-8000-000000000002",
  expectedVersion: 3,
  activeFrom: "2026-08-01",
  activeUntil: "2026-09-30",
  clientFingerprint:
    "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  draftFingerprint:
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  historyFingerprint:
    "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  issuedAtSeconds: 1_800_000_000,
  expiresAtSeconds: 1_800_000_300,
};

describe("schedule plan history preview token", () => {
  it("binds actor, plan, draft, date range and expiry without weakening its domain", () => {
    const sign = codec.signSchedulePlanHistoryPreview;
    const verify = codec.verifySchedulePlanHistoryPreview;
    const verifyPlanEnd = codec.verifySchedulePlanEndPreview;
    expect(sign).toEqual(expect.any(Function));
    expect(verify).toEqual(expect.any(Function));

    const token = sign(SECRET as never, payload as never) as string;
    expect(verify(SECRET as never, token as never, NOW as never)).toEqual(
      payload,
    );

    const [version, body, signature] = token.split(".");
    const changed = { ...payload, actorUserId: payload.planId };
    const changedBody = Buffer.from(JSON.stringify(changed), "utf8").toString(
      "base64url",
    );
    const actorSwapped = `${version}.${changedBody}.${signature}`;
    expect(() =>
      verify(SECRET as never, actorSwapped as never, NOW as never),
    ).toThrow();
    const changedClient = {
      ...payload,
      clientFingerprint:
        "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    };
    const changedClientBody = Buffer.from(
      JSON.stringify(changedClient),
      "utf8",
    ).toString("base64url");
    expect(() =>
      verify(
        SECRET as never,
        `${version}.${changedClientBody}.${signature}` as never,
        NOW as never,
      ),
    ).toThrow();
    expect(() =>
      verifyPlanEnd(SECRET as never, token as never, NOW as never),
    ).toThrow(expect.objectContaining({ code: "PREVIEW_TOKEN_INVALID" }));
    expect(() =>
      verify(SECRET as never, token as never, 1_800_000_301 as never),
    ).toThrow(expect.objectContaining({ code: "PREVIEW_TOKEN_EXPIRED" }));
    expect(body).toBeDefined();
  });
});
