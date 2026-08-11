# MagicMusicCRM — Current-State Inventory

**Source digest:** `47270233d0c5308a053f14fc023eec7b4bb684fe480d3cceb2b4a6fa5db518b8`
**Validation:** PASS

> Имя generator-файла и legacy JSON field names сохранены для artifact compatibility. Фактические counts/paths актуальны; code ownership и dependency graph проверяются через RepoWise по текущему checkout.

## Coverage

| Slice | Count |
|---|---:|
| backend routes | 321 |
| role guards | 22 |
| policy calls | 246 |
| dto fields | 808 |
| flutter role checks | 143 |
| flutter navigation sources | 334 |
| schedule entry points | 48 |
| attendance mutations | 0 |
| finance writes | 48 |
| schema tables | 5 |
| unowned items | 0 |
| missing status items | 0 |

Every row in the JSON artifact has one subsystem owner and an explicit implementation status. The JSON file is the exhaustive machine-readable inventory; this document is its review summary.

## Ownership and status model

| Status | Meaning |
|---|---|
| `compatibility-facade` | Existing public route retained during incremental v4 migration |
| `legacy-review-required` | Role/nav decision must be mapped to capability-based access |
| `policy-protected` | Existing backend policy call is present |
| `current-contract` | Existing DTO field requiring actor-aware contract review |
| `workspace-migration-pending` | Navigation source awaits typed context/workspace migration |
| `legacy-unified-service-pending` | Schedule path awaits the unified constraint/lifecycle service |
| `removal-required` | Attendance write path must leave the active domain |
| `commerce-migration-pending` | Finance write awaits v4 immutable-fact boundaries |
| `current-schema` | Current migration-derived table/column/index state |

## Database inventory

| Table | Owner | Columns | Indexes |
|---|---|---:|---:|
| `app.lessons` | SYS-SCHEDULE | 24 | 15 |
| `app.subscriptions` | SYS-COMMERCE | 28 | 5 |
| `app.payments` | SYS-COMMERCE | 19 | 6 |
| `app.tasks` | SYS-WORKFLOW | 15 | 5 |
| `app.users` | SYS-PLATFORM | 14 | 3 |

### `app.lessons`

Columns: `branch_id`, `created_at`, `created_by`, `deleted_at`, `duration_minutes`, `group_id`, `id`, `is_trial`, `lead_id`, `lifecycle_state`, `notes`, `original_scheduled_at`, `predecessor_id`, `room_id`, `scheduled_at`, `series_date`, `series_id`, `status`, `student_id`, `successor_id`, `teacher_id`, `teacher_rate`, `updated_at`, `version`

Indexes: `lessons_branch_scheduled_idx`, `lessons_group_idx`, `lessons_lead_scheduled_idx`, `lessons_lifecycle_due_idx`, `lessons_one_successor_per_predecessor_idx`, `lessons_room_active_overlap_idx`, `lessons_room_scheduled_idx`, `lessons_scheduled_idx`, `lessons_series_date_active_unique_idx`, `lessons_series_idx`, `lessons_status_scheduled_idx`, `lessons_student_scheduled_idx`, `lessons_successor_reference_unique_idx`, `lessons_teacher_active_overlap_idx`, `lessons_teacher_scheduled_idx`

### `app.subscriptions`

Columns: `base_price_minor`, `commercial_snapshot`, `conversion_lead_id`, `created_at`, `currency_code`, `discount_fixed_minor`, `discount_percent_basis_points`, `discount_reason`, `discount_type`, `expires_at`, `final_price_minor`, `funding_mode`, `id`, `lessons_total`, `lessons_used`, `package_id`, `package_version`, `payer_student_id`, `payment_id`, `purchase_reason`, `snapshot_version`, `starts_at`, `status`, `student_id`, `surcharge_minor`, `surcharge_reason`, `updated_at`, `version`

Indexes: `subscriptions_conversion_lead_unique_idx`, `subscriptions_student_expires_idx`, `subscriptions_v4_client_status_idx`, `subscriptions_v4_package_idx`, `subscriptions_v7_payer_status_idx`

### `app.payments`

Columns: `amount`, `amount_minor`, `branch_id`, `created_at`, `created_by`, `currency`, `deleted_at`, `external_id`, `id`, `idempotency_ref`, `invoice_number`, `issued_subscription_id`, `lesson_id`, `method`, `notes`, `payment_date`, `payment_record_id`, `request_fingerprint`, `student_id`

