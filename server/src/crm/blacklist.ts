// server/src/crm/blacklist.ts
//
// Чёрный список клиента — настоящий бан.
//
// ✔ Решение владельца 17.07: «карточка помечается красным цветом
// предупреждения, и этот клиент не может писать далее в чатах школы и админам
// — по сути бан».
//
// Здесь один вопрос: **этому пользователю запрещено писать?** Он же задаётся
// из мессенджера, и ответ на него нельзя дублировать: копия разъедется, и
// забаненный будет молча писать в тот чат, про который забыли.

import { DatabaseService } from "../db/database.service";

/** Что показать забаненному вместо отправленного сообщения. */
export const BLACKLIST_MESSAGE =
  "Вы в чёрном списке школы. Отправка сообщений недоступна — обратитесь к администрации лично.";

/**
 * Забанен ли пользователь.
 *
 * Клиентский аккаунт цепляется к CRM-записи двумя способами, и оба здесь:
 *  - `profiles.user_id` — у ученика с профилем;
 *  - `user_crm_links` — ручная/телефонная привязка, в том числе **к лиду**.
 *
 * Проверяется любая половина карточки: клиент, забаненный лидом, но не
 * учеником, — забанен. Иначе бан обходился бы сменой половины.
 *
 * Сотрудников не банит: чёрный список — свойство клиента, а не роли. Педагог,
 * которого отметили в чёрном списке в своей карточке (`teachers.custom_data`),
 * — это другое понятие и другой процесс.
 */
export async function isUserBlacklisted(
  database: DatabaseService,
  userId: string,
): Promise<boolean> {
  const result = await database.query<{ blacklisted: boolean }>(
    `
      select exists (
        select 1
        from app.students s
        join app.profiles p on p.id = s.profile_id and p.deleted_at is null
        where p.user_id = $1 and s.deleted_at is null and s.blacklisted = true
        union all
        select 1
        from app.user_crm_links link
        join app.students s on s.id = link.entity_id and s.deleted_at is null
        where link.user_id = $1
          and link.entity_type = 'student'
          and link.deleted_at is null
          and s.blacklisted = true
        union all
        select 1
        from app.user_crm_links link
        join app.leads l on l.id = link.entity_id and l.deleted_at is null
        where link.user_id = $1
          and link.entity_type = 'lead'
          and link.deleted_at is null
          and l.blacklisted = true
      ) as blacklisted
    `,
    [userId],
  );
  return result.rows[0]?.blacklisted === true;
}
