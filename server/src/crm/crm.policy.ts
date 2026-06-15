import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import {
  ActorContext,
  isManagerOrAdminRole,
} from "../common/security/actor-context";

export interface StudentAccessRecord {
  profileUserId: string | null;
  teacherUserIds: string[];
}

@Injectable()
export class CrmPolicy {
  assertCanReadStudent(
    actor: ActorContext,
    student: StudentAccessRecord,
  ): void {
    if (isManagerOrAdminRole(actor.role)) return;
    if (actor.role === "client" && student.profileUserId === actor.userId)
      return;
    if (
      actor.role === "teacher" &&
      student.teacherUserIds.includes(actor.userId)
    )
      return;
    throw new NotFoundException("Ученик не найден.");
  }

  assertCanListStudents(actor: ActorContext): void {
    if (
      actor.role === "teacher" ||
      isManagerOrAdminRole(actor.role)
    )
      return;
    throw new ForbiddenException("Недостаточно прав для просмотра учеников.");
  }

  assertCanWriteCrm(actor: ActorContext): void {
    if (isManagerOrAdminRole(actor.role)) return;
    throw new ForbiddenException("Недостаточно прав для изменения CRM.");
  }

  assertCanReadOperationalData(actor: ActorContext): void {
    if (
      actor.role === "teacher" ||
      isManagerOrAdminRole(actor.role)
    )
      return;
    throw new ForbiddenException(
      "Недостаточно прав для просмотра справочников CRM.",
    );
  }

  assertCanReadFinance(actor: ActorContext, ownerUserId: string | null): void {
    if (isManagerOrAdminRole(actor.role)) return;
    if (actor.role === "client" && ownerUserId === actor.userId) return;
    throw new NotFoundException("Платежи не найдены.");
  }
}
