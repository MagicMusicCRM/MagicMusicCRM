import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

describe("subscription lifecycle ownership boundaries", () => {
  const root = resolve(process.cwd(), "src", "crm", "commerce");
  const source = (name: string) =>
    readFileSync(resolve(root, name), "utf8");

  it("keeps each lifecycle responsibility in a named semantic owner", () => {
    for (const owner of [
      "subscription-lifecycle-command.policy.ts",
      "subscription-replacement.policy.ts",
      "subscription-cancellation.policy.ts",
      "subscription-replacement.service.ts",
      "subscription-cancellation.service.ts",
      "subscription-lifecycle.service.ts",
    ]) {
      expect(existsSync(resolve(root, owner))).toBe(true);
    }
  });

  it("keeps SubscriptionLifecycleService as a small transaction-free facade", () => {
    const facade = source("subscription-lifecycle.service.ts");
    const nloc = facade
      .split(/\r?\n/)
      .filter((line) => line.trim() && !line.trim().startsWith("//")).length;
    expect(nloc).toBeLessThanOrEqual(110);
    expect(facade).not.toContain("executeVersionedMutation");
    expect(facade).not.toContain("SubscriptionLifecycleRepository");
    expect(facade).not.toContain("PlatformIntegrityService");
    expect(facade).toContain("SubscriptionReplacementService");
    expect(facade).toContain("SubscriptionCancellationService");
  });

  it("keeps one complete transaction boundary in each executor", () => {
    const replacement = source("subscription-replacement.service.ts");
    const cancellation = source("subscription-cancellation.service.ts");
    expect(replacement.match(/executeVersionedMutation/g)).toHaveLength(1);
    expect(cancellation.match(/executeVersionedMutation/g)).toHaveLength(1);
    expect(replacement).toContain('operation: "crm.subscription.replace"');
    expect(cancellation).toContain('operation: "crm.subscription.cancel"');
    expect(replacement).toContain("publishPostCommit");
    expect(cancellation).toContain("publishPostCommit");
  });

  it("keeps pure policies free of persistence and integrity orchestration", () => {
    for (const name of [
      "subscription-lifecycle-command.policy.ts",
      "subscription-replacement.policy.ts",
      "subscription-cancellation.policy.ts",
    ]) {
      const policy = source(name);
      expect(policy).not.toContain("PlatformIntegrityService");
      expect(policy).not.toContain("DatabaseService");
      expect(policy).not.toContain("PoolClient");
      expect(policy).not.toContain("executeVersionedMutation");
    }
  });
});
