# Messenger v2 — Phase 2: Data Wipe — Runbook Plan

> This is a one-off DESTRUCTIVE operation on the live database (Selectel VPS,
> staging stack serving `api.phantom-net.ru`). It is NOT TDD code — it is a
> backup-first, dry-run-first runbook. Each destructive step is preceded by a
> read-only SELECT whose result the human approves before the matching DELETE runs.

**Goal:** Start the messenger from a clean slate — remove all chats/messages/
groups/attachments (keep the system "Объявления" channel) and remove synthetic
smoke/test accounts — without touching real users, leads, students, or the
magic1–4 test accounts.

**Where:** Postgres container `magicmusiccrm-v3-postgres-1`, db `magiccrm`, user
`magiccrm_owner`, schema `app`. SSH `magicdeploy@161.104.50.105` (key
`mmcrm_proxy_ed25519`); DB commands via `docker exec … psql` (needs the Bash tool
with `dangerouslyDisableSandbox: true`).

## Global Constraints

- **Backup before any DELETE.** `pg_dump … | gzip > /opt/magicmusiccrm/backups/magiccrm-pre-chat-wipe-<UTCstamp>.sql.gz`.
- **Keep** the system channel "Объявления" (`slug='announcements'`, `is_system=true`)
  and its `channel_permissions`. Re-run `ensureDefaultChannels` (idempotent) at the
  end to guarantee it survives.
- **Synthetic-account scope (exact):** `is_app_account = true AND deleted_at IS NULL
  AND (lower(email) LIKE '%@example.com' OR lower(email) LIKE 'realtime-smoke%')`.
  This matches the auto-signup smoke emails and the disposable `realtime-smoke-live@example.com`.
  It must NEVER match magic1–4 (they are `@gmail.com`) or any real user. The candidate
  list is shown and human-approved before deletion.
- Synthetic accounts are **soft-deleted** (`deleted_at = now()`, `is_app_account = false`),
  not hard-deleted — reversible, and they disappear from all queries (every read filters
  `deleted_at is null`). Hard delete is out of scope unless explicitly requested.
- Run the whole wipe in a single transaction; verify counts, then COMMIT.

---

## Step 0 — Backup

```bash
ssh … 'TS=$(date -u +%Y%m%dT%H%M%SZ); F=/opt/magicmusiccrm/backups/magiccrm-pre-chat-wipe-$TS.sql.gz; \
  docker exec magicmusiccrm-v3-postgres-1 pg_dump -U magiccrm_owner -d magiccrm --no-owner --clean --if-exists | gzip > "$F" && ls -la "$F"'
```
Record the backup path. Do not proceed until it exists and is non-trivial in size.

## Step 1 — Dry-run candidate counts (READ ONLY — approve before Step 2)

```sql
-- chat data volume
select 'chats' k, count(*) from app.chats where deleted_at is null
union all select 'messages', count(*) from app.messages where deleted_at is null
union all select 'chat_members', count(*) from app.chat_members
union all select 'channels (non-system)', count(*) from app.channels where coalesce(is_system,false)=false and deleted_at is null
union all select 'channel_posts', count(*) from app.channel_posts where deleted_at is null
union all select 'chat file_objects', count(*) from app.file_objects where owner_type='chat' and purpose in ('chat_attachment','chat_voice') and deleted_at is null;

-- accounts that WILL be soft-deleted (review every row; confirm none are real)
select id, email, role, full_name, created_at
from app.users
where is_app_account = true and deleted_at is null
  and (lower(email) like '%@example.com' or lower(email) like 'realtime-smoke%')
order by created_at;

-- safety assertion: magic1-4 and @gmail are NOT in the candidate set (must return 0)
select count(*) as must_be_zero
from app.users
where deleted_at is null
  and (lower(email) like '%@example.com' or lower(email) like 'realtime-smoke%')
  and (lower(email) like 'magic_%@gmail.com' or lower(email) like '%@gmail.com');
```
**Gate:** Human reviews the candidate-account list and the `must_be_zero = 0` assertion.
Only on explicit approval proceed to Step 2.

## Step 2 — Wipe (single transaction, verify, then COMMIT)

```sql
begin;

-- chat content (children first; chats.last_message_id has no FK)
delete from app.message_reactions;
delete from app.messages;
delete from app.chat_members;
delete from app.file_objects where owner_type = 'chat' and purpose in ('chat_attachment','chat_voice');
delete from app.chats;

-- channels: clean slate for announcements content; drop any non-system channels
delete from app.channel_posts;
delete from app.channel_permissions
  where channel_id in (select id from app.channels where coalesce(is_system,false) = false);
delete from app.channels where coalesce(is_system, false) = false;

-- synthetic smoke/test accounts → soft delete (reversible)
update app.users
set deleted_at = now(), is_app_account = false, updated_at = now()
where is_app_account = true and deleted_at is null
  and (lower(email) like '%@example.com' or lower(email) like 'realtime-smoke%');

-- verify before commit
select 'chats_left' k, count(*) from app.chats
union all select 'messages_left', count(*) from app.messages
union all select 'announcements_channel', count(*) from app.channels where slug='announcements' and deleted_at is null
union all select 'announcements_perms', count(*) from app.channel_permissions
  where channel_id in (select id from app.channels where slug='announcements')
union all select 'synthetic_active_left', count(*) from app.users
  where is_app_account=true and deleted_at is null
    and (lower(email) like '%@example.com' or lower(email) like 'realtime-smoke%');

-- EXPECTED: chats_left=0, messages_left=0, announcements_channel=1,
-- announcements_perms=5, synthetic_active_left=0.
commit;  -- (run as a separate confirmed statement after the human sees the verify rows)
```

If any verify row is unexpected → `rollback;` and investigate.

## Step 3 — Ensure default channel survives

After commit, run the idempotent guard (the API does this on boot; can also be invoked
by restarting the api container or via a one-off): confirm `app.channels` still has the
`announcements` channel with its 5 role permissions (from the verify query). If missing,
re-deploy/restart the api so `MessengerService.onModuleInit → ensureDefaultChannels` runs.

## Step 4 — Post-wipe sanity

- `curl -s https://api.phantom-net.ru/api/health` → ok.
- A `GET /messenger/channels` (any role) still returns "Объявления".
- Soft-deleted synthetic accounts can no longer log in (login filters `deleted_at is null`).

## Rollback

Restore the Step 0 backup if anything is wrong:
`gunzip -c <backup>.sql.gz | docker exec -i magicmusiccrm-v3-postgres-1 psql -U magiccrm_owner -d magiccrm`.

## Notes

- Timing: run this together with the Phase 3 messenger-v2 backend deploy (so users
  don't recreate old-style chats between the wipe and the new model). Until then it's
  safe to run independently — it only clears chat content.
- If you later want the synthetic accounts hard-deleted (rows gone), that's a separate
  confirmed step (cascades to `app.profiles`); soft-delete is the default here.
