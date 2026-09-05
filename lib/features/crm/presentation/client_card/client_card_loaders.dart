part of 'client_card.dart';

extension _ClientCardLoaders on _ClientCardState {
  // Loads the student card in one round-trip (getStudentCard), mirroring
  // student_detail_screen._loadAllData. Per-section failures are isolated: the
  // bulk card load only fails the card if the student record itself is
  // unavailable; family loads independently via [_fetchFamily].
  Future<void> _fetchStudentData({
    String? studentId,
    bool preserveVisibleContent = false,
  }) => AppPerformance.measureScreen(
    AppOperation.studentCard,
    () => _fetchStudentSnapshot(
      studentId: studentId,
      preserveVisibleContent: preserveVisibleContent,
    ),
    isVisible: () => mounted && _realtimeVisible,
  );

  Future<void> _fetchStudentSnapshot({
    String? studentId,
    bool preserveVisibleContent = false,
  }) async {
    final id = studentId ?? _studentId;
    final requestEditRevision = _draft.revision;
    final snapshot = await _readController.loadStudent(
      id,
      preserveContent: preserveVisibleContent,
    );
    if (!mounted || snapshot == null) return;
    final applyIdentity =
        !preserveVisibleContent &&
        !_edited &&
        requestEditRevision == _draft.revision;
    if (applyIdentity) {
      _emitState(() {
        _student = {
          ...snapshot.student,
          'custom_data': Map<String, dynamic>.from(
            snapshot.student['custom_data'] as Map? ?? {},
          ),
        };
        _editorEpoch++;
      });
      _syncWorkspaceTitle();
      _resolveLeadCounterpart();
    }
    _tryApplyRestoredWorkspaceDraft();
  }

  Future<void> _fetchStatuses() async {
    try {
      final raw = await ref.read(leadStatusesProvider.future);
      if (!mounted) return;
      _emitState(() {
        _statuses = raw
            .map<StatusRecord>(
              (r) => (
                r['key'].toString(),
                r['label'].toString(),
                statusColorFromValue(r['color']),
              ),
            )
            .toList();
      });
    } catch (e) {
      // Card still renders with a fallback status; log so the failure is not
      // completely silent during development.
      debugPrint('Lead status list load failed: $e');
    }
  }

  Future<void> _fetchCard({
    String? leadId,
    bool preserveVisibleContent = false,
  }) async {
    final id = leadId ?? _leadId;
    final requestEditRevision = _draft.revision;
    try {
      final card = await _readController.loadLead(id, applySnapshot: false);
      if (!mounted || card == null) {
        return;
      }
      final applyIdentity =
          !preserveVisibleContent &&
          !_edited &&
          requestEditRevision == _draft.revision;
      _emitState(() {
        if (applyIdentity) _leadCard = card;
        if (applyIdentity && card['lead'] is Map<String, dynamic>) {
          _leadData = {..._leadData, ...(card['lead'] as Map<String, dynamic>)};
          _leadData['custom_data'] = {
            ...Map<String, dynamic>.from(
              _leadData['custom_data'] as Map? ?? {},
            ),
            ...Map<String, dynamic>.from(
              card['custom_field_values'] as Map? ?? {},
            ),
          };
          _editorEpoch++;
          // After merging the lead record, `_leadData['id']` is the lead id —
          // keep `_resolvedLeadId` in sync so lead-side ops target it.
          _resolvedLeadId = _leadData['id']?.toString() ?? id;
        }
      });
      if (applyIdentity) {
        _syncWorkspaceTitle();
        _resolveStudentCounterpart();
      }
      _tryApplyRestoredWorkspaceDraft();
    } catch (e) {
      debugPrint('Lead card load failed: $e');
    }
  }

  Future<void> _fetchDuplicateCandidates() async {
    final leadId = _leadData['id']?.toString() ?? widget.lead['id']?.toString();
    if (leadId == null || leadId.isEmpty) {
      if (mounted) _emitState(() => _loadingDuplicates = false);
      return;
    }
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .listDuplicateCandidates(leadId: leadId, limit: 20);
      if (!mounted) return;
      _emitState(() {
        _duplicateCandidates = items
            .where(_isCurrentLeadDuplicateCandidate)
            .toList();
        _loadingDuplicates = false;
      });
    } catch (e) {
      debugPrint('Duplicate candidates load failed: $e');
      if (mounted) _emitState(() => _loadingDuplicates = false);
    }
  }

  Future<void> _fetchFamily() async {
    try {
      final result = await ref
          .read(magicCrmServiceProvider)
          .getFamilyForEntity(
            entityType: widget.entityType,
            entityId: widget.lead['id'].toString(),
          );
      if (!mounted) return;
      _emitState(() {
        _family = result;
        _loadingFamily = false;
      });
    } catch (e) {
      debugPrint('Family load failed: $e');
      if (mounted) _emitState(() => _loadingFamily = false);
    }
  }

  Future<void> _fetchClientAccess() async {
    try {
      final role = await _resolveActorRole();
      if (!crmHasManagerAccess(role)) return;
      if (mounted) {
        _emitState(() {
          _clientAccessAllowed = true;
          _loadingClientAccess = true;
          _clientAccessError = null;
        });
      }
      final crm = ref.read(magicCrmServiceProvider);
      final values = await Future.wait<List<Map<String, dynamic>>>([
        crm.getClientLinkedUsers(widget.entityType, _entityId),
        crm.listClientUserCandidates(widget.entityType, _entityId),
      ]);
      if (!mounted) return;
      _emitState(() {
        _linkedUsers = values[0];
        _clientUserCandidates = values[1];
        _loadingClientAccess = false;
      });
    } catch (error) {
      if (!mounted) return;
      _emitState(() {
        _clientAccessError = userErrorMessage(
          error,
          fallback: 'Не удалось загрузить доступ клиента.',
        );
        _loadingClientAccess = false;
      });
    }
  }

  Future<void> _fetchMetadata() async {
    final crm = ref.read(magicCrmServiceProvider);
    final forms = ref.read(clientFormsApiProvider);
    final results = await Future.wait<dynamic>([
      crm.listBranches(limit: 100),
      forms.listFields(entityType: 'lead'),
      forms.listFields(entityType: 'student'),
      // KVA-234: справочник дисциплин для мультивыбора; сбой не роняет форму.
      crm.listDisciplines().catchError((_) => const <Map<String, dynamic>>[]),
      forms.listSources(includeArchived: true),
    ]);

    if (mounted) {
      _emitState(() {
        _branches = List<Map<String, dynamic>>.from(results[0] as List);
        _customFieldSchema = [
          for (final row in results[1] as List<Map<String, dynamic>>)
            CrmCustomFieldDefinition.fromClientConfig(row),
          for (final row in results[2] as List<Map<String, dynamic>>)
            CrmCustomFieldDefinition.fromClientConfig(row),
        ];
        _typedCustomFieldSchemaLoaded = true;
        _disciplineOptions = List<Map<String, dynamic>>.from(
          results[3] as List,
        );
        _sources = List<Map<String, dynamic>>.from(results[4] as List);
        _loadingMetadata = false;
      });
    }
  }
}
