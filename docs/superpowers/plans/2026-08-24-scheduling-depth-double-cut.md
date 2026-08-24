# Scheduling Depth Double Cut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce production dependency depth from 15 to at most 13 without changing scheduling, settlement, client-card, or navigation behavior.

**Architecture:** Break the backend chain by moving two settlement catalog types out of `CrmConfigurationService` into a dependency-free contract file. Break the Flutter chain by separating the lightweight routed client-card launcher from the heavy routed surfaces, then point list and board callers at the launcher-only file.

**Tech Stack:** NestJS 11, TypeScript 5.8, Flutter 3/Dart 3.11, Riverpod 3, RepoWise, Sentrux.

**Spec:** `docs/architecture/CURRENT-DECISIONS.md` and the owner-approved corrected double-cut analysis from 2026-08-24.

## Global Constraints

- Preserve the single Flutter/NestJS/PostgreSQL runtime and canonical routed client workspace.
- Do not change SQL, transactions, expected versions, idempotency, audit/outbox, frozen settlement plans, or append-only facts.
- Do not introduce a UI service locator, a second navigation path, or a second scheduling model.
- Run `repowise update --index-only` and a Sentrux scan after each structural task.
- Accept only a non-regressing quality signal and final maximum depth of 13 or less.

---

### Task 1: Extract settlement configuration type contracts

**Files:**
- Create: `server/src/crm/crm-configuration.contracts.ts`
- Modify: `server/src/crm/crm-configuration.service.ts`
- Modify: `server/src/crm/commerce/lesson-settlement.repository.ts`
- Test: `server/src/crm/crm-configuration.contracts.spec.ts`

**Interfaces:**
- Produces: `LessonSettlementTypeConfig` and `TeacherCompensationRuleConfig` as dependency-free exported interfaces.
- Preserves: type re-exports from `crm-configuration.service.ts` for source compatibility.

- [ ] Write an import-boundary test that expects both production files to reference `crm-configuration.contracts` and rejects a repository import from `crm-configuration.service`.
- [ ] Run the test and verify it fails because the contract file and imports do not exist yet.
- [ ] Add the two interfaces, type-only imports, and compatibility re-exports without changing runtime code.
- [ ] Run the boundary test, backend typecheck, and the CRM configuration and lesson-settlement integration tests.
- [ ] Update RepoWise, scan Sentrux, check rules, and commit the backend cut independently.

### Task 2: Split the routed client-card launcher from routed surfaces

**Files:**
- Create: `lib/features/crm/presentation/client_card/client_card_launcher.dart`
- Modify: `lib/features/crm/presentation/client_card/show_client_card.dart`
- Modify: launcher-only caller imports under admin, manager, messenger, and teacher presentation.
- Test: `test/features/navigation/client_card_launcher_boundary_test.dart`

**Interfaces:**
- Produces: unchanged `Future<bool?> showClientCard(BuildContext, {required String entityType, required String entityId, Map<String, dynamic>? seed, String? presentationLabel})`.
- Preserves: `show_client_card.dart` re-exports the launcher for compatibility while retaining `buildClientWorkspaceSurface`, `ClientCardRouteScreen`, and `ClientCardRouteSurface`.

- [ ] Write an import-boundary test that requires launcher-only callers to import `client_card_launcher.dart` and rejects their import of `show_client_card.dart`.
- [ ] Run the test and verify it fails because callers still import the heavy surface file.
- [ ] Move only the launcher function and label helper, retain a compatibility export, and update launcher-only imports.
- [ ] Run the boundary test, Flutter analysis, routed client workspace tests, production workspace mount test, and profile detail test.
- [ ] Update RepoWise, scan Sentrux, check rules, verify depth is at most 13, and commit the Flutter cut independently.
