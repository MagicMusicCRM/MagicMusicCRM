# ADR-001: Messenger Stability, Performance, and Type Safety

## Status
Accepted

## Context
The messenger exhibited "infinite loading" issues due to network hanging and race conditions during rapid chat switching. Additionally, database triggers were failing on PostgreSQL 17 due to strict type checking on custom `user_role` enums when compared to `text` values.

## Decisions

### 1. Race Condition Prevention (`LoadId`)
Implement a non-incremental, single-source-of-truth `_currentLoadId` in `MessengerScreen`. 
- **Mechanism**: Each `_loadMessages` call is assigned a unique `loadId`. Only results matching the latest `loadId` are committed to the UI state.
- **Benefit**: Prevents stale network responses from overwriting the UI state of a newly selected chat.

### 2. Network Resilience (Timeouts)
Add mandatory `.timeout()` decorators to all Supabase fetch operations.
- **Duration**: 10-15 seconds depending on complexity.
- **Mechanism**: Future-based timeout that resets loading indicators and notifies users of network failure instead of hanging indefinitely.

### 3. Database Type Safety (Enum Casting)
Abandon implicit casting in favor of explicit client-side filtering and server-side explicit casting.
- **Client**: Fetch `profiles` without role filters and filter in-memory (`.where((p) => p['role'].toString() == 'admin'`).
- **Server**: Redefine triggers (`handle_admin_response`, `handle_message_notification`) with explicit casts (`v_role::public.user_role`).
- **Rationale**: Avoids `operator is not unique` ambiguity while maintaining strict type integrity required by Postgres 17.

### 4. Component Loading Parallelization
Use `Future.wait` for all Chat List components (Direct, Group, Channels, Unread counts).
- **Result**: Drastic reduction in initial load time (from sequential blocks to a single parallel batch).

## Consequences
- **Positive**: Perfectly stable messenger state, faster cold starts, and reliable background notifications.
- **Negative**: Slightly higher client-side memory usage (negligible for current profile counts).
