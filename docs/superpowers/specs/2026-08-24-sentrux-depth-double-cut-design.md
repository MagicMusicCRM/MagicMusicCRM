# Sentrux Depth Double Cut Design

**Date:** 2026-08-24  
**Status:** Owner approved  
**Scope:** Backend access-control and notification module boundaries

## Context

Sentrux reports `quality_signal=4975` with dependency depth as the primary
bottleneck (`depth.raw=13`). The longest production-source chain is:

```text
main
  -> AppModule
  -> AnalyticsModule
  -> CrmModule
  -> AccessControlModule
  -> PlatformModule
  -> NotificationsModule
  -> NotificationsController
  -> JwtAuthGuard
  -> CapabilityRequestAuthorizer
  -> EffectiveAccessEvaluator
  -> HardInvariantPolicy
  -> capability-registry
```

Removing any single outer module edge does not improve the metric: equally
long paths exist through `HealthModule`, `MessengerModule`, `ProfileModule`,
CRM controllers, and notification delivery internals. A virtual import-graph
simulation shows that both cuts below are required to reduce the maximum
source depth from 13 to 12.

RepoWise reports no governing ADR for these boundaries. Git archaeology shows
that the platform outbox and notification delivery path has recent correctness
fixes, so runtime ownership and worker singleton semantics must remain intact.

## Goals

1. Reduce Sentrux production-source dependency depth from 13 to 12.
2. Preserve all RBAC decisions, hard-deny precedence, API routes, notification
   delivery, timers, outbox retry behavior, audit behavior, and realtime fanout.
3. Make the notification API boundary independent from the durable delivery
   runtime used by Auth, CRM, and Platform.
4. Keep one authoritative definition of capability hard-deny rules.

## Non-goals

- No endpoint, DTO, database, migration, environment, or production change.
- No change to role packages, capability keys, rollout flags, or resource scope.
- No rewrite of `NotificationsService`, `NotificationWorker`, or platform outbox
  orchestration.
- No broad split of `CrmModule`, `CrmPolicy`, or `DashboardService` in this task.

## Cut 1: capability authorization policy

`capability-registry.ts` already owns capability definitions, key validation,
and override modes. It will also expose a pure hard-capability decision function
containing the existing teacher, configuration, admin-persona, and
director-only deny sets.

`EffectiveAccessEvaluator` will call that pure registry function directly. It
will no longer inject or import `HardInvariantPolicy`, making the evaluator a
stateless capability decision component.

`HardInvariantPolicy.capabilityDecision` remains as a compatibility method for
access mutation flows and delegates to the same registry function. Role
assignment, user deactivation, override mutation, emergency-surface, and
last-system-admin rules remain in `HardInvariantPolicy` unchanged.

All evaluator construction sites will use the dependency-free constructor.
Tests will continue to assert the full six-role matrix, hard-deny precedence,
override modes, resource scope, and fail-closed behavior.

```text
Before: EffectiveAccessEvaluator -> HardInvariantPolicy -> capability-registry
After:  EffectiveAccessEvaluator -----------------------> capability-registry
        HardInvariantPolicy ----------------------------> capability-registry
```

## Cut 2: notification API versus delivery runtime

A new `NotificationDeliveryModule` will own exactly one shared runtime graph:

- `NotificationsService` and `NotificationsPolicy`;
- `NotificationWorker`;
- token crypto, email providers, and push provider;
- `AuditModule` and `DatabaseModule` dependencies.

The existing `NotificationsModule` becomes the HTTP composition shell. It will
import and re-export `NotificationDeliveryModule`, register both notification
controllers, and provide only the authentication/role guards needed by those
controllers.

`AuthModule`, `CrmModule`, and `PlatformModule` will import
`NotificationDeliveryModule` directly. `AppModule` will continue importing
`NotificationsModule`, so all existing routes remain registered. Nest module
deduplication will preserve one delivery-module instance and therefore one set
of worker/reminder timers.

```text
AppModule -> NotificationsModule (controllers + guards)
                         |
                         v
             NotificationDeliveryModule (service + workers + providers)
                         ^
                         |
              Auth / CRM / Platform
```

## Failure handling and invariants

- Capability evaluation remains fail-closed for inactive actors, unknown keys,
  inactive definitions, registry drift, hard denies, and resource denial.
- Existing exception codes, decision sources, and reason strings do not change.
- Notification worker retry limits, polling intervals, lifecycle hooks, and
  delivery provider selection do not change.
- Platform outbox events are marked published only after their existing
  notification and realtime dispatch path succeeds.
- No second `NotificationsService` or `NotificationWorker` provider is declared
  outside `NotificationDeliveryModule`.

## Verification

After cut 1:

1. Run focused evaluator, authorizer, mutation, JWT guard, and registry tests.
2. Run backend typecheck.
3. Run Sentrux rescan, health, and architectural rules; no regression is allowed.

After cut 2:

1. Run notification service/worker, platform outbox, auth, health, and app-module
   composition tests.
2. Run the full backend test suite and build.
3. Run Sentrux rescan, health, and rules. Acceptance requires `depth.raw <= 12`,
   `quality_signal >= 4975`, no new cycle, and passing rules.
4. Run `repowise update --index-only`, then inspect changed-file health and
   change risk against the updated index.

## Expected graph result

The virtual source-graph result is depth 12. The expected next longest chain is:

```text
main -> AppModule -> AnalyticsModule -> CrmModule -> AuthModule
  -> AuthController -> AuthService -> NotificationsService
  -> NotificationWorker -> AuditService -> platform-integrity.util
  -> redact.util
```

This new chain is evidence for the next task only; it is not expanded in the
current double-cut scope.

## Rollback

Each cut is committed separately. If cut 1 fails RBAC parity, revert only the
access-control commit. If cut 2 creates duplicate workers, missing providers,
or outbox regressions, revert only the notification-boundary commit. Neither
rollback requires a database or production-data action.
