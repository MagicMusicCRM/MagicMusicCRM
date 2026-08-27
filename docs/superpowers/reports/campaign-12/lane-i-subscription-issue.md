# Campaign-12 Lane I — Subscription Issue UI

## Dependency and baseline

- Tier 3 dependency SHA: `37667c097e850092dbafaa0480c5e4b64e623025`.
- Source owner: `subscription_issue_sheet.dart`.
- Baseline RepoWise health: `3.04`; NLOC: `1114`; max CCN: `19`;
  weighted deficit: `5525`.
- Risk: hotspot `94%` and increasing, bug-prone, three fixes in six months
  (latest on the task date), two dependents, bus factor `1`. `_submit` and
  `build` were treated as the sensitive cut points.

## RED and implementation

- RED command:
  `flutter test test/features/commerce/subscription_issue_controller_test.dart`.
- RED result: exit `1`, because the new controller and model owners did not
  exist. The failure named both missing imports and every wished-for public
  contract.
- Extracted immutable draft/parsing, PostgreSQL-parity pricing, command input
  construction, preview/commit state machine, identity lifecycle, stateless
  form view, and stateless presentation components.
- The public sheet keeps the existing entry point, widget constructor, public
  typedefs/models through exports, dirty-exit lifecycle, focus dismissal, and
  navigation only after `committed`.

## Focused verification

- Lane smoke: `16/16` passed across the existing form characterization suite,
  new controller/pricing suite, and architecture guard.
- Targeted analyze: six production files, `No issues found`.
- Format check: nine matching source/test files, `0 changed`.
- Required `rg` proof found preview token, mutation identity, commit blocker,
  purchase reason, installment, submit-key, and preview-key ownership.
- `git diff --check`: passed.
- Verify-only diff is empty for `client_card_student.dart`, `client_card.dart`,
  `magic_crm_service.dart`, `magic_crm_service_finance.dart`, and
  `subscription_issue_form_test.dart`.

## Pricing, scheduling, and idempotency proofs

- `0,01%` is serialized as one basis point and a half-minor result rounds
  half-up to one minor unit, matching PostgreSQL.
- Percent above `100%`, fixed discount above base, non-positive/unreasoned
  surcharge, and foreign payer without reason are blocked before preview.
- Installments accept `2..12`, require every amount to remain positive, clamp
  UTC month ends, and distribute remainder to the first payments.
- A non-committable balance preview never invokes commit and exposes the exact
  insufficient-balance message.
- Pricing/input changes clear preview/error and rotate identity. Once commit is
  attempted, inputs freeze; an ambiguous failed commit retries with the exact
  same identity and purchase JSON.

## RepoWise health and structural result

Exact-SHA evidence was collected after indexing
`72a239e574dd3a7265d336d95a9e18a7a0ddaca5` with one module-health pass:

| Owner | Raw health | NLOC | Max CCN | Recorded penalties |
| --- | ---: | ---: | ---: | --- |
| Public shell | 5.90 | 135 | 6 | DRY 0.60; historical/evolution 3.50 |
| Models | 8.09 | 130 | 4 | DRY 0.35; untested-hotspot 1.56 |
| Pricing | 8.35 | 191 | 10 | two complex-method 0.75; DRY 0.15 |
| Controller | 9.85 | 195 | 6 | DRY 0.15 |
| Form view | 8.15 | 359 | 19 | large-method 0.949; complex 0.551; DRY 0.35 |
| Components | 9.65 | 415 | 7 | DRY 0.35 |

The shell's raw `5.90` is not a remaining god/brain owner. Its current static
penalty is the `0.60` DRY marker; the other `3.50` points are history/evolution
signals retained after the cut: churn, change entropy, co-change scatter, two
hidden-coupling rows, and three prior defects. Static-only shell health is
therefore `9.40`. No extracted owner has a god-class or brain-method marker,
and every extracted owner is above the Campaign threshold of `7.00` raw.

Coverage provenance from the same indexed state is explicit:
`coverage=null`, `test_map=null`. Campaign lane rules intentionally defer fresh
coverage to the global gate. RepoWise therefore applies the visible `1.56`
untested-hotspot penalty to models despite the focused controller/form tests;
the raw model score remains `8.09` without adjustment.

The shell has seven imports and `_SubscriptionIssueFormState` has 76 physical
lines. The structural guard enforces shell `<=220` NLOC, state `<=160` NLOC,
imports `<=12`, and every extracted owner `<=500` NLOC.

## Integrated review hardening

The independent Tier 3 review found and the integration branch fixed a stale
preview race, residual form-view complexity, stale percent-to-fixed input, and
invalid total presentation. The controller now rejects stale success and error
by request id, draft generation, and command identity; the runtime test proves
that only the latest preview payload and identity can be committed. The discount
field remounts on mode changes, while malformed, zero, or over-base amounts show
`Итого: Не указано`.

The three lane guards now share analyzer-AST infrastructure and dynamically
discover semantic owners, preventing comment/string/alias/new-file bypasses.
At exact integration HEAD `b586a29dc362b8a860d233f3846d9caff1d2c6a6`,
the form view is health `8.10`, NLOC `404`, max CCN `6`; every extracted owner
is at least `8.09`, every production owner is `<=500` NLOC and `<=10` CCN, and
no god/brain marker remains. Final Lane I smoke is `21/21`; combined Tier 3
smoke is `48/48`, analyzer `23/23`, format `20/20`, and all `19/19`
verify-only paths are unchanged.
