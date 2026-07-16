// server/src/crm/lead-student-link.ts
import { ConflictException } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";

/**
 * Привязывает ученика к лиду.
 *
 * Общий для двух путей: автоподбор дублей (DuplicatesService) и ручное
 * «Прикрепить к ученику» из карточки лида (LeadsService). Условие
 * `lead_id is null or lead_id = $2` — не украшение: без него прикрепление
 * молча переписало бы чужую связь, и лид, к которому ученик относился раньше,
 * потерял бы его без следа. Поэтому «уже связан с другим» — это конфликт, а не
 * успешная перезапись.
 *
 * Повторная привязка к тому же лиду проходит без ошибки: операция
 * идемпотентна.
 */
export async function attachStudentToLead(
  database: DatabaseService,
  studentId: string,
  leadId: string,
): Promise<void> {
  const result = await database.query<{ id: string }>(
    `
      update app.students
      set lead_id = $2, updated_at = now()
      where id = $1
        and deleted_at is null
        and (lead_id is null or lead_id = $2)
      returning id
    `,
    [studentId, leadId],
  );
  if (!result.rows[0]) {
    throw new ConflictException("Ученик уже связан с другим лидом.");
  }
}
