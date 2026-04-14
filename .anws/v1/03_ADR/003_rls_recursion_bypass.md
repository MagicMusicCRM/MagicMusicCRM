# ADR-003: RLS Recursion Bypass via Security Definer

## Status
Accepted

## Context
Standard RLS (Row Level Security) policies on the `group_chat_members` and `group_chats` tables were causing `PostgrestException: infinite recursion detected` (Postgres error 42P17). This occurred because the policy logic (checking if the `auth.uid()` is a member of the group) triggered a secondary query to the same table, which in turn re-evaluated the policy, leading to an infinite loop.

## Decisions

### 1. Security Definer Helper Function
Implement a specialized PostgreSQL function `is_group_member_v2(chat_id, user_id)`:
- **Modifier**: `SECURITY DEFINER`. This allows the function to execute with the privileges of the owner (bypassing RLS for the internal query).
- **Search Path**: Explicitly set to `public` to prevent search path injection attacks.
- **ReturnType**: `boolean`.

### 2. Policy Refactoring
Update all recursive policies to delegate the membership check to the `is_group_member_v2` function.
- **Example**: `USING (is_group_member_v2(id, auth.uid()))` for `group_chats`.
- **Logic**: Since the function runs as `SECURITY DEFINER`, it can query `group_chat_members` without re-triggering the RLS check on that table for the internal query.

### 3. Service-Layer Stabilization
Update `SupaMessageService` to gracefully handle any remaining 42P17 or 500 errors by logging and returning empty lists instead of crashing the UI.

## Consequences

### Positive
- **Rock-Solid Stability**: Infinite recursion errors are eliminated.
- **Performance**: Internal queries bypassed by RLS are slightly faster.
- **Security**: The use of `SECURITY DEFINER` is strictly limited to an existence check (`EXISTS`) and forced to the `public` schema.

### Negative
- **Privilege Escalation Risk**: Requires careful auditing of the function logic to ensure it only returns a boolean and does not leak data.
- **Maintenance**: Changes to the membership logic now require updating the SQL function rather than just the policy string.
