part of 'client_card.dart';

const _clientCardWorkspaceDraftSchema = 1;

extension _ClientCardWorkspaceDraft on _ClientCardState {
  int? get _workspaceExpectedVersion {
    if (widget.entityType == 'student') {
      return _restoredStudentExpectedVersion ??
          _clientVersion(_student?['version']) ??
          _workspaceInternalNoteDraft?.expectedVersion;
    }
    return _restoredLeadExpectedVersion ??
        _clientVersion(_leadData['version']) ??
        _workspaceInternalNoteDraft?.expectedVersion;
  }

  void _scheduleWorkspaceDraftSync() {
    if (_workspaceDraftSyncScheduled) return;
    _workspaceDraftSyncScheduled = true;
    scheduleMicrotask(() {
      _workspaceDraftSyncScheduled = false;
      if (mounted) _syncWorkspaceFormDirty();
    });
  }

  Map<String, Object?> _buildWorkspaceDraft() {
    final restored = _restoredWorkspaceForm;
    if (!_restoredWorkspaceDraftApplied && restored != null) {
      final draft = Map<String, Object?>.from(restored.draft);
      final note = _workspaceInternalNoteDraft;
      if (note != null) {
        draft['internalNote'] = note.toJson();
      }
      return draft;
    }

    final note = _workspaceInternalNoteDraft;
    return {
      'schemaVersion': _clientCardWorkspaceDraftSchema,
      'entityType': widget.entityType,
      'entityId': _entityId,
      if (_autoSaveConflict) 'requiresExplicitApply': true,
      if (_hasPendingLeadDraft) 'lead': _buildLeadWorkspaceDraft(),
      if (_hasPendingStudentDraft) 'student': _buildStudentWorkspaceDraft(),
      if (note != null) 'internalNote': note.toJson(),
    };
  }

  bool get _hasPendingLeadDraft =>
      _leadCoreEditRevisions.isNotEmpty ||
      _leadCustomEditRevisions.isNotEmpty ||
      _leadStatusEditRevision != null ||
      _leadResponsibleEditRevision != null;

  bool get _hasPendingStudentDraft =>
      _studentCoreEditRevisions.isNotEmpty ||
      _studentCustomEditRevisions.isNotEmpty ||
      _studentStatusEditRevision != null ||
      _studentResponsibleEditRevision != null;

  Map<String, Object?> _buildLeadWorkspaceDraft() {
    final customData = Map<String, dynamic>.from(
      _leadData['custom_data'] as Map? ?? const {},
    );
    final expectedVersion =
        _restoredLeadExpectedVersion ?? _clientVersion(_leadData['version']);
    return {
      ..._expectedVersionEntry(expectedVersion),
      'core': {
        for (final key in _leadCoreEditRevisions.keys)
          key: _leadCoreDraftValue(key),
      },
      'custom': {
        for (final key in _leadCustomEditRevisions.keys) key: customData[key],
      },
      if (_leadStatusEditRevision != null) 'status': _leadData['status'],
      if (_leadResponsibleEditRevision != null)
        'responsible': {
          'changed': _leadResponsibleChanged,
          'assignedTo': _leadData['assigned_to'],
          'assignedName': _leadData['assigned_name'],
        },
    };
  }

  Object? _leadCoreDraftValue(String key) => switch (key) {
    'firstName' => _leadData['name'] ?? _leadData['first_name'],
    'lastName' => _leadData['last_name'],
    'phone' => _leadData['phone'],
    'email' => _leadData['email'],
    'branchId' => _leadData['branch_id'],
    'sourceId' => _leadData['source_id'],
    _ => null,
  };

  Map<String, Object?> _buildStudentWorkspaceDraft() {
    final student = _student ?? const <String, dynamic>{};
    final customData = Map<String, dynamic>.from(
      student['custom_data'] as Map? ?? const {},
    );
    final expectedVersion =
        _restoredStudentExpectedVersion ?? _clientVersion(student['version']);
    return {
      ..._expectedVersionEntry(expectedVersion),
      'core': {
        for (final key in _studentCoreEditRevisions.keys)
          key: _studentCoreDraftValue(key),
      },
      'custom': {
        for (final key in _studentCustomEditRevisions.keys)
          key: customData[key],
      },
      if (_studentStatusEditRevision != null) 'status': student['status'],
      if (_studentResponsibleEditRevision != null)
        'responsible': {
          'changed': _studentResponsibleChanged,
          for (final key in const [
            'responsible',
            'responsibleUserId',
            'responsibleName',
          ])
            key: customData[key],
        },
    };
  }

  Object? _studentCoreDraftValue(String key) {
    final student = _student ?? const <String, dynamic>{};
    return switch (key) {
      'firstName' => student['first_name'],
      'lastName' => student['last_name'],
      'phone' => student['phone'],
      'email' => student['email'],
      'branchId' => Map<String, dynamic>.from(
        student['custom_data'] as Map? ?? const {},
      )['branchId'],
      'sourceId' => student['source_id'],
      _ => null,
    };
  }

  bool _restoreWorkspaceFormIfNeeded(WorkspaceFormState? form) {
    if (form == null ||
        !form.dirty ||
        form.draft.isEmpty ||
        _restoredWorkspaceDraftApplied) {
      return false;
    }
    final draft = form.draft;
    if (draft['schemaVersion'] != _clientCardWorkspaceDraftSchema ||
        draft['entityType'] != widget.entityType ||
        draft['entityId'] != _entityId) {
      return false;
    }
    _restoredWorkspaceForm = form;
    final note = ClientInternalNoteDraft.fromJson(draft['internalNote']);
    if (note != null) {
      _workspaceInternalNoteDraft = note;
      _internalNoteIsPending = true;
    }
    _tryApplyRestoredWorkspaceDraft();
    return true;
  }

