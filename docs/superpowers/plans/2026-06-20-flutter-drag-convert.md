# Flutter — Drag-to-convert lead → student (branch + discipline modal) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a manager convert a lead into a student by **dragging the lead card from the «Лиды» board onto the «Ученики» board** (and via an explicit «Convert» menu action). The drop opens a modal that picks a **branch** (from `listBranches`) and a **discipline** (from that branch's `GET /crm/branches/:branchId/disciplines`). On confirm it calls `createStudent(leadId:…, branchId, discipline)`, then performs an **optimistic move** of the card into the Ученики board with an **undo SnackBar**.

**Architecture:** Today the lead→student conversion already exists in two places — `lead_detail_dialog.dart::_convertToStudent` (lib/features/manager/presentation/widgets/lead_detail_dialog.dart:189) and `leads_widget.dart::_convertToStudent` (lib/features/manager/presentation/widgets/leads_widget.dart:1555) — but both just confirm and call `createStudent` with whatever `branch_id`/`discipline` the lead already carries; **neither lets the user pick branch + discipline at convert time**. This plan adds:
1. A thin `MagicCrmService.listBranchDisciplines(branchId)` method (the Flutter service has **no** branch-disciplines call yet — verified by grep; the server endpoint exists at crm.controller.ts:358 / crm.service.ts:2665 returning `{ items: [{ id, disciplineId, name, sortOrder }] }`).
2. A reusable **`ConvertLeadDialog`** widget: branch dropdown (defaults to the lead's `branch_id`), discipline dropdown that reloads when the branch changes, returns `{branchId, discipline}` on confirm. It calls `createStudent(leadId, branchId, discipline)` itself and surfaces errors, mirroring the existing convert flow's payload shape.
3. A **`ConvertLeadController`** mixin/helper on `LeadsWidget` that opens the dialog, then does the **optimistic hide + undo SnackBar** (reusing the existing `_hiddenLeadIds` / `_pendingLeadIds` machinery already in `leads_widget.dart`).
4. The **drag target**: the new Ученики board (the «Клиенты» window — a **separate sub-plan**, not built here) will host a `DragTarget<String>` that, on `onAcceptWithDetails`, calls back into this convert flow. Because that board does not exist yet, this plan wires the **menu action** end-to-end now and **exposes a single public entry-point** (`LeadsWidget` → `convertLeadToStudent(lead)`) plus a documented callback contract so the Ученики board can call it once it lands. The drag *source* (`LongPressDraggable<String>` on `_LeadCard`, leads_widget.dart:1073) already emits the lead id as drag data — no change needed there.

The service layer (Task 1) is fully unit-tested (mock API client, mirroring `test/core/services/magic_crm_service_test.dart`). The dialog (Task 2) gets a widget test with overridden providers. The board glue (Task 3) is analyzed + on-device verified by the owner.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod`), Dio. Tests: `flutter test`; lint: `flutter analyze` (flutter at `/c/flutter/bin/flutter`). No new dependency.

## Global Constraints

- **API client pattern:** `ref.read(magicCrmServiceProvider)` → `_api.get<Map<String, dynamic>>(path, queryParameters: {...})`. Path-param endpoints interpolate (`'/crm/branches/$branchId/disciplines'`), mirroring `getStudentCard` (magic_crm_service.dart:164). Parse list payloads with the existing `_items(response)` helper (magic_crm_service.dart:1489).
- **Branch-disciplines server contract (live):** `GET /crm/branches/:branchId/disciplines` → `{ items: [{ id, disciplineId, name, sortOrder }] }`. `:branchId` is run through `ParseUUIDPipe` server-side, so **only send a real UUID** (the lead-card `branch_id` is a UUID; the leads-board filter uses `''` for "all" — never pass an empty string).
- **createStudent payload (existing):** `createStudent({required firstName, lastName, phone, email, status='active', leadId, customDataPatch})` (magic_crm_service.dart:129). Discipline + branch ride in `customDataPatch` as `{'discipline': <name>, 'branchId': <uuid>}` — this matches both existing convert flows (leads_widget.dart:1614-1618, lead_detail_dialog.dart:200-206) and the `'creates student from lead with conversion payload'` test (magic_crm_service_test.dart:980).
- **Lead field names are snake_case** on the board map: `id`, `name`, `last_name`, `phone`, `email`, `branch_id`, `linked_student_id`, and `custom_data['discipline']` (see `_LeadCard.build`, leads_widget.dart:1051-1071). Only offer convert when `linked_student_id` is empty (already the gate at leads_widget.dart:1287).
- **Optimistic move + undo:** reuse the in-state sets already on `_LeadsWidgetState`: `_hiddenLeadIds` (hide the card from columns, leads_widget.dart:784) and `_pendingLeadIds` (block re-drag / show spinner). On success hide the card and show a SnackBar with an **«Отменить»** action (4s); on Undo, just un-hide locally (the created student is **not** deleted — Undo only reverts the visual move, with a clarifying SnackBar). On error, un-hide + red error SnackBar (mirror `_showError`, leads_widget.dart:329).
- **Colours/theme:** reuse `AppTheme.primaryPurple` / `AppTheme.success` / `AppTheme.danger` and the existing dialog idioms (`DropdownButtonFormField`, `FilledButton.icon`) — do **not** introduce new styles.
- Run from repo root: `flutter analyze` (0 new issues in touched files) + `flutter test` (full suite stays green).

---

## File Structure

- **Modify** `lib/core/services/magic_crm_service.dart` — add `listBranchDisciplines(String branchId)`.
- **Modify** `test/core/services/magic_crm_service_test.dart` — unit test for the new method.
- **Create** `lib/features/manager/presentation/widgets/convert_lead_dialog.dart` — the branch + discipline modal that performs the `createStudent` call and returns the created student (or `null` on cancel).
- **Create** `test/features/manager/convert_lead_dialog_test.dart` — widget test (branch/discipline dropdowns, discipline reload on branch change, confirm payload).
- **Modify** `lib/features/manager/presentation/widgets/leads_widget.dart` — replace the two confirm-only `_convertToStudent` paths with `ConvertLeadDialog`; add the public `convertLeadToStudent(lead)` entry-point + optimistic-move/undo glue; export a typed callback for the future Ученики DragTarget.

> **Shared-file note:** `leads_widget.dart` is the shared file with the «Клиенты» window sub-plan (which adds the Ученики board / DragTarget). This plan only *adds* a public entry-point and *replaces the body* of the existing `_convertToStudent` helpers — it does not restructure the board, the kanban columns, or the drag *source*, minimising merge conflict surface. Coordinate ordering: land Task 1 + Task 2 first (independent), then Task 3.

---

## Task 1: `MagicCrmService.listBranchDisciplines` + unit test

**Files:**
- Modify: `lib/core/services/magic_crm_service.dart`, `test/core/services/magic_crm_service_test.dart`

**Interfaces (produces):** `Future<List<Map<String, dynamic>>> listBranchDisciplines(String branchId)` on `MagicCrmService`.

- [ ] **Step 1: Read the pattern**

Read `listBranches` (magic_crm_service.dart:461) + `_items` (magic_crm_service.dart:1489) + the `'maps CRM reference data to legacy keys'` test (magic_crm_service_test.dart:138). The new method is a sibling of `listBranches`: GET a path-param endpoint, map `items` to snake_case keys.

- [ ] **Step 2: Write the failing test**

Add to `magic_crm_service_test.dart` (mirror the `_FakeAdapter` style; the adapter asserts `options.uri.path` and records the request):

```dart
test('maps branch disciplines to selectable options', () async {
  final adapter = _FakeAdapter([
    _FakeResponse(
      path: '/crm/branches/branch-a/disciplines',
      statusCode: 200,
      body: {
        'items': [
          {
            'id': 'bd-a',
            'disciplineId': 'disc-a',
            'name': 'Вокал',
            'sortOrder': 0,
          },
          {
            'id': 'bd-b',
            'disciplineId': 'disc-b',
            'name': 'Фортепиано',
            'sortOrder': 1,
          },
        ],
      },
    ),
  ]);
  final service = MagicCrmService(_client(adapter));

  final disciplines = await service.listBranchDisciplines('branch-a');

  expect(disciplines.length, 2);
  expect(disciplines.first['discipline_id'], 'disc-a');
  expect(disciplines.first['name'], 'Вокал');
  expect(disciplines.first['sort_order'], 0);
  expect(adapter.requests.single.queryParameters, isEmpty);
});
```

- [ ] **Step 3: Run to verify failure** — `/c/flutter/bin/flutter test test/core/services/magic_crm_service_test.dart` → FAIL (`listBranchDisciplines` undefined).

- [ ] **Step 4: Implement the method**

Add to `MagicCrmService`, right after `updateBranch` (so it sits with the branch methods, magic_crm_service.dart:484):

```dart
  Future<List<Map<String, dynamic>>> listBranchDisciplines(
    String branchId,
  ) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/branches/$branchId/disciplines',
    );
    return _items(response).map(_legacyBranchDiscipline).toList();
  }
