import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import {
  ActorContext,
  canAssignRole,
  isManagerOrAdminRole,
  UserRole
} from '../common/security/actor-context';

@Injectable()
export class ProfilePolicy {
  assertCanReadProfile(actor: ActorContext, profileUserId: string): void {
    if (isManagerOrAdminRole(actor.role)) return;
    if (actor.userId === profileUserId) return;
    throw new NotFoundException('Профиль не найден.');
  }

  assertCanListProfiles(actor: ActorContext): void {
    // Operational work needs the full people directory: groups, tasks,
    // lessons, links between app accounts and CRM cards. Role mutation remains
    // guarded separately by assertCanUpdateRole below.
    if (isManagerOrAdminRole(actor.role)) return;
    throw new ForbiddenException('Недостаточно прав для просмотра профилей.');
  }

  assertCanUpdateRole(
    actor: ActorContext,
    currentRole?: UserRole,
    newRole?: UserRole
  ): void {
    // Иерархия ролей (правило владельца): client < teacher < admin < manager
    // < system_admin. Управление ролями доступно ТОЛЬКО Управляющему (manager)
    // и Администратору системы (system_admin). Администратор (admin) — ниже
    // Управляющего и НЕ управляет ролями вообще (не может повысить себя до
    // manager и не может назначить teacher/admin/manager/system_admin).
    // Управляющий может назначать только роли СТРОГО НИЖЕ себя
    // (client/teacher/admin) и не может менять роль пользователя, который уже
    // является manager/system_admin. system_admin имеет полный контроль; защита
    // от потери последнего активного system_admin реализована в сервисе.
    if (actor.role === 'system_admin') return;
    // KVA-239: director управляет ролями строго ниже себя (включая manager);
    // manager — строго ниже себя (и НЕ может назначать director/system_admin).
    if (
      (actor.role === 'manager' || actor.role === 'director') &&
      (currentRole === undefined || canAssignRole(actor.role, currentRole)) &&
      (newRole === undefined || canAssignRole(actor.role, newRole))
    ) {
      return;
    }
    throw new ForbiddenException(
      'Недостаточно прав для изменения роли пользователя.'
    );
  }
}
