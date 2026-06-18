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
    // Администратор / Администратор системы: полный контроль над ролями.
    if (isAdminRole(actor.role)) return;
    // Управляющий (manager): может назначать любую операционную роль —
    // «Клиент», «Преподаватель» и саму высшую операционную «Управляющий»,
    // — но НЕ может выдавать admin/system_admin и НЕ может менять роль
    // пользователям admin-уровня (нет эскалации выше собственного уровня).
    if (actor.role === 'manager') {
      const targetIsAdminTier =
        currentRole === 'admin' || currentRole === 'system_admin';
      const grantsAdminTier =
        newRole === 'admin' || newRole === 'system_admin';
      if (!targetIsAdminTier && !grantsAdminTier) return;
    }
    throw new ForbiddenException(
      'Недостаточно прав для изменения роли пользователя.'
    );
  }
}
