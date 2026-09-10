part of 'client_card.dart';

extension _ClientCardCounterpartResolution on _ClientCardState {
  /// Resolve the lead half after every successful student load, including a
  /// retry. An already resolved pair must not start another fetch cycle.
  void _resolveLeadCounterpart() {
    if (!mounted || _isConverted) return;
    final leadId = _student?['lead_id']?.toString();
    if (leadId == null || leadId.isEmpty) return;
    _emitState(() {
      _mode = ClientMode.converted;
      _resolvedLeadId = leadId;
      // Lead-side sections start loading now.
    });
    // Parallel, isolated lead-half fetches against the resolved lead id. Lead
    // statuses are needed for the header label and the originating-lead card;
    // the editable lead form / branch metadata isn't shown in converted mode,
    // so we skip _fetchMetadata here.
    _statuses = widget.allStatuses ?? _statuses;
    if (_statuses.isEmpty) _fetchStatuses();
    _fetchCard(leadId: leadId);
  }

  /// Lead-opened path: if the lead card lists linked students, pick the primary
  /// (first / most recent) one, fetch the student half and flip to `converted`.
  /// Additional linked students stay visible via the existing linked-students
  /// UI. An already resolved pair must not start another fetch cycle.
  void _resolveStudentCounterpart() {
    if (!mounted || _isConverted) return;
    final linked = _list(_leadCard?['linked_students']);
    if (linked.isEmpty) return;
    final primary = _primaryLinkedStudent(linked);
    final studentId = primary?['id']?.toString();
    if (studentId == null || studentId.isEmpty) return;
    _emitState(() {
      _mode = ClientMode.converted;
      _resolvedStudentId = studentId;
    });
    // Parallel, isolated student-half fetch against the resolved student id.
    _fetchStudentData(studentId: studentId);
  }

  /// Picks the primary linked student: most recently created, falling back to
  /// the first row when no timestamps are present.
  Map<String, dynamic>? _primaryLinkedStudent(
    List<Map<String, dynamic>> linked,
  ) {
    if (linked.isEmpty) return null;
    final sorted = [...linked]
      ..sort(
        (a, b) => (b['created_at']?.toString() ?? '').compareTo(
          a['created_at']?.toString() ?? '',
        ),
      );
    return sorted.first;
  }

  // True when the lead card lists at least one linked student — used to hide the
  // «Создать ученика» button even before resolution flips the mode.
  bool get _hasLinkedStudent => _list(_leadCard?['linked_students']).isNotEmpty;
}
