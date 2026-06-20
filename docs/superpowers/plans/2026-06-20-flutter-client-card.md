# Flutter — Unified Client Card (tasks, comments, family, status history) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the client card (lead + student) a real "single source of truth" by: (1) verifying + cleanly surfacing the imported **tasks** (485) and **comments** (909 student notes + 782 lead comments) already returned by `getLeadCard`/`getStudentCard`; (2) adding a **«Семья»** section backed by the existing `GET /crm/families/by-entity/{entityType}/{entityId}`; (3) adding an **«История статусов»** section backed by the existing `GET /crm/leads/{leadId}/status-history`; (4) ensuring the **student** detail screen has a comparable card (it already exists as `StudentDetailScreen` with a History tab — add «Семья» to it so leads and students stay symmetric).

**Architecture:** The two backend endpoints we need are **already deployed** (`crm.controller.ts:606` `leads/:leadId/status-history`, `crm.controller.ts:687` `families/by-entity/:entityType/:entityId`). No server work and no migration. The whole change is **Flutter-only**: add two thin typed methods to `MagicCrmService` (manual `fromJson`-style mapping mirroring the existing `_legacy*` transforms), unit-test them against the existing fake-adapter harness in `test/core/services/magic_crm_service_test.dart`, then render two new sections in `lead_detail_dialog.dart` (the shared file) and add the «Семья» section to `student_detail_screen.dart`. The service layer is fully unit-tested; the dialog/screen changes are analyzed + verified on-device by the owner (Flutter widget tests for these large stateful dialogs are low-value).

**Tech Stack:** Flutter, Riverpod 3.x, Dio, `intl`. Tests: `flutter test`; lint: `flutter analyze` (flutter at `/c/flutter/bin/flutter`).

**Backend (already live on prod — read-only consumption):**
- `GET /crm/leads/{id}/card` → `{ lead, linkedStudents, otherLeads, comments[], tasks[], trials[], timeline[] }` (`crm.service.ts:4031`). Already consumed by `getLeadCard` (`magic_crm_service.dart:717`).
- `GET /crm/leads/{leadId}/status-history` → `{ items: [{ id, oldStatus, newStatus, oldOwnerId, newOwnerId, changedBy, changedAt, reasonId, comment }] }` (`crm.service.ts:4134` `listLeadStatusHistory`; controller `crm.controller.ts:606`). **No Flutter method yet.**
- `GET /crm/families/by-entity/{entityType}/{entityId}` → `{ family: { id, name, branchId, primaryPayerMemberId } | null, members: [{ id, entityType, entityId, role, isPrimaryContact, name }] }` (`crm.service.ts:5874` `getFamilyForEntity`; controller `crm.controller.ts:687`). **No Flutter method yet.**

## Global Constraints

- API client: `ref.read(magicCrmServiceProvider)` → `_api.get<Map<String, dynamic>>(path, queryParameters: {...})` (Dio, bearer auth handled by the client). The service base host already targets `/crm/...` paths (see existing methods, e.g. `getLeadCard` at `magic_crm_service.dart:717`).
- New service methods return plain `Map<String, dynamic>` / `List<Map<String,dynamic>>` with snake_case keys, mirroring the existing `_legacy*` transforms (`magic_crm_service.dart:1956` `_legacyTask`, `:2009` `_legacyComment`, `:2027` `_legacyTimelineItem`). Use `_mapList` (`:1495`) and `_items` (`:1489`) helpers; reuse `_splitName` only if a full name needs splitting (members already arrive as a single `name`).
- The server returns **camelCase** JSON; the transforms convert to the **snake_case** keys the widgets read. Keep numeric coercion defensive where needed (`num.tryParse(...)`).
- The lead card already loads via `_fetchCard()` (`lead_detail_dialog.dart:87`) and stores `_leadCard`. The new sections fetch family + status-history in `initState` alongside the existing fetches and store them in `setState`. Do **not** block the dialog on these (each section renders its own loading/empty state, mirroring `_buildAggregateCard` at `:717`).
- Reuse existing visual idioms: `_sectionTitle` (`lead_detail_dialog.dart:471`), `_miniSection` (`:959`), `_summaryChip` (`:814`), `AppTheme.primaryPurple` / `AppTheme.primaryGold`, `DateFormat('dd.MM.yyyy HH:mm')`. No new dependency, no new chart.
- Run from repo root: `flutter analyze` (0 new issues in touched files) + `flutter test` (full suite stays green: server 279, Flutter 106 → 106 + the new service tests).
- **Shared file:** `lib/features/manager/presentation/widgets/lead_detail_dialog.dart` is touched by this stream and possibly others — keep edits additive (new private methods + new section calls in the existing `build` column); do not reorder or rename existing members.

