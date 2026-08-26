import { UserRole } from "../common/security/actor-context";

export interface UserRecord {
  id: string;
  email: string;
  password_hash: string | null;
  role: UserRole;
  email_verified_at: Date | string | null;
  email_otp_2fa_enabled?: boolean;
  is_app_account?: boolean;
}

export interface CountRecord {
  count: string;
}

export interface IdentityRecord {
  provider: string;
}

export interface AuthUserResponse {
  id: string;
  email: string;
  role: UserRole;
  emailVerified: boolean;
}

export interface SignupResponse {
  user: AuthUserResponse;
  emailVerificationRequired: boolean;
}

export interface AcceptedResponse {
  accepted: true;
}
