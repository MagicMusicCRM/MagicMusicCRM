import { createHash } from "node:crypto";
import { AuthUserResponse, UserRecord } from "./auth.types";

export const normalizeEmail = (email: string): string =>
  email.trim().toLowerCase();

export const normalizePhone = (phone?: string | null): string | null => {
  const digits = (phone ?? "").replace(/\D/g, "");
  if (!digits) return null;
  if (digits.length === 11 && digits.startsWith("8")) {
    return `7${digits.slice(1)}`;
  }
  return digits;
};

export const splitFullName = (fullName: string): [string, string | null] => {
  const [firstName, ...rest] = fullName.trim().split(/\s+/);
  return [firstName, rest.length > 0 ? rest.join(" ") : null];
};

export const sha256 = (value: string): string =>
  createHash("sha256").update(value).digest("hex");

export const otpHash = (email: string, code: string): string =>
  sha256(`${email}:${code}`);

export const toAuthUserResponse = (user: UserRecord): AuthUserResponse => ({
  id: user.id,
  email: user.email,
  role: user.role,
  emailVerified: Boolean(user.email_verified_at),
});
