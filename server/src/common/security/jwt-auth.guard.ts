import {
  CanActivate,
  ExecutionContext,
  Injectable,
  Optional,
  UnauthorizedException
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Request } from 'express';
import {
  AuthenticatedRequest,
  JWT_AUDIENCE,
  JWT_ISSUER,
  UserRole
} from './actor-context';
import { DatabaseService } from '../../db/database.service';
import { CapabilityRequestAuthorizer } from '../../access-control/capability-request-authorizer';

interface AccessTokenPayload {
  sub?: string;
  role?: UserRole;
}

const VALID_ROLES = new Set<UserRole>([
  'client',
  'teacher',
  'manager',
  'admin',
  'director',
  'system_admin'
]);

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    @Optional() private readonly database?: DatabaseService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context
      .switchToHttp()
      .getRequest<Request & AuthenticatedRequest>();
    const token = this.extractBearerToken(request);

    if (!token) throw new UnauthorizedException('Требуется авторизация.');

    let payload: AccessTokenPayload;
    try {
      payload = await this.jwt.verifyAsync<AccessTokenPayload>(token, {
        secret: this.config.getOrThrow<string>('JWT_ACCESS_SECRET'),
        issuer: JWT_ISSUER,
        audience: JWT_AUDIENCE,
        algorithms: ['HS256']
      });
    } catch {
      throw new UnauthorizedException('Требуется авторизация.');
    }

    if (!payload.sub || !payload.role || !VALID_ROLES.has(payload.role)) {
      throw new UnauthorizedException('Требуется авторизация.');
    }

    request.user = { userId: payload.sub, role: payload.role };
    if (this.database) {
      const route = request.route as { path?: string } | undefined;
      const authorization =
        await new CapabilityRequestAuthorizer(this.database).authorize(
          request.user,
          request.method,
          request.originalUrl ||
            `${request.baseUrl ?? ''}${route?.path ?? request.path}`,
        );
      request.capabilityAccess = {
        capabilityKey: authorization.policy.capabilityKey,
        scope: authorization.policy.scope,
        decisionSource: authorization.source,
        legacyPolicy: authorization.policy.legacyPolicy,
      };
    }
    return true;
  }

  private extractBearerToken(request: Request): string | undefined {
    const authorization = request.headers.authorization;
    if (!authorization) return undefined;

    const [scheme, token] = authorization.split(' ');
    if (scheme !== 'Bearer' || !token) return undefined;
    return token;
  }
}
