import { ForbiddenException } from '@nestjs/common';
import { ActorContext, isStaffRole } from '../common/security/actor-context';
import { DatabaseService } from './database.service';

export abstract class ScopedRepository {
  protected constructor(protected readonly database: DatabaseService) {}

  protected assertSelfOrStaff(actor: ActorContext, ownerId: string) {
    if (actor.userId === ownerId || this.isStaff(actor)) return;
    throw new ForbiddenException('Недостаточно прав для доступа к данным.');
  }

  protected isStaff(actor: ActorContext): boolean {
    return isStaffRole(actor.role);
  }
}
