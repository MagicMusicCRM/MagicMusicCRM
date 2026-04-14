# ADR-002: Database Trigger Integrity & Notification Stability

## Status
Accepted

## Context
During the expansion of the Messenger notification system, two critical database-level errors occurred:
1. **Operator Ambiguity (42883)**: PostgreSQL 17 failed to implicitly compare the custom `user_role` enum with `text` values in trigger functions (`role = ANY($1::text[])`).
2. **Infinite Recursion (54001)**: A failed attempt to fix the ambiguity by creating a custom implicit cast (`CREATE CAST (text AS public.user_role) WITH FUNCTION ... AS IMPLICIT`) caused a stack overflow because the conversion function itself triggered a recursive lookup to the same cast.

## Decisions

### 1. Explicit Type Casting (`::text`)
Instead of relying on custom casts or redefining the schema, all trigger functions were refactored to use explicit casting to `text` for comparisons and array operations.
- **Example**: `role::text = ANY(target_roles::text[])`
- **Rationale**: This is the most portable and safest way to handle enums in Postgres without introducing hidden side-effects or recursion.

### 2. Execution Context (`SECURITY DEFINER`)
Specific background triggers (`on_message_notify`, `handle_message_notification`, `handle_admin_response`, `trigger_invoke_send_notification`) were updated to use `SECURITY DEFINER`.
- **Mechanism**: The function executes with the privileges of the user who created it (owner), bypassing potential RLS (Row Level Security) restrictions that might prevent background workers from reading `profiles` or `notifications`.
- **Constraint**: `SET search_path = public` was enforced to prevent search path hijacking (security best practice).

### 3. Notification Payloads
The `notifications` table structure was respected by ensuring that data inserted by triggers (like `target_roles`) is correctly cast into the receiver's column types at the source.

## Consequences
- **Positive**: Complete elimination of `PostgrestException` during message transmission. Consistent delivery of notifications even when RLS for the acting user is restrictive.
- **Negative**: Manual casting is required in any future triggers interacting with the `user_role` type, increasing code verbosity.
- **Mitigation**: Standardized casting patterns are documented in the technical guide.