---

## File Structure

- **Modify** `lib/core/services/magic_crm_service.dart` — add `getLeadStatusHistory(String leadId)` and `getFamilyForEntity({required String entityType, required String entityId})` + two private transforms `_legacyStatusHistoryItem` / `_legacyFamilyMember`.
- **Modify** `test/core/services/magic_crm_service_test.dart` — unit tests for both new methods (path + mapped keys), using the existing `_FakeAdapter`/`_FakeResponse`/`_client` harness (`:2256`–`:2330`).
- **Modify** `lib/features/manager/presentation/widgets/lead_detail_dialog.dart` (**shared**) — clarify the tasks/comments rendering and add the «Семья» + «История статусов» sections.
- **Modify** `lib/features/admin/presentation/screens/student_detail_screen.dart` — add a «Семья» card to the Info tab so a student has a comparable card (tasks/comments already shown in its History tab at `:855`).

---

## Task 1: MagicCrmService — `getLeadStatusHistory` + `getFamilyForEntity` (+ unit tests)

**Files:**
- Modify: `lib/core/services/magic_crm_service.dart`, `test/core/services/magic_crm_service_test.dart`

**Interfaces (produces):** `MagicCrmService.getLeadStatusHistory(String leadId)`, `MagicCrmService.getFamilyForEntity({required String entityType, required String entityId})`.

- [ ] **Step 1: Read the harness + a sample mapping method**

Re-read the fake-adapter harness (`magic_crm_service_test.dart:2256`–`2330`): `_FakeAdapter` pops one `_FakeResponse` per request, asserts `options.uri.path == response.path`, records `queryParameters`/`body`. And re-read a sample transform: `_legacyComment` (`magic_crm_service.dart:2009`) and `_legacyTimelineItem` (`:2027`). Match that style exactly (camelCase in → snake_case out).

- [ ] **Step 2: Write the failing tests**

Add two tests to `magic_crm_service_test.dart` (inside the existing `group('MagicCrmService', ...)`), mirroring the existing `_FakeResponse`/`_FakeAdapter` usage:

```dart
test('getLeadStatusHistory requests /crm/leads/{id}/status-history and maps items', () async {
  final adapter = _FakeAdapter([
    _FakeResponse(
      path: '/crm/leads/lead-a/status-history',
      statusCode: 200,
      body: {
        'items': [
          {
            'id': 'h1',
            'oldStatus': 'Новый',
            'newStatus': 'В работе',
            'oldOwnerId': null,
            'newOwnerId': 'user-b',
            'changedBy': 'user-a',
            'changedAt': '2026-06-10T12:00:00.000Z',
            'reasonId': null,
            'comment': 'Перевёл в работу',
          },
        ],
      },
    ),
  ]);
  final service = MagicCrmService(_client(adapter));

  final items = await service.getLeadStatusHistory('lead-a');

  expect(adapter.requests.single, isNotNull);
  expect(items.single['old_status'], 'Новый');
  expect(items.single['new_status'], 'В работе');
  expect(items.single['changed_at'], '2026-06-10T12:00:00.000Z');
  expect(items.single['comment'], 'Перевёл в работу');
});

test('getFamilyForEntity requests /crm/families/by-entity/{type}/{id} and maps family + members', () async {
  final adapter = _FakeAdapter([
    _FakeResponse(
      path: '/crm/families/by-entity/lead/lead-a',
      statusCode: 200,
      body: {
        'family': {
          'id': 'fam-1',
          'name': 'Ивановы',
          'branchId': 'branch-a',
          'primaryPayerMemberId': 'm2',
        },
        'members': [
          {
            'id': 'm1',
            'entityType': 'lead',
            'entityId': 'lead-a',
            'role': 'child',
            'isPrimaryContact': false,
            'name': 'Аня Иванова',
          },
          {
            'id': 'm2',
            'entityType': 'profile',
            'entityId': 'prof-1',
            'role': 'parent',
            'isPrimaryContact': true,
            'name': 'Мария Иванова',
          },
        ],
      },
    ),
  ]);
  final service = MagicCrmService(_client(adapter));

  final result = await service.getFamilyForEntity(
    entityType: 'lead',
    entityId: 'lead-a',
  );

  expect((result['family'] as Map)['name'], 'Ивановы');
  expect((result['family'] as Map)['primary_payer_member_id'], 'm2');
  final members = result['members'] as List;
  expect(members.length, 2);
  expect(members.last['is_primary_contact'], true);
  expect(members.last['name'], 'Мария Иванова');
});

test('getFamilyForEntity returns null family when entity has no family', () async {
  final adapter = _FakeAdapter([
    _FakeResponse(
      path: '/crm/families/by-entity/student/student-x',
      statusCode: 200,
      body: {'family': null, 'members': <dynamic>[]},
    ),
  ]);
  final service = MagicCrmService(_client(adapter));

  final result = await service.getFamilyForEntity(
    entityType: 'student',
    entityId: 'student-x',
  );

  expect(result['family'], isNull);
  expect((result['members'] as List), isEmpty);
});
```

