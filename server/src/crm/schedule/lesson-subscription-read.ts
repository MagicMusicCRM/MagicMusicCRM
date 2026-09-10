import { DatabaseService } from '../../db/database.service';
import { LessonRow } from '../crm-mappers';
import { subscriptionLineageSql } from '../commerce/subscription-lineage';

/** Project current funding for editable plans without rewriting historical facts. */
export async function resolvePlannedSubscriptionReads<T extends LessonRow>(
  database: DatabaseService, rows: T[],
): Promise<T[]> {
  const eligible = (row: LessonRow) =>
    ['scheduled', 'settlement_pending'].includes(row.lifecycle_state ?? '') &&
    row.financial_decision_is_plan === true;
  const ids = new Set<string>();
  const collect = (value: unknown) => {
    if (typeof value === 'string') ids.add(value);
  };
  for (const row of rows.filter(eligible)) {
    collect(row.subscription_id);
    collect(row.financial_decision?.subscriptionId);
    for (const item of decisions(row.financial_decision?.clientDecisions)) collect(item.subscriptionId);
    for (const item of row.client_financial_baseline ?? []) {
      if (item._effectiveFact !== true) collect(item.subscriptionId);
    }
  }
  if (!ids.size) return rows;
  // IDs originate exclusively from the actor-scoped and finance-masked read.
  // Resolve the full batch in one query, including multi-step replacements.
  const result = await database.query<{ source_id: string; current_id: string }>(`
    select source.id as source_id, active.id as current_id
    from unnest($1::uuid[]) source(id)
    cross join lateral (
      select min(issued.id::text)::uuid as id from app.subscriptions issued
      where issued.id in (${subscriptionLineageSql('source.id', 'successors')})
        and issued.status = 'active'
      having count(*) = 1
    ) active
  `, [[...ids]]);
  const current = new Map(result.rows.map(row => [row.source_id, row.current_id]));
  const mapped = (id: unknown) => typeof id === 'string' ? current.get(id) ?? id : id;
  const funding = (item: Record<string, unknown>) => item.subscriptionId == null ? item :
    { ...item, subscriptionId: mapped(item.subscriptionId) };
  return rows.map(row => {
    if (!eligible(row)) return row;
    const decision = row.financial_decision;
    return { ...row,
      subscription_id: mapped(row.subscription_id) as string | null | undefined,
      financial_decision: decision == null ? decision : {
        ...funding(decision),
        ...(Array.isArray(decision.clientDecisions) ? {
          clientDecisions: decisions(decision.clientDecisions).map(funding),
        } : {}),
      },
      client_financial_baseline: row.client_financial_baseline?.map(item =>
        item._effectiveFact === true ? item : funding(item)),
    };
  });
}

function decisions(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? value.filter((item): item is Record<string, unknown> =>
    item !== null && typeof item === 'object' && !Array.isArray(item)) : [];
}