```

And add the private mapper next to `_legacyBranch` (magic_crm_service.dart:1744):

```dart
  Map<String, dynamic> _legacyBranchDiscipline(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'discipline_id': item['disciplineId'],
      'name': item['name'],
      'sort_order': item['sortOrder'] ?? 0,
    };
  }
```

- [ ] **Step 5: Run tests + analyze** — `/c/flutter/bin/flutter test test/core/services/magic_crm_service_test.dart` → green; `/c/flutter/bin/flutter analyze lib/core/services/magic_crm_service.dart` → no new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/magic_crm_service.dart test/core/services/magic_crm_service_test.dart
git commit -m "feat(flutter): MagicCrmService.listBranchDisciplines + test"
```

---

## Task 2: `ConvertLeadDialog` (branch + discipline modal) + widget test

**Files:**
- Create: `lib/features/manager/presentation/widgets/convert_lead_dialog.dart`
- Create: `test/features/manager/convert_lead_dialog_test.dart`

**Interfaces (consumes):** `MagicCrmService.listBranches`, `MagicCrmService.listBranchDisciplines` (Task 1), `MagicCrmService.createStudent`.
**Interfaces (produces):** `ConvertLeadDialog` `ConsumerStatefulWidget` + a static `show(...)` returning `Future<Map<String, dynamic>?>` (the created student map, or `null` if cancelled/failed).

