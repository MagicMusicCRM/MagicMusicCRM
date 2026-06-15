drop index if exists app.duplicate_candidates_status_idx;
drop index if exists app.duplicate_candidates_active_identity_idx;
drop table if exists app.duplicate_candidates;

drop index if exists app.import_source_records_target_idx;
drop index if exists app.import_source_records_batch_source_external_idx;
drop table if exists app.import_source_records;

drop index if exists app.import_batches_source_started_idx;
drop table if exists app.import_batches;
