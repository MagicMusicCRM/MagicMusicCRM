import { normalizePhoneRu, normalizedPhoneExpr } from "./phone.util";

export interface TextSearchSql {
  /** Predicate for the WHERE clause. */
  where: string;
  /** Relevance rank, lower is better. Feed it to ORDER BY. */
  rank: string;
}

/**
 * Free-text search over a person-like row (student or lead), shared so the two
 * call sites cannot drift apart.
 *
 * Three things the previous `concat_ws(... custom_data::text) like '%q%'`
 * expression got wrong:
 *
 *  - **Phone.** The haystack held the phone verbatim, so a number stored as
 *    `+79161234567` was unreachable by typing `8916…` or `916…` — the formats
 *    people actually type. We now also compare the canonical form.
 *  - **custom_data.** Casting the whole jsonb to text put KEYS and ids in the
 *    haystack: searching `level` matched every row that merely has that field,
 *    and a fragment of a uuid matched at random. We search the values only.
 *  - **Order.** Nothing ranked the hits, so "the five best matches" was five
 *    arbitrary ones.
 */
export function buildTextSearch(opts: {
  q: string;
  /** Searched as one string, so "Иванов Иван" matches across the columns. */
  columns: string[];
  /** Column holding a phone, compared in canonical form as well. */
  phoneColumn?: string;
  /** jsonb column whose VALUES join the haystack. */
  customDataColumn?: string;
  /** Name expression for the exact-match tier of the ranking. */
  exactColumn?: string;
  add: (value: unknown) => string;
}): TextSearchSql {
  const { q, columns, phoneColumn, customDataColumn, exactColumn, add } = opts;
  // Escape LIKE metacharacters: without this a query of "%" matches every row
  // and "_" matches any character, which reads as the search being broken.
  const likeParam = add(q.toLowerCase().replace(/[\\%_]/g, (m) => `\\${m}`));
  const haystack = `lower(concat_ws(' ', ${columns.join(", ")}))`;
  const contains = `${haystack} like '%' || ${likeParam}::text || '%'`;

  const disjuncts = [contains];

  if (phoneColumn) {
    // null unless the query really is a RU phone, which switches this off.
    const canonical = normalizePhoneRu(q).canonical;
    const phoneParam = add(canonical);
    disjuncts.push(
      `(${phoneParam}::text is not null and ${normalizedPhoneExpr(phoneColumn)} = ${phoneParam}::text)`,
    );
  }

  if (customDataColumn) {
    disjuncts.push(`
      exists (
        select 1
        from jsonb_each_text(${customDataColumn}) as cd(key, value)
        where lower(cd.value) like '%' || ${likeParam}::text || '%'
      )
    `);
  }

  const exact = exactColumn ?? columns[0];
  const rank = `
    case
      when lower(${exact}) = ${likeParam}::text then 0
      when ${haystack} like ${likeParam}::text || '%' then 1
      when ${haystack} like '% ' || ${likeParam}::text || '%' then 2
      else 3
    end
  `;

  return { where: `(${disjuncts.join(" or ")})`, rank };
}
