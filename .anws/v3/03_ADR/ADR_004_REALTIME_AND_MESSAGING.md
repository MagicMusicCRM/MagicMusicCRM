# ADR-004 - Realtime and Messaging

**Status**: Accepted
**Date**: 2026-06-10
**Influence scope**: SYS-MSG, SYS-API, SYS-APP, SYS-SEC

## Context

Supabase Realtime currently powers messenger updates and presence-like behavior. v3 needs backend-owned WebSocket authorization.

## Decision

Implement a NestJS WebSocket gateway under `/realtime`. Every connection validates session token. Every room join checks backend authorization. Messenger writes go through REST API; realtime publishes committed events after authorization and persistence.

## Consequences

- Client subscriptions must be rewritten.
- Room naming cannot leak private IDs beyond authorized users.
- Reconnect logic must re-authorize subscriptions.

## Verification

- Client A never receives client B events.
- Expired/revoked tokens close realtime connection.
- Reconnect restores only authorized rooms.
