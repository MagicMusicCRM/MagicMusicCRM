# Human-readable Audit Journal Design

**Status:** approved by the product owner on 2026-08-30

## Problem

The client card history and Analytics journal currently interpret the same immutable audit stream in two unrelated ways. The client card has a hand-written action allowlist and displays implementation details such as `Версия 11 → 12`; Analytics receives raw maps and falls back to labels such as `Действие`, `Изменение ученика`, and technical tags such as `auth.session_rotated`. Neither view consistently names the affected person or entity, shows the actual field changes, or separates expansion from navigation.

The product owner approved a global approach rather than a list of special cases: every business change must become a short human-readable card, with useful details on expansion and a link to the related entity where the current user's permissions and the existing navigation registry allow it.

## Product Behaviour

Every visible journal event has one consistent structure:

- a concrete Russian title, for example `Электронная почта изменена`, never the generic `Действие`;
- the affected entity type and display name, for example `Ученик · Мария Баранова`;
- the employee or system process that performed the action and the local date/time;
- a short summary when it adds information beyond the title;
- an expandable details area containing safe `Было → Стало` field changes and an optional business reason;
- a separate `Открыть …` action only when the entity has an id and the existing navigation/RBAC layer supports it.

The client card loads the newest 10 events and keeps the existing cursor-based `Показать ещё` flow. Analytics may continue loading at most 100 filtered events per request in this release. Expanding a card must not navigate, reload the entire page, or discard current filters.

Technical version counters, raw action keys, raw metadata, database ids, session rotation, token refresh, and authentication maintenance events are not rendered in the business UI. They remain unchanged in `app.audit_events` for diagnostics and security audit.

## Shared Backend Contract

Both endpoints return `AuditPresentationEvent` items:

```ts
interface AuditPresentationEvent {
  id: string;
  actionKey: string;
  title: string;
  summary: string | null;
  reason: string | null;
  actor: {
    id: string | null;
    name: string;
    role: string | null;
  };
  target: {
    type: string;
    id: string | null;
    label: string;
    displayName: string | null;
    routeType: string | null;
  };
  changes: Array<{
    key: string;
    label: string;
    before: string | null;
    after: string | null;
  }>;
  occurredAt: Date | string;
}
```

`actionKey` remains in the transport contract for diagnostics, filters, and forward compatibility, but Flutter never renders it as ordinary UI text. The shared `AuditPresentationService` receives a normalized database row plus an optional already-resolved target name. It owns action titles, entity labels, field labels, safe value formatting, reason selection, and generic fallbacks.

The generic fallback is data-driven:

1. Prefer a known action title when it exists.
2. Otherwise, when safe changes exist, build `<Поле> изменено` for one change or `<Сущность> изменена/изменён` for several changes.
3. Otherwise, derive a readable Russian verb from the action suffix (`created`, `updated`, `deleted`, `archived`, `restored`, `assigned`, `cancelled`, `completed`).
4. If the suffix is unknown, use `Изменение: <readable action words>`; never use only `Действие` or expose snake/camel case.

Known labels improve wording, but they are not an allowlist. Unknown business actions and fields still render through the generic path.

## Change Extraction and Safety

The presenter builds changes from, in priority order:

1. `metadata.changes` when it is a valid array of `{ key|field, before|oldValue, after|newValue }` objects;
2. the union of keys in `before_ref` and `after_ref`, retaining only values that differ;
3. safe primitive metadata fields only when they explicitly carry `before`/`after` semantics.

Only strings, numbers, booleans, nulls, dates, and short arrays of primitives may be formatted. Complex objects become a count/neutral summary or are omitted; raw JSON is never returned to Flutter. Empty values render as `Не указано`. Boolean and enum values use Russian labels where the registry knows them.

Keys containing password, token, secret, authorization, credential, otp, hash, session, refresh, cookie, or private key material are discarded case-insensitively. Redaction markers such as `[PRIVATE]`, `[PII]`, and `[REDACTED]` become absent values. The API no longer sends raw metadata to either journal consumer.

The client note `version` is deliberately ignored. A note change is described as `Общая заметка изменена`; its previous and new text are not exposed because internal notes can contain sensitive data. The audit fact itself remains append-only.

## Query and Target Resolution

`GET /crm/activity` keeps the existing CRM write permission check and filters. Its SQL selects `before_ref`, `after_ref`, `reason`, and `reason_text`, excludes technical authentication/session events from the business result, and resolves a target display name in the same query. Target resolution uses bounded SQL joins/`CASE`, not one query per event. A missing historical target produces a stable entity label with no display name and may still be shown.

`GET /crm/clients/:type/:id/operational-history` keeps its manager/admin scope check and lead↔student lineage. The fixed `HISTORY_ACTIONS` allowlist is replaced with a business-event predicate for lineage-related `crm.*` and `workflow.*` events while excluding auth/session maintenance. Synthetic lead status history rows are normalized through the same presenter. The current default/page limit of 10, maximum 100, ordering, cursor, and immutable sources remain unchanged.

No audit rows are deleted or rewritten. No production migration is required.

## Flutter Architecture

Flutter gets one typed model in `lib/core/models/audit_presentation_event.dart`. `MagicCrmService.listActivityLog` returns `List<AuditPresentationEvent>` directly; the `_legacyActivityLog` adapter is deleted. `ClientOperationalHistoryPage.items` uses the same type, so client history no longer owns a second event model.

One shared `AuditEventCard` in `lib/shared/widgets/audit_event_card.dart` renders both surfaces. It owns only presentation and local expanded state. Consumers provide an optional `onOpenTarget`; navigation remains in the client-card/Analytics feature layer through the existing `ContextTransitionRegistry` and `openEntityLink` helpers.

Collapsed cards show title, target, actor, and time. A chevron/row expands details. The open-target control is visually and semantically separate from expansion. Unknown target types are readable but not tappable.

## Compatibility and Removal

The endpoint shape changes atomically with the Flutter client in this repository. Old response aliases (`action`, `actorName`, `created_at`, `history_type`, raw `metadata`) are not kept in parallel. Existing API query filters remain compatible. Tests that asserted the legacy map are replaced with typed-contract tests.

The old backend `ACTION_LABELS`/`historySummary`/`historyReason` client-only translator, Flutter `_ActivityLogTile`, `_activityLabel` fallback, and `_OperationalHistoryRow` are removed after both consumers use the shared units. This prevents two presentation systems from drifting again.

## Verification

Backend unit tests cover known and unknown actions, generic fields, before/after extraction, empty values, sensitive key removal, redaction markers, note-version suppression, and safe fallback wording. Service tests cover SQL parameters, technical-event filtering, target data, client lineage, pagination, and identical DTO shape from both endpoints.

Flutter tests cover strict JSON parsing, the collapsed/expanded card, `Было → Стало`, absence of raw tags/version text, independent expand versus open actions, client first-10 pagination, Analytics filtering, and navigation availability. Focused tests run first under TDD, followed by backend typecheck/build, Flutter analyze, and the relevant regression suites. Production release and deployment remain a separate explicit owner command.
