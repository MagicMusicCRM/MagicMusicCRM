import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Request } from 'express';
import { ActorContext, AuthenticatedRequest } from './actor-context';
import { ROLES_KEY } from './roles.decorator';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<ActorContext['role'][]>(
      ROLES_KEY,
      [context.getHandler(), context.getClass()]
    );

    if (!requiredRoles || requiredRoles.length === 0) return true;

    const request = context.switchToHttp().getRequest<Request & AuthenticatedRequest>();
    const actor = request.user;
    if (!actor) throw new UnauthorizedException('Требуется авторизация.');

    if (actor.role === 'system_admin') return true;

    if (!requiredRoles.includes(actor.role)) {
      throw new ForbiddenException('Недостаточно прав для выполнения действия.');
    }

    return true;
  }
}
