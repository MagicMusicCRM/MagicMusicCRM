# V6-201 — Adaptive surface policy

**Дата:** 2026-08-04  
**Статус:** PASS

## Declarative contract

`AdaptiveSurfacePolicy` выбирает контейнер только из job kind и доступной ширины:

| Job kind | 360 / 600 | 840+ |
|---|---|---|
| Primary / comparison | existing route callback | existing route callback |
| Quick view / contextual edit | existing `MagicSheet` | existing `MagicDrawer` |
| Selection | existing `MagicSheet` | existing `MagicDrawer` |
| Confirmation | `AlertDialog` | `AlertDialog` |

Primary/comparison требуют callback существующего canonical route и не строят дубликат content. Overlay jobs строят ровно один переданный body и не создают router/workspace stack.

## Production mounting

- Client app-user selector переведён с unconditional sheet на `selection`: full-width sheet policy на compact, v7 drawer на desktop.
- Finance add-expense form переведена с unconditional sheet на `quickView/contextual edit`: compact sheet, desktop drawer.
- `MagicDrawer` сохраняет title/subtitle/icon v7 chrome и получил labelled close action.
- Service/provider/DTO вызовы не изменены.

## Проверки

```text
flutter analyze
PASS — No issues found

flutter test test/core/widgets/adaptive_surface_policy_test.dart \
  test/core/widgets/v7_components_test.dart \
  test/features/v4/client_finance_roles_test.dart
PASS — 12/12

scripts/v6_ux_inventory.ps1 -Check
PASS — routes=21, reachable=256, workspaceProduction=2, unowned=0

git diff --exit-code -- docs/audits/v6-wire-service-baseline.{json,md}
PASS — exact wire baseline unchanged

git diff -- server
PASS — empty
```

Widget matrix покрывает Client/Payment primary route callbacks, Lesson quick view, selection и confirmation на целевых breakpoint без повторного content build.
