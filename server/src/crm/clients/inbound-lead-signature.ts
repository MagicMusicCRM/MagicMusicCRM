import { createHmac, timingSafeEqual } from "node:crypto";
import { fingerprintPayload } from "../../platform/platform-integrity.util";

export const INBOUND_LEAD_REPLAY_WINDOW_SECONDS = 300;

export function createInboundLeadSignature(
  secret: string,
  timestampSeconds: number,
  ingestionId: string,
  payload: unknown,
): string {
  const material = [
    String(timestampSeconds),
    ingestionId,
    fingerprintPayload(payload),
  ].join(".");
  return `sha256=${createHmac("sha256", secret).update(material).digest("hex")}`;
}

export function inboundLeadSignatureMatches(
  provided: string,
  expected: string,
): boolean {
  const left = Buffer.from(provided);
  const right = Buffer.from(expected);
  return left.length === right.length && timingSafeEqual(left, right);
}
