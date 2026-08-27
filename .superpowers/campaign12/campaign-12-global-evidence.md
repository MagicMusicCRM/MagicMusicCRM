# Campaign-12 global evidence

## Provenance and outcome

- Campaign baseline: `9cb1f506a5c5418650926fe53b81fe2667ba9bd7`.
- Reviewed code HEAD: `734a5f0f44b6bd9ec8861c05ec4e0c3959f697f1`.
- Final evidence commit: assigned by the commit containing this file; the exact
  post-commit SHA and RepoWise index equality are verified after commit because
  a commit cannot contain its own SHA.
- Accepted lanes: 12/12. Production RepoWise `god_class`: `23 -> 11`.
- Baseline weighted deficit: `61,154`; final 92-owner ledger deficit: `5,734`;
  recovered: `55,420` (`90.62%`).

## Lane and tier ledger

| Lane | Owner | Implementation commit |
|---|---|---|
| A | Messenger | `37e2ee728a658d13ea9ebe624d307468fb4b0883` |
| B | Payroll | `0e59445d03319772f9dcfd271c1ac23446b81620` |
| C | Subscription issue service | `43fc7c7072b400105f1372b3793a14571d104c74` |
| D | Profile | `e57ad45fad6212e206ac1aa48948e6777dd4c1ef` |
| E | Auth | `6a1c4dbd774fe9b0af0d0b77c7539f6c4f6aedc4` |
| F | Lesson transition | `bb88b9e96097c57c49cd07e20259ae120c0aa781` |
| G | Chat info | `d972e2b6840e0eec3d2d3d714d12db05cbac4a33` |
| H | Teacher statistics | `6910b207daf37499c9eada0d1c0b16661ebc8a6b` |
| I | Subscription issue UI | `f3282da96b2ff1a3acd653ff6ec84703d0002618` |
| J | Schedule plan | `cb36e126f4442ecdd6b22f1e344cf2de8b94ccd6` |
| K | Staff detail | `91348a626378eb2b58ec3f52bbc44a40a64c5a52` |
| L | Schedule reference | `bcc1cd0afeb8db29a3168347a0633e42cfffd138` |

Tier review commits are `2c08eab6cce223b7a5ca2dc56b1455cfbd098ef8`,
`37667c097e850092dbafaa0480c5e4b64e623025`,
`624f36c560ed7fb2de5f92612c3a9b2445339d68`, and
`5c30d9b9a11183ccc8a843f8c7f65b4657d6a373`. The literal Git range is the
authoritative complete correction/merge ledger.

## Global executable gates

- Backend: 251/251 suites and 1,723/1,723 tests passed in 138.908 s;
  `tsc --noEmit` and `nest build` passed. The production-server diff after
  that gate is empty; the corrective commit changes only two boundary specs,
  whose focused run is 12/12 PASS with a fresh typecheck PASS.
- Flutter: 1,214/1,214 tests passed with coverage in 4m08s; full `flutter
  analyze` returned zero issues in 17.1 s.
- Backend LCOV: 814,225 bytes, SHA-256
  `DA2F403822A590828258EC706BC1E63554DFF28E1C78666A823C18B83630525E`.
- Flutter LCOV: 442,301 bytes, SHA-256
  `D1D6B580D2CB5797A04099F1DFB0DD10B079A2013A965BD30E1E06C9FF32B355`.
- RepoWise ingested 829 files: 77.1% lines, 61.2% branches; test map 290
  tests, 618 files, 6,586 records. Both LCOV files are ignored.

## RepoWise production recount

The production filter includes `lib/*` and `server/src/*`, excludes test,
integration, coverage, generated/build/dist/docs/fixture/mock directories,
spec/test suffixes, generated Dart files, and `server/src/migration/*`.
It resolves 859 production files at the exact indexed code HEAD. The eleven
remaining owners are:

