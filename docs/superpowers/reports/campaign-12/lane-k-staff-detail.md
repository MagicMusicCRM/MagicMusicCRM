# Campaign-12 Lane K — Staff Detail

## Baseline and risk

- Tier 4 base: `624f36c560ed7fb2de5f92612c3a9b2445339d68`.
- Branch: `codex/campaign12-staff-detail`.
- Source owner: `staff_detail_dialog.dart::_StaffDetailDialogState`.
- Baseline RepoWise health: `1.04`; NLOC: `662`; max CCN: `30`;
  weighted deficit: `4608`.
- Risk: `92%`, increasing, with five fixes in six months and a bug-magnet
  marker. The extraction therefore preserves the public dialog/navigation
  surface and adds behavior-first characterization before moving logic.

## RED and semantic cut

- RED command:
  `flutter test test/features/settings/staff_detail_dialog_contract_test.dart`.
- RED result: exit `1` because `StaffDetailController`, `StaffDetailDraft`,
  and their source files did not exist. The compiler named the wished-for
  owners and validation boundary before production code was added.
- A mutation run also removed required-field validation and made the focused
  first-name/last-name/status test fail before the guard was restored.
- `StaffDetailDraft` owns legacy profile fallback, canonical link identity,
  editable profile state, branch selection, and birthday patch calculation.
- `StaffDetailController` owns branch loading/retry state, ignores late branch
  responses after disposal, profile validation,
  the exact update payload, credential reads/provisioning, and local role
  translation. `StaffDetailAccessFlow` owns the three existing access and
  lifecycle dialogs. `StaffDetailContent` is stateless presentation.
- The public `StaffDetailDialog` constructor, `show` signature, provider
  ownership, root navigation result, snackbars, and Russian copy remain at the
  compatibility shell.

## Contract proof

- Direct staff values retain precedence, while missing first name, last name,
  and phone fall back to the legacy profile map.
- Canonical phone wins over email for user linking. Migration and local invalid
  email suffixes return no link value.
- Save requires first name, last name, status, and at least one branch. The
  empty-branch path shows `Выберите хотя бы один филиал.` and sends no PATCH.
- The PATCH contains `firstName`, `lastName`, `phone`, `position`, `status`,
  `branchIds`, plus only a changed nonempty birthday in `customDataPatch`.
  Characterization proves `email`, `password`, and `role` are absent.
- Credentials, lifecycle, and access-role UI remain limited to `director` and
  `system_admin`; role change also requires `profile_user_id`. Archived cards
  disable access and save while retaining the restore action and
  `staff-change-access-role` remains unchanged.
- Successful save root-pops `true` before showing its snackbar. Linking first
  publishes the users-search navigation request and then root-pops `false`.

## Structural evidence

The shared analyzer-AST guard dynamically discovers every `staff_detail_*.dart`
owner, rejects parse errors, `part`/`part of`, future files above `500` NLOC,
executables above CCN `10`, oversized type/callable proxies, provider ownership
leaks, and CRM effects outside the controller. Negative fixtures prove that
comments and strings are ignored while aliases, future god/brain owners, and
decision shapes are caught.

| Owner | Token NLOC | Imports | Max CCN | Max executable NLOC |
| --- | ---: | ---: | ---: | ---: |
| `staff_detail_dialog.dart` | 140 | 9 | 8 | 29 |
| `staff_detail_model.dart` | 144 | 0 | 8 | 14 |
| `staff_detail_controller.dart` | 146 | 4 | 6 | 21 |
| `staff_detail_content.dart` | 471 | 5 | 9 | 50 |
| `staff_detail_access_flow.dart` | 62 | 5 | 5 | 23 |

The shell is below its `240` NLOC and `14` import ceilings, contains one
`magicCrmServiceProvider` identifier, and contains none of `updateStaff`,
`getStaffAccess`, `provisionStaffAccess`, `_credentialHelper`, `_branchesText`,
or `_dropdownItems`. Every new owner is below `500` NLOC and every executable
is CCN `<= 9`; the former CCN `30` god owner no longer exists.

Per owner RepoWise raw-health indexing is intentionally deferred to the root
integrator's one exact Tier 4 index, as required by the lane dispatch. This
branch does not run an independent RepoWise update or Sentrux scan; the table
above is the live analyzer-AST evidence consumed by the permanent guard.

## Lane smoke and scope

- Contract plus architecture suites: `16/16` PASS.
- Existing shared workspace smoke: `2/2` PASS for profile save without
  credentials and legacy staff access creation.
- Targeted Flutter analyze of all five production owners: `No issues found`.
- Exact format gate, invariant `rg`, and `git diff --check`: PASS.
- Verify-only diff is empty for both CRM service files, both shared settings
  parents, all three access/lifecycle dialogs, the shared workspace test, and
  `test/support/settings_test_api.dart`.
- Flutter-generated registrants were restored exactly to Tier 4 base and are
  excluded from the lane commit.
