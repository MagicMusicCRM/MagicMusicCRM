# Task 1 report — monthly teacher accrual XLSX

## Result

- `GET /crm/reports/teacher-stats/export` now returns an OOXML XLSX download named `teacher-stats.xlsx`, with columns from `Преподаватель` through `Начислено` only.
- The Flutter report downloads authenticated bytes, validates the XLSX ZIP signature, and saves/opens `teacher-stats-YYYY-MM-DD.xlsx` with every existing filter forwarded unchanged.
- The visible teacher report is accrual-only: no paid, payout, bonus, deduction, or period-balance text. The teacher-detail payroll section is no longer rendered. Rate controls retain the existing backend Director/system_admin enforcement and use the UI `canManageTeacherRates` policy.
- Historical payout storage, audit facts, and compatibility payout API routes remain unchanged.

## RED evidence

1. `server && npm test -- --runTestsByPath src/crm/payroll.service.spec.ts`
   - Failed as expected: XLSX contract required `PK`, while the CSV response began `o;`.
2. `flutter test test/features/manager/teacher_stats_controller_test.dart test/features/manager/teacher_stats_bulk_rate_test.dart`
   - Failed as expected: controller opened UTF-8 CSV bytes instead of `PK\x03\x04`, used `.csv`, and the loaded report displayed `выплачено 0 ₽`.

## GREEN verification

1. `server && npm test -- --runTestsByPath src/crm/payroll.service.spec.ts src/crm/payroll/payroll-service-boundary.spec.ts src/crm/payroll-postgres.integration.spec.ts src/analytics/report-export.service.spec.ts` — 4 suites, 39 tests passed.
2. `server && npm run typecheck` — passed.
3. `flutter test test/features/manager/teacher_stats_controller_test.dart test/features/manager/teacher_stats_bulk_rate_test.dart test/features/manager/teacher_stats_rate_dialogs_test.dart test/features/manager/teacher_stats_architecture_test.dart test/features/admin/presentation/widgets/teacher_detail_dialog_test.dart test/features/admin/teacher_detail_content_test.dart` — 28 tests passed.
4. `flutter analyze` for all touched Flutter production files — no issues.
5. `git diff --check` — clean.

## Changed files

- Backend: neutral `common` OOXML module/builder, teacher XLSX exporter, payroll facade/module/controller, payroll and analytics test imports.
- Flutter: binary export service/controller, `.xlsx` filename, accrual-only report view, capability naming, removed rendered teacher-detail payroll section.
- Documentation: current product rule and architecture decision for the accrual-only XLSX surface and compatibility gate.

## Concerns

- No production deployment was attempted. Payout endpoints and data are deliberately retained until the separate adoption/telemetry gate.
- RepoWise index refresh was run; it reported the linked-worktree seed source was behind and completed the local index update.