Indexes: `payments_branch_id_idx`, `payments_lesson_idx`, `payments_payment_date_idx`, `payments_student_date_idx`, `payments_v4_idempotency_idx`, `payments_v4_issued_idx`

### `app.tasks`

Columns: `assigned_to`, `branch_id`, `created_at`, `created_by`, `deleted_at`, `description`, `due_all_day`, `due_at`, `entity_id`, `entity_type`, `id`, `priority`, `status`, `title`, `updated_at`

Indexes: `tasks_assignee_status_due_idx`, `tasks_branch_id_idx`, `tasks_entity_status_due_active_idx`, `tasks_priority_idx`, `tasks_status_due_created_idx`

### `app.users`

Columns: `created_at`, `deleted_at`, `email`, `email_verified_at`, `full_name`, `id`, `is_app_account`, `password_hash`, `phone`, `phone_normalized`, `phone_verified_at`, `profile_completed`, `role`, `updated_at`

Indexes: `users_app_accounts_role_created_idx`, `users_email_lower_unique`, `users_phone_normalized_idx`

## Active attendance mutations

| Kind | Entry | Location | Status |
|---|---|---|---|
| — | No active attendance mutations | — | PASS |

## Active finance writes

| Kind | Entry | Location | Status |
|---|---|---|---|
| backend-route | POST /crm/payments | `server/src/crm/crm-finance.controller.ts:66` | commerce-migration-pending |
| backend-route | POST /crm/expenses | `server/src/crm/crm-finance.controller.ts:82` | commerce-migration-pending |
| backend-route | PATCH /crm/expenses/:id | `server/src/crm/crm-finance.controller.ts:90` | commerce-migration-pending |
| backend-route | DELETE /crm/expenses/:id | `server/src/crm/crm-finance.controller.ts:99` | commerce-migration-pending |
| backend-route | POST /crm/subscription-packages | `server/src/crm/crm-finance.controller.ts:115` | commerce-migration-pending |
| backend-route | PATCH /crm/subscription-packages/:id | `server/src/crm/crm-finance.controller.ts:128` | commerce-migration-pending |
| backend-route | DELETE /crm/subscription-packages/:id | `server/src/crm/crm-finance.controller.ts:142` | commerce-migration-pending |
| backend-route | POST /crm/subscription-packages/:id/restore | `server/src/crm/crm-finance.controller.ts:156` | commerce-migration-pending |
| backend-route | POST /crm/leads/:leadId/subscriptions/issue | `server/src/crm/crm-leads.controller.ts:123` | commerce-migration-pending |
| backend-route | POST /crm/teachers/:id/payouts | `server/src/crm/crm-people.controller.ts:91` | commerce-migration-pending |
| backend-route | POST /crm/teachers/:id/rates | `server/src/crm/crm-people.controller.ts:100` | commerce-migration-pending |
| backend-route | PATCH /crm/lessons/teacher-rate | `server/src/crm/crm-schedule.controller.ts:264` | commerce-migration-pending |
| backend-route | POST /crm/students/:id/adjustments | `server/src/crm/crm-students.controller.ts:126` | commerce-migration-pending |
| backend-route | POST /crm/students/:id/transfer | `server/src/crm/crm-students.controller.ts:140` | commerce-migration-pending |
| backend-route | POST /crm/students/:studentId/subscriptions/issue | `server/src/crm/subscription-commerce.controller.ts:50` | commerce-migration-pending |
| backend-route | POST /crm/students/:studentId/payment-records/:paymentRecordId/reversal/preview | `server/src/crm/subscription-commerce.controller.ts:64` | commerce-migration-pending |
| backend-route | POST /crm/students/:studentId/payment-records/:paymentRecordId/reversal | `server/src/crm/subscription-commerce.controller.ts:79` | commerce-migration-pending |
| backend-route | POST /crm/students/:studentId/payment-records | `server/src/crm/subscription-commerce.controller.ts:100` | commerce-migration-pending |
| backend-route | POST /crm/students/:studentId/payment-records/:paymentRecordId/transition | `server/src/crm/subscription-commerce.controller.ts:114` | commerce-migration-pending |
| backend-route | POST /crm/students/:studentId/subscriptions/purchase/preview | `server/src/crm/subscription-commerce.controller.ts:135` | commerce-migration-pending |
| backend-route | POST /crm/students/:studentId/subscriptions/purchase | `server/src/crm/subscription-commerce.controller.ts:144` | commerce-migration-pending |
| backend-route | POST /crm/students/:studentId/subscription-payments | `server/src/crm/subscription-commerce.controller.ts:158` | commerce-migration-pending |
| backend-route | POST /crm/students/:studentId/subscriptions/:issuedSubscriptionId/replace/preview | `server/src/crm/subscription-commerce.controller.ts:172` | commerce-migration-pending |
| backend-route | POST /crm/students/:studentId/subscriptions/:issuedSubscriptionId/replace | `server/src/crm/subscription-commerce.controller.ts:188` | commerce-migration-pending |
| backend-route | POST /crm/students/:studentId/subscriptions/:issuedSubscriptionId/cancel/preview | `server/src/crm/subscription-commerce.controller.ts:210` | commerce-migration-pending |
| backend-route | POST /crm/students/:studentId/subscriptions/:issuedSubscriptionId/cancel | `server/src/crm/subscription-commerce.controller.ts:225` | commerce-migration-pending |
| sql-mutation | insert into app.account_adjustments | `server/src/crm/finance.service.ts:593` | commerce-migration-pending |
| sql-mutation | insert into app.payments | `server/src/crm/finance.service.ts:692` | commerce-migration-pending |
| sql-mutation | insert into app.expenses | `server/src/crm/finance.service.ts:789` | commerce-migration-pending |
| sql-mutation | update app.expenses | `server/src/crm/finance.service.ts:826` | commerce-migration-pending |
| sql-mutation | update app.expenses | `server/src/crm/finance.service.ts:865` | commerce-migration-pending |
| sql-mutation | insert into app.teacher_payouts | `server/src/crm/payroll.service.ts:365` | commerce-migration-pending |
| sql-mutation | insert into app.teacher_rates | `server/src/crm/payroll.service.ts:413` | commerce-migration-pending |
| sql-mutation | insert into app.payments | `server/src/crm/subscriptions.service.ts:285` | commerce-migration-pending |
| sql-mutation | insert into app.subscriptions | `server/src/crm/subscriptions.service.ts:294` | commerce-migration-pending |
| sql-mutation | insert into app.payments | `server/src/crm/subscriptions.service.ts:669` | commerce-migration-pending |
| sql-mutation | insert into app.subscriptions | `server/src/crm/subscriptions.service.ts:687` | commerce-migration-pending |
| sql-mutation | insert into app.teacher_rates | `server/src/crm/teachers.service.ts:488` | commerce-migration-pending |
| sql-mutation | insert into app.teacher_rates | `server/src/crm/teachers.service.ts:835` | commerce-migration-pending |
| sql-mutation | insert into app.subscriptions | `server/src/crm/commerce/commerce-schema.repository.ts:185` | commerce-migration-pending |
| sql-mutation | insert into app.payments | `server/src/crm/commerce/commerce-schema.repository.ts:333` | commerce-migration-pending |
| sql-mutation | update app.payments | `server/src/crm/commerce/payment-lifecycle.repository.ts:340` | commerce-migration-pending |
| sql-mutation | insert into app.subscriptions | `server/src/crm/commerce/subscription-issue.repository.ts:329` | commerce-migration-pending |
| sql-mutation | insert into app.payments | `server/src/crm/commerce/subscription-issue.repository.ts:698` | commerce-migration-pending |
| sql-mutation | insert into app.account_adjustments | `server/src/crm/commerce/subscription-issue.repository.ts:855` | commerce-migration-pending |
| sql-mutation | update app.subscriptions | `server/src/crm/commerce/subscription-lifecycle.repository.ts:863` | commerce-migration-pending |
| sql-mutation | update app.subscriptions | `server/src/crm/commerce/subscription-lifecycle.repository.ts:891` | commerce-migration-pending |
| sql-mutation | insert into app.subscriptions | `server/src/crm/commerce/subscription-lifecycle.repository.ts:924` | commerce-migration-pending |

## Verification

```powershell
pwsh -File scripts/v4_inventory.ps1 -Check
```

The check regenerates both artifacts from source, validates route/category/schema coverage, and fails if either checked-in artifact is stale.