1. `lib/core/workspace/production_workspace_host.dart::_ProductionWorkspaceHostState`
2. `lib/features/admin/presentation/widgets/reference_catalog_lifecycle_dialog.dart::_ReferenceCatalogLifecycleDialogState`
3. `lib/features/crm/presentation/client_card/client_card.dart::_ClientCardState`
4. `lib/features/crm/presentation/client_card/preferred_schedule_editor.dart::_PreferredScheduleEditorState`
5. `lib/features/manager/presentation/tasks/shared_task_editor.dart::_SharedTaskEditorState`
6. `lib/features/manager/presentation/widgets/finance_widget.dart::_FinanceWidgetState`
7. `lib/features/manager/presentation/widgets/student_funnel_editor.dart::_StudentFunnelEditorState`
8. `lib/features/manager/presentation/widgets/students_board_widget.dart::_StudentsBoardWidgetState`
9. `server/src/crm/finance.service.ts::FinanceService`
10. `server/src/crm/schedule/lesson-command.service.ts::LessonCommandService`
11. `server/src/crm/student-funnel.service.ts::StudentFunnelService`

The expected/actual delta is empty. No changed production file has a
`brain_method`; all 80 added production owners have health `>=7.0`, max CCN
`<=10`, and no god/brain finding.

## Owner health ledger

Weighted deficit is `round(max(0, 8.0 - health) * NLOC)`. `original` denotes
the twelve compatibility/source paths; `new` denotes every added production
owner in the campaign range.

