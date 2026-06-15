# ADR-003 - Private File Storage

**Status**: Accepted
**Date**: 2026-06-10
**Influence scope**: SYS-FILES, SYS-API, SYS-MSG, SYS-OPS

## Context

Supabase Storage currently hosts avatars and chat attachments. v3 must keep files private without public bucket URLs.

## Decision

Store files on primary server NVMe outside web root for first production v3. File access goes through backend metadata, authorization and short-lived signed download tokens. File snapshots are encrypted and copied to external backup storage.

## Consequences

- One primary server requires strict backup discipline.
- File IDs replace absolute Supabase URLs in application data.
- Future migration to S3/MinIO remains possible because app sees only backend file API.

## Verification

- Upload validation tests.
- Foreign file access denied.
- Backup restore includes file content and metadata.
