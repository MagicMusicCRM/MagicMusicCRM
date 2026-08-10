import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:magic_music_crm/core/models/student_funnel.dart';
import 'package:magic_music_crm/core/services/magic_crm_service.dart';

/// The disciplines configured for a branch (the Ученики board's columns).
final branchDisciplinesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, branchId) {
      return ref.watch(magicCrmServiceProvider).listBranchDisciplines(branchId);
    });

/// Sentinel branch id for the «Без филиала» board — students with no branch.
/// Must equal `kNoBranchValue` in the transfer controller (both `__none__`).
const String kNoBranchBoardId = '__none__';

/// Effective school + optional branch funnel used by every student workflow.
final studentFunnelProvider =
    FutureProvider.family<StudentFunnelConfiguration, String>((ref, branchId) {
      return ref
          .watch(magicCrmServiceProvider)
          .getClientPipeline(
            clientType: 'student',
            branchId: branchId == kNoBranchBoardId ? null : branchId,
          );
    });

/// The Ученики board for a branch: effective configured funnel columns plus
/// grouped students. Mirrors how the Leads board is organised so the board can
/// act as a status-based draggable kanban.
///
/// Pass [kNoBranchBoardId] to load students that have no branch at all.
class StudentBoardPage {
  final List<Map<String, dynamic>> students;
  final List<StudentFunnelStage> stages;
  final String? nextCursor;
  final int totalCount;

  const StudentBoardPage({
    required this.students,
    required this.stages,
    required this.nextCursor,
    required this.totalCount,
  });

  List<Map<String, dynamic>> get columns =>
      groupStudentsByStatus(students, stages);
}

final studentBoardProvider = FutureProvider.autoDispose
    .family<StudentBoardPage, String>((ref, branchId) async {
      final service = ref.watch(magicCrmServiceProvider);
      final funnel = await ref.watch(studentFunnelProvider(branchId).future);
      final search = branchId == kNoBranchBoardId
          ? await service.searchStudents(noBranch: true, limit: 100)
          : await service.searchStudents(branchId: branchId, limit: 100);
      final students = (search['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      return StudentBoardPage(
        students: students,
        stages: funnel.activeStages,
        nextCursor: search['next_cursor']?.toString(),
        totalCount: (search['total_count'] as num?)?.toInt() ?? students.length,
      );
    });

/// Pure: bucket students into the column whose `status` matches (case-
/// insensitive). Configured active stages are the draggable targets; any
/// unknown status (or missing status) lands in the remediation column.
List<Map<String, dynamic>> groupStudentsByStatus(
  List<Map<String, dynamic>> students,
  List<StudentFunnelStage> stages,
) {
  final columns = <Map<String, dynamic>>[
    for (final stage in stages)
      {
        'status': stage.key,
        'name': stage.label,
        'style': stage.style,
        'allowedTransitions': stage.allowedTransitions,
        'students': <Map<String, dynamic>>[],
      },
  ];
  // Trailing bucket for unknown / empty statuses. `status: null` marks it as a
  // non-droppable column (the widget only accepts drops onto real statuses).
  final other = <String, dynamic>{
    'status': null,
    'name': 'Требуют сопоставления',
    'style': 'red',
    'allowedTransitions': const <String>[],
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

  // Only show remediation when it actually holds students.
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
    ..sort(
      (a, b) => ((a['sort_order'] as num?) ?? (1 << 30)).compareTo(
        (b['sort_order'] as num?) ?? (1 << 30),
      ),
    );

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
      (c['name'] as String).toLowerCase():
          c['students'] as List<Map<String, dynamic>>,
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
