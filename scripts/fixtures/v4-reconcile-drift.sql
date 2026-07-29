insert into v4_reconcile_target_facts (invariant_id, entity_id, fact)
select invariant_id, entity_id, fact
from v4_reconcile_source_facts
where invariant_id = 'finance.payment-facts'
  and entity_id = 'payment-1';
