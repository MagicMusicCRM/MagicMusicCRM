-- Intentionally irreversible: the owner rejected these UI fields. Historical
-- students.custom_data values were never deleted, so no customer data needs a
-- rollback. Reintroducing the fields requires an explicit product decision.
select 1;
