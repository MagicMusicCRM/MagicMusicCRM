import type { Server } from "socket.io";
import { redactSensitive } from "../common/logging/redact.util";
import { RealtimeBus } from "../realtime/realtime-bus";
import {
  ActorClientProjectionFactory,
  CLIENT_PROJECTION_SURFACES,
  ClientProjectionSource,
} from "./actor-client-projection.factory";

const forbiddenTeacherKey =
  /contacts?|representatives?|finance|subscriptions?|payments?|balance|debt|price|cost|rate|payer|refund|reason|reversal|exclusion|compensation|phone|email|address/i;
const forbiddenValue =
  /LEAK_(?:PHONE|EMAIL|ADDRESS|REPRESENTATIVE|RATE|COST|PRIVATE_COMMENT|BALANCE|DEBT|PAYMENT|SUBSCRIPTION|PRICE)/;

const source: ClientProjectionSource = {
  id: "client-1",
  userId: "client-user-1",
  displayName: "Visible Student",
  lifecycleStatus: "active",
  branchId: "branch-1",
  contacts: {
    phone: "LEAK_PHONE",
    email: "LEAK_EMAIL",
    address: "LEAK_ADDRESS",
  },
  representatives: [
    {
      id: "representative-1",
      name: "LEAK_REPRESENTATIVE",
      phone: "LEAK_PHONE",
      relationship: "parent",
    },
  ],
  lessons: [
    {
      id: "lesson-1",
      scheduledAt: "2026-07-25T10:00:00.000Z",
      status: "scheduled",
      teacherRate: 991_001,
      clientCost: 991_002,
    },
  ],
  homework: [
    { id: "homework-1", title: "Visible exercise", status: "assigned" },
  ],
  comments: [
    {
      id: "comment-shared",
      body: "Visible shared comment",
      sharedWithTeacher: true,
    },
    {
      id: "comment-private",
      body: "LEAK_PRIVATE_COMMENT",
      sharedWithTeacher: false,
    },
  ],
  finance: {
    balance: 991_003,
    debt: 991_004,
    payments: [
      { id: "payment-1", amount: 991_005, paidAt: "2026-07-01T10:00:00Z" },
    ],
  },
  subscriptions: [
    {
      id: "subscription-1",
      packageName: "LEAK_SUBSCRIPTION",
      remainingLessons: 4,
      price: 991_006,
    },
  ],
};

function collectKeys(value: unknown): string[] {
  if (Array.isArray(value)) return value.flatMap(collectKeys);
  if (!value || typeof value !== "object") return [];
  return Object.entries(value as Record<string, unknown>).flatMap(
    ([key, child]) => [key, ...collectKeys(child)],
  );
}

describe("v4 Teacher payload leak scan", () => {
  it.each(CLIENT_PROJECTION_SURFACES)(
    "keeps %s JSON/read-model payload free of forbidden keys and values",
    (surface) => {
      const projected = new ActorClientProjectionFactory().project(
        { userId: "teacher-1", role: "teacher" },
        source,
        { self: false, assigned: true, branchAllowed: true },
        surface,
      );
      expect(collectKeys(projected)).not.toEqual(
        expect.arrayContaining([expect.stringMatching(forbiddenTeacherKey)]),
      );
      expect(JSON.stringify(projected)).not.toMatch(forbiddenValue);
    },
  );

  it("keeps access/CRM realtime payloads free of business and PII values", () => {
    const payloads: unknown[] = [];
    const emit = (_event: string, payload: unknown) => payloads.push(payload);
    const bus = new RealtimeBus();
    bus.setServer({
      emit,
      to: () => ({ emit }),
    } as unknown as Server);

    bus.emitUserAccessInvalidated("user-1", 2);
    bus.emitRoleAccessInvalidated("manager", 3);
    bus.emitCrmChanged({
      entity: "comment",
      action: "updated",
      id: "comment-1",
    });

    for (const payload of payloads) {
      expect(JSON.stringify(payload)).not.toMatch(forbiddenValue);
      expect(collectKeys(payload)).not.toEqual(
        expect.arrayContaining([expect.stringMatching(forbiddenTeacherKey)]),
      );
    }
  });

  it("redacts forbidden fields before structured log serialization", () => {
    const redacted = redactSensitive({
      phone: "LEAK_PHONE",
      email: "LEAK_EMAIL",
      address: "LEAK_ADDRESS",
      representativeName: "LEAK_REPRESENTATIVE",
      teacherRate: "LEAK_RATE",
      clientCost: "LEAK_COST",
      balance: "LEAK_BALANCE",
      debt: "LEAK_DEBT",
      paymentAmount: "LEAK_PAYMENT",
      subscriptionPrice: "LEAK_PRICE",
      commentBody: "LEAK_PRIVATE_COMMENT",
    });

    expect(JSON.stringify(redacted)).not.toMatch(forbiddenValue);
  });
});