| Owner | Kind | Health | NLOC | CCN | Line cov. | Branch cov. | Deficit |
|---|---|---:|---:|---:|---:|---:|---:|
| `lib/core/models/subscription_purchase.dart` | new | 9.36 | 169 | 5 | 92.86 | — | 0 |
| `lib/core/widgets/telegram/chat_info_add_members_dialog.dart` | new | 9.27 | 226 | 5 | 90.57 | — | 0 |
| `lib/core/widgets/telegram/chat_info_controller.dart` | new | 8.85 | 287 | 9 | 70.12 | — | 0 |
| `lib/core/widgets/telegram/chat_info_dialog.dart` | original | 2.94 | 271 | 8 | 39.46 | — | 1371 |
| `lib/core/widgets/telegram/chat_info_member_dialogs.dart` | new | 8.45 | 145 | 4 | 96.49 | — | 0 |
| `lib/core/widgets/telegram/chat_info_models.dart` | new | 9.65 | 231 | 5 | 91.18 | — | 0 |
| `lib/core/widgets/telegram/chat_info_tabs.dart` | new | 7.61 | 381 | 5 | 56.41 | — | 149 |
| `lib/core/widgets/telegram/chat_info_view.dart` | new | 9.21 | 453 | 8 | 93.49 | — | 0 |
| `lib/core/widgets/telegram/chat_info_view_components.dart` | new | 10.00 | 67 | 4 | 100.00 | — | 0 |
| `lib/features/admin/presentation/widgets/schedule_reference_cards.dart` | new | 7.47 | 325 | 10 | 83.45 | — | 172 |
| `lib/features/admin/presentation/widgets/schedule_reference_controller.dart` | new | 7.95 | 308 | 7 | 91.53 | — | 15 |
| `lib/features/admin/presentation/widgets/schedule_reference_dialogs.dart` | new | 8.13 | 126 | 8 | 62.07 | — | 0 |
| `lib/features/admin/presentation/widgets/schedule_reference_draft_operations.dart` | new | 8.35 | 154 | 5 | 67.57 | — | 0 |
| `lib/features/admin/presentation/widgets/schedule_reference_models.dart` | new | 9.00 | 168 | 8 | 91.30 | — | 0 |
| `lib/features/admin/presentation/widgets/schedule_reference_settings.dart` | original | 5.07 | 57 | 3 | 73.08 | — | 167 |
| `lib/features/admin/presentation/widgets/schedule_reference_view.dart` | new | 9.09 | 196 | 4 | 93.55 | — | 0 |
| `lib/features/admin/presentation/widgets/staff_detail_access_flow.dart` | new | 8.07 | 61 | 5 | 51.85 | — | 0 |
| `lib/features/admin/presentation/widgets/staff_detail_content.dart` | new | 9.36 | 470 | 9 | 92.74 | — | 0 |
| `lib/features/admin/presentation/widgets/staff_detail_controller.dart` | new | 9.02 | 176 | 6 | 82.98 | — | 0 |
| `lib/features/admin/presentation/widgets/staff_detail_dialog.dart` | original | 4.83 | 139 | 8 | 67.11 | — | 441 |
| `lib/features/admin/presentation/widgets/staff_detail_model.dart` | new | 9.18 | 143 | 8 | 88.24 | — | 0 |
| `lib/features/crm/presentation/client_card/subscription_issue_adjustment_sections.dart` | new | 9.23 | 253 | 5 | 98.92 | — | 0 |
| `lib/features/crm/presentation/client_card/subscription_issue_components.dart` | new | 9.06 | 417 | 7 | 92.81 | — | 0 |
| `lib/features/crm/presentation/client_card/subscription_issue_controller.dart` | new | 9.24 | 247 | 7 | 92.20 | — | 0 |
| `lib/features/crm/presentation/client_card/subscription_issue_form_feedback.dart` | new | 9.28 | 92 | 7 | 100.00 | — | 0 |
| `lib/features/crm/presentation/client_card/subscription_issue_form_sections.dart` | new | 9.65 | 63 | 1 | 100.00 | — | 0 |
| `lib/features/crm/presentation/client_card/subscription_issue_models.dart` | new | 9.46 | 130 | 4 | 95.35 | — | 0 |
| `lib/features/crm/presentation/client_card/subscription_issue_payment_section.dart` | new | 8.97 | 111 | 3 | 92.31 | — | 0 |
| `lib/features/crm/presentation/client_card/subscription_issue_pricing.dart` | new | 8.20 | 199 | 10 | 100.00 | — | 0 |
| `lib/features/crm/presentation/client_card/subscription_issue_sheet.dart` | original | 4.48 | 165 | 7 | 94.29 | — | 581 |
| `lib/features/manager/presentation/widgets/teacher_stats_components.dart` | new | 8.27 | 289 | 7 | 69.85 | — | 0 |
| `lib/features/manager/presentation/widgets/teacher_stats_controller.dart` | new | 8.70 | 325 | 10 | 87.08 | — | 0 |
| `lib/features/manager/presentation/widgets/teacher_stats_models.dart` | new | 8.32 | 139 | 7 | 66.67 | — | 0 |
| `lib/features/manager/presentation/widgets/teacher_stats_rate_dialogs.dart` | new | 9.64 | 157 | 3 | 94.74 | — | 0 |
| `lib/features/manager/presentation/widgets/teacher_stats_view.dart` | new | 7.05 | 390 | 8 | 64.32 | — | 371 |
| `lib/features/manager/presentation/widgets/teacher_stats_widget.dart` | original | 5.33 | 62 | 3 | 79.41 | — | 166 |
| `server/src/auth/auth-account.service.ts` | new | 8.45 | 147 | 6 | 88.68 | 59.18 | 0 |
| `server/src/auth/auth-email-challenge.service.ts` | new | 9.03 | 106 | 5 | 91.89 | 61.90 | 0 |
| `server/src/auth/auth-login.service.ts` | new | 9.24 | 169 | 4 | 98.48 | 68.09 | 0 |
| `server/src/auth/auth-normalization.ts` | new | 9.83 | 26 | 4 | 95.65 | 80.00 | 0 |
| `server/src/auth/auth-password-recovery.service.ts` | new | 9.57 | 132 | 3 | 98.11 | 56.76 | 0 |
| `server/src/auth/auth-rate-limit.service.ts` | new | 9.04 | 137 | 2 | 97.37 | 56.76 | 0 |
| `server/src/auth/auth-registration.service.ts` | new | 9.17 | 114 | 5 | 97.37 | 58.97 | 0 |
| `server/src/auth/auth-verification.service.ts` | new | 8.85 | 186 | 4 | 98.21 | 63.41 | 0 |
| `server/src/auth/auth.service.ts` | original | 5.44 | 88 | 1 | 97.14 | 48.28 | 225 |
| `server/src/auth/auth.types.ts` | new | 8.00 | 29 | 1 | 0.00 | — | 0 |
| `server/src/crm/commerce/subscription-commercial-terms.service.ts` | new | 8.16 | 355 | 7 | 86.60 | 70.19 | 0 |
| `server/src/crm/commerce/subscription-grant-command.service.ts` | new | 8.44 | 182 | 5 | 91.53 | 57.45 | 0 |
| `server/src/crm/commerce/subscription-issue-result.service.ts` | new | 9.14 | 66 | 3 | 91.67 | 48.48 | 0 |
| `server/src/crm/commerce/subscription-issue.contracts.ts` | new | 8.00 | 53 | 1 | 0.00 | — | 0 |
| `server/src/crm/commerce/subscription-issue.service.ts` | original | 5.97 | 43 | 1 | 95.45 | 48.28 | 87 |
| `server/src/crm/commerce/subscription-purchase-command.service.ts` | new | 7.62 | 250 | 5 | 95.38 | 58.33 | 95 |
| `server/src/crm/commerce/subscription-purchase-preview.service.ts` | new | 7.68 | 196 | 6 | 92.86 | 65.52 | 63 |
| `server/src/crm/crm-analytics-support.module.ts` | new | 9.71 | 10 | 1 | 92.86 | 36.36 | 0 |
| `server/src/crm/payroll.service.ts` | original | 6.20 | 115 | 1 | 96.67 | 48.28 | 207 |
| `server/src/crm/payroll/payroll-accrual-calculator.ts` | new | 9.27 | 113 | 6 | 96.83 | 73.17 | 0 |
| `server/src/crm/payroll/payroll-read.repository.ts` | new | 9.20 | 243 | 3 | 97.56 | 64.41 | 0 |
| `server/src/crm/payroll/payroll.types.ts` | new | 9.85 | 90 | 1 | 100.00 | — | 0 |
| `server/src/crm/payroll/teacher-payroll-command.service.ts` | new | 7.22 | 449 | 6 | 85.56 | 53.73 | 350 |
| `server/src/crm/payroll/teacher-payroll-query.service.ts` | new | 9.08 | 87 | 4 | 94.55 | 60.47 | 0 |
| `server/src/crm/payroll/teacher-stats-csv.service.ts` | new | 9.36 | 112 | 3 | 96.43 | 54.05 | 0 |
| `server/src/crm/payroll/teacher-stats-report.service.ts` | new | 9.00 | 364 | 4 | 97.39 | 70.79 | 0 |
| `server/src/crm/schedule/lesson-bulk-transition.service.ts` | new | 8.20 | 210 | 7 | 90.67 | 53.06 | 0 |
| `server/src/crm/schedule/lesson-command-metadata.ts` | new | 8.00 | 4 | 1 | 0.00 | — | 0 |
| `server/src/crm/schedule/lesson-draft.contracts.ts` | new | 7.65 | 65 | 1 | 0.00 | — | 23 |
| `server/src/crm/schedule/lesson-transition-command.service.ts` | new | 8.04 | 162 | 8 | 95.35 | 67.35 | 0 |
| `server/src/crm/schedule/lesson-transition-commit.service.ts` | new | 8.47 | 330 | 8 | 96.05 | 77.63 | 0 |
| `server/src/crm/schedule/lesson-transition-financial.service.ts` | new | 9.07 | 159 | 4 | 93.02 | 62.50 | 0 |
| `server/src/crm/schedule/lesson-transition-preparation.service.ts` | new | 7.51 | 462 | 8 | 86.62 | 64.95 | 226 |
| `server/src/crm/schedule/lesson-transition-preview.service.ts` | new | 9.18 | 80 | 3 | 97.06 | 54.55 | 0 |
| `server/src/crm/schedule/lesson-transition.rules.ts` | new | 7.20 | 256 | 9 | 91.00 | 87.01 | 205 |
| `server/src/crm/schedule/lesson-transition.service.ts` | original | 6.50 | 86 | 1 | 96.30 | 48.28 | 129 |
| `server/src/crm/schedule/lesson-transition.types.ts` | new | 9.85 | 196 | 1 | 100.00 | — | 0 |
| `server/src/crm/schedule/schedule-plan-constraint-preview.service.ts` | new | 8.98 | 170 | 2 | 98.18 | 51.61 | 0 |
| `server/src/crm/schedule/schedule-plan-definition.service.ts` | new | 7.79 | 500 | 8 | 84.81 | 70.19 | 105 |
| `server/src/crm/schedule/schedule-plan-end.service.ts` | new | 7.38 | 324 | 6 | 92.77 | 58.82 | 201 |
| `server/src/crm/schedule/schedule-plan-mutation.service.ts` | new | 8.13 | 375 | 4 | 96.91 | 59.57 | 0 |
| `server/src/crm/schedule/schedule-plan-overlap-analyzer.ts` | new | 9.06 | 141 | 4 | 92.86 | 60.00 | 0 |
| `server/src/crm/schedule/schedule-plan-query.service.ts` | new | 8.33 | 176 | 9 | 95.74 | 74.29 | 0 |
| `server/src/crm/schedule/schedule-plan.service.ts` | original | 5.41 | 74 | 1 | 96.55 | 48.28 | 192 |
| `server/src/messenger/messenger-chat-access.service.ts` | new | 9.79 | 15 | 2 | 94.74 | 51.61 | 0 |
| `server/src/messenger/messenger-chat-command.service.ts` | new | 8.92 | 365 | 8 | 89.31 | 62.35 | 0 |
| `server/src/messenger/messenger-chat-query.service.ts` | new | 9.26 | 429 | 7 | 93.98 | 76.19 | 0 |
| `server/src/messenger/messenger-message-delivery.service.ts` | new | 8.78 | 300 | 8 | 92.00 | 77.88 | 0 |
| `server/src/messenger/messenger-system-chat.service.ts` | new | 9.70 | 46 | 2 | 96.30 | 51.61 | 0 |
| `server/src/messenger/messenger.constants.ts` | new | 10.00 | 1 | 1 | 100.00 | — | 0 |
| `server/src/messenger/messenger.service.ts` | original | 6.69 | 63 | 1 | 97.14 | 48.28 | 83 |
| `server/src/profile/my-profile.service.ts` | new | 8.48 | 155 | 10 | 96.30 | 73.02 | 0 |
| `server/src/profile/profile-directory.service.ts` | new | 9.63 | 356 | 2 | 94.59 | 62.79 | 0 |
| `server/src/profile/profile-notes.service.ts` | new | 9.44 | 94 | 3 | 94.87 | 54.29 | 0 |
| `server/src/profile/profile-record.repository.ts` | new | 7.66 | 195 | 2 | 65.22 | 45.45 | 66 |
| `server/src/profile/profile.service.ts` | original | 6.78 | 36 | 1 | 96.15 | 48.28 | 44 |

