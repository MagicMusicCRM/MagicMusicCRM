# Flutter — Phone input mask `+7 (XXX) XXX XX XX` (A2 / KVA-185) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build ONE reusable phone input that displays the Russian mask `+7 (XXX) XXX XX XX` while the user types, and emits/reads the canonical `+7XXXXXXXXXX` string (literal `+7` + exactly 10 digits) that the backend already expects. Wire it into the three lead/student create+edit call-sites that currently use a bare `TextField`/`TextFormField` with `keyboardType: TextInputType.phone`.

**Architecture:** A pure `RuPhoneTextInputFormatter` (`TextInputFormatter`) plus tiny pure helpers (`digitsToCanonical`, `canonicalToDisplay`, `digitsFrom`) live in a single new util file `lib/core/utils/ru_phone.dart` — the only source of truth for formatting, fully unit-testable with no Flutter widget tree. A thin `RuPhoneField` widget (`StatefulWidget`) wraps a `TextFormField`, applies the formatter, seeds its own controller from an `initialCanonical`, and calls `onCanonicalChanged(String canonical)` on every edit. The three call-sites swap their hand-rolled phone field for `RuPhoneField`:
- `create_student_dialog.dart` — controller-backed → use `RuPhoneField` + a local `String _canonicalPhone`.
- `leads_widget.dart` `_LeadDialog` (new-lead) — controller-backed → same.
- `lead_detail_dialog.dart` `_buildTextField('Телефон', 'phone', …)` (edit) → seed from `_leadData['phone']`, write canonical back into `_leadData['phone']` via `onCanonicalChanged`.

The formatter is the testable core (Task 1 + Task 2, unit + widget tests). The widget swaps (Task 3) are analyze-verified + on-device verified by the owner.

**Tech Stack:** Flutter, Riverpod 3.3.1, Material `TextFormField`, `flutter/services.dart` `TextInputFormatter`. No new package (the project already imports `flutter/services.dart` formatters — see `lib/features/auth/presentation/screens/email_otp_screen.dart:186-189`). Tests: `flutter test`; lint: `flutter analyze` (flutter at `/c/flutter/bin/flutter`).

**Linear:** KVA-185 (A2) under epic KVA-178 (A). Canonical format and the "display is a client concern (Task A2)" boundary are fixed by A1: `docs/superpowers/plans/2026-06-19-epic-a-task-a1-phone-normalization.md:15` — *"Canonical phone format stored in DB: `+7XXXXXXXXXX`… Display formatting `+7 (XXX) XXX XX XX` is a client concern (Task A2, not here)."*

## Global Constraints

- **Canonical out:** the widget emits `+7XXXXXXXXXX` (literal `+7` + exactly 10 digits) when 10 national digits are present, else `''` (empty) for a partial/empty number. The create call-sites already trim and pass `phone` straight to `createLead` / `createStudent` (`leads_widget.dart:240`, `create_student_dialog.dart:39`); the edit call-site writes into `_leadData['phone']` which flows to `updateLead` (`lead_detail_dialog.dart:167`). All three must receive canonical (or empty), never the masked display text.
- **Display in:** when seeding from an existing value (edit dialog has `_leadData['phone']` already canonical from A1 backfill), re-render it through the mask so the user sees `+7 (909) 123 45 67`.
- **Russian-only scope (matches A1):** the mask assumes RU `+7`. Strip all non-digits; treat a leading `8` or `7` as the country code (drop it) and keep the trailing 10 national digits; never guess/keep more than 10 national digits.
- **No over-engineering:** one formatter, one widget, one util file. Do not add a phone package, do not add country-picker UI, do not touch the employee/teacher create dialogs (out of scope — A2 is lead/student only).
- Reuse the existing input-formatter pattern (`FilteringTextInputFormatter`, `LengthLimitingTextInputFormatter` already used at `email_otp_screen.dart:186`). New util file mirrors `lib/core/utils/status_color.dart` (pure, top-level functions, no Flutter widgets) + its test mirrors `test/core/status_color_test.dart`.
- Run from repo root: `flutter analyze` (0 new issues in touched files) + `flutter test` (full suite stays green, currently 106).

---

## File Structure

