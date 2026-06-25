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

  // Управляющий-онли операции: Обзор/Финансы/Отчёты/Задачи/Пользователи.
  // Администратор (admin) — ниже Управляющего и сюда не допускается (бизнес-
  // правило A1, KVA-216; зеркалит фронтовый crm_nav_rbac.dart). system_admin —
  // полный доступ.
  assertManagerOnly(actor: ActorContext): void {
    if (isManagerRole(actor.role)) return;
    throw new ForbiddenException(
      "Недостаточно прав: операция доступна только Управляющему.",
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
    // Финансы — только Управляющий/Администратор системы (A1); клиент видит свои.
    if (isManagerRole(actor.role)) return;
    if (actor.role === "client" && ownerUserId === actor.userId) return;
    throw new NotFoundException("Платежи не найдены.");
  }
}
