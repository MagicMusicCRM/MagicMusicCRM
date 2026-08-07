# v7 T5.1.1 — Client Card Commerce UI

**Date:** 2026-08-07  
**Scope:** `REQ-COMMERCE-101`, `REQ-PAYMENT-101/102`, `REQ-COMMERCE-102`

## Result

The canonical Student card now owns the complete commerce workflow. Subscription
purchase uses the signed preview/commit contract, allows another Student to pay,
requires a cross-payer reason and shows recipient, payer, final price and payer
balance before commit. The retained mutation identity makes retry idempotent;
the backend invalidates both affected cards after commit.

Payment creation and lifecycle use exactly three business statuses: unpaid,
posted pending confirmation and paid. Pending and debt totals are visible beside
the personal account balance; payment rows expose only valid transitions. Paid
confirmation captures branch, method and external operation identifier.

Reversal always starts from the backend impact preview and requires a reason.
Reversed records disappear from ordinary financial totals and remain visible in
the collapsed technical history with author, reason and timestamp. Existing
subscription cancellation/refund continues through the same card controller and
the immutable commerce contracts.

The general Student `Actions` menu was removed. Subscription purchase/cancel/
replace live in the subscription section, homework lives in Progress and archive
remains a separate action. Payment movements and installment obligations are
collapsed by default. No dependency or parallel form system was added.

## Contracts verified

- Same-client and cross-payer purchase preview/commit, required reason and stable
  retry identity.
- Full purchase amount is reserved/debited while installments remain separate
  due records.
- Payment projection includes lifecycle status/version/installment/due date and
  parses the technical finance history without legacy runtime failures.
- Admin, Manager and Director use the existing client-finance boundary; Teacher
  mounts neither the finance tab nor hidden finance reads.
- Mobile payment rows wrap actions without overflow; desktop keeps one canonical
  section title and no duplicate command.

## Verification

| Gate | Result |
|---|---|
| Commerce/card Flutter targeted | PASS — 10/10 |
| Client workspace regression | PASS — 17/17 |
| Student action ownership | PASS — 4/4 |
| Flutter analyze | PASS — no issues |
| Flutter full | PASS — 633/633 |
| Commerce PostgreSQL/contracts | PASS — 58/58 |
| Backend typecheck/build | PASS |
| Backend full | PASS — 155/155 suites, 1223/1223 tests |
| v7 reconciliation | PASS twice — `issues=[]` |

