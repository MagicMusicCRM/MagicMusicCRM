# V6-404 — Canonical Client Payments

Date: 2026-08-04  
Status: PASS

## Delivered

- The routed Student workspace now has one canonical `Оплаты` section for the personal-account balance, actual payments, obligations and installments.
- The duplicate editable legacy ledger from `Обзор` was removed. An immutable payment cannot be edited or deleted from the client card; a correction must be a separate typed operation.
- The adaptive section works at 360/840/1200 px and keeps the create form inline in the workspace instead of opening a second desktop dialog.
- Payment creation contains the authoritative client branch, date, positive exact minor-unit amount, cash/cashless method, immutable `Проведён` status, authenticated accepting employee, optional subscription destination, invoice identifier and comment.
- A network failure leaves the draft intact. An unchanged retry reuses the same mutation identity and produces one ledger effect.
- A received ActualPayment is always a completed fact. Pending/paid installment state is derived from cumulative immutable payments and cannot be rewritten manually.
- Discount, fixed surcharge with mandatory reason and installment schedule remain typed subscription commercial terms. The preview reconciles `base − discount + surcharge` and requires installment and immediate-payment totals to match the final price.

## Scope and access

- ActualPayment is always anchored to the Student's authoritative branch; a mismatched branch is rejected before the write.
- There is intentionally no school-wide payment option: a client payment is a branch-owned client fact, not a truly school-wide operation.
- Admin/Manager/Director can use the client-finance surface according to the existing capability projection. Teacher receives no payments tab and performs no commerce request.
- Manager access remains client-finance-only; no school-finance endpoint or projection was added.
- `branchId`, accepting actor and scope are resolved and validated server-side, so the UI cannot spoof them.

## Data and wire contracts

- Existing canonical `POST /crm/students/:studentId/subscription-payments` is reused with stable mutation metadata.
- `GET /crm/students/:studentId/commerce` now projects branch, method, invoice, comment, status and accepting actor for immutable movements.
- Migration `0095_subscription_surcharge_terms` adds typed surcharge columns and updates the commercial-snapshot constraint and immutability trigger.
- The rollback refuses to drop surcharge columns while surcharge facts exist; an empty-schema down→up transaction is verified without drift.
- No dependency or speculative payment domain was added.

## Verification

- `flutter analyze`: PASS.
- Payment/subscription form and role tests: 8/8 PASS.
- Client-card regression: 26/26 PASS.
- Route/width/restore matrix: 15/15 PASS.
- Full Flutter suite: 573/573 PASS.
- Commerce PostgreSQL/contract suite: 37/37 PASS.
- Surcharge schema down→up + issue integration: 9/9 PASS.
- Full backend suite: 150/150 suites and 1161/1161 tests PASS.
- Backend typecheck/build: PASS.
- `git diff --check`: PASS.
