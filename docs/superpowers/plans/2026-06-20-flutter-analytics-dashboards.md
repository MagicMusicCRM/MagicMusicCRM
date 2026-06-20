# Flutter — Management analytics dashboards (8 reports) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the 8 backend `/analytics` reports (funnel, branch comparison, loss reasons, debts, forecast, churn, chat SLA, weekly report) — now live on prod with real data — in the manager UI, reusing the existing `fl_chart` + KPI-card patterns.

**Architecture:** Add typed methods to `MagicCrmService` for the `/analytics/*` endpoints (manual `fromJson` mapping like the existing CRM methods), unit-tested by mocking the API client (mirroring `test/core/services/magic_crm_service_test.dart`). Then Riverpod `FutureProvider`s + a new **«Управление»** tab in the existing `ReportsWidget` that renders the reports with `fl_chart` (BarChart) + KPI cards (reusing `financial_dashboard_widget.dart` patterns). The service layer (Task 1) is fully testable; the widgets (Task 2) are verified on-device by the owner.

**Tech Stack:** Flutter, Riverpod 3.3.1, Dio, fl_chart 1.2.0. Tests: `flutter test`; lint: `flutter analyze`.

**Backend (live on prod):** `GET /analytics/{funnel,branches,loss-reasons,debts,forecast,churn-risk,chats/sla,weekly-report}` — all gated manager/admin, all return the shapes below.

## Global Constraints

- API client: `ref.watch(magicCrmServiceProvider)` → `_api.get<Map<String, dynamic>>(path, queryParameters: {...})` (Dio, bearer auth handled by the client). Non-null query params only (drop nulls), mirroring `listLeadBoard`.
- Backend response shapes (camelCase JSON from the server):
  - funnel: `{ from, to, stages: [{ statusId, name, sortOrder, leadsEntered, ratioToPrevStage }] }`
  - branches: `{ from, to, branches: [{ branchId, name, revenue, activeStudents, newLeads, completedLessons }] }`
  - loss-reasons: `{ from, to, reasons: [{ reasonId, name, kind, leads }], unspecifiedCount }`
  - debts: `{ buckets: [{ bucket, students, amount }], bucketStudentSum, distinctStudents, totalAmount }`
  - forecast: `{ next7, next14, next30 }`
  - churn-risk: `{ inactiveDays, students: [{ studentId, name, lastCompletedAt, daysSinceLast }], totalAtRisk }`
  - chats/sla: `{ from, to, inboundCount, respondedCount, responseRate, avgMinutes, medianMinutes, p90Minutes }`
  - weekly-report: `{ window:{from,to}, funnel, debts, forecast, churn:{inactiveDays,totalAtRisk}, branches, lossReasons, chatSla }`
- The service methods return plain `Map<String, dynamic>` / `List<Map<String,dynamic>>` with snake_case-or-camel keys consistent with the existing legacy transforms (use camelCase keys directly here — these are NEW methods, no legacy contract; keep numeric coercion `(v as num?)?.toDouble()` / `?.toInt()`).
- Date range: default last 90 days (`from = now-90d`, `to = now`) ISO; `branchId` optional.
- Widgets gate on role already (the manager/admin nav). Reuse `AppTheme`/`TelegramColors`, `fl_chart` `BarChart`, and the `financial_dashboard_widget.dart` card/legend pattern. Money formatted like the existing finance widgets.
- Run from repo root: `flutter analyze` (0 issues in touched files) + `flutter test` (green).

---

## File Structure

- **Modify** `lib/core/services/magic_crm_service.dart` — add the 8 `/analytics` methods.
- **Modify** `test/core/services/magic_crm_service_test.dart` — unit tests for the new methods.
- **Create** `lib/features/manager/presentation/providers/analytics_providers.dart` — Riverpod providers.
- **Create** `lib/features/manager/presentation/widgets/management_dashboard_widget.dart` — the «Управление» dashboard.
- **Modify** `lib/features/manager/presentation/widgets/reports_widget.dart` — add the «Управление» tab.

---

## Task 1: MagicCrmService `/analytics` methods + unit tests

**Files:**
- Modify: `lib/core/services/magic_crm_service.dart`, `test/core/services/magic_crm_service_test.dart`

**Interfaces (produces):** `getAnalyticsFunnel`, `getAnalyticsBranches`, `getAnalyticsLossReasons`, `getAnalyticsDebts`, `getAnalyticsForecast`, `getAnalyticsChurn`, `getAnalyticsChatSla`, `getAnalyticsWeeklyReport` on `MagicCrmService`.

- [ ] **Step 1: Read the existing test harness + a sample method**

