/// Typed view over a lead in the legacy map shape produced by
/// `MagicCrmService`'s `_legacyLead` / `_legacyLeadBoardItem` mappers
/// (snake_case keys). F0 lead domain: replaces `lead['key']` access with typed
/// getters. Covers both the base lead and the kanban board-item (which adds
/// counts / assignee / branch name / linked student); board-only fields return
/// safe defaults when absent, so one model serves both shapes.
///
/// Getters mirror the widgets' exact prior expressions so migrating call sites
/// is behaviour-preserving: string getters carry the `?.toString() ?? ''`
/// fallbacks, counts parse leniently (matching lead_card's `_intValue`), and
/// [raw] is the underlying map for the few APIs that still take a map
/// (for example, when opening the unified client card from the lead board).
class Lead {
  final Map<String, dynamic> _m;

  const Lead(this._m);

  factory Lead.fromMap(Map<String, dynamic> map) => Lead(map);

  /// The underlying legacy map — escape hatch for APIs not yet typed.
  Map<String, dynamic> get raw => _m;

  String get id => _m['id']?.toString() ?? '';
  String? get statusId => _m['status_id']?.toString();
  String get status => _m['status']?.toString() ?? 'new';
  String? get statusLabel => _m['status_label']?.toString();

  /// Display name — the lead's first name (matches the mapper's `name`).
  String get name => _m['name']?.toString() ?? '';
  String? get firstName => _m['first_name']?.toString();
  String get lastName => _m['last_name']?.toString() ?? '';
  String get phone => _m['phone']?.toString() ?? '';
  String? get email => _m['email']?.toString();
  String get source => _m['source']?.toString() ?? '';
  String? get notes => _m['notes']?.toString();
  String? get assignedTo => _m['assigned_to']?.toString();
  String? get hollihopId => _m['hollihop_id']?.toString();
  String? get branchId => _m['branch_id']?.toString();
  String? get createdBy => _m['created_by']?.toString();
  String? get createdAt => _m['created_at']?.toString();
  String? get updatedAt => _m['updated_at']?.toString();

  Map<String, dynamic> get customData =>
      _m['custom_data'] is Map<String, dynamic>
      ? _m['custom_data'] as Map<String, dynamic>
      : const <String, dynamic>{};

  /// Discipline / level from [customData] (kanban chips).
  String get discipline => customData['discipline']?.toString() ?? '';
  String get level => customData['level']?.toString() ?? '';

  // ── Board-item fields (present on kanban items; safe defaults otherwise) ──
  Object? get statusColor => _m['status_color'];
  String get assignedName => _m['assigned_name']?.toString() ?? '';
  String get branchName => _m['branch_name']?.toString() ?? '';
  String get linkedStudentId => _m['linked_student_id']?.toString() ?? '';
  String get linkedUserId => _m['linked_user_id']?.toString() ?? '';
  int get openTasksCount => _intOf(_m['open_tasks_count']);
  int get commentsCount => _intOf(_m['comments_count']);
  int get trialLessonsCount => _intOf(_m['trial_lessons_count']);

  static int _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
