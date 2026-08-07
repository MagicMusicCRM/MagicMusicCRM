# SYS-COMMERCE-INTEGRITY — L1 Details

## 1. Additive database shape

### `app.subscriptions`

- `payer_student_id uuid references app.students on delete restrict`;
- `funding_mode text check in ('personal_account','installment','legacy')`;
- `purchase_reason text` required when payer ≠ recipient;
- legacy rows backfill payer=`student_id`, mode=`legacy`; issued snapshots remain
  immutable, новые поля входят в snapshot-protection trigger.

`subscription_obligation_facts.student_id` продолжает означать владельца
личного счёта. Для новых покупок это payer, а `issued_subscription_id` определяет
recipient через subscription. Отдельный дублирующий wallet ledger не нужен.

### `app.client_payment_records`

| Column | Contract |
|---|---|
| `id uuid PK` | deterministic/idempotent aggregate id |
| `student_id uuid` | payer/account owner |
| `issued_subscription_id uuid?` | назначение |
| `installment_id uuid? unique` | due installment source |
| `amount_minor bigint` | `> 0` |
| `currency_code text` | ISO uppercase |
| `status text` | `unpaid`, `posted_pending`, `paid` |
| `due_at timestamptz?` | debt/pending schedule |
| `method text?` | required for paid |
| `external_identifier text?` | required for paid verification |
| `verification_note text?` | default installment marker |
| `actual_payment_id uuid? unique` | non-null iff paid |
| `version bigint` | positive expected-version |
| `created_by/verified_by/verified_at` | staff evidence |
| `created_at/updated_at` | timestamps |

Identity, amount, currency, student and assignment columns become immutable
after insert. Status/version/check fields change only through service command;
once paid, all record fields are immutable.

### `app.client_payment_status_events`

Append-only: payment record, before/after status, human reason, actor, occurred,
aggregate version, actual payment ref. `UNIQUE(payment_record_id,
aggregate_version)` and immutable trigger.

### `app.commerce_reporting_exclusions`

Append-only pair: `source_kind/source_id`, `counterpart_kind/counterpart_id`,
reason, actor, audit ref, occurred. Unique active source and counterpart. Ordinary
finance queries use a shared `NOT EXISTS` predicate; Client technical history
joins it explicitly.

### Existing `app.payments` / `app.account_adjustments`

- `payments.payment_record_id uuid unique` links a paid record;
- actual paid amount remains immutable;
- reversal inserts an opposite signed `account_adjustment` linked by
  `source_payment_id`, then exclusion links source payment and adjustment;
- repeated reversal returns prior result; second different command conflicts.

### Catalog snapshot additions

`ConfigSnapshot` gains:

- `lessonSettlementTypes[]`: stableKey, label, colorToken, hourShareBasisPoints
  `0..20000`, fixedPenaltyMinor?, allowedContexts, active, order;
- `teacherCompensationRules[]`: stableKey, label, mode
  `none|standard|percent|fixed|hourly`, value, active, order.

Branch revision stores only explicit override if allowed. Used keys may be
archived, never deleted/renamed in a way that rewrites facts. Catalogs are
independent: no allowed-pair matrix.

## 2. Purchase algorithm

1. Resolve effective package/config and both actor-scoped Students.
2. Calculate base − discount + surcharge and validate installments sum exactly.
3. Preview reads current payer balance and returns signed facts/token.
4. Commit validates idempotency/fingerprint/token, then locks both students in
   sorted UUID order and locks package/subscription aggregate.
5. Reload balance/config/package; reject stale/archived/scope changes.
6. `personal_account`: require available balance ≥ final price.
7. Insert subscription with recipient/payer snapshot and all hours.
8. Insert obligation debit against payer for full final price. For installment,
   insert schedule rows; future schedule is not yet a payment/debt.
9. Insert lifecycle event, operational audit and outbox invalidating both cards.
10. Commit; post-commit realtime only hints refetch.

The full debit makes the purchase reservation visible immediately. Confirmed
installment payments later credit the payer account. Debt reporting uses due
`unpaid` records, not the mere existence of future installments.

## 3. Installment worker and transitions

- Worker selects due unlinked installments in bounded batches using
  `FOR UPDATE SKIP LOCKED`.
- For each, deterministically inserts one `posted_pending` payment record with
  note `Проверить оплату за рассрочку`; repeated runs produce no duplicate.