- [ ] **Step 1: Read the patterns to mirror**

Read `lead_detail_dialog.dart::_fetchMetadata` + `_buildBranchDropdown` (lib/features/manager/presentation/widgets/lead_detail_dialog.dart:127, :671) for the branch-dropdown idiom, and `leads_widget.dart::_convertToStudent` (leads_widget.dart:1555) for the `createStudent` payload shape (firstName fallback, `customDataPatch` with `discipline`/`level`/`branchId`). The new dialog generalises that: branch + discipline become **user-picked** instead of inherited.

- [ ] **Step 2: Write the failing widget test**

`test/features/manager/convert_lead_dialog_test.dart` — pump the dialog with a `ProviderScope` override that injects a fake `MagicCrmService`. Use a hand-rolled fake (no codegen) implementing the 3 methods. Assert: (a) branch dropdown lists the branches; (b) selecting a branch loads + lists its disciplines; (c) confirm calls `createStudent` with `leadId`, `customDataPatch['branchId']`, `customDataPatch['discipline']`. Skeleton:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/convert_lead_dialog.dart';

class _FakeCrm implements MagicCrmService {
  Map<String, dynamic>? createStudentArgs;

  @override
  Future<List<Map<String, dynamic>>> listBranches({int limit = 100}) async => [
        {'id': 'branch-a', 'name': 'Центр'},
        {'id': 'branch-b', 'name': 'Восток'},
      ];

  @override
  Future<List<Map<String, dynamic>>> listBranchDisciplines(String branchId) async =>
      branchId == 'branch-a'
          ? [
              {'id': 'bd-a', 'discipline_id': 'd1', 'name': 'Вокал', 'sort_order': 0},
            ]
          : [
              {'id': 'bd-b', 'discipline_id': 'd2', 'name': 'Гитара', 'sort_order': 0},
            ];

