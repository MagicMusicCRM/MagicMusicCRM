# Flutter — «Клиенты» window (rename Лиды, Лиды/Ученики segments, per-branch Ученики board) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing «Лиды» nav item into a «Клиенты» window with a count badge fed by `GET /crm/leads/app-count`, a **Лиды / Ученики** segmented control at the top, the existing `LeadsWidget` kanban under **Лиды** (reused as-is), and a NEW **Ученики** board: a branch selector → columns = that branch's disciplines (`GET /crm/branches/:branchId/disciplines`), cards = students grouped by their primary discipline (`GET /crm/students/search`, grouped client-side by `custom_data['discipline']`).

**Architecture:** No new backend endpoint is required — every read already exists on prod:
- `GET /crm/leads/app-count` → `{ count }` (`crm.controller.ts:593`, `crm.service.ts:6191 countAppLeads`).
- `GET /crm/branches/:branchId/disciplines` → `{ items: [{ id, disciplineId, name, sortOrder }] }` (`crm.controller.ts:358`, `crm.service.ts:2665 listBranchDisciplines`).
- `GET /crm/students/search` → `{ items, totalCount }`, each item carrying `branchId` and `custom_data.discipline` (`crm.controller.ts:99`, `crm.service.ts:873 searchStudents` + `5291 toStudentSearchDto`; the discipline lives at `custom_data->>'discipline'`, see the filter at `crm.service.ts:4632`).

So the work is **Flutter-only**, in 3 layers, each TDD'd where it's a pure function and analyze-gated where it's a widget:
1. **Service** — add `getAppLeadsCount`, `listBranchDisciplines`, `listDisciplines` to `MagicCrmService` (manual `fromJson` like every other method), unit-tested against the existing `_FakeAdapter` harness in `test/core/services/magic_crm_service_test.dart`.
2. **Providers** — `appLeadsCountProvider`, `branchDisciplinesProvider(branchId)`, `studentBoardProvider(branchId)` (mirroring `leadBoardProvider` in `leads_providers.dart`), plus a pure `groupStudentsByDiscipline(...)` helper that's unit-tested.
3. **Widgets** — a new `ClientsWidget` (segmented control hosting `LeadsWidget` + the new `StudentsBoardWidget`), wired into `messenger_screen.dart` in place of the bare `LeadsWidget`, with the nav label renamed «Лиды»→«Клиенты» and a `Badge` driven by `appLeadsCountProvider`.

