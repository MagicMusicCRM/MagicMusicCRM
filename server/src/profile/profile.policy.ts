import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import {
  ActorContext,
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
    _currentRole?: ActorContext['role'],
    _newRole?: ActorContext['role']
  ): void {
    // Управляющий, Администратор и Администратор системы получают полный
    // контроль над ролями: могут назначить ЛЮБУЮ роль системы любому
    // пользователю и сменить роль в любой момент. Защита от потери последнего
    // активного администратора системы реализована в сервисе (требует
    // запроса к БД и не может быть выражена в чистой policy).
    if (isManagerOrAdminRole(actor.role)) return;
    throw new ForbiddenException(
      'Недостаточно прав для изменения роли пользователя.'
    );
  }
}
