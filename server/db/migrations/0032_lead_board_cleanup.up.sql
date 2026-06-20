-- server/db/migrations/0032_lead_board_cleanup.up.sql
-- Spec C3 lead-board cleanup. IDEMPOTENT + GUARDED: every statement no-ops on an
-- empty DB (fresh Docker has zero lead_statuses/leads — all rows come from the prod
-- import). Keyed on status NAME, never on a hardcoded uuid. Safe to re-run.
--
-- Gated prod apply: the standard runner picks up 0032 automatically after deploy and
-- wraps it in one transaction. Because the legacy-column delete is 0-leads-guarded, it
-- is safe even if an operator earlier hand-cleaned some columns. If a legacy column is
-- unexpectedly non-empty in prod the migration leaves it (partial no-op); the operator
-- reassigns those leads manually, then re-runs (idempotent). If the «Новый» status was
-- imported under a different name, the NULL-remap no-ops (leaves NULLs) rather than
-- mis-assigning — adjust the single literal before applying.

-- (1) Migrate NULL-status leads ('Без статуса') -> the «Новый» status, but only if a
--     «Новый» status actually exists (import present). No-op on empty DB.
update app.leads l
set status_id = ns.id,
    updated_at = now()
from app.lead_statuses ns
where ns.name = 'Новый'
  and l.status_id is null
  and l.deleted_at is null;

-- (2) Mark terminal statuses. is_terminal := true for «Успешный» and «Отказ».
update app.lead_statuses
set is_terminal = true
where name in ('Успешный', 'Отказ')
  and is_terminal is distinct from true;

-- (2a) «Отказ» also requires a loss reason on transition.
update app.lead_statuses
set requires_reason = true
where name = 'Отказ'
  and requires_reason is distinct from true;

-- (2b) Recolor «Отказ» -> danger red (#E53935), only if not already that color.
update app.lead_statuses
set color = '#E53935'  -- danger swatch (matches the Flutter lead-board danger color)
where name = 'Отказ'
  and color is distinct from '#E53935';

-- (3) Remove the 3 empty legacy columns. HARD delete (no deleted_at on lead_statuses),
--     guarded so a status that still holds ANY lead is never deleted (FK is
--     'on delete set null' — deleting a non-empty status would silently orphan leads).
--     The guard counts ALL leads (including soft-deleted) on purpose: a soft-deleted
--     lead still FK-references the status, and 'on delete set null' would mutate it.
delete from app.lead_statuses ls
where ls.name in ('Контакт', 'Переговоры', 'Договор')
  and not exists (
    select 1 from app.leads l
    where l.status_id = ls.id  -- includes soft-deleted leads on purpose: never orphan
  );

-- (4) Dense renumber sort_order 0..N over the survivors, preserving the existing order
--     (sort_order, then name) so the board column order is stable. CTE keeps it
--     deterministic and idempotent (re-running yields the same 0..N).
with ordered as (
  select id,
    (row_number() over (order by sort_order asc, name asc, id asc) - 1) as new_order
  from app.lead_statuses
)
update app.lead_statuses ls
set sort_order = ordered.new_order
from ordered
where ordered.id = ls.id
  and ls.sort_order is distinct from ordered.new_order;
