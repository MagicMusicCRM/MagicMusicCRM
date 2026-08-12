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
    // Operational work needs the full people directory: groups, tasks,
    // lessons and links between app accounts and CRM cards. Role mutation is
    // owned exclusively by the versioned Access settings service.
    if (isManagerOrAdminRole(actor.role)) return;
    throw new ForbiddenException('Недостаточно прав для просмотра профилей.');
  }
}
