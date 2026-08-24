# Notification Delivery Depth Cut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal (original forecast):** Separate notification HTTP composition from the durable delivery runtime and reduce the forecast Sentrux depth from 13 to 12.

**Architecture:** A new `NotificationDeliveryModule` exclusively owns notification services, workers, policy, crypto, and providers. `NotificationsModule` becomes the API shell; Auth, CRM, and Platform import only the delivery module, while AppModule retains the API module and all routes.

**Tech Stack:** NestJS 11, TypeScript 5.8, Jest 30, RepoWise, Sentrux

**Spec:** `docs/superpowers/specs/2026-08-24-sentrux-depth-double-cut-design.md`

## Global Constraints

- Preserve notification routes, DTOs, audit behavior, realtime fanout, provider selection, retry limits, polling intervals, lifecycle hooks, and platform outbox publish ordering.
- Declare `NotificationsService` and `NotificationWorker` in exactly one Nest module.
- Do not change database schema, migrations, environment variables, API responses, or production state.
- The original graph forecast targeted root Sentrux `depth.raw <= 12`; the accepted observed outcome is documented below and supersedes that target as the active final gate.
- Run `repowise update --index-only` after the structural change.
- Keep each logical refactor in its own commit and do not include unrelated working-tree changes.

## Accepted implementation correction

- `NotificationsModule` must keep a direct `DatabaseModule` import. `JwtAuthGuard`
  uses optional database injection, and `NotificationDeliveryModule` does not
  export `DatabaseService`; removing the API-shell import would skip capability
  authorization on notification routes.
- The implemented backend/server graph reached depth 11 edges / 12 nodes. The
  repository-root Sentrux scan remains at `depth.raw=13` only because of the
  pre-existing Flutter integration-test chain beginning at
  `integration_test/app_launch_smoke_test.dart` and passing through
  `lib/main.dart` to `magic_api_error.dart`.
- Final acceptance is the verified server cut, `quality_signal >= 4975`, no new
  cycle, and passing architectural rules. Do not hide or exclude tests to change
  the metric, and do not add a Flutter cut without separate owner approval.

## File Structure

- `server/src/notifications/notification-delivery.module.ts`: sole provider owner for delivery services and workers.
- `server/src/notifications/notifications.module.ts`: HTTP controllers, guards, and the direct guard database dependency; re-exports delivery.
- `server/src/notifications/notification-module-boundary.spec.ts`: module ownership/import contract.
- `server/src/auth/auth.module.ts`: imports delivery services without notification controllers.
- `server/src/crm/crm.module.ts`: imports delivery services without notification controllers.
- `server/src/platform/platform.module.ts`: imports delivery services for outbox dispatch.
- `server/src/app.module.spec.ts`: production module compilation and singleton provider assertion.

---

### Task 1: Extract the delivery provider module

**Files:**
- Create: `server/src/notifications/notification-delivery.module.ts`
- Create: `server/src/notifications/notification-module-boundary.spec.ts`
- Modify: `server/src/notifications/notifications.module.ts`

**Interfaces:**
- Consumes: `AuditModule`, `DatabaseModule`, existing notification providers, policy, service, and worker.
- Produces: `NotificationDeliveryModule`, exporting `NotificationsService` and `NotificationWorker`.

- [ ] **Step 1: Write the failing module-boundary test**