- Staff verification to paid requires date, amount, method, operation/receipt id
  and actor; transaction creates immutable `app.payments`, status event and link.
- Transition to unpaid requires human reason and adds debt without wallet credit.
- A later received payment transitions unpaid→paid through a new event; amount
  identity cannot change. Wrong amount is voided/recreated via explicit reason.

## 4. Payment reversal

Preview returns wallet delta, linked subscription/obligation and warning if the
resulting balance is negative. Commit locks payment record, actual payment and
student; verifies paid and not excluded; inserts equal opposite adjustment and
exclusion pair, then audit/outbox. Pending/unpaid deletion inserts a technical
void event/exclusion without monetary adjustment. UI continues to label the
command `Удалить`, but confirmation explains the immutable operation.

## 5. Subscription cancellation/refund

Cancellation separates two effects:

- `unfundedCancellationMinor`: unused share of the future/pending/unpaid
  obligation, closed without income;
- `recommendedRefundMinor`:
  `floor(confirmedFundedMinor × unusedUnits / totalUnits)`.

For `personal_account`, confirmed funding is the full amount atomically debited
from already confirmed wallet funds. For `installment`, it is the sum of linked
paid records. Unused excludes settled and reserved units; previous refunds reduce
the cap. Staff may choose a lower nonnegative refund only with reason.

One account credit equals `unfundedCancellationMinor + chosenRefundMinor`:
the first part removes unpaid commitment, the second restores paid money. This
avoids both residual phantom debt and double credit. Refund credits original
payer; active reservations release; future unpaid/pending records receive
technical closure/exclusion; previous settlements remain immutable. Purchase
debit/cancellation credit are excluded from ordinary sale movement; external paid
facts are excluded only when explicitly reversed.

## 6. Lesson settlement calculation

For each client participant:

- `units = lessonDurationHours × hourShareBasisPoints / 10000`;
- subscription charge consumes/reserves units from selected subscription;
- personal-account charge converts units by immutable lesson/package rate;
- fixed penalty adds minor units; both may coexist;
- 200% share is allowed, insufficient subscription units rejects preview/commit;
- free/zero types create an explicit zero settlement snapshot for history.

Teacher rule is selected separately:

- `none`: 0;
- `standard`: immutable effective teacher/lesson rate;
- `percent`: standard × basis points;
- `fixed`: configured/overridden minor units;
- `hourly`: rate × duration.

Override value requires human reason. One teacher accrual fact is created per
terminal lesson transition independently of client payment statuses. Group lesson
has N client facts and exactly one teacher accrual.

## 7. Snapshot payloads

Client fact stores stable key, label, color token, share, penalty, calculated
units/amount/currency, subscription id and configuration revision. Teacher fact
stores rule key/label/mode/default value/actual value/amount/currency/reason and
revision. UI never reconstructs historical meaning from the current catalog.

## 8. Query predicates

Every ordinary payment/revenue query excludes a source when
`commerce_reporting_exclusions.source_kind/source_id` matches. The predicate is
implemented once in repository SQL fragments or one database view and covered by
inventory tests; copying ad-hoc `deleted_at` filters is forbidden.

Technical history is the inverse: it intentionally includes source, counterpart,
human reason, actor and time, bounded by client lineage and capability.

## 9. Migration/backfill

- Backfill subscription payer to recipient and mode `legacy`.
- Backfill every immutable legacy actual payment into a paid payment record and
  link it without changing payment id/amount/date.
- Existing installment rows remain schedule facts; link created only when due or
  when an unambiguous actual payment association already exists.
- Existing negative refunds already converted to account adjustments stay facts;
  no speculative exclusions are invented.
- Down migration is blocked once v7 payer-different, status-event or exclusion
  facts exist; never destroy them to satisfy rollback.

## 10. Required executable checks

- two purchases from same payer with only one affordable;
- payer/recipient reversed lock order cannot deadlock;
- fault after debit before subscription/audit rolls all back;
- due worker replay produces one payment record;
- two verifiers produce one paid fact;
- paid reversal changes wallet exactly once and ordinary revenue excludes pair;
- cancellation refund cap with used/reserved hours and previous refund;
- group settlement N client facts + one teacher fact;
- config publish never rewrites historical snapshots;
- role/payload matrix and reconciliation delta 0.
