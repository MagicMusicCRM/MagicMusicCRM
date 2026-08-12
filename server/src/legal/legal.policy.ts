import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import {
  ActorContext,
  isAdminRole,
  isManagerOrAdminRole,
} from "../common/security/actor-context";
import { AccountDeletionStatus } from "./legal.types";

export interface DeletionRequestAccessRecord {
  id: string;
  user_id: string;
  status: AccountDeletionStatus;
}

@Injectable()
export class LegalPolicy {
  assertCanReadDeletionRequest(
    actor: ActorContext,
    request: DeletionRequestAccessRecord,
  ): void {
    if (actor.userId === request.user_id) return;
    if (isManagerOrAdminRole(actor.role)) return;
    throw new NotFoundException("Запрос на удаление не найден.");
  }

  assertCanListDeletionRequests(actor: ActorContext): void {
    if (isManagerOrAdminRole(actor.role)) return;
    throw new ForbiddenException("Недостаточно прав для просмотра запросов.");
  }

  assertCanUpdateDeletionRequest(actor: ActorContext): void {
    if (isAdminRole(actor.role) || actor.role === "director") return;
    throw new ForbiddenException(
      "Статус удаления может менять администратор, директор или системный администратор.",
    );
  }

  assertValidTransition(
    current: AccountDeletionStatus,
    next: AccountDeletionStatus,
  ): void {
    const allowed: Record<AccountDeletionStatus, AccountDeletionStatus[]> = {
      pending: ["processing", "cancelled"],
      processing: ["completed", "rejected"],
      completed: [],
      rejected: [],
      cancelled: [],
    };

    if (allowed[current].includes(next)) return;
    throw new ForbiddenException("Недопустимый переход статуса удаления.");
  }
}