**Tech Stack:** Flutter, Riverpod 3.3.1, Dio. Tests: `flutter test`; lint: `flutter analyze` (flutter at `/c/flutter/bin/flutter`). No new dependency (no chart here — it's a kanban, reusing the `LeadsWidget` column/card visual language).

## Global Constraints

- **API client:** `ref.watch(magicCrmServiceProvider)` → `_api.get<Map<String, dynamic>>(path, queryParameters: {...})` (Dio, bearer auth handled by the client). Build `queryParameters` dropping null/empty, mirroring `searchStudents` (`magic_crm_service.dart:98`) and `listLeadBoard` (`:685`).
- **Response shapes (camelCase JSON from the server):**
  - app-count: `{ count: number }`.
  - branch disciplines: `{ items: [{ id, disciplineId, name, sortOrder }] }`.
  - disciplines: `{ items: [{ id, name }] }`.
  - student search item (already mapped by `_legacyStudentSearchItem`, `magic_crm_service.dart:1559`): exposes `id`, `first_name`, `last_name`, `phone`, `branch_id`, `branch_name`, `custom_data` (a `Map`), `groups_count`, `open_tasks_count`, `lessons_count`, `status`. The primary discipline is `custom_data['discipline']` (string, may be empty).
- **Legacy snake_case contract:** existing methods map camelCase→snake_case via `_legacy*` helpers. The NEW `getAppLeadsCount` returns a plain `int`; `listBranchDisciplines` / `listDisciplines` return `List<Map<String, dynamic>>` with the **camelCase keys preserved** as `{'id', 'discipline_id', 'name', 'sort_order'}` (snake) to match the project's snake-at-the-widget convention — mirror `_legacyBranch` shape style. Use numeric coercion `(v as num?)?.toInt()` for `count`/`sortOrder`.
- **Branch selector reuse:** the Ученики board's branch list comes from the same `listBranches()` the `LeadsWidget` already calls (`magic_crm_service.dart:461`); load it once in the board widget's `initState` (mirror `_loadFilterMetadata`, `leads_widget.dart:117`).
- **Card/column visual language:** mirror `_KanbanColumn` (`leads_widget.dart:830`) and `_LeadCard` (`:1024`) — fixed-width 300px columns in a horizontal `SingleChildScrollView`, a colored dot + count chip header, `Card` items. The Ученики board is **read-only for v1** (tap → open the student card via the existing `getStudentCard`/`StudentDetail` flow if present; NO drag-to-move between disciplines in this plan — disciplines aren't a status machine).
- **messenger_screen.dart is a shared file** (also touched by the analytics/overview navigation work). Keep edits surgical: only the `Text('Лиды')` label (`:1873` desktop, `:1941` mobile), the badge wrapper around the desktop destination icon, and swapping `const LeadsWidget()` (`:1800`) for `const ClientsWidget()`. Do not renumber tabs — the index stays `3`.
- Run from repo root: `flutter analyze` (0 new issues in touched files) + `flutter test` (full suite stays green; current Flutter suite is 106).

---

## File Structure

- **Modify** `lib/core/services/magic_crm_service.dart` — add `getAppLeadsCount`, `listBranchDisciplines`, `listDisciplines`.
- **Modify** `test/core/services/magic_crm_service_test.dart` — unit tests for the 3 new methods.
- **Create** `lib/features/manager/presentation/providers/students_board_providers.dart` — `appLeadsCountProvider`, `branchDisciplinesProvider`, `studentBoardProvider`, and the pure `groupStudentsByDiscipline` helper.
- **Create** `test/features/manager/students_board_grouping_test.dart` — unit tests for `groupStudentsByDiscipline`.
- **Create** `lib/features/manager/presentation/widgets/students_board_widget.dart` — the per-branch Ученики board.
- **Create** `lib/features/manager/presentation/widgets/clients_widget.dart` — the segmented Лиды/Ученики host.
- **Modify** `lib/features/messenger/presentation/screens/messenger_screen.dart` — rename label, add badge, swap body widget.

---

## Task 1: MagicCrmService methods + unit tests

**Files:**
- Modify: `lib/core/services/magic_crm_service.dart`, `test/core/services/magic_crm_service_test.dart`

**Interfaces (produces):** `getAppLeadsCount`, `listBranchDisciplines`, `listDisciplines` on `MagicCrmService`.

- [ ] **Step 1: Re-read the harness + a sample method**

Read the `_FakeAdapter`/`_FakeResponse`/`_client` harness (`test/core/services/magic_crm_service_test.dart:2256-2330`) — each `_FakeResponse(path, statusCode, body)` is consumed in order, `options.uri.path` is asserted equal to `path`, and `requests[i].queryParameters` captures the GET query. Read `listBranches` (`magic_crm_service.dart:461`) + `searchStudents` (`:83`) for the `_api.get` + non-null-query pattern, and `_legacyBranch` for the snake-key mapping style.

- [ ] **Step 2: Write the failing tests**

Add to `magic_crm_service_test.dart` (inside the `group('MagicCrmService', ...)`):

```dart
    test('getAppLeadsCount reads /crm/leads/app-count and returns the count', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/leads/app-count',
          statusCode: 200,
          body: {'count': 7},
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final count = await service.getAppLeadsCount();

      expect(count, 7);
      expect(adapter.requests.single.queryParameters, isEmpty);
    });

    test('getAppLeadsCount coerces a missing/string count to int', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/leads/app-count',
          statusCode: 200,
          body: {'count': '12'},
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      expect(await service.getAppLeadsCount(), 12);
    });

    test('listBranchDisciplines maps items to snake keys ordered by sort', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/branches/branch-a/disciplines',
          statusCode: 200,
          body: {
            'items': [
              {
                'id': 'bd-1',
                'disciplineId': 'disc-1',
                'name': 'Вокал',
                'sortOrder': 0,
              },
              {
                'id': 'bd-2',
                'disciplineId': 'disc-2',
                'name': 'Гитара',
                'sortOrder': 1,
              },
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final items = await service.listBranchDisciplines('branch-a');

      expect(items, hasLength(2));
      expect(items.first['discipline_id'], 'disc-1');
      expect(items.first['name'], 'Вокал');
      expect(items.first['sort_order'], 0);
      expect(adapter.requests.single.uri.path, '/crm/branches/branch-a/disciplines');
    });

    test('listDisciplines maps items to {id,name}', () async {
      final adapter = _FakeAdapter([
        _FakeResponse(
          path: '/crm/disciplines',
          statusCode: 200,
          body: {
            'items': [
              {'id': 'disc-1', 'name': 'Вокал'},
            ],
          },
        ),
      ]);
      final service = MagicCrmService(_client(adapter));

      final items = await service.listDisciplines();

      expect(items.single['id'], 'disc-1');
      expect(items.single['name'], 'Вокал');
    });
```

> `_CapturedRequest` exposes `queryParameters` and `body` only — to assert the path, the harness already asserts `options.uri.path == response.path` inside `fetch`, so the `expect(adapter.requests.single.uri.path, ...)` line above must instead rely on that built-in assertion (drop the explicit `.uri.path` access — `_CapturedRequest` has no `uri`). Keep the path assertion as the harness's responsibility and assert only on the mapped result + queryParameters. **Adjust the two `.uri.path` lines to remove them before running.**

- [ ] **Step 3: Run to verify failure** — `cd /c/Projects/MagicMusicCRM && /c/flutter/bin/flutter test test/core/services/magic_crm_service_test.dart` → FAIL (methods undefined).

- [ ] **Step 4: Implement the methods**

Add to `MagicCrmService` (place next to `listBranches`, near `magic_crm_service.dart:461`):

```dart
  Future<int> getAppLeadsCount() async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/leads/app-count',
    );
    return (response['count'] as num?)?.toInt() ??
        int.tryParse(response['count']?.toString() ?? '') ??
        0;
  }

  Future<List<Map<String, dynamic>>> listBranchDisciplines(
    String branchId,
  ) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/branches/$branchId/disciplines',
    );
    return _items(response).map((item) {
      return {
        'id': item['id'],
        'discipline_id': item['disciplineId'],
        'name': item['name'],
        'sort_order': (item['sortOrder'] as num?)?.toInt() ?? 0,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listDisciplines() async {
    final response = await _api.get<Map<String, dynamic>>('/crm/disciplines');
    return _items(response)
        .map((item) => {'id': item['id'], 'name': item['name']})
        .toList();
  }
```

(`_items(response)` is the existing helper that reads `response['items']` as a `List<Map<String,dynamic>>` — confirm its name/signature; it's used by `listStudents` at `:80`.)

- [ ] **Step 5: Run tests + analyze** — `/c/flutter/bin/flutter test test/core/services/magic_crm_service_test.dart` → green; `/c/flutter/bin/flutter analyze lib/core/services/magic_crm_service.dart` → no new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/magic_crm_service.dart test/core/services/magic_crm_service_test.dart
git commit -m "feat(flutter): MagicCrmService getAppLeadsCount + listBranchDisciplines/listDisciplines + tests"
```

---

## Task 2: Providers + pure grouping helper (+ unit tests)

**Files:**
- Create: `lib/features/manager/presentation/providers/students_board_providers.dart`, `test/features/manager/students_board_grouping_test.dart`

**Interfaces (produces):** `appLeadsCountProvider`, `branchDisciplinesProvider`, `studentBoardProvider`, `groupStudentsByDiscipline`.
**Consumes:** Task-1 service methods + existing `searchStudents`.

- [ ] **Step 1: Write the failing test for the pure grouping helper**

`groupStudentsByDiscipline` takes the branch's disciplines (`[{discipline_id, name, sort_order}]`) and the searched students (`[{custom_data:{discipline:..}, ...}]`) and returns ordered columns `[{discipline_id, name, students:[...]}]` plus a trailing "Без направления" column for students whose `custom_data['discipline']` is empty or matches no column (matched case-insensitively by **name**, since student `custom_data.discipline` stores the discipline *name*, not the id — see `crm.service.ts:4632`). Create `test/features/manager/students_board_grouping_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_music_crm/features/manager/presentation/providers/students_board_providers.dart';

void main() {
  group('groupStudentsByDiscipline', () {
    final disciplines = [
      {'discipline_id': 'd1', 'name': 'Вокал', 'sort_order': 0},
      {'discipline_id': 'd2', 'name': 'Гитара', 'sort_order': 1},
    ];

    test('groups students into discipline columns by name, case-insensitive', () {
      final students = [
        {'id': 's1', 'first_name': 'Аня', 'custom_data': {'discipline': 'Вокал'}},
        {'id': 's2', 'first_name': 'Боря', 'custom_data': {'discipline': 'гитара'}},
        {'id': 's3', 'first_name': 'Вера', 'custom_data': {'discipline': 'Вокал'}},
      ];

      final columns = groupStudentsByDiscipline(disciplines, students);

      expect(columns.map((c) => c['name']), ['Вокал', 'Гитара', 'Без направления']);
      expect((columns[0]['students'] as List).map((s) => s['id']), ['s1', 's3']);
      expect((columns[1]['students'] as List).single['id'], 's2');
      expect((columns[2]['students'] as List), isEmpty);
    });

    test('puts unmatched/empty-discipline students in the trailing column', () {
      final students = [
        {'id': 's4', 'first_name': 'Гена', 'custom_data': {'discipline': 'Фортепиано'}},
        {'id': 's5', 'first_name': 'Дина', 'custom_data': {}},
        {'id': 's6', 'first_name': 'Женя'},
      ];

      final columns = groupStudentsByDiscipline(disciplines, students);

      final fallback = columns.last;
      expect(fallback['name'], 'Без направления');
      expect((fallback['students'] as List).map((s) => s['id']), ['s4', 's5', 's6']);
    });

    test('keeps discipline column order by sort_order', () {
      final unordered = [
        {'discipline_id': 'd2', 'name': 'Гитара', 'sort_order': 1},
        {'discipline_id': 'd1', 'name': 'Вокал', 'sort_order': 0},
      ];

      final columns = groupStudentsByDiscipline(unordered, const []);

      expect(columns.map((c) => c['name']), ['Вокал', 'Гитара', 'Без направления']);
    });
  });
}
```

- [ ] **Step 2: Run to verify failure** — `/c/flutter/bin/flutter test test/features/manager/students_board_grouping_test.dart` → FAIL (file/symbol missing).

- [ ] **Step 3: Implement the providers + helper**

Create `lib/features/manager/presentation/providers/students_board_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

/// Badge count for the «Клиенты» nav item — leads created from the app.
final appLeadsCountProvider = FutureProvider<int>((ref) {
  return ref.watch(magicCrmServiceProvider).getAppLeadsCount();
});

/// The disciplines configured for a branch (the Ученики board's columns).
final branchDisciplinesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, branchId) {
  return ref.watch(magicCrmServiceProvider).listBranchDisciplines(branchId);
});

/// The Ученики board for a branch: discipline columns + grouped students.
final studentBoardProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
  ref,
  branchId,
) async {
  final service = ref.watch(magicCrmServiceProvider);
  final disciplines = await service.listBranchDisciplines(branchId);
  final search = await service.searchStudents(branchId: branchId, limit: 100);
  final students = (search['items'] as List).cast<Map<String, dynamic>>();
  return groupStudentsByDiscipline(disciplines, students);
});

