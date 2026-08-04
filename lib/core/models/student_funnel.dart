class StudentFunnelStage {
  const StudentFunnelStage({
    required this.key,
    required this.label,
    required this.style,
    required this.active,
    required this.allowedTransitions,
  });

  factory StudentFunnelStage.fromJson(Map<String, dynamic> json) {
    return StudentFunnelStage(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      style: json['style']?.toString() ?? 'gray',
      active: json['active'] == true,
      allowedTransitions: (json['allowedTransitions'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }

  final String key;
  final String label;
  final String style;
  final bool active;
  final List<String> allowedTransitions;

  StudentFunnelStage copyWith({
    String? label,
    String? style,
    bool? active,
    List<String>? allowedTransitions,
  }) => StudentFunnelStage(
    key: key,
    label: label ?? this.label,
    style: style ?? this.style,
    active: active ?? this.active,
    allowedTransitions: allowedTransitions ?? this.allowedTransitions,
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label.trim(),
    'style': style,
    'active': active,
    'allowedTransitions': allowedTransitions,
  };
}

class StudentFunnelConfiguration {
  const StudentFunnelConfiguration({
    required this.branchId,
    required this.source,
    required this.schoolVersion,
    required this.branchVersion,
    required this.stages,
    required this.remediationStatuses,
  });

  factory StudentFunnelConfiguration.fromJson(Map<String, dynamic> json) {
    final stages = (json['stages'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StudentFunnelStage.fromJson)
        .where((stage) => stage.key.isNotEmpty && stage.label.isNotEmpty)
        .toList(growable: false);
    if (stages.isEmpty) {
      throw const FormatException('Student funnel has no configured stages.');
    }
    return StudentFunnelConfiguration(
      branchId: json['branchId']?.toString(),
      source: json['source']?.toString() ?? 'school',
      schoolVersion: (json['schoolVersion'] as num?)?.toInt() ?? 0,
      branchVersion: (json['branchVersion'] as num?)?.toInt() ?? 0,
      stages: stages,
      remediationStatuses: (json['remediationStatuses'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false),
    );
  }

  final String? branchId;
  final String source;
  final int schoolVersion;
  final int branchVersion;
  final List<StudentFunnelStage> stages;
  final List<Map<String, dynamic>> remediationStatuses;

  int get scopeVersion => branchId == null ? schoolVersion : branchVersion;
  List<StudentFunnelStage> get activeStages =>
      stages.where((stage) => stage.active).toList(growable: false);
}
