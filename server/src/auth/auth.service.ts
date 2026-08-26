import { Injectable } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { AuthAccountService } from "./auth-account.service";
import { AuthLoginService } from "./auth-login.service";
import { AuthPasswordRecoveryService } from "./auth-password-recovery.service";
import { AuthRegistrationService } from "./auth-registration.service";
import {
  AcceptedResponse,
  AuthUserResponse,
  SignupResponse,
} from "./auth.types";
import { AuthVerificationService } from "./auth-verification.service";
import { LoginDto } from "./dto/login.dto";
import { SignupDto } from "./dto/signup.dto";
import { TokenPair } from "./session.service";

@Injectable()
export class AuthService {
  constructor(
    private readonly registration: AuthRegistrationService,
    private readonly loginFlow: AuthLoginService,
    private readonly verification: AuthVerificationService,
    private readonly recovery: AuthPasswordRecoveryService,
    private readonly account: AuthAccountService,
  ) {}

  signup(dto: SignupDto, clientIp?: string): Promise<SignupResponse> {
    return this.registration.signup(dto, clientIp);
  }

  login(
    dto: LoginDto,
  ): Promise<{
    user: AuthUserResponse;
    session?: TokenPair;
    emailOtpRequired?: boolean;
  }> {
    return this.loginFlow.login(dto);
  }

  refresh(refreshToken: string): Promise<{ session: TokenPair }> {
    return this.loginFlow.refresh(refreshToken);
  }

  logoutAll(actor: ActorContext): Promise<{ success: true }> {
    return this.loginFlow.logoutAll(actor);
  }

  requestOtp(emailInput: string): Promise<AcceptedResponse> {
    return this.verification.requestOtp(emailInput);
  }

  verifyOtp(
    emailInput: string,
    code: string,
  ): Promise<{ user: AuthUserResponse; session?: TokenPair }> {
    return this.verification.verifyOtp(emailInput, code);
  }

  requestPasswordReset(emailInput: string): Promise<AcceptedResponse> {
    return this.recovery.requestPasswordReset(emailInput);
  }

  resetPassword(
    token: string,
    password: string,
    clientIp?: string,
  ): Promise<{ user: AuthUserResponse }> {
    return this.recovery.resetPassword(token, password, clientIp);
  }

  setPassword(
    actor: ActorContext,
    password: string,
  ): Promise<{ user: AuthUserResponse }> {
    return this.account.setPassword(actor, password);
  }

  changeEmail(
    actor: ActorContext,
    emailInput: string,
    currentPassword: string,
  ): Promise<{ user: AuthUserResponse }> {
    return this.account.changeEmail(actor, emailInput, currentPassword);
  }

  listIdentities(
    actor: ActorContext,
  ): Promise<{ items: Array<{ provider: string }> }> {
    return this.account.listIdentities(actor);
  }

  verifyEmail(token: string): Promise<{ user: AuthUserResponse }> {
    return this.verification.verifyEmail(token);
  }
}

export type {
  AcceptedResponse,
  AuthUserResponse,
  SignupResponse,
} from "./auth.types";
