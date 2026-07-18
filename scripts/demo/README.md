# Four-role demo reset and preflight (T9.2)

This directory contains the guarded data preparation for the four-role Android
demo. It is intentionally tied to the exact production identities and CRM
containers audited on 2026-07-18. It is not a general user-deletion utility.

## Safety model

- The default action is a read-only `Preflight`.
- The only reset target is `magic1@gmail.com`, user
  `18e4ca3f-f479-4ad8-875d-ed687b9fdcbc`.
- The exact user IDs, profile IDs, roles, personal administration chat and
  shared announcements chat are asserted before any mutation.
- Every apply creates a full `pg_dump | gzip` backup, checks that it is
  non-empty and prints its SHA-256 before opening the SQL transaction.
- Apply requires an action-specific confirmation phrase.
- Supporting teacher/staff/package records are created only by the separate
  `EnsureSupport` action plus the explicit `-CreateMissingSupport` switch.
- No SQL in this directory changes `app.users.role`.
- An unexpected owner, CRM link, shared chat, imported/merged entity or
  cross-student lesson dependency aborts the transaction.

The scripts never accept or persist account passwords, FCM tokens or database
credentials. SSH uses the existing deploy key and `docker exec` on the host.

## Commands

Run these from the repository root in PowerShell.

Read-only preflight (default):

```powershell
./scripts/demo/demo-reset.ps1
```

Show the missing-support plan without writing:

```powershell
./scripts/demo/demo-reset.ps1 -Action EnsureSupport
```

Create only missing support records. This is a production write and therefore
requires both explicit switches and automatically creates a verified backup:

```powershell
./scripts/demo/demo-reset.ps1 `
  -Action EnsureSupport `
  -Apply `
  -CreateMissingSupport `
  -Confirm "ENSURE DEMO SUPPORT magic1@gmail.com"
```

Preview the reset scope without writing:

```powershell
./scripts/demo/demo-reset.ps1 -Action Reset
```

Apply the reset after support preflight is green. A second verified backup is
created immediately before the reset transaction:

```powershell
./scripts/demo/demo-reset.ps1 `
  -Action Reset `
  -Apply `
  -Confirm "RESET DEMO magic1@gmail.com"
```

Local parser/contract check (no SSH and no database access):

```powershell
./scripts/demo/tests/demo-reset-contract.tests.ps1
```

## Exact support fixture

`EnsureSupport` preserves all four auth roles and creates only missing active
CRM support around the existing profiles:

- `magic2@gmail.com`: teacher, Piano, Sokol;
- `magic3@gmail.com`: admin staff, Sokol;
- `magic4@gmail.com`: manager staff, Sokol;
- an active subscription package only when the catalog has no active package:
  `Демо — Фортепиано, 8 часов`, 24,000, valid for 60 days.

The selected schedule resources are:

- Sokol: `62f5f8f6-5d03-4138-9189-15064c8f4a72`;
- Piano: `13dc04ee-9a88-4fab-87ba-24d4591439d0`;
- Piano room 7: `b97da1d3-cf10-4b5a-8f77-bd1c30edd5e1`.

## Reset effects

The reset discovers the current CRM graph from the exact magic1 user/profile,
so it works before the first demo and after a completed lead-to-student demo.
It removes:

- linked leads and students;
- their direct lessons, recurring series, homework, attendance, subscriptions,
  payments, account adjustments, tasks, comments and related CRM rows;
- magic1 notification history, while preserving notification devices;
- messages and staff inbox/work/read state in the exact private administration
  chat.

It preserves and post-checks:

- auth account, role and profile;
- legal consents and FCM device registrations;
- immutable audit events;
- the administration-chat container and all memberships;
- the shared announcements chat, messages and memberships;
- all other users and CRM entities.

Messages are hard-deleted only inside magic1's exact private administration
chat. A normal messenger soft-delete is unsuitable for reset because the
current client renders it as a visible `Сообщение удалено` bubble.

The next client message in the preserved administration chat is expected to
invoke `autoCreateLeadFromChat` and create exactly one fresh lead.

## Recovery

The apply output contains a line with the verified backup path and SHA-256.
Keep that output with the demo evidence. Restoring a full backup is destructive
and must be separately approved; do not paste a backup path into an unattended
automation.