  void _tryApplyRestoredWorkspaceDraft() {
    final form = _restoredWorkspaceForm;
    if (_restoredWorkspaceDraftApplied || form == null) {
      return;
    }
    final draft = form.draft;
    final leadDraft = _stringMap(draft['lead']);
    final studentDraft = _stringMap(draft['student']);
    if (leadDraft != null && _clientVersion(_leadData['version']) == null) {
      return;
    }
    if (studentDraft != null && _clientVersion(_student?['version']) == null) {
      return;
    }

    final revision = ++_editRevision;
    var restoredCardFields = false;
    final requiresExplicitApply = draft['requiresExplicitApply'] == true;
    _emitState(() {
      if (leadDraft != null) {
        restoredCardFields = true;
        _applyLeadWorkspaceDraft(leadDraft, revision);
      }
      if (studentDraft != null) {
        restoredCardFields = true;
        _applyStudentWorkspaceDraft(studentDraft, revision);
      }
      if (restoredCardFields) {
        _workspaceController.edited = true;
        _autoSaveConflict = requiresExplicitApply;
        _autoSaveFailed = requiresExplicitApply;
        _editorEpoch++;
      }
      _restoredWorkspaceDraftApplied = true;
    });
    if (restoredCardFields && !requiresExplicitApply) _scheduleAutoSave();
    _syncWorkspaceFormDirty();
  }

  void _applyLeadWorkspaceDraft(Map<String, Object?> draft, int revision) {
    _restoredLeadExpectedVersion = _intValue(draft['expectedVersion']);
    final core = _stringMap(draft['core']) ?? const {};
    for (final entry in core.entries) {
      switch (entry.key) {
        case 'firstName':
          _leadData['name'] = entry.value;
          _leadData['first_name'] = entry.value;
        case 'lastName':
          _leadData['last_name'] = entry.value;
        case 'phone':
          _leadData['phone'] = entry.value;
        case 'email':
          _leadData['email'] = entry.value;
        case 'branchId':
          _leadData['branch_id'] = entry.value;
        case 'sourceId':
          _leadData['source_id'] = entry.value;
        default:
          continue;
      }
      _leadCoreEditRevisions[entry.key] = revision;
    }
    final custom = _stringMap(draft['custom']) ?? const {};
    final customData = Map<String, dynamic>.from(
      _leadData['custom_data'] as Map? ?? const {},
    );
    for (final entry in custom.entries) {
      if (entry.value == null) {
        customData.remove(entry.key);
      } else {
        customData[entry.key] = entry.value;
      }
      _leadCustomEditRevisions[entry.key] = revision;
    }
    _leadData['custom_data'] = customData;
    if (draft.containsKey('status')) {
      _leadData['status'] = draft['status'];
      _leadStatusEditRevision = revision;
    }
    if (_stringMap(draft['responsible']) case final responsible?) {
      _leadResponsibleChanged = responsible['changed'] == true;
      _putOrRemove(_leadData, 'assigned_to', responsible['assignedTo']);
      _putOrRemove(_leadData, 'assigned_name', responsible['assignedName']);
      _leadResponsibleEditRevision = revision;
    }
  }

  void _applyStudentWorkspaceDraft(Map<String, Object?> draft, int revision) {
    final student = _student;
    if (student == null) return;
    _restoredStudentExpectedVersion = _intValue(draft['expectedVersion']);
    final core = _stringMap(draft['core']) ?? const {};
    for (final entry in core.entries) {
      switch (entry.key) {
        case 'firstName':
          student['first_name'] = entry.value;
        case 'lastName':
          student['last_name'] = entry.value;
        case 'phone':
          student['phone'] = entry.value;
        case 'email':
          student['email'] = entry.value;
        case 'branchId':
          final customData = Map<String, dynamic>.from(
            student['custom_data'] as Map? ?? const {},
          );
          _putOrRemove(customData, 'branchId', entry.value);
          student['custom_data'] = customData;
        case 'sourceId':
          student['source_id'] = entry.value;
        default:
          continue;
      }
      _studentCoreEditRevisions[entry.key] = revision;
    }
    final custom = _stringMap(draft['custom']) ?? const {};
    final customData = Map<String, dynamic>.from(
      student['custom_data'] as Map? ?? const {},
    );
    for (final entry in custom.entries) {
      _putOrRemove(customData, entry.key, entry.value);
      _studentCustomEditRevisions[entry.key] = revision;
    }
    if (draft.containsKey('status')) {
      student['status'] = draft['status'];
      _studentStatusEditRevision = revision;
    }
    if (_stringMap(draft['responsible']) case final responsible?) {
      _studentResponsibleChanged = responsible['changed'] == true;
      for (final key in const [
        'responsible',
        'responsibleUserId',
        'responsibleName',
      ]) {
        _putOrRemove(customData, key, responsible[key]);
      }
      _studentResponsibleEditRevision = revision;
    }
    student['custom_data'] = customData;
  }

  void _putOrRemove(Map<String, dynamic> target, String key, Object? value) {
    if (value == null) {
      target.remove(key);
    } else {
      target[key] = value;
    }
  }

  Map<String, Object?>? _stringMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  int? _intValue(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Map<String, Object?> _expectedVersionEntry(int? version) => version == null
      ? const {}
      : <String, Object?>{'expectedVersion': version};
}