## RepoWise risk and missing-test ruling

- Full-range change risk: percentile 100.0, priority `high`, classification
  `Elevated`, score 10.0, probability 0.9951. Shape: 18,020 additions,
  12,981 deletions, 106 production files, 14 directories, entropy 6.0811.
- PR blast radius: overall 6.11; 199 changed paths, 106 production targets,
  167 direct risk records, 101 coverage-backed guarding tests.
- `breaking_changes`, `will_break_consumers`,
  `missing_cross_repo_cochanges`, `dependency_cycles`,
  `conformance_violations`, governance risk, and all target security signals
  are empty.
- MCP changed-line coverage reports 24 impacted tests. Its only
  `untested_changes` are `magic_crm_service.dart:16-18` and
  `lesson-command.service.ts:34-35`; live source proves both ranges contain
  only import/export/type-export declarations, so there is no uncovered
  executable behavior. The complete global suites additionally passed.

## Sentrux acceptance and explicit ruling

| Metric | Baseline | Code HEAD | Delta/ruling |
|---|---:|---:|---|
| Files | 2,454 | 2,598 | complete tracked scan |
| Import edges | 4,829 | 5,333 | semantic owner graph expanded |
| Cross-module edges | 2,764 | 2,849 | ratio improved through modularity |
| Lines | 515,470 | 533,441 | complete tracked scan |
| Quality | 5,757 | 5,829 | +72 |
| Depth raw / score | 13 / 3,810 | 13 / 3,810 | unchanged |
| Cycles raw / score | 0 / 10,000 | 0 / 10,000 | unchanged/perfect |
| Equality raw / score | 0.365813 / 6,342 | 0.356743 / 6,433 | improved |
| Modularity raw / score | 0.311773 / 5,412 | 0.338975 / 5,593 | improved |
| Redundancy raw / score | 0.516376 / 4,836 | 0.508978 / 4,910 | improved |
| Rules | 2/2 | 2/2 | zero violations |

The persisted `.sentrux/baseline.json` predates this campaign (quality 4,734)
and makes `sentrux gate` compare fan-out counts `33 -> 35`. An exact diagnostic
rule at the Campaign baseline and code HEAD shows `32 -> 35` whole-repository
fan-out files, but production improves `23 -> 22`: the campaign removes
`messenger.service.ts` and `schedule-plan.service.ts`, adds only
`messenger.module.ts`, and the net `+4` is integration/spec files importing
the extracted owners. The old baseline is not rewritten. This test-only
fan-out delta is accepted because every production root-cause score and the
production fan-out count improve, while RepoWise god/brain and all global
behavioral gates pass.

## Review

The independent whole-campaign review, its exact range, severity totals, and
dispositions are recorded in `campaign-12-whole-review.md`.
