# V6-305 — Typography, responsive and reduced-motion baseline

**Дата:** 2026-08-04
**Статус:** PASS

## Результат

- Official Inter 4.1 variable regular/italic bundled locally under SIL OFL; light/dark themes resolve both text themes to `Inter` without a runtime font download.
- Existing v7 palette and spacing remain authoritative; no new color system or UI framework was introduced.
- Motion stays on the existing 160/240/300 ms tokens. Shared sheet, drawer, toast and workspace transitions resolve to zero when `disableAnimations` is enabled.
- Critical error/retry state fits 360/600/840/1200 at 200% text scale; long Russian breadcrumb nodes fit 840/1000/1200 through the existing responsive context-bar policy.
- Focus/semantic labels and lifecycle text/badges preserve meaning without relying on color alone.

## Gate

```text
visual_baseline_test.dart -d windows
PASS — 6/6: Inter, canonical motion, widths 360/600/840/1200,
       200% text, reduced motion

desktop_context_bar_test.dart
PASS — long Russian nodes at 840/1000/1200

accessibility + lesson palette regressions
PASS — focus/semantic activation and text-backed state meaning

flutter analyze
PASS — No issues found

flutter test
PASS — 538/538

git diff -- server
PASS — empty
```
