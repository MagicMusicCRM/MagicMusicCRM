# Messenger v2 — Phase 1: Phone & Onboarding Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture a valid `+7` phone at signup and fix the profile phone field so deletion works and the format is enforced — the prerequisite for the messenger v2 phone→folder linking — and remove the stray glowing ellipse on the signup screen.

**Architecture:** Fix the shared RU phone logic (`lib/core/utils/ru_phone.dart`) that powers `RuPhoneField`; add the existing `RuPhoneField` to the registration screen and thread the canonical phone through `signUpWithPassword` → `POST /auth/signup`; backend stores the normalized phone on the profile at signup. Remove the registration screen's `RadialGradient` glow.

**Tech Stack:** Flutter (Dart) client; NestJS (TypeScript) + Postgres backend. Tests: `flutter test`, `jest`.

## Global Constraints

- Canonical phone format is `+7` followed by exactly 10 digits (`^\+7\d{10}$`). Display mask: `+7 (XXX) XXX XX XX`. Verbatim from spec §7.
- Backend phone normalization rule (existing, reuse): strip non-digits; if 11 digits starting with `8` → `7` + last 10; canonical store as digits. See `profile.service.ts normalizePhone`.
- Do NOT change `RuPhoneField`'s public API (`onCanonicalChanged`, `initialCanonical`, `labelText`, `decoration`, `international`) — other call sites depend on it (leads_widget, client_card, onboarding, admin dialogs, data_quality).
- Follow existing v7 auth field styling (`_V7Field`) on the registration screen.
- Commit after each task. Branch is `kvazar2727/leads-to-students-dnd`.

---

### Task 1: Fix the RU phone formatter (can't-delete / `+7` prefix double-count)

**Root cause:** `nationalDigits` (ru_phone.dart:15-22) only strips a leading `7`/`8` when the digit count is exactly 11. The field's text always contains the literal `+7` prefix, so at intermediate lengths the prefix `7` is counted as a national digit — digits are shifted and the field cannot be cleared (stuck at `+7 (7…`).

**Files:**
- Modify: `lib/core/utils/ru_phone.dart:15-22` (`nationalDigits`)
- Test: `test/core/utils/ru_phone_test.dart` (create if absent)

**Interfaces:**
- Produces: `nationalDigits(String) -> String` (≤10 national digits, country code stripped), `canonicalToDisplay`, `digitsToCanonical`, `RuPhoneTextInputFormatter` — signatures unchanged.

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/utils/ru_phone_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/core/utils/ru_phone.dart';

