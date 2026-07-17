// server/src/crm/lead-student-link.ts
import { ConflictException } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";

/**
 * «Этот ученик и этот лид — один человек»: телефон совпал И имя, И фамилия.
 *
 * ⚠️ ЕДИНСТВЕННОЕ место, где это правило записано. Им пользуются двое:
 *   • доска лидов — прячет лид, у которого уже есть ученик (`hideConverted`);
 *   • импорт — проставляет `students.lead_id` (`link-students-to-leads.ts`).
 *
 * Разъедься они — и карточки снова начнут двоиться: импорт свяжет по одному
 * правилу, доска не спрячет по другому. Ровно этим прод и болен: `lead_id`
 * проставлен у 1 ученика из 1036, потому что связывать было некому.
 *
 * Правило нарочно строгое (телефон И имя И фамилия): на выгрузке оно даёт 987
 * из 996 (99%), а оставшиеся 16 неоднозначных лучше показать человеку, чем
 * угадать и склеить разных людей.
 *
 * Активность ученика сюда НЕ входит, и это осознанно: `lead_id` — факт о том,
 * кто это, а не о том, учится ли он сейчас. Кому нужна активность (доске —
 * нужна), тот добавляет `status = 'active'` у себя.
 *
 * Псевдонимы таблиц — из кода, не из запроса пользователя: в SQL они
 * подставляются как есть.
 */
export function leadStudentMatchSql(lead: string, profile: string): string {
  return `
    ${lead}.phone_normalized is not null
    and ${profile}.phone_normalized = ${lead}.phone_normalized
    and lower(btrim(coalesce(${profile}.first_name, ''))) = lower(btrim(coalesce(${lead}.first_name, '')))
    and lower(btrim(coalesce(${profile}.last_name, '')))  = lower(btrim(coalesce(${lead}.last_name, '')))
  `;
}

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