- **Create** `lib/core/utils/ru_phone.dart` — pure helpers + `RuPhoneTextInputFormatter`.
- **Create** `lib/core/widgets/ru_phone_field.dart` — the reusable `RuPhoneField` widget.
- **Create** `test/core/utils/ru_phone_test.dart` — unit tests for the helpers + formatter.
- **Create** `test/core/widgets/ru_phone_field_test.dart` — widget test (type digits → mask shown + canonical emitted).
- **Modify** `lib/features/admin/presentation/widgets/create_student_dialog.dart` — swap the phone `TextField` for `RuPhoneField`.
- **Modify** `lib/features/manager/presentation/widgets/leads_widget.dart` — swap the `_LeadDialog` phone `TextField`.
- **Modify** `lib/features/manager/presentation/widgets/lead_detail_dialog.dart` — swap the `_buildTextField('Телефон', 'phone', …)` for `RuPhoneField`.

---

## Task 1: Pure RU phone formatter + helpers (util)

**Files:**
- Create: `lib/core/utils/ru_phone.dart`
- Test: `test/core/utils/ru_phone_test.dart`

**Interfaces (produces):**
- `String digitsFrom(String raw)` — every digit char of `raw`, in order (e.g. `"+7 (909) 12"` → `"790912"`).
- `String nationalDigits(String raw)` — the up-to-10 national digits: strip non-digits, then if it starts with `8` or `7` and has 11 digits drop that leading country digit; take at most the last 10. (e.g. `"89091234567"`→`"9091234567"`, `"+79091234567"`→`"9091234567"`, `"9091234567"`→`"9091234567"`, `"909123"`→`"909123"`).
- `String digitsToCanonical(String raw)` — `"+7" + nationalDigits` **only when** `nationalDigits.length == 10`, else `""`.
- `String canonicalToDisplay(String raw)` — render `raw` (canonical or partial) as `+7 (XXX) XXX XX XX`, filling only as many groups as there are national digits (so a partial `"909"` → `"+7 (909"`; empty → `""`).
- `class RuPhoneTextInputFormatter extends TextInputFormatter` — `formatEditUpdate` re-masks the new value and places the caret at end.

- [ ] **Step 1: Write the failing test**

Mirror `test/core/status_color_test.dart` (pure, `group`/`test`/`expect`, no `WidgetTester`).

```dart
// test/core/utils/ru_phone_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/utils/ru_phone.dart';

void main() {
  group('nationalDigits', () {
    test('drops country code variants and keeps 10 national digits', () {
      expect(nationalDigits('+7 (909) 123-45-67'), '9091234567');
      expect(nationalDigits('89091234567'), '9091234567');
      expect(nationalDigits('79091234567'), '9091234567');
      expect(nationalDigits('9091234567'), '9091234567');
    });
    test('keeps partial input untouched (no padding/guessing)', () {
      expect(nationalDigits('909123'), '909123');
      expect(nationalDigits(''), '');
    });
    test('never returns more than 10 digits', () {
      expect(nationalDigits('890912345670000').length <= 10, isTrue);
    });
  });

  group('digitsToCanonical', () {
    test('emits +7XXXXXXXXXX only when 10 national digits present', () {
      expect(digitsToCanonical('+7 (909) 123 45 67'), '+79091234567');
      expect(digitsToCanonical('89091234567'), '+79091234567');
    });
    test('returns empty for partial/empty', () {
      expect(digitsToCanonical('909123'), '');
      expect(digitsToCanonical(''), '');
    });
  });

  group('canonicalToDisplay', () {
    test('renders full canonical as the RU mask', () {
      expect(canonicalToDisplay('+79091234567'), '+7 (909) 123 45 67');
    });
    test('renders partials by group, no trailing separators added blindly', () {
      expect(canonicalToDisplay('909'), '+7 (909');
      expect(canonicalToDisplay('90912'), '+7 (909) 12');
      expect(canonicalToDisplay(''), '');
    });
  });

  group('RuPhoneTextInputFormatter', () {
    final f = RuPhoneTextInputFormatter();
    TextEditingValue v(String t) => TextEditingValue(text: t);

    test('masks raw digits as the user types', () {
      final out = f.formatEditUpdate(v(''), v('9091234567'));
      expect(out.text, '+7 (909) 123 45 67');
      expect(out.selection.baseOffset, out.text.length); // caret at end
    });
    test('normalizes a pasted 8XXXXXXXXXX', () {
      final out = f.formatEditUpdate(v(''), v('89091234567'));
      expect(out.text, '+7 (909) 123 45 67');
    });
    test('partial entry shows partial mask', () {
      final out = f.formatEditUpdate(v(''), v('909'));
      expect(out.text, '+7 (909');
    });
  });
}
```

