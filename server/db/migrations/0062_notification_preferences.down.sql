-- server/db/migrations/0062_notification_preferences.down.sql
drop index if exists app.notification_preferences_event_idx;
drop table if exists app.notification_preferences;
