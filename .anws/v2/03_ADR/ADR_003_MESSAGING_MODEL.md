# ADR-003 — Personal Administration Chat and Read-Only Announcements

**Status**: Accepted  
**Date**: 2026-05-30  
**Influence scope**: SYS-MSG, SYS-DATA, SYS-APP, SYS-NOTIFY

## Context

The user confirmed the desired model: every user gets a personal chat `Администрация`, and broadcasts are handled through a separate read-only `Объявления` channel. The existing message model overloads direct messages, null receivers, group chats and channels, which caused new users not to see the expected admin chat and creates unclear RLS.

## Decision

Implement two separate communication concepts:

- `Администрация`: private staff-user thread. A client sees exactly their own thread. Staff sees assigned/all permitted admin threads.
- `Объявления`: read-only announcement channel. Staff can publish; clients can read according to target/audience rules; clients cannot reply.

The UI can present both in the messenger, but database authorization must distinguish them.

## Options Considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| Personal admin thread + read-only announcements | Clear privacy, matches user confirmation, testable RLS | Requires schema/policy cleanup | Accepted |
| One shared global admin chat for all users | Simple UI | Leaks all clients to each other; wrong privacy model | Rejected |
| Continue null `receiver_id` broadcasts | Minimal code change | Ambiguous semantics; current bug source | Rejected |

## Consequences

- New user provisioning must ensure an admin thread exists after onboarding.
- `messages` INSERT/SELECT policies must validate thread membership or recipient authorization.
- Announcement posting is staff-only.
- Messenger UI hides send input for read-only announcements.

## Verification

- Client A cannot read Client B admin thread.
- New client sees `Администрация` after onboarding even with zero messages.
- Client cannot post into `Объявления`.
