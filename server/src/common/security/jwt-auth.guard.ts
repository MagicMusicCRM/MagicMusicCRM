import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
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
import { resolveCapabilityRoutePolicy } from '../../access-control/capability-route-policy';
import { V4DomainFlagsService } from '../../platform/rollout/v4/domain-flags';

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
    @Optional() private readonly v4DomainFlags?: V4DomainFlagsService,
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
      const path = request.originalUrl ||
        `${request.baseUrl ?? ''}${route?.path ?? request.path}`;
      const policy = resolveCapabilityRoutePolicy(request.method, path);
      const rollout = (this.v4DomainFlags ?? new V4DomainFlagsService())
        .get('access');
      const authorizer = new CapabilityRequestAuthorizer(this.database);

      if (rollout.effectivePath === 'legacy') {
        if (
          !policy.authenticatedOnly &&
          !policy.legacyAllowedRoles.includes(request.user.role)
        ) {
          throw new ForbiddenException({
            code: 'LEGACY_ROLE_DENIED',
            capabilityKey: policy.capabilityKey,
          });
        }

        let decisionSource = 'legacy';
        if (rollout.shadowCompare) {
          try {
            const shadow = await authorizer.authorize(
              request.user,
              request.method,
              path,
            );
            decisionSource = `legacy;shadow:${shadow.source}:allow`;
          } catch (error) {
            decisionSource = error instanceof ForbiddenException
              ? 'legacy;shadow:deny'
              : 'legacy;shadow:error';
          }
        }
        request.capabilityAccess = {
          capabilityKey: policy.capabilityKey,
          scope: policy.scope,
          decisionSource,
          legacyPolicy: policy.legacyPolicy,
        };
        return true;
      }

      const authorization = await authorizer.authorize(
        request.user,
        request.method,
        path,
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
