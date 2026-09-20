-- Intentionally preserve appended catalog revisions referenced by plans/facts.
-- Roll back with a forward compatibility release, never by deleting history.
select 1;