```ts
import { MODULE_METADATA } from "@nestjs/common/constants";
import { DatabaseModule } from "../db/database.module";
import { NotificationDeliveryModule } from "./notification-delivery.module";
import { NotificationWorker } from "./notification-worker.service";
import { NotificationsController } from "./notifications.controller";
import { NotificationsModule } from "./notifications.module";
import { NotificationsService } from "./notifications.service";

function metadata<T>(key: string, target: object): T[] {
  return (Reflect.getMetadata(key, target) as T[] | undefined) ?? [];
}

describe("notification module boundary", () => {
  it("keeps delivery providers in one controller-free module", () => {
    expect(metadata(MODULE_METADATA.PROVIDERS, NotificationDeliveryModule)).toEqual(
      expect.arrayContaining([NotificationsService, NotificationWorker]),
    );
    expect(metadata(MODULE_METADATA.CONTROLLERS, NotificationDeliveryModule)).toEqual([]);
  });

  it("keeps HTTP controllers in the API module", () => {
    expect(metadata(MODULE_METADATA.IMPORTS, NotificationsModule)).toContain(
      NotificationDeliveryModule,
    );
    expect(metadata(MODULE_METADATA.IMPORTS, NotificationsModule)).toContain(
      DatabaseModule,
    );
    expect(metadata(MODULE_METADATA.CONTROLLERS, NotificationsModule)).toContain(
      NotificationsController,
    );
    expect(metadata(MODULE_METADATA.PROVIDERS, NotificationsModule)).not.toContain(
      NotificationsService,
    );
    expect(metadata(MODULE_METADATA.PROVIDERS, NotificationsModule)).not.toContain(
      NotificationWorker,
    );
  });
});
```

- [ ] **Step 2: Run the boundary test and verify the missing-module failure**

```powershell
Set-Location server
npm test -- --runTestsByPath src/notifications/notification-module-boundary.spec.ts
```

Expected: FAIL because `notification-delivery.module.ts` does not exist.

- [ ] **Step 3: Create the delivery module**

```ts
import { Module } from "@nestjs/common";
import { AuditModule } from "../audit/audit.module";
import { DatabaseModule } from "../db/database.module";
import { ResendEmailProvider, SmtpFallbackEmailProvider } from "./notification-email.provider";
import { FirebasePushProvider } from "./notification-push.provider";
import { NotificationTokenCrypto } from "./notification-token-crypto.service";
import { NotificationWorker } from "./notification-worker.service";
import { NotificationsPolicy } from "./notifications.policy";
import { NotificationsService } from "./notifications.service";

@Module({
  imports: [AuditModule, DatabaseModule],
  providers: [
    NotificationsService,
    NotificationsPolicy,
    NotificationWorker,
    NotificationTokenCrypto,
    FirebasePushProvider,
    ResendEmailProvider,
    SmtpFallbackEmailProvider,
  ],
  exports: [NotificationsService, NotificationWorker],
})
export class NotificationDeliveryModule {}
```

- [ ] **Step 4: Convert `NotificationsModule` to the API shell**

Keep `JwtModule.register({})`, both controllers, `JwtAuthGuard`, and
`RolesGuard`. Import and re-export `NotificationDeliveryModule`. Remove
delivery providers and the direct `AuditModule` import. Keep a direct
`DatabaseModule` import in this API shell because `JwtAuthGuard` optionally
injects `DatabaseService`; the delivery module does not export that service, so
removing this import would skip notification-route capability authorization:

```ts
@Module({
  imports: [NotificationDeliveryModule, DatabaseModule, JwtModule.register({})],
  controllers: [NotificationsController, AdminNotificationsController],
  providers: [JwtAuthGuard, RolesGuard],
  exports: [NotificationDeliveryModule],
})
export class NotificationsModule {}
```

- [ ] **Step 5: Run boundary and notification unit tests**

```powershell
Set-Location server
npm test -- --runTestsByPath src/notifications/notification-module-boundary.spec.ts src/notifications/notifications.service.spec.ts src/notifications/notification-worker.service.spec.ts src/notifications/notifications.policy.spec.ts
```

Expected: PASS.

- [ ] **Step 6: Run typecheck and Sentrux gate**

```powershell
Set-Location server
npm run typecheck
Set-Location ..
```

Then call Sentrux `rescan`, `health`, and `check_rules`. Expected: rules PASS,
no new cycle, and no quality regression. The original forecast allowed depth to
remain 13 until consumers stopped importing the API shell; the observed root
depth also remains 13 after Task 2 for the accepted Flutter test-chain reason
recorded above.

- [ ] **Step 7: Commit the provider ownership boundary**

```powershell
git add -- server/src/notifications/notification-delivery.module.ts server/src/notifications/notification-module-boundary.spec.ts server/src/notifications/notifications.module.ts
git commit -m "refactor(notifications): isolate delivery module"
```

---

### Task 2: Route backend consumers through the delivery boundary