/// Pure: order the branch disciplines by sort_order, bucket students into the
/// column whose name matches `custom_data['discipline']` (case-insensitive),
/// and append a trailing "Без направления" column for the rest.
List<Map<String, dynamic>> groupStudentsByDiscipline(
  List<Map<String, dynamic>> disciplines,
  List<Map<String, dynamic>> students,
) {
  final ordered = [...disciplines]
    ..sort((a, b) =>
        ((a['sort_order'] as num?) ?? 0).compareTo((b['sort_order'] as num?) ?? 0));

  final columns = <Map<String, dynamic>>[
    for (final d in ordered)
      {
        'discipline_id': d['discipline_id'],
        'name': d['name'],
        'students': <Map<String, dynamic>>[],
      },
  ];
  final fallback = <String, dynamic>{
    'discipline_id': null,
    'name': 'Без направления',
    'students': <Map<String, dynamic>>[],
  };

  final byName = <String, List<Map<String, dynamic>>>{
    for (final c in columns)
      (c['name'] as String).toLowerCase(): c['students'] as List<Map<String, dynamic>>,
  };

  for (final student in students) {
    final custom = student['custom_data'];
    final discipline = custom is Map
        ? custom['discipline']?.toString().trim() ?? ''
        : '';
    final bucket = byName[discipline.toLowerCase()];
    if (discipline.isEmpty || bucket == null) {
      (fallback['students'] as List<Map<String, dynamic>>).add(student);
    } else {
      bucket.add(student);
    }
  }

  return [...columns, fallback];
}
```

- [ ] **Step 4: Run tests + analyze** — `/c/flutter/bin/flutter test test/features/manager/students_board_grouping_test.dart` → green; `/c/flutter/bin/flutter analyze lib/features/manager/presentation/providers/students_board_providers.dart` → no new issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/manager/presentation/providers/students_board_providers.dart test/features/manager/students_board_grouping_test.dart
git commit -m "feat(flutter): students-board providers + pure groupStudentsByDiscipline + tests"
```

