# MagicMusicCRM v6 — v7 Component Contract

**Task:** V6-004  
**Status:** owner-approved direction; implementation evidence follows per consumer.

## Reuse boundary

- Visual source of truth stays `lib/core/theme/design_tokens.dart`, `app_theme.dart` and `lib/core/widgets/v7/`.
- Brand palette remains charcoal + `#C5A059` gold with existing semantic success/warning/danger/action colors.
- Existing spacing, radius and 160/240/300ms motion tokens remain authoritative.
- Existing GoRouter, workspace, entity registry, Riverpod providers and feature services are reused.
- No new UI framework, router, state stack, palette, typography package or speculative base class is approved.

## Confirmed repeated behavior

| Contract | First consumers | Implementation rule |
|---|---|---|
| Adaptive workspace shell | Manager/Admin shell; Client workspace | Extend production shell; branch by available width |
| Context bar | Client route; Schedule/Reports drilldown | Back/Forward + typed breadcrumbs + action overflow |
| Adaptive surface | Lesson quick view; Client/Payment forms | Primary route, quick-view sheet, short confirmation dialog |
| Expandable mobile sheet | Lesson quick view; selectors | Native `DraggableScrollableSheet`, supplied controller, safe-area/keyboard/back |
| Explicit desktop scrollbar | Schedule; boards/tables | Native Flutter scrollbar; one owner/controller per axis |
| Typed entity link | Lesson; reports/tasks/client card | Existing `EntityRouteRegistry`; no display-name routing |
| Page state | Client, Tasks, Dashboard, Config | Reuse skeleton/toast; consistent empty/error/forbidden/retry |
| Scope selector | Client Lessons/Payments; Dashboard/Config | Existing branch providers + capability intersection |

## State contract

Every repeated component must define default, hover, focus, pressed/selected, disabled, loading, empty/error where applicable, forbidden, conflict and retry. Color is never the only state signal. All icon-only actions require tooltip and semantic label.

## Acceptance

- Owner confirmed the v7 direction and requested implementation of all v6 tasks.
- A component ships only with its first production consumer and one smallest runnable regression check.
- A proposed primitive with only one consumer must remain local until repetition is proven.