- [ ] **Step 3: Run to verify failure** — `/c/flutter/bin/flutter test test/core/services/magic_crm_service_test.dart` → FAIL (methods undefined / compile error).

- [ ] **Step 4: Implement the methods + transforms**

Add to `MagicCrmService` (near `getLeadCard`, after `:734`):

```dart
  Future<List<Map<String, dynamic>>> getLeadStatusHistory(String leadId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/leads/$leadId/status-history',
    );
    return _mapList(response['items'], _legacyStatusHistoryItem);
  }

  Future<Map<String, dynamic>> getFamilyForEntity({
    required String entityType,
    required String entityId,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/crm/families/by-entity/$entityType/$entityId',
    );
    final family = response['family'];
    return {
      'family': family is Map<String, dynamic>
          ? {
              'id': family['id'],
              'name': family['name'],
              'branch_id': family['branchId'],
              'primary_payer_member_id': family['primaryPayerMemberId'],
            }
          : null,
      'members': _mapList(response['members'], _legacyFamilyMember),
    };
  }
```

Add the two transforms next to the existing `_legacy*` transforms (after `_legacyComment`, `:2025`):

```dart
  Map<String, dynamic> _legacyStatusHistoryItem(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'old_status': item['oldStatus'],
      'new_status': item['newStatus'],
      'old_owner_id': item['oldOwnerId'],
      'new_owner_id': item['newOwnerId'],
      'changed_by': item['changedBy'],
      'changed_at': item['changedAt'],
      'reason_id': item['reasonId'],
      'comment': item['comment'],
    };
  }

  Map<String, dynamic> _legacyFamilyMember(Map<String, dynamic> item) {
    return {
      'id': item['id'],
      'entity_type': item['entityType'],
      'entity_id': item['entityId'],
      'role': item['role'],
      'is_primary_contact': item['isPrimaryContact'] == true,
      'name': item['name'],
    };
  }
```

- [ ] **Step 5: Run tests + analyze** — `/c/flutter/bin/flutter test test/core/services/magic_crm_service_test.dart` → green; `/c/flutter/bin/flutter analyze lib/core/services/magic_crm_service.dart` → no new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/core/services/magic_crm_service.dart test/core/services/magic_crm_service_test.dart
git commit -m "feat(flutter): MagicCrmService getLeadStatusHistory + getFamilyForEntity + tests"
```

---

## Task 2: Lead card — verify tasks/comments + add «Семья» and «История статусов»

**Files:**
- Modify: `lib/features/manager/presentation/widgets/lead_detail_dialog.dart` (**shared**)

**Interfaces (consumes):** `getLeadStatusHistory`, `getFamilyForEntity` from Task 1; existing `getLeadCard`.

**What already renders (verified — do NOT re-build):**
- **Tasks** already show inside `_buildAggregateCard` via `_miniSection(title: 'Задачи', ...)` (`lead_detail_dialog.dart:781`), reading `card['tasks']` (`:733`).
- **Comments** already show via the `_CommentsList` widget under the «Комментарии» section title (`:416`–`:420`); note this list re-fetches with `listComments(entityType:'lead', ...)` (`:1072`) rather than reading `card['comments']` — that is fine and stays.
- The current gap: tasks are buried under «Связи и активность» and capped at `.take(4)` in `_miniSection` (`:985`). This task **promotes** tasks/comments to clear top-level sections and adds the two new sections.

- [ ] **Step 1: Add state fields + fetches**

In `_LeadDetailDialogState` (after `_leadCard` at `:31`), add:

```dart
  List<Map<String, dynamic>> _statusHistory = [];
  bool _loadingHistory = true;
  Map<String, dynamic>? _family;
  bool _loadingFamily = true;