**Files:**
- Modify: `server/src/notifications/notification-module-boundary.spec.ts`
- Modify: `server/src/auth/auth.module.ts`
- Modify: `server/src/crm/crm.module.ts`
- Modify: `server/src/platform/platform.module.ts`
- Modify: `server/src/app.module.spec.ts`

**Interfaces:**
- Consumes: `NotificationDeliveryModule` from Task 1.
- Produces: API-only `NotificationsModule` and delivery-only imports for Auth, CRM, and Platform.

- [ ] **Step 1: Extend the failing boundary contract for consumers**

Add imports for `AuthModule`, `CrmModule`, and `PlatformModule`, then add:

```ts
it.each([AuthModule, CrmModule, PlatformModule])(
  "%p imports delivery without mounting notification controllers",
  (consumer) => {
    const imports = metadata(MODULE_METADATA.IMPORTS, consumer);
    expect(imports).toContain(NotificationDeliveryModule);
    expect(imports).not.toContain(NotificationsModule);
  },
);
```

- [ ] **Step 2: Run the boundary test and verify the old imports fail**

```powershell
Set-Location server
npm test -- --runTestsByPath src/notifications/notification-module-boundary.spec.ts
```

Expected: FAIL because Auth, CRM, and Platform still import
`NotificationsModule`.

- [ ] **Step 3: Replace the three consumer imports**

In `auth.module.ts`, `crm.module.ts`, and `platform.module.ts`, replace:

```ts
import { NotificationsModule } from "../notifications/notifications.module";
```

with:

```ts
import { NotificationDeliveryModule } from "../notifications/notification-delivery.module";
```

Replace each `NotificationsModule` entry in `@Module({ imports: [...] })` with
`NotificationDeliveryModule`. Do not change `AppModule`.

- [ ] **Step 4: Assert the compiled graph exposes one delivery runtime**

In `app.module.spec.ts`, import `NotificationsService` and
`NotificationWorker`, then after compilation add:

```ts
expect(moduleRef.get(NotificationsService, { strict: false })).toBeDefined();
expect(moduleRef.get(NotificationWorker, { strict: false })).toBeDefined();
```

The test already closes `moduleRef`, exercising lifecycle cleanup.

- [ ] **Step 5: Run focused module and durable-delivery tests**

```powershell
Set-Location server
npm test -- --runTestsByPath src/notifications/notification-module-boundary.spec.ts src/app.module.spec.ts src/auth/auth.controller.spec.ts src/notifications/notifications.service.spec.ts src/notifications/notification-worker.service.spec.ts src/platform/platform-outbox.worker.spec.ts src/health/health.service.spec.ts
```

Expected: PASS with one compiled provider graph and unchanged outbox behavior.

- [ ] **Step 6: Run full backend verification**

```powershell
Set-Location server
npm run typecheck
npm test
npm run build
Set-Location ..
```

Expected: all backend suites PASS and Nest build succeeds.

- [ ] **Step 7: Run the final Sentrux gate**

Call Sentrux `rescan`, `health`, and `check_rules`. Acceptance:

```text
server depth = 11 edges / 12 nodes
root depth.raw = 13 (accepted pre-existing Flutter integration-test chain)
quality_signal >= 4975
acyclicity.raw = 1
rules pass = true
```

The original root `depth.raw <= 12` target was a pre-implementation forecast.
Do not hide or exclude the Flutter integration test to satisfy it, and do not
expand this backend task into an unapproved Flutter cut.

- [ ] **Step 8: Update RepoWise and inspect the live change**

```powershell
repowise update --index-only
```

Then call RepoWise `get_health` for the changed access-control and notification
files, plus `get_change_risk` for the implementation commit range. Verify
`index_behind=false` and no dependency cycle or breaking consumer.

- [ ] **Step 9: Commit the consumer routing cut**

```powershell
git add -- server/src/notifications/notification-module-boundary.spec.ts server/src/auth/auth.module.ts server/src/crm/crm.module.ts server/src/platform/platform.module.ts server/src/app.module.spec.ts
git commit -m "refactor(notifications): route consumers through delivery"
```
