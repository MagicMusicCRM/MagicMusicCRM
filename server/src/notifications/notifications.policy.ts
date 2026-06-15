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
}
