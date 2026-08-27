class TeacherEmploymentReferenceOption {
  final String id;
  final String name;
  final String lifecycleState;

  const TeacherEmploymentReferenceOption({
    required this.id,
    required this.name,
    this.lifecycleState = 'active',
  });

  factory TeacherEmploymentReferenceOption.fromRow(Map<String, dynamic> row) {
    return TeacherEmploymentReferenceOption(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      lifecycleState:
          row['lifecycleState']?.toString() ??
          row['lifecycle_state']?.toString() ??
          'active',
    );
  }
}

abstract interface class TeacherEmploymentReferenceGateway {
  Future<List<TeacherEmploymentReferenceOption>> loadBranches();

  Future<List<TeacherEmploymentReferenceOption>> loadDisciplines();

  Future<List<String>> loadTeacherCustomOptions(String key);
}