---

## Task 3: StudentsBoardWidget (per-branch Ученики board)

**Files:**
- Create: `lib/features/manager/presentation/widgets/students_board_widget.dart`

**Consumes:** `studentBoardProvider`, `listBranches()` (for the selector).

- [ ] **Step 1: Read the column/card source to mirror**

Read `_KanbanColumn` (`leads_widget.dart:830-1020`) and `_LeadCard` (`:1024-1442`) — copy the visual structure (300px column, dot+title+count chip header, `Card` items, `_IconBadge` for branch). Read `_loadFilterMetadata` (`leads_widget.dart:117`) for the `listBranches()` load + `setState` pattern, and the board error/empty handling in `LeadsWidget.build` (`:700-738`).

- [ ] **Step 2: Implement the widget**

Create `lib/features/manager/presentation/widgets/students_board_widget.dart` — a `ConsumerStatefulWidget` that:
1. In `initState`, calls `listBranches(limit: 100)` and sets `_selectedBranchId` to the first branch's `id`.
2. Renders a header `Row` with a `DropdownButtonFormField<String>` branch selector (options from `_branches`, mirror `_filterDropdown` in `leads_widget.dart:646`) + a refresh `IconButton` that `ref.invalidate(studentBoardProvider(_selectedBranchId!))`.
3. If `_selectedBranchId == null` (no branches yet): a centered "Нет филиалов" placeholder.
4. Otherwise `ref.watch(studentBoardProvider(_selectedBranchId!))` with `.when`:
   - `loading:` `const KanbanSkeleton()` (already imported in `leads_widget.dart:14` from `core/widgets/skeletons.dart`).
   - `error:` the same retry block shape as `LeadsWidget` (icon + "Не удалось загрузить учеников" + «Повторить» button that invalidates the provider).
   - `data: (columns)` → a horizontal `Scrollbar`+`SingleChildScrollView` of `_DisciplineColumn`s (mirror `LeadsWidget.build`'s board `Row`, `:758-820`).

Column widget (`_DisciplineColumn`, private, mirror `_KanbanColumn` header but **no DragTarget** — read-only):

```dart
class _DisciplineColumn extends StatelessWidget {
  final String name;
  final List<Map<String, dynamic>> students;
  final ValueChanged<Map<String, dynamic>> onTap;
  const _DisciplineColumn({
    required this.name,
    required this.students,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(127),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.school_rounded, size: 14,
                    color: AppTheme.primaryPurple),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${students.length}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: students.length,
              itemBuilder: (context, index) =>
                  _StudentCard(student: students[index], onTap: onTap),
            ),
          ),
        ],
      ),
    );
  }
}
```

Card widget (`_StudentCard`, private) — name from `first_name`+`last_name`, phone subtitle, a `branch_name` `_IconBadge`-style chip, and the open-tasks/lessons counts as small metric chips (mirror `_LeadCard`'s `_MetricBadge` usage, `leads_widget.dart:1386`). Tap → `onTap(student)`. For v1, `onTap` shows the student via the existing detail flow if one is wired in `ManagerOverviewWidget`/students screens; otherwise a minimal read-only `AlertDialog` listing name/phone/branch/groups (so the board is self-contained — do NOT block on a not-yet-existing student dialog). **Confirm during Step 1** whether a `StudentDetailDialog`/students card route exists; reuse it if so, else the inline dialog.

Imports: `package:flutter/material.dart`, `package:flutter_riverpod/flutter_riverpod.dart`, `app_theme.dart`, `skeletons.dart`, `magic_crm_service.dart` (for `magicCrmServiceProvider`/`listBranches`), and `students_board_providers.dart`.

- [ ] **Step 3: Analyze** — `/c/flutter/bin/flutter analyze lib/features/manager/presentation/widgets/students_board_widget.dart` → 0 issues. (No widget test — the board renders network data; the grouping logic is already unit-tested in Task 2, and the visual board is owner-verified on-device, consistent with the analytics-dashboard plan's stance that chart/kanban widget tests are low-value.)

- [ ] **Step 4: Commit**

```bash
git add lib/features/manager/presentation/widgets/students_board_widget.dart
git commit -m "feat(flutter): per-branch Ученики board (branch selector -> discipline columns)"
```

---

## Task 4: ClientsWidget (Лиды/Ученики segmented host)

**Files:**
- Create: `lib/features/manager/presentation/widgets/clients_widget.dart`

**Consumes:** `LeadsWidget`, `StudentsBoardWidget`.

- [ ] **Step 1: Implement the segmented host**

Create `lib/features/manager/presentation/widgets/clients_widget.dart` — a `StatefulWidget` (no providers of its own) holding `int _segment = 0`, rendering a top `SegmentedButton<int>` (Лиды / Ученики) and below it the matching body. Keep both children alive across switches with an `IndexedStack` so the kanban scroll position and `LeadsWidget`'s loaded-more state survive a toggle:

```dart
import 'package:flutter/material.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/leads_widget.dart';
import 'package:magic_music_crm/features/manager/presentation/widgets/students_board_widget.dart';

class ClientsWidget extends StatefulWidget {
  const ClientsWidget({super.key});

  @override
  State<ClientsWidget> createState() => _ClientsWidgetState();
}

class _ClientsWidgetState extends State<ClientsWidget> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.people_outline_rounded),
                  label: Text('Лиды'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.school_outlined),
                  label: Text('Ученики'),
                ),
              ],
              selected: {_segment},
              onSelectionChanged: (s) => setState(() => _segment = s.first),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _segment,
            children: const [LeadsWidget(), StudentsBoardWidget()],
          ),
        ),
      ],
    );
  }
}
```

> `LeadsWidget` keeps its own `FloatingActionButton` (it returns a `Scaffold`). Inside an `IndexedStack` that's fine — the FAB renders within the lead segment's own `Scaffold`. Verify on-device the FAB doesn't bleed into the Ученики segment (IndexedStack keeps the off-screen child built but not visible; if the FAB shows through, gate `LeadsWidget` behind `Offstage`/`Visibility` on `_segment == 0` instead — note this as the fallback).

- [ ] **Step 2: Analyze** — `/c/flutter/bin/flutter analyze lib/features/manager/presentation/widgets/clients_widget.dart` → 0 issues.

- [ ] **Step 3: Commit**

```bash
git add lib/features/manager/presentation/widgets/clients_widget.dart
git commit -m "feat(flutter): ClientsWidget — Лиды/Ученики segmented control"
```

---

## Task 5: Wire into messenger_screen.dart (rename + badge + body swap)

**Files:**
- Modify: `lib/features/messenger/presentation/screens/messenger_screen.dart`

**SHARED FILE — keep edits surgical.** This file is also touched by overview-navigation work; do not renumber CRM tabs (the Клиенты index stays `3`).

- [ ] **Step 1: Swap the body widget (tab index 3)**

In `_buildCrmBody` (`messenger_screen.dart:1800`), replace `3 => const LeadsWidget(),` with `3 => const ClientsWidget(),`. Add the import:
`import 'package:magic_music_crm/features/manager/presentation/widgets/clients_widget.dart';` (the `leads_widget.dart` import can stay if still referenced elsewhere; remove it only if it becomes unused — `flutter analyze` will flag an unused import).

- [ ] **Step 2: Rename + badge on the desktop NavigationRail destination**

In `_desktopCrmDestinations()` (`:1867-1874`), the «Лиды» destination currently is:

```dart
      NavigationRailDestination(
        icon: Icon(Icons.people_outline_rounded),
        selectedIcon: Icon(
          Icons.people_rounded,
          color: TelegramColors.brandPurple,
        ),
        label: Text('Лиды'),
      ),
```

Change `label: Text('Лиды')` → `label: Text('Клиенты')`, and wrap the unselected `icon` in a `Badge` driven by `appLeadsCountProvider`. Because `_desktopCrmDestinations()` is a method on a `ConsumerState`, read the count via `ref.watch` (the class is `ConsumerState`, `messenger_screen.dart:60`) and make the destination list non-`const`:

```dart
      NavigationRailDestination(
        icon: _leadsBadge(const Icon(Icons.people_outline_rounded)),
        selectedIcon: const Icon(
          Icons.people_rounded,
          color: TelegramColors.brandPurple,
        ),
        label: const Text('Клиенты'),
      ),
```

Note: `_desktopCrmDestinations()` currently returns a `const [...]`. Removing `const` from the returned literal (and from sibling entries that now mix in the non-const badge entry) is required. Keep the other destinations as plain (non-const) `NavigationRailDestination(...)` — the simplest diff is to drop the leading `const` on the `return [...]` and let the unchanged entries stay as-is (they're still cheap to construct each build).

Add the helper on the state class (near `_mobileCrmItems`, `:1910`):

```dart
  Widget _leadsBadge(Widget child) {
    final count = ref.watch(appLeadsCountProvider).asData?.value ?? 0;
    if (count <= 0) return child;
    return Badge(
      label: Text('$count'),
      backgroundColor: AppTheme.danger,
      child: child,
    );
  }
```

Add imports: `appLeadsCountProvider` from `students_board_providers.dart`, and `AppTheme` from `core/theme/app_theme.dart` if not already imported (it is used widely — confirm via the existing import block; `TelegramColors` is already imported).

- [ ] **Step 3: Rename the mobile bottom-nav label**

In `_mobileCrmItems()` (`:1941`), change:
`BottomNavigationBarItem(icon: Icon(Icons.people_rounded), label: 'Лиды'),`
→ wrap the icon in `_leadsBadge(...)` and set `label: 'Клиенты'`:
`BottomNavigationBarItem(icon: _leadsBadge(const Icon(Icons.people_rounded)), label: 'Клиенты'),`
and drop `const` from the returned `[...]` list (same reason as Step 2). The teacher-role branch of both nav builders is untouched.

- [ ] **Step 4: Update the stale reference in the contacts hint**

The snackbar at `messenger_screen.dart:298` says `«Лиды»`. Update its copy to `«Клиенты»` so the in-app guidance matches the renamed section.

- [ ] **Step 5: Analyze + full test suite**

Run from repo root: `/c/flutter/bin/flutter analyze` (0 new issues in `messenger_screen.dart`, `clients_widget.dart`, `students_board_widget.dart`, `students_board_providers.dart`, `magic_crm_service.dart`) and `/c/flutter/bin/flutter test` (full suite green — Task 1 + Task 2 unit tests pass, no existing widget-test regressions; if any widget test pumped `LeadsWidget` via the old tab path, it still resolves because index 3 now builds `ClientsWidget` which renders `LeadsWidget` inside the Лиды segment).

- [ ] **Step 6: Commit**

```bash
git add lib/features/messenger/presentation/screens/messenger_screen.dart
git commit -m "feat(flutter): rename «Лиды»→«Клиенты» nav + app-leads count badge + ClientsWidget body (KVA-184)"
```

---

## Self-Review

- **Backend untouched / no migration:** every read (`/crm/leads/app-count`, `/crm/branches/:branchId/disciplines`, `/crm/students/search`) already exists on prod and is role-gated (`assertCanReadOperationalData` / `assertCanListStudents`). The Ученики board is composed client-side from `searchStudents` + `listBranchDisciplines` — **no new `GET /crm/students/board` endpoint is needed**, avoiding a VPS deploy. (If, on-device, the client-side grouping proves too heavy for very large branches, a future `GET /crm/students/board?branchId=` that does the bucketing server-side is the documented follow-up — but it is out of scope here.)
- **Testability:** the two pure layers — the 3 service methods (path + mapping + numeric coercion) and `groupStudentsByDiscipline` (name-match, fallback column, sort order) — are unit-tested against the existing `_FakeAdapter` harness and plain Dart. The widgets are analyze-gated + owner-verified on-device, matching the project's stated stance on kanban/chart widget tests.
- **Grouping correctness:** student `custom_data.discipline` stores the discipline **name** (confirmed by `crm.service.ts:4632` and the convert-to-student path `leads_widget.dart:1611`), so the helper matches by name case-insensitively, with an explicit "Без направления" column for empty/unmatched — no student is silently dropped.
- **Reuse, not reinvent:** the Ученики board mirrors `_KanbanColumn`/`_LeadCard` (300px columns, header chip, `Card` items) minus drag (disciplines aren't a status machine); the branch selector mirrors `_filterDropdown`; loading/error mirror `LeadsWidget.build`. `LeadsWidget` is reused verbatim under the Лиды segment.
- **Shared-file risk (messenger_screen.dart):** edits are limited to one body line (`:1800`), two nav labels + a badge wrapper (`:1873`, `:1941`), one snackbar string (`:298`), and one small `_leadsBadge` helper — no tab renumbering, so this composes with concurrent overview-navigation edits with at most a trivial merge.
- **Badge behavior:** shows only when count > 0, reads `appLeadsCountProvider` (a plain `FutureProvider<int>`); a load error/`AsyncLoading` falls back to "no badge" (`asData?.value ?? 0`), so the rail never throws on a slow/failed count.

## Dependency note

This is the «Клиенты» window sub-plan of the «Клиенты» program. It depends on Task 1's service methods being present before Tasks 2–5. Sibling sub-plans (drag-to-convert lead→student, the unified client card with imported tasks/comments + «Семья») layer on top of this window and the existing `getLeadCard`/`getStudentCard` payloads. A server-side `GET /crm/students/board` and drag-to-move-discipline are explicitly deferred.
