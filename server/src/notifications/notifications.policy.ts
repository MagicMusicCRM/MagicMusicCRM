import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import {
  ActorContext,
  isManagerOrAdminRole
} from '../common/security/actor-context';

export interface NotificationRecipientRecord {
  notification_id: string;
  user_id: string;
}

@Injectable()
export class NotificationsPolicy {
  assertCanReadRecipient(actor: ActorContext, recipient: NotificationRecipientRecord): void {
    if (recipient.user_id === actor.userId) return;
    throw new NotFoundException('Уведомление не найдено.');
  }

  assertCanAdminSend(actor: ActorContext): void {
    if (isManagerOrAdminRole(actor.role)) return;
    throw new ForbiddenException('Недостаточно прав для отправки уведомлений.');
  }

  /**
   * Same tier as sending broadcasts (admin/manager/director/system_admin):
   * deciding who hears about a new lead is the same class of operational
   * decision as sending them a message.
   */
  assertCanManagePreferences(actor: ActorContext): void {
    if (isManagerOrAdminRole(actor.role)) return;
    throw new ForbiddenException(
      'Недостаточно прав для настройки уведомлений.'
    );
  }
}