- [ ] **Step 2: Run to verify failure** — `/c/flutter/bin/flutter test test/core/utils/ru_phone_test.dart` → FAIL (file/symbols undefined).

- [ ] **Step 3: Implement `lib/core/utils/ru_phone.dart`**

```dart
import 'package:flutter/services.dart';

/// All digit characters of [raw], in order.
String digitsFrom(String raw) => raw.replaceAll(RegExp(r'\D'), '');

/// Up to 10 Russian national digits (country code 7/8 stripped, never padded).
String nationalDigits(String raw) {
  var d = digitsFrom(raw);
  if (d.length == 11 && (d.startsWith('7') || d.startsWith('8'))) {
    d = d.substring(1);
  }
  if (d.length > 10) d = d.substring(d.length - 10);
  return d;
}

/// `+7XXXXXXXXXX` only when 10 national digits are present, else `''`.
String digitsToCanonical(String raw) {
  final d = nationalDigits(raw);
  return d.length == 10 ? '+7$d' : '';
}

/// Renders [raw] (canonical or partial) as `+7 (XXX) XXX XX XX`,
/// filling only the groups for which digits exist.
String canonicalToDisplay(String raw) {
  final d = nationalDigits(raw);
  if (d.isEmpty) return '';
  final b = StringBuffer('+7 (');
  b.write(d.substring(0, d.length < 3 ? d.length : 3));
  if (d.length >= 3) b.write(')');
  if (d.length > 3) b.write(' ${d.substring(3, d.length < 6 ? d.length : 6)}');
  if (d.length > 6) b.write(' ${d.substring(6, d.length < 8 ? d.length : 8)}');
  if (d.length > 8) b.write(' ${d.substring(8, d.length < 10 ? d.length : 10)}');
  return b.toString();
}

/// Re-masks the input on every edit and pins the caret to the end
/// (simple, predictable for a fixed-format field).
class RuPhoneTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final masked = canonicalToDisplay(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}
```

> Note: `canonicalToDisplay('909')` → `'+7 (909'` (no trailing `)` until the 3rd digit is committed; matches the test). `nationalDigits` is the single normalizer both the canonical and display paths share, so paste of `+7…`, `8…`, `7…`, or bare 10 digits all converge.

- [ ] **Step 4: Run tests** — `/c/flutter/bin/flutter test test/core/utils/ru_phone_test.dart` → green.

- [ ] **Step 5: Analyze** — `/c/flutter/bin/flutter analyze lib/core/utils/ru_phone.dart test/core/utils/ru_phone_test.dart` → no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/utils/ru_phone.dart test/core/utils/ru_phone_test.dart
git commit -m "feat(flutter): RU phone mask formatter + canonical helpers (KVA-185)"
```

---

## Task 2: `RuPhoneField` reusable widget + widget test

**Files:**
- Create: `lib/core/widgets/ru_phone_field.dart`
- Test: `test/core/widgets/ru_phone_field_test.dart`

**Interfaces (produces):** `class RuPhoneField extends StatefulWidget` with:
- `final String? initialCanonical` — seed value (canonical or empty); displayed via the mask.
- `final ValueChanged<String> onCanonicalChanged` — fires the canonical (`+7XXXXXXXXXX` or `''`) on every edit.
- `final String labelText` (default `'Телефон'`), `final InputDecoration? decoration` (optional override).

- [ ] **Step 1: Write the failing widget test**

Mirror the `WidgetTester` usage in `test/core/widgets/avatar_cropper_dialog_test.dart` (same folder/import style). Pump the field in a minimal `MaterialApp`, type digits, assert the masked text is shown and the latest canonical callback value.

```dart
// test/core/widgets/ru_phone_field_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';

