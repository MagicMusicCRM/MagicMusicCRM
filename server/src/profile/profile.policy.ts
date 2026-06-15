import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import {
  ActorContext,
  isAdminRole,
  isManagerOrAdminRole
} from '../common/security/actor-context';

@Injectable()
export class ProfilePolicy {
  assertCanReadProfile(actor: ActorContext, profileUserId: string): void {
    if (isManagerOrAdminRole(actor.role)) return;
    if (actor.userId === profileUserId) return;
    throw new NotFoundException('Профиль не найден.');
  }

  assertCanListProfiles(actor: ActorContext): void {
    if (isManagerOrAdminRole(actor.role)) return;
    throw new ForbiddenException('Недостаточно прав для просмотра профилей.');
  }

  assertCanUpdateRole(
    actor: ActorContext,
    currentRole?: ActorContext['role'],
    newRole?: ActorContext['role']
  ): void {
    if (isAdminRole(actor.role)) return;
    if (
      actor.role === 'manager' &&
      currentRole !== 'admin' &&
      currentRole !== 'manager' &&
      currentRole !== 'system_admin' &&
      (newRole === 'client' || newRole === 'teacher')
    ) {
      return;
    }
    throw new ForbiddenException(
      'Недостаточно прав для изменения роли пользователя.'
    );
  }
}
