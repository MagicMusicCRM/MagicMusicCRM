// server/src/migration/link-students-to-leads.ts
//
// Проставляет `students.lead_id` — связь «этот ученик пришёл из этого лида».
//
// ЗАЧЕМ. Это то, из-за чего в приложении двоятся карточки. Карточка клиента
// умеет показывать человека целиком — и лидом, и учеником, с общей историей
// (`ClientMode`, `mergeByIdSorted`), — но только если связь проставлена. На
// проде она проставлена у **1 ученика из 1036**: связывать было некому, потому
// что API HolliHop связи не отдаёт, а руками 996 человек никто не сводил.
//
// ПРАВИЛО НЕ СВОЁ. Берётся `leadStudentMatchSql` — то же самое, которым доска
// лидов прячет сконвертированные (`hideConverted`). Заведи мы здесь второе
// правило «под импорт» — импорт связал бы одних, доска спрятала бы других, и
// карточки продолжили бы двоиться, только по-новому.
//
// ЧЕГО ОН НЕ ДЕЛАЕТ. Не угадывает. Если под ученика подходит больше одного лида
// (дубли лидов в HolliHop — 16 случаев из 996), он не берёт «первый попавшийся»,
// а печатает их списком: склеить двух разных людей хуже, чем оставить связь
// человеку.
//
// Usage — сухой прогон (по умолчанию; читает базу, не пишет):
//   MIGRATION_DATABASE_URL=... npm run hollihop:link-leads
// Usage — запись:
//   MIGRATION_DATABASE_URL=... LINK_LEADS_MODE=apply npm run hollihop:link-leads

import { Pool, PoolClient } from "pg";
import { leadStudentMatchSql } from "../crm/lead-student-link";

type LinkMode = "dry_run" | "apply";
/** Нужен только query — на этом же держится прогон на фейке в тестах. */
type QueryClient = Pick<PoolClient, "query">;

export interface AmbiguousStudent {
  studentId: string;
  name: string;
  phone: string | null;
  leadIds: string[];
}

export interface LinkRun {
  /** Учеников без связи на входе. */
  candidates: number;
  /** Под скольких подошёл ровно один лид. */
  unambiguous: number;
  /** Под скольких подошло несколько — связь не ставим. */
  ambiguous: number;
  /** Под скольких не подошёл ни один лид. */
  unmatched: number;
  /** Сколько связей реально записано (0 в сухом прогоне). */
  linked: number;
  ambiguousList: AmbiguousStudent[];
}

/**
 * Кандидаты: ученик без связи ↔ подходящие ему лиды.
 *
 * `lead_id is null` — не только оптимизация: у кого связь уже есть, тот её и
 * сохраняет. Перепроставлять чужую связь этот скрипт не вправе — ровно как
 * `attachStudentToLead`, который на такое отвечает конфликтом.
 */
const CANDIDATES_SQL = `
  select
    s.id as student_id,
    btrim(concat_ws(' ', p.last_name, p.first_name)) as name,
    p.phone_normalized as phone,
    array_agg(l.id::text order by l.created_at, l.id) as lead_ids
  from app.students s
  join app.profiles p
    on p.id = s.profile_id
   and p.deleted_at is null
  join app.leads l
    on l.deleted_at is null
   and (${leadStudentMatchSql("l", "p")})
  where s.deleted_at is null
    and s.lead_id is null
  group by s.id, p.last_name, p.first_name, p.phone_normalized
`;

/**
 * Сколько всего учеников ждут связи. Считается отдельно от кандидатов: без
 * этого «не нашлось ни одного лида» было бы неотличимо от «не искали», а
 * молчание об этом и есть то, из-за чего прошлый импорт считался успешным.
 */
const WAITING_SQL = `
  select count(*)::int as n
  from app.students
  where deleted_at is null
    and lead_id is null
`;

const LINK_SQL = `
  update app.students s
  set lead_id = $2::uuid, updated_at = now()
  where s.id = $1::uuid
    and s.deleted_at is null
    and s.lead_id is null
  returning s.id
`;

export async function runLink(options: {
  client: QueryClient;
  mode: LinkMode;
}): Promise<LinkRun> {
  const { client, mode } = options;

  const waiting = await client.query<{ n: number }>(WAITING_SQL);
  const rows = await client.query<{
    student_id: string;
    name: string;
    phone: string | null;
    lead_ids: string[];
  }>(CANDIDATES_SQL);

  const run: LinkRun = {
    candidates: waiting.rows[0]?.n ?? 0,
    unambiguous: 0,
    ambiguous: 0,
    unmatched: 0,
    linked: 0,
    ambiguousList: [],
  };

  for (const row of rows.rows) {
    if (row.lead_ids.length > 1) {
      run.ambiguous++;
      run.ambiguousList.push({
        studentId: row.student_id,
        name: row.name,
        phone: row.phone,
        leadIds: row.lead_ids,
      });
      continue;
    }
    run.unambiguous++;
    if (mode !== "apply") continue;
    const linked = await client.query<{ id: string }>(LINK_SQL, [
      row.student_id,
      row.lead_ids[0],
    ]);
    if (linked.rows[0]) run.linked++;
  }

  // Кто ждал связи, но ни одного лида под него не подошло.
  run.unmatched = run.candidates - rows.rows.length;
  return run;
}

/** Отчёт: без него «связали» — надежда, а не факт. */
export function formatLinkReport(run: LinkRun, mode: LinkMode): string {
  const lines = [
    `\nСвязь лид↔ученик — режим=${mode}`,
    `\nучеников без связи:     ${run.candidates}`,
    `  ровно один лид:       ${run.unambiguous}`,
    `  несколько лидов:      ${run.ambiguous} (связь не ставим — см. список)`,
    `  ни одного лида:       ${run.unmatched}`,
    `  записано связей:      ${run.linked}${
      mode === "apply" ? "" : " (сухой прогон — ничего не записано)"
    }`,
  ];
  if (run.ambiguousList.length > 0) {
    lines.push(
      `\n⚠️  ${run.ambiguousList.length} ученик(ов) подошли сразу к нескольким лидам — это дубли лидов в HolliHop.`,
      `    Склеить их наугад нельзя: выберите нужный лид руками в карточке.`,
    );
    for (const item of run.ambiguousList) {
      lines.push(`     ${item.name} (${item.phone ?? "без телефона"}) → ${item.leadIds.join(", ")}`);
    }
  }
  if (mode !== "apply") {
    lines.push("\nСухой прогон. Повторите с LINK_LEADS_MODE=apply, чтобы записать.");
  }
  return lines.join("\n");
}

async function main(): Promise<void> {
  const mode: LinkMode =
    process.env.LINK_LEADS_MODE?.trim().toLowerCase() === "apply" ? "apply" : "dry_run";
  const connectionString =
    process.env.MIGRATION_DATABASE_URL ?? process.env.DATABASE_URL;
  if (!connectionString) {
    throw new Error("MIGRATION_DATABASE_URL or DATABASE_URL is required.");
  }

  const pool = new Pool({ connectionString, max: 2, connectionTimeoutMillis: 10_000 });
  const client = await pool.connect();
  try {
    if (mode === "apply") await client.query("begin");
    const run = await runLink({ client, mode });
    if (mode === "apply") await client.query("commit");
    console.log(formatLinkReport(run, mode));
  } catch (error) {
    if (mode === "apply") await client.query("rollback");
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

if (require.main === module) {
  main().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  });
}