void main() {
  testWidgets('types digits → shows mask + emits canonical', (tester) async {
    String? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RuPhoneField(
          onCanonicalChanged: (c) => captured = c,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), '9091234567');
    await tester.pump();

    expect(find.text('+7 (909) 123 45 67'), findsOneWidget);
    expect(captured, '+79091234567');
  });

  testWidgets('partial input emits empty canonical', (tester) async {
    String? captured = 'sentinel';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RuPhoneField(onCanonicalChanged: (c) => captured = c),
      ),
    ));
    await tester.enterText(find.byType(TextField), '909');
    await tester.pump();
    expect(captured, '');
  });

  testWidgets('seeds masked display from initialCanonical', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RuPhoneField(
          initialCanonical: '+79091234567',
          onCanonicalChanged: (_) {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('+7 (909) 123 45 67'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify failure** — `/c/flutter/bin/flutter test test/core/widgets/ru_phone_field_test.dart` → FAIL (widget undefined).

- [ ] **Step 3: Implement `lib/core/widgets/ru_phone_field.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:magic_music_crm/core/utils/ru_phone.dart';

/// Russian phone input: displays `+7 (XXX) XXX XX XX`, emits canonical
/// `+7XXXXXXXXXX` (or `''` while incomplete) via [onCanonicalChanged].
class RuPhoneField extends StatefulWidget {
  const RuPhoneField({
    super.key,
    required this.onCanonicalChanged,
    this.initialCanonical,
    this.labelText = 'Телефон',
    this.decoration,
  });

  final ValueChanged<String> onCanonicalChanged;
  final String? initialCanonical;
  final String labelText;
  final InputDecoration? decoration;

  @override
  State<RuPhoneField> createState() => _RuPhoneFieldState();
}

class _RuPhoneFieldState extends State<RuPhoneField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: canonicalToDisplay(widget.initialCanonical ?? ''),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.phone,
      inputFormatters: [RuPhoneTextInputFormatter()],
      decoration:
          widget.decoration ?? InputDecoration(labelText: widget.labelText),
      onChanged: (text) => widget.onCanonicalChanged(digitsToCanonical(text)),
    );
  }
}
```

> Uses a plain `TextField` (not `TextFormField`) so `find.byType(TextField)` in the test is unambiguous and so the call-sites that use `TextField` today drop in with no `Form` requirement. The controller is owned/disposed by the widget; the parent only keeps the canonical string.

- [ ] **Step 4: Run tests** — `/c/flutter/bin/flutter test test/core/widgets/ru_phone_field_test.dart` → green.

- [ ] **Step 5: Analyze** — `/c/flutter/bin/flutter analyze lib/core/widgets/ru_phone_field.dart test/core/widgets/ru_phone_field_test.dart` → no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/ru_phone_field.dart test/core/widgets/ru_phone_field_test.dart
git commit -m "feat(flutter): RuPhoneField reusable masked phone input + widget test (KVA-185)"
```

---

## Task 3: Wire `RuPhoneField` into the three lead/student forms

**Files:**
- Modify: `lib/features/admin/presentation/widgets/create_student_dialog.dart`
- Modify: `lib/features/manager/presentation/widgets/leads_widget.dart`
- Modify: `lib/features/manager/presentation/widgets/lead_detail_dialog.dart`

**Interfaces:** consumes `RuPhoneField` (Task 2). No backend/service change — the canonical string flows into the existing `createLead`/`createStudent`/`updateLead` calls unchanged.

- [ ] **Step 1: create_student_dialog.dart**

Currently the phone is a controller-backed `TextField` (`create_student_dialog.dart:72-76`) and the controller text is passed at `:39` (`phone: _phoneController.text`). Replace the controller with a canonical string.

1. Remove the `_phoneController` field (`:16`), its `dispose()` line (`:23`), and the `TextField` block (`:72-76`).
2. Add a state field: `String _canonicalPhone = '';`
3. At the create call (`:39`), change `phone: _phoneController.text,` → `phone: _canonicalPhone.isEmpty ? null : _canonicalPhone,` (matches the `phone: phone.isEmpty ? null : phone` convention at `lead_detail_dialog.dart:213`/`leads_widget.dart:1625`).
4. Replace the removed `TextField` with:

```dart
          RuPhoneField(
            onCanonicalChanged: (c) => _canonicalPhone = c,
          ),
```

5. Add the import at the top (after the existing imports):
```dart
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
```

- [ ] **Step 2: leads_widget.dart `_LeadDialog`**

The new-lead dialog uses `_phoneCtrl` (`leads_widget.dart:1898`, `:1903-1904` dispose) and emits `'phone': _phoneCtrl.text.trim()` (`:1946`); the result feeds `createLead(phone: result['phone']!, …)` (`:240`).

1. Remove `final _phoneCtrl = TextEditingController();` (`:1898`) and `_phoneCtrl.dispose();` (`:1904`).
2. Add `String _canonicalPhone = '';` to `_LeadDialogState`.
3. Replace the phone `TextField` (`:1922-1926`) with:

```dart
          RuPhoneField(
            onCanonicalChanged: (c) => _canonicalPhone = c,
          ),
```

4. Change the result map (`:1946`) `'phone': _phoneCtrl.text.trim(),` → `'phone': _canonicalPhone,` (already canonical or empty; no `.trim()` needed).
5. Add the import near the top of the file:
```dart
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
```

> `createLead` is called with `phone: result['phone']!` (`:240`). Empty string is still a valid argument here (no behavioural change vs. the old empty trim); leave `createLead` as-is.

- [ ] **Step 3: lead_detail_dialog.dart (edit)**

The phone here is map-backed via `_buildTextField('Телефон', 'phone', keyboard: TextInputType.phone)` (`lead_detail_dialog.dart:367-371`), which writes raw text into `_leadData['phone']` (`:545`); `_save` sends `phone: _leadData['phone']?.toString()` (`:167`). Replace just the phone row with a `RuPhoneField` seeded from the existing (canonical, post-A1) `_leadData['phone']`.

Replace the `_buildTextField('Телефон', 'phone', keyboard: TextInputType.phone,)` call (`:367-371`) with:

```dart
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: RuPhoneField(
                        initialCanonical: _leadData['phone']?.toString(),
                        onCanonicalChanged: (c) {
                          setState(() {
                            _leadData['phone'] = c.isEmpty ? null : c;
                            _edited = true;
                          });
                        },
                      ),
                    ),
```

(`_edited` + `setState` mirror the `onChanged` body in `_buildTextField` at `:544-547`.) Leave `_buildTextField` itself in place — it is still used for `Имя`/`Фамилия`/`Электронная почта` (`:365-376`). Add the import near the top:
```dart
import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';
```

- [ ] **Step 4: Analyze + full test suite**

```bash
/c/flutter/bin/flutter analyze lib/features/admin/presentation/widgets/create_student_dialog.dart \
  lib/features/manager/presentation/widgets/leads_widget.dart \
  lib/features/manager/presentation/widgets/lead_detail_dialog.dart
/c/flutter/bin/flutter test
```
→ 0 new issues in the touched files; full suite green (Task 1 + Task 2 tests included). Confirm no unused-import / unused-field warnings remain from the removed controllers.

- [ ] **Step 5: Commit**

```bash
git add lib/features/admin/presentation/widgets/create_student_dialog.dart \
  lib/features/manager/presentation/widgets/leads_widget.dart \
  lib/features/manager/presentation/widgets/lead_detail_dialog.dart
git commit -m "feat(flutter): use RuPhoneField in lead/student create+edit forms (KVA-185)"
```

---

## Self-Review

- **Single source of truth:** all masking/canonicalisation lives in `lib/core/utils/ru_phone.dart` (`nationalDigits` is the one normalizer the canonical + display paths share). The widget and every call-site only deal in canonical strings.
- **Canonical contract honoured:** emits `+7XXXXXXXXXX` per A1 (`…task-a1-phone-normalization.md:15`); partial/empty → `''`/`null` so the existing `createLead`/`createStudent`/`updateLead` calls behave as before (the null-when-empty convention copied from `lead_detail_dialog.dart:213`/`leads_widget.dart:1625`).
- **Display seeding:** the edit dialog re-masks the already-canonical `_leadData['phone']`, so an existing lead shows `+7 (909) 123 45 67` on open.
- **Testability:** the formatter + helpers are pure and unit-tested (no widget tree, mirrors `status_color_test.dart`); the widget has a `WidgetTester` test (type → mask + canonical, partial → empty, seed → masked), mirroring `avatar_cropper_dialog_test.dart`.
- **Reuse, not reinvent:** uses `flutter/services.dart` `TextInputFormatter` (same family already used at `email_otp_screen.dart:186`); no new package added to `pubspec.yaml`.
- **Scope discipline:** only the three lead/student call-sites change. Employee/teacher create dialogs and the bare phone *display* sites (`leads_widget.dart:1056` etc.) are untouched — A2 is lead/student input only.

## Risks / notes

- **Caret behaviour:** the formatter pins the caret to the end on every edit (acceptable for a fixed-format field; deleting from the middle re-masks from the resulting digits). If mid-string editing becomes a complaint, a digit-position-preserving caret can be added later without changing the public API.
- **`leads_widget.dart` is large** (~1950 lines) — make the three edits precisely at the cited line ranges; the `_LeadDialog` block is near the file end (`:1896-1954`). Re-run `flutter analyze` on that file specifically to catch a stray removed-controller reference.
- **On-device gate:** widget tests cover formatting/emission; the owner verifies on desktop+Android that the soft keyboard (`TextInputType.phone`) + mask feel right and that an edited lead saves the canonical value.
