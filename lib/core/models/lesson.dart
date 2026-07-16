/// Typed view over a lesson in the legacy map shape produced by
/// `MagicCrmService`'s `_legacyLesson` mapper (snake_case keys). F0 domain.
///
/// The nested `groups` / `rooms` / `branches` / `teachers` sub-objects stay as
/// raw `Map<String, dynamic>?` getters — the client card reads them positionally
/// (`groups?['name']`, `teachers?['first_name']`), so a raw-map getter keeps
/// those reads byte-faithful without over-modelling every nested shape. Scalar
/// getters mirror the widgets' prior expressions. [raw] is the underlying map
/// for widgets still taking one (e.g. `StudentScheduleSection`).
class Lesson {
  final Map<String, dynamic> _m;

  const Lesson(this._m);

  factory Lesson.fromMap(Map<String, dynamic> map) => Lesson(map);

  Map<String, dynamic> get raw => _m;

  String? get id => _m['id']?.toString();
  String? get studentId => _m['student_id']?.toString();
  String? get groupId => _m['group_id']?.toString();
  String? get leadId => _m['lead_id']?.toString();
  String? get teacherId => _m['teacher_id']?.toString();
  String? get branchId => _m['branch_id']?.toString();
  String? get roomId => _m['room_id']?.toString();
  String? get scheduledAt => _m['scheduled_at']?.toString();
  Object? get durationMinutesRaw => _m['duration_minutes'];
  String? get status => _m['status']?.toString();
  bool get isTrial => _m['is_trial'] == true;
  String? get notes => _m['notes']?.toString();
  Object? get teacherRateRaw => _m['teacher_rate'];

  /// Rate actually paid for this lesson: the per-lesson override, else the
  /// group's, else the teacher's rate history. null when the caller may not
  /// see pay data (only director/system_admin do — KVA-239).
  Object? get appliedTeacherRateRaw => _m['applied_teacher_rate'];
  num? get appliedTeacherRate {
    final raw = appliedTeacherRateRaw;
    if (raw is num) return raw;
    return num.tryParse(raw?.toString() ?? '');
  }
  String? get studentName => _m['student_name']?.toString();
  String? get teacherName => _m['teacher_name']?.toString();
  String? get branchName => _m['branch_name']?.toString();
  String? get roomName => _m['room_name']?.toString();
  String? get groupName => _m['group_name']?.toString();
  Object? get groupPricePerLessonRaw => _m['group_price_per_lesson'];

  /// Nested sub-objects the client card reads positionally; null when absent.
  Map<String, dynamic>? get groups => _m['groups'] as Map<String, dynamic>?;
  Map<String, dynamic>? get rooms => _m['rooms'] as Map<String, dynamic>?;
  Map<String, dynamic>? get branches => _m['branches'] as Map<String, dynamic>?;
  Map<String, dynamic>? get teachers => _m['teachers'] as Map<String, dynamic>?;
}