  @override
  Future<Map<String, dynamic>> createStudent({
    required String firstName,
    String? lastName,
    String? phone,
    String? email,
    String status = 'active',
    String? leadId,
    Map<String, dynamic>? customDataPatch,
  }) async {
    createStudentArgs = {
      'firstName': firstName,
      'leadId': leadId,
      'customDataPatch': customDataPatch,
    };
    return {'id': 'student-a', 'lead_id': leadId};
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  testWidgets('picks branch + discipline and converts', (tester) async {
    final fake = _FakeCrm();
    Map<String, dynamic>? result;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [magicCrmServiceProvider.overrideWithValue(fake)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await ConvertLeadDialog.show(
                      context,
                      lead: const {
                        'id': 'lead-a',
                        'name': 'Анна',
                        'last_name': 'Иванова',
                        'phone': '+79990000000',
                        'branch_id': 'branch-a',
                        'custom_data': {'discipline': 'Вокал'},
                      },
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Branch + its disciplines are loaded; Вокал is selectable.
    expect(find.text('Центр'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Создать ученика'));
    await tester.pumpAndSettle();

    expect(fake.createStudentArgs!['leadId'], 'lead-a');
    final patch = fake.createStudentArgs!['customDataPatch'] as Map<String, dynamic>;
    expect(patch['branchId'], 'branch-a');
    expect(patch['discipline'], 'Вокал');
    expect(result!['id'], 'student-a');
  });
}
```

> `magicCrmServiceProvider.overrideWithValue` requires `MagicCrmService` to be the provided type — confirm the provider's type when implementing (it is `Provider<MagicCrmService>`). If `MagicCrmService` has many members, the `noSuchMethod` fallback keeps the fake small.

- [ ] **Step 3: Run to verify failure** — `/c/flutter/bin/flutter test test/features/manager/convert_lead_dialog_test.dart` → FAIL (`ConvertLeadDialog` undefined).

- [ ] **Step 4: Implement `ConvertLeadDialog`**

`lib/features/manager/presentation/widgets/convert_lead_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';
import 'package:magic_music_crm/core/theme/app_theme.dart';

/// Modal that converts a lead into a student, letting the user pick the
/// target branch + discipline. Returns the created student map, or null if
/// cancelled / failed.
class ConvertLeadDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> lead;
  const ConvertLeadDialog({super.key, required this.lead});

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Map<String, dynamic> lead,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ConvertLeadDialog(lead: lead),
    );
  }

  @override
  ConsumerState<ConvertLeadDialog> createState() => _ConvertLeadDialogState();
}

class _ConvertLeadDialogState extends ConsumerState<ConvertLeadDialog> {
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _disciplines = [];
  String? _branchId;
  String? _discipline; // discipline NAME (createStudent stores the name)
  bool _loadingBranches = true;
  bool _loadingDisciplines = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _branchId = widget.lead['branch_id']?.toString();
    final cd = widget.lead['custom_data'];
    if (cd is Map) _discipline = cd['discipline']?.toString();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final branches =
          await ref.read(magicCrmServiceProvider).listBranches(limit: 100);
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _loadingBranches = false;
        // Keep the inherited branch only if it is actually in the list.
        if (_branchId != null &&
            !_branches.any((b) => b['id'].toString() == _branchId)) {
          _branchId = null;
        }
      });
      if (_branchId != null) await _loadDisciplines(_branchId!);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingBranches = false;
          _error = 'Не удалось загрузить филиалы: $e';
        });
      }
    }
  }

  Future<void> _loadDisciplines(String branchId) async {
    setState(() {
      _loadingDisciplines = true;
      _disciplines = [];
    });
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .listBranchDisciplines(branchId);
      if (!mounted) return;
      setState(() {
        _disciplines = items;
        _loadingDisciplines = false;
        // Drop a stale inherited discipline that this branch doesn't offer.
        if (_discipline != null &&
            !_disciplines.any((d) => d['name']?.toString() == _discipline)) {
          _discipline = null;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDisciplines = false;
          _error = 'Не удалось загрузить направления: $e';
        });
      }
    }
  }

  Future<void> _convert() async {
    final firstNameRaw = (widget.lead['name'] ?? '').toString().trim();
    final lastName = (widget.lead['last_name'] ?? '').toString().trim();
    final phone = (widget.lead['phone'] ?? '').toString().trim();
    final email = (widget.lead['email'] ?? '').toString().trim();

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final patch = <String, dynamic>{};
      if (_branchId != null && _branchId!.isNotEmpty) {
        patch['branchId'] = _branchId;
      }
      if (_discipline != null && _discipline!.isNotEmpty) {
        patch['discipline'] = _discipline;
      }
      patch['sourceLeadId'] = widget.lead['id'].toString();

      final student = await ref.read(magicCrmServiceProvider).createStudent(
            firstName: firstNameRaw.isEmpty ? 'Без имени' : firstNameRaw,
            lastName: lastName.isEmpty ? null : lastName,
            phone: phone.isEmpty ? null : phone,
            email: email.isEmpty ? null : email,
            leadId: widget.lead['id'].toString(),
            customDataPatch: patch.isEmpty ? null : patch,
          );
      if (mounted) Navigator.pop(context, student);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Не удалось конвертировать: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = [
      widget.lead['name'],
      widget.lead['last_name'],
    ].where((v) => v != null && '$v'.trim().isNotEmpty).join(' ');

    return AlertDialog(
      title: const Text('Сделать учеником'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Лид «$name» будет конвертирован в ученика.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
            if (_loadingBranches)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _branchId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Филиал'),
                items: _branches
                    .map(
                      (b) => DropdownMenuItem(
                        value: b['id'].toString(),
                        child: Text(
                          b['name']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (v) {
                        setState(() => _branchId = v);
                        if (v != null) _loadDisciplines(v);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('disc:$_branchId'),
                initialValue: _discipline,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Направление',
                  suffixIcon: _loadingDisciplines
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  helperText: _branchId == null
                      ? 'Сначала выберите филиал'
                      : (_disciplines.isEmpty && !_loadingDisciplines
                          ? 'У филиала нет направлений'
                          : null),
                ),
                items: _disciplines
                    .map(
                      (d) => DropdownMenuItem(
                        value: d['name']?.toString(),
                        child: Text(
                          d['name']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving || _branchId == null
                    ? null
                    : (v) => setState(() => _discipline = v),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.danger, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
          onPressed: _saving || _loadingBranches ? null : _convert,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.school_rounded, size: 18),
          label: const Text('Создать ученика'),
        ),
      ],
    );
  }
}
```

> **Decisions baked in (match existing code):** discipline is stored by **name** (string), as `custom_data['discipline']` is read as a string everywhere (leads_widget.dart:1070, lead_detail_dialog excluded-keys). Branch + discipline are **optional** at the API level (so a branch with no configured disciplines still converts) — but the button stays enabled to allow that, matching the permissive existing flow. `sourceLeadId` is added to the patch to mirror `lead_detail_dialog.dart:206`.

- [ ] **Step 5: Run the widget test + analyze** — `/c/flutter/bin/flutter test test/features/manager/convert_lead_dialog_test.dart` → green; `/c/flutter/bin/flutter analyze lib/features/manager/presentation/widgets/convert_lead_dialog.dart test/features/manager/convert_lead_dialog_test.dart` → no new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/manager/presentation/widgets/convert_lead_dialog.dart test/features/manager/convert_lead_dialog_test.dart
git commit -m "feat(flutter): ConvertLeadDialog — pick branch + discipline at lead→student convert + widget test"
```

---

## Task 3: Wire the dialog into `LeadsWidget` (menu + drag entry-point + optimistic move/undo)

**Files:**
- Modify: `lib/features/manager/presentation/widgets/leads_widget.dart`

**Interfaces (consumes):** `ConvertLeadDialog.show` (Task 2).
**Interfaces (produces):** public `LeadsWidget` behaviour `convertLeadToStudent(lead)` reachable from the kanban menu action `'convert'` **and** callable by the future Ученики `DragTarget` (documented contract below).

- [ ] **Step 1: Add the public convert entry-point with optimistic move + undo**

Add a method on `_LeadsWidgetState` (sibling of `_moveStatus` / `_deleteLead`, leads_widget.dart:247-316), reusing the existing `_hiddenLeadIds` / `_pendingLeadIds` machinery:

```dart
  Future<void> convertLeadToStudent(Map<String, dynamic> lead) async {
    final id = lead['id']?.toString() ?? '';
    if (id.isEmpty || _pendingLeadIds.contains(id)) return;
    if ((lead['linked_student_id']?.toString() ?? '').isNotEmpty) {
      _showError('Лид уже связан с учеником');
      return;
    }

    final student = await ConvertLeadDialog.show(context, lead: lead);
    if (student == null || !mounted) return; // cancelled or failed in-dialog

    // Optimistic move: hide the card from the Лиды board immediately.
    setState(() {
      _hiddenLeadIds.add(id);
      _pendingLeadIds.add(id);
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Лид конвертирован в ученика'),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Отменить',
          textColor: Colors.white,
          onPressed: () {
            // Undo only reverts the visual move — the student stays created.
            if (!mounted) return;
            setState(() => _hiddenLeadIds.remove(id));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Карточка лида возвращена. Ученик остаётся созданным — '
                  'удалите его вручную при необходимости.',
                ),
              ),
            );
          },
        ),
      ),
    );

    // Reconcile with the server: the lead now carries linked_student_id, so a
    // board refresh keeps it out of the funnel on its own.
    _refreshBoard();
    try {
      await ref.read(leadBoardProvider(_filters).future);
    } catch (_) {
      // Refresh failure is non-fatal; the optimistic hide already moved it.
    }
    if (!mounted) return;
    setState(() => _pendingLeadIds.remove(id));
  }
```

> **Why hide-not-restyle:** the Ученики board is a separate window/sub-plan, so there is no in-place "move the card to the other column" within `LeadsWidget`. Hiding from the Лиды funnel is the correct optimistic effect here; the server's `linked_student_id` makes the hide durable after refresh. When the Ученики board lands, its `DragTarget.onAcceptWithDetails` will call `convertLeadToStudent(lead)` and additionally optimistically insert the new student into its own column.

- [ ] **Step 2: Route the kanban menu action through the new entry-point**

`_LeadCard` is a `ConsumerWidget` that does not hold a ref to the state; the existing `'convert'` menu case calls the card-local `_convertToStudent(context, ref)` (leads_widget.dart:1233-1234). Replace that local method's body to call `ConvertLeadDialog` directly (the card has no access to `_LeadsWidgetState`, so it does its own convert + relies on `onRefresh()` for the board reconcile — same pattern the card already uses for tasks/comments). Replace the **entire** `_LeadCard._convertToStudent` method (leads_widget.dart:1555-1649) with:

```dart
  Future<void> _convertToStudent(BuildContext context, WidgetRef ref) async {
    if ((lead['linked_student_id']?.toString() ?? '').isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лид уже связан с учеником')),
      );
      return;
    }
    final student = await ConvertLeadDialog.show(context, lead: lead);
    if (student == null) return; // cancelled / failed in-dialog
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Лид конвертирован в ученика'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    onRefresh();
  }
```

> This removes the now-duplicate confirm dialog + manual `createStudent` payload assembly from the card (the dialog owns that). The undo affordance lives on the state-level `convertLeadToStudent` path (Step 1), used by the future DragTarget; the menu action keeps the simpler refresh-only flow (no local `_hiddenLeadIds` access from the card). Keep `linked_student_id`-gated menu visibility unchanged (leads_widget.dart:1287).

- [ ] **Step 3: Update `lead_detail_dialog.dart`'s convert button (optional, same task) — OUT OF SCOPE confirm**

Do **not** change `lead_detail_dialog.dart::_convertToStudent` in this task — it lives inside the open detail dialog where branch/discipline are already editable inline (the «Основной филиал» dropdown, lead_detail_dialog.dart:397). Leaving it avoids nested-dialog UX. Note this explicitly in the commit body.

- [ ] **Step 4: Add the import**

Add to the top of `leads_widget.dart` (alongside the existing `lead_detail_dialog.dart` import, leads_widget.dart:5):

```dart
import 'package:magic_music_crm/features/manager/presentation/widgets/convert_lead_dialog.dart';
```

- [ ] **Step 5: Analyze + full suite**

Run: `/c/flutter/bin/flutter analyze lib/features/manager/presentation/widgets/leads_widget.dart` (0 new issues — watch for now-unused imports/helpers removed with the old `_convertToStudent`; `intl`/`AppTheme` stay used) and `/c/flutter/bin/flutter test` (full suite green — the deleted confirm-dialog block had no test; the new path is covered by Task 2's dialog test). On-device: drag a lead card and use the «Сделать учеником» menu item to confirm the modal opens, branch→discipline reloads, and the card leaves the funnel with an undo SnackBar.

- [ ] **Step 6: Commit**

```bash
git add lib/features/manager/presentation/widgets/leads_widget.dart
git commit -m "feat(flutter): lead→student convert via ConvertLeadDialog with optimistic move + undo; expose convertLeadToStudent for the Ученики DragTarget (KVA-184)"
```

---

## Self-Review

- **Scope match:** convert modal (branch dropdown from `listBranches`, discipline dropdown from `listBranchDisciplines`), the `createStudent(leadId, branchId, discipline)` call, optimistic move + undo SnackBar — all delivered. The drag *source* already exists (`LongPressDraggable<String>` emitting the lead id, leads_widget.dart:1073); the drag *target* (Ученики `DragTarget`) is the dependency's job — this plan exposes `convertLeadToStudent(lead)` as the exact callback it will invoke.
- **Grounded in real code:** every cited line was read (`createStudent` magic_crm_service.dart:129, `listBranches` :461, `_items` :1489, `_legacyBranch` :1744; both existing `_convertToStudent` paths; the leads board drag/optimistic machinery; the server endpoint crm.controller.ts:358 / crm.service.ts:2665 returning `{items:[{id,disciplineId,name,sortOrder}]}`). No invented endpoints — `listBranchDisciplines` is genuinely missing on the Flutter side and is the one new service method.
- **Testability:** service method = unit test (mock adapter, mirrors the existing harness exactly, including the path-param URL assertion); dialog = widget test (branch→discipline reload + convert payload) with a `noSuchMethod` fake. Board glue = analyze + on-device (drag/optimistic UI is low-value to widget-test, stated explicitly).
- **No backend change, no migration:** read-only consumption of a live endpoint + an existing POST. Nothing touches SQL.
- **Reuse, not reinvent:** dialog reuses the `DropdownButtonFormField` + `_loadBranches` idiom from `lead_detail_dialog.dart`; optimistic move reuses `_hiddenLeadIds`/`_pendingLeadIds`/`_refreshBoard` already on `_LeadsWidgetState`; theme colours unchanged.

## Dependency note

**Depends on the «Клиенты» window (Ученики board) sub-plan** for the actual cross-board *drag-and-drop* drop target. This plan is **planned independently and can be implemented now** (Tasks 1-2 fully; Task 3 wires the menu action + exposes the entry-point) but the literal drag-onto-Ученики gesture is **executed after** that board exists. Integration contract for the Ученики board sub-plan: its `DragTarget<String>` `onAcceptWithDetails: (d) => <leadsWidgetState>.convertLeadToStudent(leadById(d.data))` — or, if the boards are sibling widgets, lift `convertLeadToStudent` into a shared Riverpod controller/notifier (note for the integrator: prefer the notifier if the two boards don't share a `State`). **Shared file:** `leads_widget.dart` — keep this plan's edits additive (new public method + replaced helper bodies + one import) to minimise conflicts with the board sub-plan's structural changes.
