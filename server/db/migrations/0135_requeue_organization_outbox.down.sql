-- Delivery replay is an operational state transition and cannot be undone
-- without falsifying a later publish result. Rolling back the schema is a no-op.
select 1;
