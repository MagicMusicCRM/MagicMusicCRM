# Research — Adaptive CRM UX, navigation and input

**Дата:** 2026-08-04  
**Система:** `SYS-APP-EXPERIENCE`  
**Режим:** existing-product redesign; visual baseline = approved MagicMusic v7

## 1. Sources

- Existing product: `docs/superpowers/specs/2026-06-20-crm-feedback-redesign.md`, `docs/migration/REDESIGN-MIGRATION-PLAN.md`, `lib/core/theme/design_tokens.dart`.
- Owner specification: `ТЗ СРМ МагМуз-1 (1).docx` and four supplied HolliHop screenshots.
- Flutter: [General approach to adaptive apps](https://docs.flutter.dev/ui/adaptive-responsive/general), [DraggableScrollableSheet](https://api.flutter.dev/flutter/widgets/DraggableScrollableSheet-class.html), [PopScope](https://api.flutter.dev/flutter/widgets/PopScope-class.html), [Android predictive back migration](https://docs.flutter.dev/release/breaking-changes/android-predictive-back).
- Windows: [BreadcrumbBar](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/breadcrumbbar), [navigation history and backwards navigation](https://learn.microsoft.com/en-us/windows/apps/design/basics/navigation-history-and-backwards-navigation), [Windows controls and patterns](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/).
- Functional comparator: [HolliHop product modules](https://holyhope.ru/project), [HolliHop manual](https://holyhope.ru/Files/holyhope_manual.pdf).
- Local design intelligence: UI/UX Pro Max CRM/productivity, Flutter, navigation, accessibility and data-dashboard searches; Design System token/component/state references.

## 2. Evidence-based conclusions

### 2.1 Adapt by available space, not device name

Flutter recommends abstracting shared data, measuring available constraints and branching the presentation. `LayoutBuilder` is appropriate for local surfaces, while `MediaQuery.sizeOf` is appropriate for app-window/full-screen decisions. Therefore one content/controller must feed route, drawer, dialog or sheet variants; separate “mobile business logic” is prohibited.

### 2.2 Primary work is navigation, not a modal

Client cards, lesson editing, payments, configuration and reports are deep operational workflows. On compact screens they must be full-screen routes. On desktop they live inside a workspace tab/page. Modal dialogs remain for confirmations and short single-purpose edits only.

### 2.3 Mobile sheets need explicit expansion

`DraggableScrollableSheet` already coordinates resize and inner scroll when its supplied controller is used. Required pattern:

- visible grab handle;
- `snap: true` with documented snap points;
- explicit “Развернуть” action for users who do not discover gestures;
- `maxChildSize: 1.0` and safe-area-aware full-screen state;
- one controller shared by sheet and its scrollable content;
- unsaved-change protection before dismiss.

### 2.4 System Back must be a first-class contract

Android predictive back requires ahead-of-time knowledge of whether the route can pop. `PopScope`/`Form.canPop` must reflect dirty state continuously. Hierarchical navigation uses push; top-level destination changes use go/replace. Back closes the topmost overlay or pops one route; it never jumps silently to dashboard/home.

### 2.5 Desktop tabs and breadcrumbs solve different problems

- Tabs represent parallel work contexts.
- Back/Forward traverse history within the current tab.
- Breadcrumbs show the current hierarchical path and allow jumping to any ancestor.

Microsoft recommends breadcrumbs for paths deeper than two levels and collapsing older nodes into an ellipsis when space is limited. This matches the owner’s Explorer-like request without turning breadcrumbs into another top-level navigation.

### 2.6 Input is platform-adaptive

Flutter deliberately disables mouse drag-scrolling by default on desktop. The owner explicitly requires visible draggable scrollbars on PC, so desktop uses persistent/hover-emphasized thumb+track and mouse drag. Mobile keeps touch scrolling and does not show persistent desktop bars.

### 2.7 Preserve v7; reject generated restyling

UI/UX Pro Max correctly matched CRM/productivity to flat minimalism, data-dense dashboards, accessible focus states and subtle 150–300 ms feedback. Its suggested new teal/blue palettes, oversized editorial typography and alternative font families conflict with the approved v7. They are rejected. Existing MagicMusic tokens, Inter and gold/charcoal visual identity remain authoritative.

## 3. Role jobs-to-be-done

| Role | Primary jobs | UI emphasis | Explicit exclusions |
|---|---|---|---|
| Client | See upcoming lessons, subscription/homework, chat, profile | Calm, low-density, next action first | No staff/client directory, no school finance |
| Teacher | Day/week schedule, lesson context/comments, own students, chat | Time-first, read-only clarity | No lesson creation, no client phone/finance, no editing clients |
| Admin | Handle chat, schedule, clients quickly | Dense operational split views, shortcuts | No users/roles, reports or school finance |
| Manager | Operate clients, tasks, staff workflows and allowed reporting | Multi-tab workspace, queues and exceptions | No school finance under the current policy; client-card finance remains separately scoped |
| Director | School/branch configuration, access, finance, analytics and oversight | Scope clarity, comparisons, impact previews | Cannot bypass protected security/data invariants |

`system_admin` is a technical/emergency role and does not receive a separate everyday product IA.

## 4. Comparator lessons

HolliHop demonstrates useful adjacency of client information, preferred schedule, lessons, personal account and history. MagicMusic adopts the workflow adjacency, but keeps:

- typed links and route history;
- branch/school scope visibility;
- capability-projected data;
- immutable commerce/lesson facts;
- MagicMusic v7 visual language.

## 5. Design constraints carried forward

- Existing API calls remain stable unless a v6 requirement proves a missing authoritative field.
- One primary action per surface.
- Visible labels for primary actions; icon-only only for conventional secondary actions with tooltip/semantics.
- Touch targets ≥48 dp Android; keyboard/focus traversal on Windows.
- Color is never the only state indicator.
- Motion uses existing `AppMotion.fast/medium/slow`, is interruptible and respects reduced motion.
- Every surface defines loading, empty, error, forbidden, stale/conflict and retry behavior.
