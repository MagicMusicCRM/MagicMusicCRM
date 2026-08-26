import {
  BadRequestException,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { SubscriptionLifecycleCommandPolicy } from "./subscription-lifecycle-command.policy";

describe("SubscriptionLifecycleCommandPolicy", () => {
  const policy = new SubscriptionLifecycleCommandPolicy();
  const metadata = {
    idempotencyKey: "replace-key-001",
    requestId: "request-001",
  };

  it("validates replacement confirmation, version, reason, token and metadata", () => {
    expect(() =>
      policy.assertReplacementCommand(
        {
          confirm: false,
          expectedVersion: 1,
          reason: "Причина",
          previewToken: "signed",
        } as never,
        metadata,
      ),
    ).toThrow(UnprocessableEntityException);
    expect(() =>
      policy.assertReplacementCommand(
        {
          confirm: true as const,
          expectedVersion: 1,
          reason: "Причина",
          previewToken: "signed",
        },
        { ...metadata, idempotencyKey: "short" },
      ),
    ).toThrow(BadRequestException);
  });

  it("binds actor, student, subscription and expected version", () => {
    const payload = {
      actorUserId: "actor-1",
      studentId: "student-1",
      issuedSubscriptionId: "subscription-1",
      expectedVersion: 3,
    };
    expect(() =>
      policy.assertReplacementTokenBinding(
        payload as never,
        { userId: "actor-2", role: "director" },
        "student-1",
        "subscription-1",
        3,
      ),
    ).toThrow(UnprocessableEntityException);
    expect(() =>
      policy.assertStudentScope({ studentId: "student-2" }, "student-1"),
    ).toThrow(NotFoundException);
  });

  it("derives a stable replacement id from actor, operation and key", () => {
    expect(
      policy.deterministicId(
        "actor-1",
        "crm.subscription.replace",
        "replace-key-001",
      ),
    ).toBe("d3cff883-9392-4a0e-b7d1-cd4883852a03");
  });
});
