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

/// The Ученики board for a branch: STATUS columns (Активные / Неактивные /
/// Прочие) + grouped students. Mirrors how the Leads board is organised so the
/// board can act as a status-based draggable kanban.
final studentBoardProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
  ref,
  branchId,
) async {
  final service = ref.watch(magicCrmServiceProvider);
  // TODO: добавить серверную пагинацию/board-эндпоинт, если ветка превышает этот лимит.
  final search = await service.searchStudents(branchId: branchId, limit: 500);
  final students =
      (search['items'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
  return groupStudentsByStatus(students);
});

/// The student statuses that act as the board's draggable columns.
/// `key` is the value sent to the backend (`status`), `name` is the Russian
/// column title.
const List<({String key, String name})> studentStatusColumns = [
  (key: 'active', name: 'Активные'),
  (key: 'inactive', name: 'Неактивные'),
];

/// Pure: bucket students into the column whose `status` matches (case-
/// insensitive). Active/inactive are the draggable targets; any unknown status
/// (or missing status) lands in a trailing «Прочие» column.
List<Map<String, dynamic>> groupStudentsByStatus(
  List<Map<String, dynamic>> students,
) {
  final columns = <Map<String, dynamic>>[
    for (final s in studentStatusColumns)
      {
        'status': s.key,
        'name': s.name,
        'students': <Map<String, dynamic>>[],
      },
  ];
  // Trailing bucket for unknown / empty statuses. `status: null` marks it as a
  // non-droppable column (the widget only accepts drops onto real statuses).
  final other = <String, dynamic>{
    'status': null,
    'name': 'Прочие',
    'students': <Map<String, dynamic>>[],
  };

  final byStatus = <String, List<Map<String, dynamic>>>{
    for (final c in columns)
      (c['status'] as String): c['students'] as List<Map<String, dynamic>>,
  };

  for (final student in students) {
    final status = student['status']?.toString().trim().toLowerCase() ?? '';
    final bucket = byStatus[status];
    if (bucket != null) {
      bucket.add(student);
    } else {
      (other['students'] as List<Map<String, dynamic>>).add(student);
    }
  }

  // Only show «Прочие» when it actually holds students.
  if ((other['students'] as List).isEmpty) {
    return columns;
  }
  return [...columns, other];
}

/// Pure: order the branch disciplines by sort_order, bucket students into the
/// column whose name matches `custom_data['discipline']` (case-insensitive),
/// and append a trailing "Без направления" column for the rest.
List<Map<String, dynamic>> groupStudentsByDiscipline(
  List<Map<String, dynamic>> disciplines,
  List<Map<String, dynamic>> students,
) {
  final ordered = [...disciplines]
    ..sort((a, b) =>
        ((a['sort_order'] as num?) ?? (1 << 30))
            .compareTo((b['sort_order'] as num?) ?? (1 << 30)));

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
    // Prefer the relational disciplines (from student_disciplines, surfaced by
    // the search DTO); fall back to the legacy custom_data['discipline'] string.
    final names = <String>{};
    final disc = student['disciplines'];
    if (disc is List) {
      for (final d in disc) {
        final n = (d is Map ? d['name']?.toString() : d?.toString())?.trim();
        if (n != null && n.isNotEmpty) names.add(n.toLowerCase());
      }
    }
    if (names.isEmpty) {
      final custom = student['custom_data'];
      final legacy = custom is Map
          ? custom['discipline']?.toString().trim() ?? ''
          : '';
      if (legacy.isNotEmpty) names.add(legacy.toLowerCase());
    }

    final matched = names.where(byName.containsKey).toList();
    if (matched.isEmpty) {
      (fallback['students'] as List<Map<String, dynamic>>).add(student);
    } else {
      // A student studying several disciplines appears in each column.
      for (final n in matched) {
        byName[n]!.add(student);
      }
    }
  }

  return [...columns, fallback];
}