void main() {
  group('nationalDigits', () {
    test('does not double-count the +7 prefix at partial lengths', () {
      expect(nationalDigits('+7 (9'), '9');        // was '79' (bug)
      expect(nationalDigits('+7 (495) 12'), '49512');
    });
    test('clears to empty when only the prefix remains (deletion works)', () {
      expect(nationalDigits('+7 ('), '');          // was '7' (bug: stuck)
      expect(nationalDigits('+7'), '');
      expect(nationalDigits(''), '');
    });
    test('strips a leading 7 or 8 country code', () {
      expect(nationalDigits('+79991234567'), '9991234567');
      expect(nationalDigits('89991234567'), '9991234567');
      expect(nationalDigits('79991234567'), '9991234567');
    });
    test('keeps a full national number that does not start with 7/8', () {
      expect(nationalDigits('4951234567'), '4951234567');
    });
  });

  group('canonicalToDisplay / digitsToCanonical', () {
    test('formats a full canonical number', () {
      expect(canonicalToDisplay('+79991234567'), '+7 (999) 123 45 67');
    });
    test('emits canonical only when 10 national digits present', () {
      expect(digitsToCanonical('+7 (999) 123 45 67'), '+79991234567');
      expect(digitsToCanonical('+7 ('), '');
    });
  });

  group('RuPhoneTextInputFormatter (deletion)', () {
    test('backspace past the last digit re-masks to empty, not +7 (7', () {
      final f = RuPhoneTextInputFormatter();
      // user had '+7 (9', presses backspace -> Flutter proposes '+7 ('
      final out = f.formatEditUpdate(
        const TextEditingValue(text: '+7 (9'),
        const TextEditingValue(text: '+7 ('),
      );
      expect(out.text, '');
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/utils/ru_phone_test.dart`
Expected: FAIL — `nationalDigits('+7 (9')` returns `'79'`, `nationalDigits('+7 (')` returns `'7'`, formatter test returns `'+7 (7'`.

- [ ] **Step 3: Fix `nationalDigits`**

```dart
// lib/core/utils/ru_phone.dart  (replace nationalDigits, lines 14-22)
/// Up to 10 Russian national digits. The field always renders the `+7` country
/// code, so a single leading 7 or 8 (country code / old trunk prefix) is always
/// stripped — never padded. This keeps partial edits and deletion correct (the
/// prefix is not re-counted as a national digit).
String nationalDigits(String raw) {
  var d = digitsFrom(raw);
  if (d.startsWith('7') || d.startsWith('8')) {
    d = d.substring(1);
  }
  if (d.length > 10) d = d.substring(d.length - 10);
  return d;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/utils/ru_phone_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Run the full utils + any phone-dependent tests to check for regressions**

Run: `flutter test test/core`
Expected: PASS (no regressions in callers).

- [ ] **Step 6: Commit**

```bash
git add lib/core/utils/ru_phone.dart test/core/utils/ru_phone_test.dart
git commit -m "fix(phone): strip +7 prefix so the RU phone field can be cleared/edited

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Remove the glowing ellipse on the registration screen

**Files:**
- Modify: `lib/features/auth/presentation/screens/registration_screen.dart:83-94` (the `Scaffold` body `DecoratedBox`/`RadialGradient`)

**Interfaces:** none (UI-only).

- [ ] **Step 1: Replace the gradient background with the flat brand background**

Current (registration_screen.dart:83-94):
```dart
return Scaffold(
  backgroundColor: AppColor.bg,
  body: DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(0.0, -1.0),
        radius: 1.1,
        colors: [Color(0x1AC5A059), AppColor.bg],
        stops: [0.0, 0.6],
      ),
    ),
    child: SafeArea(
```

Replace with:
```dart
return Scaffold(
  backgroundColor: AppColor.bg,
  body: SafeArea(
```
…and remove the now-unbalanced closing `),` that closed the `DecoratedBox` (the `child: SafeArea(` becomes the direct `body:`). Verify the widget tree still balances (one fewer `)` at the end of the build method where `DecoratedBox` closed).

- [ ] **Step 2: Static analysis**

Run: `flutter analyze lib/features/auth/presentation/screens/registration_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Widget smoke test (screen builds without a RadialGradient)**

```dart
// test/features/auth/registration_no_ellipse_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/features/auth/presentation/screens/registration_screen.dart';

void main() {
  testWidgets('registration screen has no RadialGradient glow', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: RegistrationScreen()),
    ));
    expect(
      find.byWidgetPredicate((w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).gradient is RadialGradient),
      findsNothing,
    );
  });
}
```

- [ ] **Step 4: Run the widget test**

Run: `flutter test test/features/auth/registration_no_ellipse_test.dart`
Expected: PASS. (If `RegistrationScreen`'s const constructor differs, drop `const` — confirm the constructor signature in the file.)

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/presentation/screens/registration_screen.dart test/features/auth/registration_no_ellipse_test.dart
git commit -m "fix(auth): remove glowing radial-gradient ellipse on the signup screen

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Backend — accept & store a normalized phone at signup

**Files:**
- Modify: `server/src/auth/dto/signup.dto.ts` (add optional `phone`)
- Modify: `server/src/auth/auth.service.ts:63-129` (`signup` — store normalized phone on the profile)
- Test: `server/src/auth/auth.service.spec.ts`

**Interfaces:**
- Produces: `SignupDto { email, password, fullName, phone? }`; `signup(dto)` writes `app.profiles.phone` (normalized) when `dto.phone` present.

- [ ] **Step 1: Write the failing test**

```ts
// add to server/src/auth/auth.service.spec.ts
it("stores a normalized phone on the profile at signup", async () => {
  // arrange a service whose database.query is a jest.fn capturing calls
  // (mirror the existing signup test's harness in this file)
  const { service, query } = createAuthService(); // reuse the file's helper
  query.mockResolvedValue({ rows: [{ id: "u1", email: "a@b.c", role: "client",
    email_verified_at: null, is_app_account: true }] });

  await service.signup({ email: "a@b.c", password: "x".repeat(12),
    fullName: "Иван Петров", phone: "+79991234567" } as never);

  const profileInsert = query.mock.calls.find(
    (c) => typeof c[0] === "string" && c[0].includes("insert into app.profiles"),
  );
  expect(profileInsert).toBeTruthy();
  // phone param is the normalized '79991234567'
  expect(profileInsert![1]).toContain("79991234567");
});
```

(If the spec file has no `createAuthService` helper, model the mock on the existing signup test in the same file — same `DatabaseService`/`PasswordService`/`AuditService` stubs.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd server && npx jest --runInBand auth.service`
Expected: FAIL — profile insert has no phone param.

- [ ] **Step 3: Add `phone` to the DTO**

```ts
// server/src/auth/dto/signup.dto.ts — add inside SignupDto
import { IsEmail, IsOptional, IsString, MaxLength, MinLength } from "class-validator";
// ...
  @IsOptional()
  @IsString()
  @MaxLength(40)
  phone?: string;
```

- [ ] **Step 4: Store the normalized phone in `signup`**

Add a private normalizer (mirror profile.service) and include phone in the profile insert. In `auth.service.ts`:
```ts
private normalizePhone(phone?: string | null): string | null {
  const digits = (phone ?? "").replace(/\D/g, "");
  if (!digits) return null;
  if (digits.length === 11 && digits.startsWith("8")) return `7${digits.slice(1)}`;
  return digits;
}
```
Change the profile upsert (the `insert into app.profiles ... on conflict ...`) to also set `phone`:
```ts
const phone = this.normalizePhone(dto.phone);
await this.database.query(
  `
    insert into app.profiles (user_id, first_name, last_name, phone)
    values ($1, $2, $3, $4)
    on conflict (user_id) do update
    set first_name = excluded.first_name,
        last_name = excluded.last_name,
        phone = coalesce(excluded.phone, app.profiles.phone),
        updated_at = now()
  `,
  [user.id, firstName, lastName, phone],
);
```

- [ ] **Step 5: Run tests to verify pass + typecheck**

Run: `cd server && npx jest --runInBand auth.service && npm run typecheck`
Expected: PASS, typecheck clean.

- [ ] **Step 6: Commit**

```bash
git add server/src/auth/dto/signup.dto.ts server/src/auth/auth.service.ts server/src/auth/auth.service.spec.ts
git commit -m "feat(auth): accept and store a normalized phone at signup

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Flutter — thread the phone through `signUpWithPassword`

**Files:**
- Modify: `lib/features/auth/data/services/magic_auth_service.dart:148-175` (`signUpWithPassword` + POST body)
- Test: `test/features/auth/magic_auth_service_signup_phone_test.dart` (create; model on existing auth service tests using a fake Dio adapter)

**Interfaces:**
- Produces: `signUpWithPassword({ required email, required password, required fullName, String? phone })` → sends `phone` in `/auth/signup` body when non-null.

- [ ] **Step 1: Write the failing test** (assert the POST body contains `phone` when provided) — model the fake-adapter harness on `test/core/services/magic_messenger_service_test.dart`.

```dart
// test/features/auth/magic_auth_service_signup_phone_test.dart
// ... build a MagicApiClient with a fake HttpClientAdapter capturing the body ...
test('signup sends phone in the body', () async {
  // adapter captures POST /auth/signup body
  await service.signUpWithPassword(
    email: 'a@b.c', password: 'x'*12, fullName: 'Иван', phone: '+79991234567');
  expect(captured.body['phone'], '+79991234567');
});
```

- [ ] **Step 2: Run to verify fail** — `flutter test test/features/auth/magic_auth_service_signup_phone_test.dart` → FAIL (named param `phone` does not exist).

- [ ] **Step 3: Add the param + body field**

```dart
// magic_auth_service.dart
Future<MagicAuthResponse> signUpWithPassword({
  required String email,
  required String password,
  required String fullName,
  String? phone,
}) async {
  // ...
  final response = await _api.post<Map<String, dynamic>>(
    '/auth/signup',
    data: {
      'email': email.trim(),
      'password': password,
      'fullName': fullName.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    },
    authenticated: false,
  );
```

- [ ] **Step 4: Run to verify pass** — `flutter test test/features/auth/magic_auth_service_signup_phone_test.dart` → PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/data/services/magic_auth_service.dart test/features/auth/magic_auth_service_signup_phone_test.dart
git commit -m "feat(auth): pass phone through signUpWithPassword

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Flutter — add the phone field to the registration screen

**Files:**
- Modify: `lib/features/auth/presentation/screens/registration_screen.dart` (state field `_canonicalPhone`; a `RuPhoneField` between email and password; pass `phone` in `_register`)

**Interfaces:**
- Consumes: `RuPhoneField` (`onCanonicalChanged`), `signUpWithPassword({..., phone})` from Task 4.

- [ ] **Step 1: Add state + import**

At the top imports add `import 'package:magic_music_crm/core/widgets/ru_phone_field.dart';`. In the State class add: `String _canonicalPhone = '';`.

- [ ] **Step 2: Insert the phone field** (after the email `_V7Field`, before password). Use the v7 look via `decoration`:

```dart
const SizedBox(height: AppSpace.lg),
RuPhoneField(
  labelText: 'Номер телефона',
  onCanonicalChanged: (v) => _canonicalPhone = v,
),
```

(If `_V7Field` exposes a shared `InputDecoration`, pass it via `RuPhoneField(decoration: ...)` to match styling. Otherwise the default decoration is acceptable for this pass.)

- [ ] **Step 3: Validate + send phone in `_register`**

Before the service call, guard:
```dart
if (_canonicalPhone.isEmpty) {
  _showError('Введите корректный номер телефона в формате +7…');
  setState(() => _isLoading = false);
  return;
}
```
And pass it:
```dart
final response = await ref.read(magicAuthServiceProvider).signUpWithPassword(
  email: _emailController.text.trim(),
  password: password,
  fullName: _nameController.text.trim(),
  phone: _canonicalPhone,
);
```

- [ ] **Step 4: Analyze + widget test**

Run: `flutter analyze lib/features/auth/presentation/screens/registration_screen.dart`
Expected: `No issues found!`

Add a widget test that pumps the screen, enters a phone, and asserts a `RuPhoneField` is present and the submit is blocked when phone is empty (find the field by type; tap register with empty phone → error pill shows). Run it.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/presentation/screens/registration_screen.dart test/features/auth/
git commit -m "feat(auth): capture +7 phone on the signup screen

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Verify the profile phone field (RU mode + `+7` enforcement)

The profile screen already uses `RuPhoneField` (profile_screen.dart:397) — Task 1 fixes its deletion. This task confirms the profile opens in **RU-masked** mode (not `international`) for empty/new phones and rejects non-`+7` on save.

**Files:**
- Read/confirm: `lib/features/profile/presentation/screens/profile_screen.dart` around 90-170 and 393-410 (how `international` is chosen; how `_canonicalPhone` is validated before `updateMe`).
- Modify only if it opens `international: true` for empty phone, or saves a non-canonical value.

- [ ] **Step 1:** Read the `RuPhoneField` usage + the save path (`_canonicalPhone`, `international` flag derivation from `isCanonicalRu`).
- [ ] **Step 2:** If a new/empty phone opens in international mode, force RU mode for empty (`international: phone.isNotEmpty && !isCanonicalRu(phone)`), so new numbers are masked to `+7`.
- [ ] **Step 3:** Before `updateMe`, block save when `_canonicalPhone` is non-empty but not canonical (`isCanonicalRu`), with a clear error. Add/extend a widget test asserting a non-`+7` entry can't be saved.
- [ ] **Step 4:** `flutter analyze` the file; run the test.
- [ ] **Step 5: Commit**

```bash
git add lib/features/profile/presentation/screens/profile_screen.dart test/features/profile/
git commit -m "fix(profile): keep RU-masked +7 phone entry and enforce canonical on save

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review (coverage vs spec §7)

- Phone in signup → Tasks 3,4,5. ✓
- Profile delete bug → Task 1 (formatter), confirmed in Task 6. ✓
- `+7` enforcement → Task 1 (mask) + Task 5/6 (validation). ✓
- Remove ellipse → Task 2. ✓
- Phone normalization on store → Task 3 (backend). ✓

No placeholders; signatures (`nationalDigits`, `signUpWithPassword({..., phone})`, `SignupDto.phone`) consistent across tasks.

## After Phase 1

Run `flutter test` + `cd server && npm test` green, then rebuild artifacts only if we want to test signup on a device, OR proceed to Phase 2 (data wipe) before rebuilding. Phase 2 plan will be written next.
