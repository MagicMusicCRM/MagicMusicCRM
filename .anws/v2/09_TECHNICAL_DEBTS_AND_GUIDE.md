# 🧠 UI Lessons Learned & Model Guide

## 🎨 Design Philosophy: Flat Magic
The project has transitioned from a high-contrast Purple/Gold theme to a **Deep Charcoal & Sophisticated Gold** style.

### Key Rules:
- **Background**: Solid `#101012` (Deep Charcoal). Avoid gradients in small/auth screens; they create a "halo" effect that complicates the UI.
- **Accents**: Solid `#C5A059` (Sophisticated Gold). 
- **NO GLOW**: Strictly prohibited `boxShadow` on buttons and icons. It looks "cheap" on dark backgrounds unless handled with extreme care.
- **NO GLOSS**: Avoid complex gradients with white highlights to simulate gloss. A flat, matte look is preferred for a premium feel.
- **Desktop Layout**: Always wrap mobile-first content in `ConstrainedBox(maxWidth: 450)` and center it using `Center` or `Align`.

---

## ⚠️ Common Pitfalls (Technical)

### 1. Bracket Corruption in Flutter Widget Trees
When moving from a simple layout to a deeply nested one (e.g., adding `ConstrainedBox` inside a `SingleChildScrollView` inside a `SafeArea`), the likelihood of messing up closing brackets is **100%** if using partial edits (`replace_file_content`).
- **SOLUTION**: If the widget tree becomes deeper than 5-6 levels, use `write_to_file` to rewrite the entire `build` method or the entire file. This ensures syntax integrity.

### 2. Name Collision in Color Themes
Renaming colors in `TelegramColors.dart` (e.g., `brandGold` -> `primaryGold`) will break multiple files:
- `AppTheme.dart` (which maps legacy names)
- Custom widgets (like `CreateGroupDialog`)
- Features using specific color constants.
- **SOLUTION**: Always maintain **Backward Compatibility Aliases** in `TelegramColors.dart` during a transition.

### 3. Button Internal Padding/Elevation
Using `ElevatedButton` often adds default shadows and padding that clash with a "Flat" design.
- **SOLUTION**: Use a custom `Container` + `InkWell` pattern for full control over background color, border radius, and lack of shadows.

---

## ✅ Checklist for Future Tasks
- [ ] Check `AGENTS.md` for the latest "Magic Music Rules".
- [ ] Ensure all new UI text is in **Russian**.
- [ ] Verify `ConstrainedBox` on Windows/Desktop.
- [ ] Run `flutter run -d windows` early to catch layout issues.