Read `test/core/services/magic_crm_service_test.dart` (how it mocks the API client / Dio and asserts the GET path + result) and one existing method like `getManagerDashboard` / `listLeadBoard` in `magic_crm_service.dart` (the `_api.get` + query-param-building + mapping pattern). Match that style exactly.

- [ ] **Step 2: Write the failing tests**

Add to `magic_crm_service_test.dart` (mirror the existing mock style — the harness stubs the API client to return a canned `Map`; assert the requested path and the mapped output). Cover at least funnel, debts, branches, weeklyReport. Example shape (adapt to the real harness):

```dart
test('getAnalyticsFunnel requests /analytics/funnel and maps stages', () async {
  // arrange: stub api.get('/analytics/funnel', ...) -> { 'from':'..','to':'..','stages':[
  //   {'statusId':'s1','name':'Новый','sortOrder':0,'leadsEntered':100,'ratioToPrevStage':null} ] }
  final result = await service.getAnalyticsFunnel(from: '2026-01-01', to: '2026-04-01');
  expect(captured.path, '/analytics/funnel');
  expect((result['stages'] as List).first['name'], 'Новый');
  expect((result['stages'] as List).first['leadsEntered'], 100);
});

test('getAnalyticsDebts maps buckets + totals', () async {
  // stub -> { 'buckets':[{'bucket':'0-7','students':5,'amount':50000}], 'bucketStudentSum':5,'distinctStudents':5,'totalAmount':50000 }
  final r = await service.getAnalyticsDebts();
  expect(captured.path, '/analytics/debts');
  expect((r['buckets'] as List).first['bucket'], '0-7');
  expect(r['totalAmount'], 50000);
});
```

(Add similar minimal asserts for `getAnalyticsBranches` and `getAnalyticsWeeklyReport` — path + a key field.)

- [ ] **Step 3: Run to verify failure** — `flutter test test/core/services/magic_crm_service_test.dart` → FAIL (methods undefined).

- [ ] **Step 4: Implement the methods**

Add to `MagicCrmService` (mirror the existing `_api.get` + non-null query-param pattern). Build `queryParameters` dropping nulls. Return the parsed map/list. Example:

```dart
  Future<Map<String, dynamic>> getAnalyticsFunnel({String? from, String? to, String? branchId}) async {
    final q = <String, dynamic>{};
    if (from != null) q['from'] = from;
    if (to != null) q['to'] = to;
    if (branchId != null) q['branchId'] = branchId;
    final res = await _api.get<Map<String, dynamic>>('/analytics/funnel', queryParameters: q);
    return res;
  }

  Future<Map<String, dynamic>> getAnalyticsBranches({String? from, String? to}) async { /* GET /analytics/branches */ }
  Future<Map<String, dynamic>> getAnalyticsLossReasons({String? from, String? to, String? branchId}) async { /* /analytics/loss-reasons */ }
  Future<Map<String, dynamic>> getAnalyticsDebts({String? branchId}) async { /* /analytics/debts */ }
  Future<Map<String, dynamic>> getAnalyticsForecast({String? branchId}) async { /* /analytics/forecast */ }
  Future<Map<String, dynamic>> getAnalyticsChurn({int? inactiveDays, String? branchId}) async { /* /analytics/churn-risk */ }
  Future<Map<String, dynamic>> getAnalyticsChatSla({String? from, String? to}) async { /* /analytics/chats/sla */ }
  Future<Map<String, dynamic>> getAnalyticsWeeklyReport({String? branchId}) async { /* /analytics/weekly-report */ }
```

> If the existing methods wrap/transform responses (e.g. `_legacy*`), these NEW methods can return the raw `res` map directly (the widgets read camelCase keys). Keep them thin — the mapping lives in the widget. If the test harness's API-client mock returns the canned map, these pass-throughs are still worth a test (path + that the result is returned unchanged).

- [ ] **Step 5: Run tests + analyze** — `flutter test test/core/services/magic_crm_service_test.dart` → green; `flutter analyze lib/core/services/magic_crm_service.dart` → no new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/magic_crm_service.dart test/core/services/magic_crm_service_test.dart
git commit -m "feat(flutter): MagicCrmService methods for the 8 /analytics reports + tests"
```

---

## Task 2: «Управление» dashboard tab (providers + widgets)

**Files:**
- Create: `lib/features/manager/presentation/providers/analytics_providers.dart`, `lib/features/manager/presentation/widgets/management_dashboard_widget.dart`
- Modify: `lib/features/manager/presentation/widgets/reports_widget.dart`

**Interfaces:** consumes the Task-1 service methods.

- [ ] **Step 1: Providers**

`analytics_providers.dart` — `FutureProvider`s (mirror `leadBoardProvider`):
```dart
final analyticsFunnelProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) =>
  ref.watch(magicCrmServiceProvider).getAnalyticsFunnel());
final analyticsDebtsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) =>
  ref.watch(magicCrmServiceProvider).getAnalyticsDebts());
final analyticsBranchesProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) =>
  ref.watch(magicCrmServiceProvider).getAnalyticsBranches());
final analyticsForecastProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) =>
  ref.watch(magicCrmServiceProvider).getAnalyticsForecast());
final analyticsChurnProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) =>
  ref.watch(magicCrmServiceProvider).getAnalyticsChurn());
final analyticsChatSlaProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) =>
  ref.watch(magicCrmServiceProvider).getAnalyticsChatSla());
final analyticsLossReasonsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) =>
  ref.watch(magicCrmServiceProvider).getAnalyticsLossReasons());
```

- [ ] **Step 2: The dashboard widget**

`management_dashboard_widget.dart` — a `ConsumerWidget` scrollable column of `Card` sections (reuse `financial_dashboard_widget.dart`'s Card/legend/BarChart structure + `manager_overview_widget.dart`'s KPI-card structure):
1. **Воронка** — horizontal `BarChart` of `stages[].leadsEntered` (label = stage name; show `ratioToPrevStage`% under each). `analyticsFunnelProvider`.
2. **Долги по срокам** — `BarChart` of the 4 buckets (`students`/`amount`) + a KPI row (`distinctStudents` должников, `totalAmount` ₽). `analyticsDebtsProvider`.
3. **Прогноз выручки** — 3 KPI cards (7/14/30 дней) from `analyticsForecastProvider`.
4. **Сравнение филиалов** — a table/`BarChart` per branch (revenue / activeStudents / newLeads / completedLessons). `analyticsBranchesProvider`.
5. **Риск оттока** — KPI `totalAtRisk` + the first ~10 `students` (name + daysSinceLast). `analyticsChurnProvider`.
6. **SLA чатов** — KPI cards avg/median/p90 мин + response rate %. `analyticsChatSlaProvider`.
7. **Причины потерь** — list of `reasons` (name + leads) + `unspecifiedCount`. `analyticsLossReasonsProvider`.

Each section: `provider.when(loading: KanbanSkeleton-like/CircularProgressIndicator, error: a small retry, data: the chart/cards)`. Reuse `AppTheme.success/danger`, `_LegendItem`, money formatting from the finance widgets. Keep it one file, sections as private widgets.

- [ ] **Step 3: Wire into ReportsWidget**

In `reports_widget.dart`, change the `TabController` length to 4 and add a `Tab(text: 'Управление')` whose body is `const ManagementDashboardWidget()` (mirror how the existing 3 tabs are wired). Keep the existing 3 tabs unchanged.

- [ ] **Step 4: Analyze + test**

Run: `flutter analyze` (0 new issues in the touched files) and `flutter test` (the full suite stays green — the service tests pass; no widget test regressions). If a quick widget smoke test is feasible (pump `ManagementDashboardWidget` with an overridden provider returning canned data, expect a section title), add one; otherwise rely on analyze + on-device verification.

- [ ] **Step 5: Commit**

```bash
git add lib/features/manager/presentation/providers/analytics_providers.dart lib/features/manager/presentation/widgets/management_dashboard_widget.dart lib/features/manager/presentation/widgets/reports_widget.dart
git commit -m "feat(flutter): «Управление» dashboard tab — 7 analytics reports (funnel/debts/forecast/branches/churn/SLA/loss) (KVA-183)"
```

---

## Self-Review

- **Coverage:** all 8 `/analytics` endpoints have a service method (Task 1, tested); 7 surfaced as dashboard sections + the weekly report method available for a later "one-glance" screen.
- **Testability:** the service layer is unit-tested (mock API client); the widgets are analyzed + on-device verified (Flutter widget tests for charts are low-value, so on-device is the real gate — stated explicitly).
- **Reuse, not reinvent:** fl_chart BarChart + the `financial_dashboard_widget` Card/legend + `manager_overview_widget` KPI patterns; no new chart dependency.
- **No backend change:** the endpoints are live on prod; this is read-only consumption.

## Dependency note

This is the first Flutter sub-plan of the «Клиенты» program. Subsequent sub-plans: the «Клиенты» window (rename «Лиды»→«Клиенты» + badge from `GET /crm/leads/app-count`, the Лиды/Ученики segment, the per-branch Ученики board reading `branch_disciplines`), drag-to-convert (lead→student modal), and the unified client card showing the imported tasks/comments (`getLeadCard` already returns `tasks`/`comments` — verify the dialog renders them) + the «Семья» section. Date-range + branch filters on the dashboard can be added once the base sections are verified on-device.
