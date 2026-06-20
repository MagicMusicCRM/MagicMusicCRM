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
