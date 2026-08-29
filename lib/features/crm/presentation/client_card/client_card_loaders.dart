part of 'client_card.dart';

extension _ClientCardLoaders on _ClientCardState {
  // The student timeline is part of the student card payload; kept separately so
  // the merged history can fold it in alongside the lead status history.

  // Loads the student card in one round-trip (getStudentCard), mirroring
  // student_detail_screen._loadAllData. Per-section failures are isolated: the
  // bulk card load only fails the card if the student record itself is
  // unavailable; family loads independently via [_fetchFamily].
  Future<void> _fetchStudentData({
    String? studentId,
    VoidCallback? then,
    bool preserveVisibleContent = false,
  }) async {
    final id = studentId ?? _studentId;
    if (id.isEmpty) return;
    final requestEditRevision = _editRevision;
    if (mounted && !preserveVisibleContent) {
      _emitState(() {
        _loadingStudent = true;
        _studentError = null;
      });
    }
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final cardFuture = crm.getStudentCard(id);
      StudentCommerceProjection? commerce;
      try {
        final role = await _resolveActorRole();
        if (crmHasClientCardFinanceAccess(role)) {
          commerce = await crm.getStudentCommerceProjection(id);
        }
      } catch (error) {
        // Finance is an independently scoped section. Fail closed (and keep the
        // base card usable) when identity or commerce projection loading fails.
        debugPrint('Student commerce projection load failed: $error');
      }
      final card = await cardFuture;
      if (!mounted) return;
      final student = card['student'] is Map<String, dynamic>
          ? card['student'] as Map<String, dynamic>
          : <String, dynamic>{};
      student['custom_data'] = {
        ...Map<String, dynamic>.from(student['custom_data'] as Map? ?? {}),
        ...Map<String, dynamic>.from(card['custom_field_values'] as Map? ?? {}),
      };
      StudentFunnelConfiguration? funnel;
      String? funnelError;
      try {
        funnel = await crm.getClientPipeline(
          clientType: 'student',
          branchId: student['branch_id']?.toString(),
        );
      } catch (error) {
        funnelError = userErrorMessage(
          error,
          fallback: 'Не удалось загрузить воронку.',
        );
      }
      final applyIdentity =
          !preserveVisibleContent &&
          !_edited &&
          requestEditRevision == _editRevision;
      _emitState(() {
        if (applyIdentity) {
          _student = student;
        } else if (_student != null) {
          final incomingVersion = _clientVersion(student['version']);
          final currentVersion = _clientVersion(_student?['version']);
          if (incomingVersion != null &&
              (currentVersion == null || incomingVersion > currentVersion)) {
            _student!['version'] = incomingVersion;
          }
        }
        _studentFunnel = funnel;
        _studentFunnelError = funnelError;
        if (applyIdentity) _editorEpoch++;
        // Never merge finance keys from the broad base-card response. Teacher
        // therefore performs zero commerce requests and still cannot surface
        // stale/accidental balance, payment or subscription fields.
        _balance = commerce?.student.primaryBalance;
        _commerceStudent = commerce?.student;
        _subscriptions =
            commerce?.student.subscriptionModels
                .where((subscription) => subscription.isActive)
                .toList(growable: false) ??
            const <Subscription>[];
        _payments = commerce?.student.paymentModels ?? const <Payment>[];
        _lessons = _list(card['lessons']).map(Lesson.fromMap).toList();
        final indicators = Map<String, dynamic>.from(
          card['indicators'] as Map? ?? const <String, dynamic>{},
        );
        _studentIndicators = {
          for (final key in const [
            'paidMisses',
            'partiallyPaidMisses',
            'unpaidMisses',
          ])
            key: (indicators[key] as num?)?.toInt() ?? 0,
        };
        _studentTasks = _list(card['tasks']);
        _studentComments = _list(card['comments']);
        _groups = _list(card['groups']);
        _studentCardTimeline = _list(card['timeline']);
        _studentTasks.sort(
          (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
        );
        _studentComments.sort(
          (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
        );
        _studentError = null;
        _loadingStudent = false;
      });
      if (applyIdentity) {
        _syncWorkspaceTitle();
        then?.call();
      }
      _tryApplyRestoredWorkspaceDraft();
    } catch (e) {
      debugPrint('Error loading student card: $e');
      if (mounted) {
        _emitState(() {
          if (!preserveVisibleContent) {
            _studentError = userErrorMessage(
              e,
              fallback: 'Не удалось загрузить карточку ученика.',
            );
          }
          _loadingStudent = false;
        });
      }
    }
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
    VoidCallback? then,
    bool preserveVisibleContent = false,
  }) async {
    final id = leadId ?? _leadId;
    if (id.isEmpty) {
      if (mounted) _emitState(() => _loadingCard = false);
      return;
    }
    final requestEditRevision = _editRevision;
    try {
      final card = await ref.read(magicCrmServiceProvider).getLeadCard(id);
      if (!mounted) return;
      final applyIdentity =
          !preserveVisibleContent &&
          !_edited &&
          requestEditRevision == _editRevision;
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
        } else if (card['lead'] is Map<String, dynamic>) {
          final lead = card['lead'] as Map<String, dynamic>;
          final incomingVersion = _clientVersion(lead['version']);
          final currentVersion = _clientVersion(_leadData['version']);
          if (incomingVersion != null &&
              (currentVersion == null || incomingVersion > currentVersion)) {
            _leadData['version'] = incomingVersion;
          }
        }
        _loadingCard = false;
      });
      if (applyIdentity) {
        _syncWorkspaceTitle();
        then?.call();
      }
      _tryApplyRestoredWorkspaceDraft();
    } catch (e) {
      debugPrint('Lead card load failed: $e');
      if (mounted) _emitState(() => _loadingCard = false);
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

  Future<void> _fetchStatusHistory({String? leadId}) async {
    final id = leadId ?? _leadId;
    if (id.isEmpty) {
      if (mounted) _emitState(() => _loadingHistory = false);
      return;
    }
    try {
      final items = await ref
          .read(magicCrmServiceProvider)
          .getLeadStatusHistory(id);
      if (!mounted) return;
      _emitState(() {
        _statusHistory = items;
        _loadingHistory = false;
      });
    } catch (e) {
      debugPrint('Lead status history load failed: $e');
      if (mounted) _emitState(() => _loadingHistory = false);
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
