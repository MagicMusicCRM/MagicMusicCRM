import {
  Body,
  Controller,
  GoneException,
  Get,
  HttpCode,
  HttpStatus,
  Ip,
  Post,
  UseGuards,
} from "@nestjs/common";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { ActorContext } from "../common/security/actor-context";
import { AuthService } from "./auth.service";
import { LoginDto } from "./dto/login.dto";
import { RefreshSessionDto } from "./dto/refresh-session.dto";
import { RequestOtpDto } from "./dto/request-otp.dto";
import { RequestPasswordResetDto } from "./dto/request-password-reset.dto";
import { ResetPasswordDto } from "./dto/reset-password.dto";
import { SetPasswordDto } from "./dto/set-password.dto";
import { SignupDto } from "./dto/signup.dto";
import { VerifyOtpDto } from "./dto/verify-otp.dto";
import { VerifyEmailDto } from "./dto/verify-email.dto";

@Controller("auth")
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post("signup")
  async signup(@Body() dto: SignupDto, @Ip() ip: string) {
    return this.authService.signup(dto, ip);
  }

  @Post("login")
  @HttpCode(HttpStatus.OK)
  async login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  @Post("verify-email")
  @HttpCode(HttpStatus.OK)
  async verifyEmail(@Body() dto: VerifyEmailDto) {
    return this.authService.verifyEmail(dto.token);
  }

  @Post("otp/request")
  @HttpCode(HttpStatus.OK)
  async requestOtp(@Body() dto: RequestOtpDto) {
    return this.authService.requestOtp(dto.email);
  }

  @Post("otp/verify")
  @HttpCode(HttpStatus.OK)
  async verifyOtp(@Body() dto: VerifyOtpDto) {
    return this.authService.verifyOtp(dto.email, dto.code);
  }

  @Post("password-reset/request")
  @HttpCode(HttpStatus.OK)
  async requestPasswordReset(@Body() dto: RequestPasswordResetDto) {
    return this.authService.requestPasswordReset(dto.email);
  }

  @Post("password-reset/confirm")
  @HttpCode(HttpStatus.OK)
  async resetPassword(@Body() dto: ResetPasswordDto, @Ip() ip: string) {
    return this.authService.resetPassword(dto.token, dto.password, ip);
  }

  @Post("password")
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard)
  async setPassword(
    @CurrentActor() actor: ActorContext,
    @Body() dto: SetPasswordDto,
  ) {
    return this.authService.setPassword(actor, dto.password);
  }

  @Post("google/start")
  @HttpCode(HttpStatus.OK)
  async googleStart() {
    throw new GoneException(
      "Вход через Google отключен. Используйте почту и код из письма.",
    );
  }

  @Post("google/callback")
  @HttpCode(HttpStatus.OK)
  async googleCallback() {
    throw new GoneException(
      "Вход через Google отключен. Используйте почту и код из письма.",
    );
  }

  @Post("google/id-token")
  @HttpCode(HttpStatus.OK)
  async googleIdToken() {
    throw new GoneException(
      "Вход через Google отключен. Используйте почту и код из письма.",
    );
  }

  @Post("google/link-id-token")
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard)
  async googleLinkIdToken(
    @CurrentActor() _actor: ActorContext,
  ) {
    throw new GoneException(
      "Привязка Google отключена. Используйте почту и код из письма.",
    );
  }

  @Get("identities")
  @UseGuards(JwtAuthGuard)
  async identities(@CurrentActor() actor: ActorContext) {
    return this.authService.listIdentities(actor);
  }

  @Post("refresh")
  @HttpCode(HttpStatus.OK)
  async refresh(@Body() dto: RefreshSessionDto) {
    return this.authService.refresh(dto.refreshToken);
  }

  @Post("logout-all")
  @HttpCode(HttpStatus.OK)
  @UseGuards(JwtAuthGuard)
  async logoutAll(@CurrentActor() actor: ActorContext) {
    return this.authService.logoutAll(actor);
  }
}
