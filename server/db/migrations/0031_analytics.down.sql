-- server/db/migrations/0031_analytics.down.sql
drop materialized view if exists app.mv_room_load;
drop materialized view if exists app.mv_teacher_performance;
drop materialized view if exists app.mv_finance_monthly;
drop table if exists app.analytics_refresh_runs;
