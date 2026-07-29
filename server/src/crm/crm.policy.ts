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

  /**
   * ОБЩЕШКОЛЬНЫЕ финансы и финансовая аналитика (отчёт по выручке, расходы,
   * помесячные финансы, долги, прогноз выручки): ТОЛЬКО Директор (director)
   * и Администратор системы (system_admin). Управляющий (manager) и
   * Администратор (admin) ИСКЛЮЧЕНЫ — решение владельца (KVA-239).
   * Финансы в КАРТОЧКЕ клиента (история оплат, баланс, личный счёт) у
   * Управляющего остаются — см. canReadStudentFinance выше.
   */
  canReadSchoolFinance(actor: ActorContext): boolean {
    return actor.role === "director" || actor.role === "system_admin";
  }

  assertCanReadSchoolFinance(actor: ActorContext): void {
    if (this.canReadSchoolFinance(actor)) return;
    throw new ForbiddenException(
      "Недостаточно прав для общешкольных финансов.",
    );
  }

  /**
   * Управление КАТАЛОГОМ абонементов (создание/редактирование/удаление пакетов
   * с ценами) — это ценовая конфигурация, т.е. общешкольные финансы: только
   * Директор и Администратор системы. ✔ Владелец: Управляющий абонементы ВИДИТ
   * (каталог + абонементы учеников) и может ВЫДАВАТЬ их ученикам, но САМИ пакеты
   * не создаёт и не правит.
   */
  assertCanManageSubscriptionPackages(actor: ActorContext): void {
    if (this.canReadSchoolFinance(actor)) return;
    throw new ForbiddenException(
      "Управление каталогом абонементов доступно только директору.",
    );
  }

  /**
   * Системные настройки (конфигурация воронки лидов: колонки/их порядок и т.п.).
   * ✔ Владелец: «любые настройки системы может вносить только сис-админ,
   * директор и управляющий» — Администратор (администратор филиала) СЮДА не
   * входит, в отличие от обычной операционной записи (assertCanWriteCrm).
   */
  assertCanManageSystemSettings(actor: ActorContext): void {
    if (isManagerRole(actor.role)) return;
    throw new ForbiddenException(
      "Настройки системы доступны только управляющему, директору и системному администратору.",
    );
  }

  /**
   * Client schema is business-critical configuration. Unlike operational
   * system settings, sources and required/custom client fields are changed
   * only by Director or the hidden system administrator.
   */
  assertCanManageClientConfiguration(actor: ActorContext): void {
    if (actor.role === "director" || actor.role === "system_admin") return;
    throw new ForbiddenException(
      "Настройка источников и полей клиентов доступна только директору.",
    );
  }

  assertCanArchiveClient(actor: ActorContext): void {
    if (actor.role === "director" || actor.role === "system_admin") return;
    throw new ForbiddenException(
      "Архивировать клиента может только директор.",
    );
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

  /**
   * ПОРАЗРЕЗНЫЕ финансы: ставка педагога за занятие, начисления и выплаты
   * конкретного педагога, отчёт «Статистика преподавателей».
   *
   * ✔ Решение владельца 16.07.2026: доступны Администратору и Управляющему —
   * «ставки педагога и иная подобная НЕ обще-суммарная фин. информация».
   * Раньше это приравнивалось к общешкольным финансам (только Директор), и
   * получалась нестыковка: Управляющий мог массово проставить «входит в оклад»
   * (assertManagerOnly), но не мог открыть отчёт, из которого это делается.
   *
   * Обще-суммарное (выручка, расходы, помесячные финансы, прогноз, аналитика)
   * остаётся у Директора — см. canReadSchoolFinance.
   */
  canReadTeacherRates(actor: ActorContext): boolean {
    return isManagerOrAdminRole(actor.role);
  }

  assertCanReadPayroll(actor: ActorContext): void {
    if (this.canReadTeacherRates(actor)) return;
    throw new ForbiddenException(
      "Недостаточно прав для зарплатного раздела.",
    );
  }

  assertCanReadFinance(actor: ActorContext, ownerUserId: string | null): void {
    // Staff finance: admin/manager/system_admin. Client sees only own rows.
    if (isManagerOrAdminRole(actor.role)) return;
    if (actor.role === "client" && ownerUserId === actor.userId) return;
    throw new NotFoundException("Платежи не найдены.");
  }
}
