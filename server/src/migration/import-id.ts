// server/src/migration/import-id.ts
import { createHash } from "node:crypto";

/**
 * Stable UUIDv4-shaped id derived from a namespace + key.
 *
 * This is what makes the import idempotent: the same export row always yields
 * the same id, so `on conflict (id) do nothing` turns a re-run into a no-op
 * instead of a second copy of every task. Recovered from the retired
 * server/src/migration/import/v3/v3-import-utils.ts (commit 7f2a3fd7^) so the ids match
 * the rows already in production — a different scheme would duplicate all 514.
 */
export function deterministicUuid(namespace: string, key: string): string {
  const bytes = createHash("sha256")
    .update(`${namespace}:${key}`)
    .digest()
    .subarray(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20, 32),
  ].join("-");
}
