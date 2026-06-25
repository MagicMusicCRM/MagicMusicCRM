import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import {
  ActorContext,
  isManagerOrAdminRole,
  isManagerRole,
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

  /**
   * Финансы ученика в карточке (баланс/оплаты/ожидаемые платежи): Управляющий +
   * Администратор (+ system_admin). Преподаватель/клиент финансы в карточке не
   * видят. Отдельно от общего Финансы-таба (`assertManagerOnly`), который остаётся
   * только у Управляющего.
   */
  canReadStudentFinance(actor: ActorContext): boolean {
    return isManagerOrAdminRole(actor.role);
  }

  assertCanReadStudentFinance(actor: ActorContext): void {
    if (this.canReadStudentFinance(actor)) return;
    throw new NotFoundException("Платежи не найдены.");
  }

  // Operational CRM work: administrators must be able to cover each other's
  // shifts. Role management stays separate in ProfilePolicy/canAssignRole.
  assertManagerOnly(actor: ActorContext): void {
    if (isManagerOrAdminRole(actor.role)) return;
    throw new ForbiddenException(
      "Недостаточно прав для операционного раздела CRM.",
    );
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
    // Staff finance: admin/manager/system_admin. Client sees only own rows.
    if (isManagerOrAdminRole(actor.role)) return;
    if (actor.role === "client" && ownerUserId === actor.userId) return;
    throw new NotFoundException("Платежи не найдены.");
  }
}
