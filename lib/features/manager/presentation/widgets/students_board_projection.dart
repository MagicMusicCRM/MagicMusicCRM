import 'students_board_models.dart';

List<StudentsBoardColumnData> projectStudentsBoard(
  List<Map<String, dynamic>> columns, {
  Map<String, String> optimisticStatuses = const {},
  String query = '',
}) {
  final mutable = [
    for (final column in columns)
      _MutableBoardColumn(
        status: column['status'] as String?,
        name: column['name']?.toString() ?? 'Без названия',
        style: column['style']?.toString() ?? 'gray',
        allowedTransitions: (column['allowedTransitions'] as List? ?? const [])
            .map((value) => value.toString())
            .toSet(),
        students: (column['students'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
      ),
  ];
  _applyOptimisticMoves(mutable, optimisticStatuses);

  final normalizedQuery = query.trim().toLowerCase();
  return List.unmodifiable(
    mutable.map(
      (column) => column.freeze(
        students: normalizedQuery.isEmpty
            ? null
            : column.students
                  .where((student) => _matchesQuery(student, normalizedQuery))
                  .toList(),
      ),
    ),
  );
}

Map<String, Set<String>> studentBoardTransitions(
  List<StudentsBoardColumnData> columns,
) => Map.unmodifiable(<String, Set<String>>{
  for (final column in columns)
    if (column.status != null) column.status!: column.allowedTransitions,
});

void _applyOptimisticMoves(
  List<_MutableBoardColumn> columns,
  Map<String, String> optimisticStatuses,
) {
  final targets = <String, _MutableBoardColumn>{
    for (final column in columns)
      if (column.status != null) column.status!: column,
  };
  for (final entry in optimisticStatuses.entries) {
    final target = targets[entry.value];
    if (target == null) continue;
    for (final source in columns) {
      final index = source.students.indexWhere(
        (student) => student['id']?.toString() == entry.key,
      );
      if (index < 0 || identical(source, target)) continue;
      target.students.add(source.students.removeAt(index));
      break;
    }
  }
}

class _MutableBoardColumn {
  _MutableBoardColumn({
    required this.status,
    required this.name,
    required this.style,
    required this.allowedTransitions,
    required this.students,
  });

  final String? status;
  final String name;
  final String style;
  final Set<String> allowedTransitions;
  final List<Map<String, dynamic>> students;

  StudentsBoardColumnData freeze({List<Map<String, dynamic>>? students}) {
    return StudentsBoardColumnData(
      status: status,
      name: name,
      style: style,
      allowedTransitions: allowedTransitions,
      students: students ?? this.students,
    );
  }
}

bool _matchesQuery(Map<String, dynamic> student, String query) {
  final haystack =
      [
            student['name'],
            student['first_name'],
            student['last_name'],
            student['phone'],
          ]
          .whereType<Object>()
          .map((value) => value.toString().toLowerCase())
          .join(' ');
  return haystack.contains(query);
}

extension StudentsBoardColumnsProjection on List<StudentsBoardColumnData> {
  Map<String, Set<String>> get transitions => studentBoardTransitions(this);
}
