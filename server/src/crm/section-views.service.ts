// server/src/crm/section-views.service.ts
//
// Счётчики непросмотренного на вкладках CRM.
//
// ✔ Требование заказчика 17.07: «по приложению в зависимости от изменений в
// определённых папках или окнах должны приходить свои уведомления с счётчиком
// непрочитанных или непросмотренных изменений — всё это нужно корректно
// адаптировать под функционал и специфику приложения».
// ✔ Решение заказчика: хранить на СЕРВЕРЕ, чтобы счётчик пережил перезапуск и
// совпадал на телефоне и на компьютере.

import { BadRequestException, Injectable } from "@nestjs/common";
import { ActorContext, isManagerOrAdminRole } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";

/**
 * Разделы, у которых есть счётчик.
 *
 * ⚠️ Ключи обязаны совпадать с `sectionKey` во фронте
 * (lib/core/services/alert_policy.dart). Разъедутся — вкладка будет просить
 * счёт по разделу, которого сервер не знает, и бейдж молча замрёт.
 *
 * «Чата» здесь нет НАМЕРЕННО: у него непрочитанные считаются по-настоящему —
 * по факту прочтения каждого сообщения (`messenger.service.ts`), а не по
 * «когда я в последний раз заглядывал». Подменять точный счёт приблизительным
 * значило бы ухудшить работающее.
 *
 * «Обзора», «Пользователей» и «Отчётов» нет по другой причине: там нет
 * собственных объектов, которые «появляются». Обзор и отчёты — это витрины над
 * теми же данными, и счётчик на них дублировал бы соседние вкладки.
 */
export const SECTION_KEYS = ["clients", "tasks", "schedule", "finance"] as const;
export type SectionKey = (typeof SECTION_KEYS)[number];

export function isSectionKey(value: string): value is SectionKey {
  return (SECTION_KEYS as readonly string[]).includes(value);
}

interface CountRow {
  clients: string | number;
  tasks: string | number;
  schedule: string | number;
  finance: string | number;
}

@Injectable()
export class SectionViewsService {
  constructor(private readonly database: DatabaseService) {}

  /**
   * Сколько нового в каждом разделе с тех пор, как человек его открывал.
   *
   * Считаются НОВЫЕ записи, а не правки. «Непросмотренное изменение» для
   * человека — это «появилось то, чего я не видел»; правка существующего в
   * счётчик не просится, зато требует хранить, что именно поменялось, и по
   * каждому полю решать, достойно ли оно бейджа. Появление — однозначно.
   *
   * Отсчёт для нового пользователя — от его `created_at`, а не от начала
   * времён: иначе человек в первый же вход увидит «12 483» и перестанет
   * смотреть на цифру вообще.
   */
  async unseenCounts(actor: ActorContext): Promise<Record<SectionKey, number>> {
    // Разделы CRM — не для клиента и не для педагога: у них своих вкладок с
    // этими объектами нет.
    if (!isManagerOrAdminRole(actor.role)) {
      return { clients: 0, tasks: 0, schedule: 0, finance: 0 };
    }

    const result = await this.database.query<CountRow>(
      `
        with seen as (
          select
            -- Отметка раздела, иначе — момент появления самого пользователя.
            coalesce(
              (select v.last_seen_at from app.section_views v
                where v.user_id = $1 and v.section = 'clients'),
              u.created_at
            ) as clients_at,
            coalesce(
              (select v.last_seen_at from app.section_views v
                where v.user_id = $1 and v.section = 'tasks'),
              u.created_at
            ) as tasks_at,
            coalesce(
              (select v.last_seen_at from app.section_views v
                where v.user_id = $1 and v.section = 'schedule'),
              u.created_at
            ) as schedule_at,
            coalesce(
              (select v.last_seen_at from app.section_views v
                where v.user_id = $1 and v.section = 'finance'),
              u.created_at
            ) as finance_at
          from app.users u
          where u.id = $1
        )
        select
          (
            (select count(*) from app.leads l, seen
              where l.deleted_at is null and l.created_at > seen.clients_at)
            +
            (select count(*) from app.students s, seen
              where s.deleted_at is null and s.created_at > seen.clients_at)
          ) as clients,
          -- Задачи — ТОЛЬКО свои: чужая задача не требует от человека действия,
          -- а бейдж «сделай что-то» должен звать именно его. Иначе у школы с
          -- 12 483 задачами цифра станет фоном.
          (select count(*) from app.canonical_tasks t, seen
            where t.deleted_at is null
              and t.created_at > seen.tasks_at
              and exists (
                select 1 from app.shared_task_recipients recipient
                where recipient.task_id = t.id and recipient.user_id = $1
              )
          ) as tasks,
          (select count(*) from app.lessons les, seen
            where les.deleted_at is null and les.created_at > seen.schedule_at) as schedule,
          (
            (select count(*) from app.payments p, seen
              where p.deleted_at is null and p.created_at > seen.finance_at)
            +
            (select count(*) from app.expenses e, seen
              where e.deleted_at is null and e.created_at > seen.finance_at)
          ) as finance
        from seen
      `,
      [actor.userId],
    );

    const row = result.rows[0];
    if (!row) return { clients: 0, tasks: 0, schedule: 0, finance: 0 };
    return {
      clients: Number(row.clients ?? 0),
      tasks: Number(row.tasks ?? 0),
      schedule: Number(row.schedule ?? 0),
      finance: Number(row.finance ?? 0),
    };
  }

  /**
   * «Я посмотрел этот раздел». Сдвигает отметку на сейчас — счётчик обнуляется.
   *
   * `on conflict do update`, а не «удалить и вставить»: пользователь открывает
   * вкладки постоянно, и гонка двух вкладок не должна ронять запрос.
   */
  async markSeen(actor: ActorContext, section: string): Promise<{ section: string }> {
    if (!isSectionKey(section)) {
      throw new BadRequestException(`Неизвестный раздел: ${section}`);
    }
    await this.database.query(
      `
        insert into app.section_views (user_id, section, last_seen_at)
        values ($1, $2, now())
        on conflict (user_id, section) do update set last_seen_at = now()
      `,
      [actor.userId, section],
    );
    return { section };
  }
}