```

In `initState` (`:74`), after `_fetchCard();` (`:83`), add `_fetchStatusHistory();` and `_fetchFamily();`. Implement them next to `_fetchCard` (`:87`), mirroring its try/`if (!mounted) return;`/`setState` shape:

```dart
  Future<void> _fetchStatusHistory() async {
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .getLeadStatusHistory(widget.lead['id'].toString());
      if (!mounted) return;
      setState(() {
        _statusHistory = items;
        _loadingHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _fetchFamily() async {
    try {
      final result = await ref
          .read(magicCrmServiceProvider)
          .getFamilyForEntity(
            entityType: 'lead',
            entityId: widget.lead['id'].toString(),
          );
      if (!mounted) return;
      setState(() {
        _family = result;
        _loadingFamily = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingFamily = false);
    }
  }
```

- [ ] **Step 2: Promote a clear «Задачи» section + add «Семья» and «История статусов» to the build column**

In `build` (`:358`–`:423`), inside the scroll `Column`, after the existing «Связи и активность» block (`:411`–`:413` `_sectionTitle('Связи и активность')` + `_buildAggregateCard()`) and before «Комментарии» (`:416`), insert:

```dart
                    const SizedBox(height: 16),
                    _sectionTitle('Семья'),
                    _buildFamilySection(),

                    const SizedBox(height: 16),
                    _sectionTitle('История статусов'),
                    _buildStatusHistorySection(),
```

Leave the existing «Комментарии» (`:416`) and the `_CommentsList` untouched — comments already render there.

- [ ] **Step 3: Implement `_buildFamilySection` + `_buildStatusHistorySection`**

Add these private methods near `_buildAggregateCard` (`:717`), reusing `_summaryChip` and the `_miniSection`/ListTile idiom. Role labels mirror the Russian-UI convention used elsewhere.

```dart
  String _familyRoleLabel(Object? role) {
    return switch (role?.toString()) {
      'parent' => 'Родитель',
      'child' => 'Ребёнок',
      'guardian' => 'Опекун',
      'payer' => 'Плательщик',
      'sibling' => 'Брат/сестра',
      final value when value != null && value.isNotEmpty => value,
      _ => 'Член семьи',
    };
  }

  Widget _buildFamilySection() {
    if (_loadingFamily) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    final family = _family?['family'] as Map<String, dynamic>?;
    final members = _list(_family?['members']);
    if (family == null) {
      return Text(
        'Семья не указана',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    final primaryId = family['primary_payer_member_id']?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((family['name']?.toString().trim().isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              family['name'].toString(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        if (members.isEmpty)
          Text(
            'Участники не добавлены',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          )
        else
          ...members.map((m) {
            final isPayer =
                primaryId != null && m['id']?.toString() == primaryId;
            final subtitle = [
              _familyRoleLabel(m['role']),
              if (m['is_primary_contact'] == true) 'Осн. контакт',
              if (isPayer) 'Плательщик',
            ].where((value) => value.isNotEmpty).join(' · ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                tileColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withAlpha(120),
                leading: Icon(
                  Icons.people_alt_rounded,
                  size: 18,
                  color: AppTheme.primaryPurple,
                ),
                title: Text(
                  (m['name']?.toString().trim().isNotEmpty ?? false)
                      ? m['name'].toString()
                      : 'Без имени',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: subtitle.isEmpty ? null : Text(subtitle),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildStatusHistorySection() {
    if (_loadingHistory) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    if (_statusHistory.isEmpty) {
      return Text(
        'Изменений статуса пока нет',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _statusHistory.take(12).map((h) {
        final from = h['old_status']?.toString();
        final to = h['new_status']?.toString();
        final transition = [
          if (from != null && from.isNotEmpty) from else '—',
          '→',
          if (to != null && to.isNotEmpty) to else '—',
        ].join(' ');
        final comment = h['comment']?.toString().trim() ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            tileColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withAlpha(120),
            leading: const Icon(
              Icons.history_rounded,
              size: 18,
              color: AppTheme.primaryGold,
            ),
            title: Text(transition, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                _formatDate(h['changed_at']),
                if (comment.isNotEmpty) comment,
              ].where((value) => value.isNotEmpty).join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(),
    );
  }
```

> `_list` (`:809`) and `_formatDate` (`:1030`) already exist on the state class — reuse them; do not redefine.

- [ ] **Step 4: Analyze**

`/c/flutter/bin/flutter analyze lib/features/manager/presentation/widgets/lead_detail_dialog.dart` → 0 new issues. (Watch for unused-import / unused-field warnings — every new field is read in a build method.)

- [ ] **Step 5: Verify on-device (owner)**

Open a lead that has imported tasks/comments + a family + status changes (e.g. one of the migrated HolliHop leads). Confirm: «Задачи» rows render, «Семья» lists members with role/primary-payer chips, «История статусов» lists transitions newest-first with dates. Empty leads show the empty-state strings (no crash, no infinite spinner).

- [ ] **Step 6: Commit**

```bash
git add lib/features/manager/presentation/widgets/lead_detail_dialog.dart
git commit -m "feat(flutter): lead card «Семья» + «История статусов» sections; surface tasks/comments"
```

---

## Task 3: Student card — add «Семья» (tasks/comments already present)

**Files:**
- Modify: `lib/features/admin/presentation/screens/student_detail_screen.dart`

**Context:** A full student card already exists — `StudentDetailScreen` (`student_detail_screen.dart:11`), routed at `/student/:id` (`app_router.dart:248`) and opened from the manager debtors/finance/tasks widgets (`debtors_widget.dart:74`, `finance_widget.dart:272`, `tasks_widget.dart:1006`). It already shows **tasks + comments** in its «История» tab (`:855` `_buildHistoryTab`) and progress notes in «Прогресс» (`:962`). The only missing parity item vs the lead card is **«Семья»**. Status-history for a student lives in a separate `app.student_status_history` table with no endpoint yet — out of scope here (noted in Backlog below).

- [ ] **Step 1: Load the family alongside the existing parallel loads**

In `_StudentDetailScreenState` (after `_groups` field at `:27`), add:

```dart
  Map<String, dynamic>? _family;
```

In `_loadAllData` (`:37`), append `crm.getFamilyForEntity(entityType: 'student', entityId: widget.studentId)` to the existing `Future.wait` list (`:41`–`:54`) as the 9th entry, then read `results[8]` into `_family` inside the `setState` (`:66`):

```dart
        crm.getFamilyForEntity(
          entityType: 'student',
          entityId: widget.studentId,
        ),
```
```dart
          _family = results[8] as Map<String, dynamic>;
```

- [ ] **Step 2: Render a «Семья» card in the Info tab**

In `_buildInfoTab` (`:221`), after the existing «Группы» card (`:292`–`:319`) inside the `ListView` children, add:

```dart
        SizedBox(height: 16),
        _buildInfoCard('Семья', _buildFamilyRows()),
```

Add a helper next to `_buildInfoCard` (`:557`), reusing the existing `_InfoRow` (`:1046`) idiom:

```dart
  List<Widget> _buildFamilyRows() {
    final family = _family?['family'] as Map<String, dynamic>?;
    final members = (_family?['members'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const <Map<String, dynamic>>[];
    if (family == null || members.isEmpty) {
      return const [
        _InfoRow(
          icon: Icons.people_outline_rounded,
          label: 'Семья',
          value: 'Не указана',
        ),
      ];
    }
    final primaryId = family['primary_payer_member_id']?.toString();
    return members.map((m) {
      final role = switch (m['role']?.toString()) {
        'parent' => 'Родитель',
        'child' => 'Ребёнок',
        'guardian' => 'Опекун',
        'payer' => 'Плательщик',
        'sibling' => 'Брат/сестра',
        final v when v != null && v.isNotEmpty => v,
        _ => 'Член семьи',
      };
      final isPayer = primaryId != null && m['id']?.toString() == primaryId;
      final label = [
        role,
        if (m['is_primary_contact'] == true) 'осн. контакт',
        if (isPayer) 'плательщик',
      ].join(' · ');
      return _InfoRow(
        icon: Icons.people_alt_rounded,
        label: label,
        value: (m['name']?.toString().trim().isNotEmpty ?? false)
            ? m['name'].toString()
            : 'Без имени',
      );
    }).toList();
  }
```

- [ ] **Step 3: Analyze**

`/c/flutter/bin/flutter analyze lib/features/admin/presentation/screens/student_detail_screen.dart` → 0 new issues.

- [ ] **Step 4: Verify on-device (owner)**

Open a student that belongs to a family (e.g. a sibling pair from the import). Info tab shows the «Семья» card listing members with role/contact/payer labels; the «История» tab continues to show their tasks + comments. A student with no family shows «Не указана».

- [ ] **Step 5: Commit**

```bash
git add lib/features/admin/presentation/screens/student_detail_screen.dart
git commit -m "feat(flutter): student card «Семья» section (family members + primary payer)"
```

---

## Task 4: Full-suite green + analyze gate

**Files:** none (verification only).

- [ ] **Step 1:** `/c/flutter/bin/flutter analyze` → 0 issues in the four touched files.
- [ ] **Step 2:** `/c/flutter/bin/flutter test` → full Flutter suite green (existing 106 + the 3 new service tests = no regressions).
- [ ] **Step 3:** (sanity) server unchanged → no `npm test` needed; confirm `git status` shows only the four intended files modified.

---

## Self-Review

- **Tasks + comments (requirement 1):** Verified — the lead card already renders tasks (`_miniSection 'Задачи'`, `lead_detail_dialog.dart:781`) and comments (`_CommentsList`, `:416`); the student card renders both in its «История» tab (`student_detail_screen.dart:855`). Task 2 promotes them to clearer top-level sections rather than re-implementing. No double-fetch introduced (comments keep their existing `listComments` source).
- **«Семья» (requirement 2):** Backend endpoint already exists (`GET /crm/families/by-entity/:entityType/:entityId`, `crm.controller.ts:687` → `getFamilyForEntity`, `crm.service.ts:5874`) — **no backend task needed**. Added one Flutter service method (tested) + a section in both the lead dialog and the student screen.
- **«История статусов» (requirement 3):** `getLeadCard`'s `timeline` does **not** include status changes; the dedicated endpoint `GET /crm/leads/:leadId/status-history` (`crm.controller.ts:606` → `listLeadStatusHistory`, `crm.service.ts:4134`) does. Surfaced via a new tested service method + a «История статусов» section newest-first.
- **Student card parity (requirement 4):** A comparable card already exists (`StudentDetailScreen`); this plan only closes the «Семья» gap. Student **status** history (`app.student_status_history`) has no endpoint yet — explicitly deferred (see Backlog), not silently dropped.
- **Testability:** the two new service methods are unit-tested against the real fake-adapter harness (path + mapped keys + null-family branch). The dialog/screen edits are analyzed + owner-verified on-device (consistent with the analytics-dashboards plan's stated rationale that widget tests for large stateful dialogs are low-value).
- **No backend change, no migration:** read-only consumption of already-deployed endpoints; mirrors the analytics-dashboards plan's posture.
- **Shared-file safety:** all `lead_detail_dialog.dart` edits are additive (new fields, new fetches, new private methods, two new section calls in the existing build column) — no renames/reorders that would conflict with a parallel stream.

## Backlog / follow-ups (out of scope, note for the program)

- **Student status history:** add `GET /crm/students/:studentId/status-history` on the server (reading `app.student_status_history`, mirroring `listLeadStatusHistory` at `crm.service.ts:4134`) + a `getStudentStatusHistory` Flutter method + a section in `StudentDetailScreen` — for full lead/student symmetry.
- **Family editing from the card:** the server already exposes `POST /crm/families`, `POST /crm/families/:familyId/members`, `DELETE /crm/family-members/:memberId`, `POST /crm/families/:familyId/primary-payer/:memberId` (`crm.controller.ts:673`–`710`). A future card iteration can add "add member / set payer / detach" actions; this plan is read-only display.
