part of 'client_card.dart';

/// UUID-формат (8-4-4-4-12 hex). Сервер валидирует `statusId` как `@IsUUID()`,
/// поэтому легаси-значения вроде 'new' или имени статуса слать нельзя — они
/// роняют весь PATCH, включая правки имени/телефона (#2).
final RegExp _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool _hasResponsibleInCustomData(Map<String, dynamic> customData) {
  for (final key in const [
    'responsibleUserId',
    'responsible',
    'responsibleName',
  ]) {
    if ((customData[key]?.toString().trim() ?? '').isNotEmpty) return true;
  }
  return false;
}

extension _ClientCardData on _ClientCardState {
  /// lead half (lead card, status history, statuses, metadata) and flip to
  /// `converted`. Failures degrade silently back to studentOnly.
  void _resolveLeadCounterpart() {
    if (!mounted) return;
    final leadId = _student?['lead_id']?.toString();
    if (leadId == null || leadId.isEmpty) return;
    _emitState(() {
      _mode = ClientMode.converted;
      _resolvedLeadId = leadId;
      // Lead-side sections start loading now.
      _loadingCard = true;
      _loadingHistory = true;
    });
    // Parallel, isolated lead-half fetches against the resolved lead id. Lead
    // statuses are needed for the header label and the originating-lead card;
    // the editable lead form / branch metadata isn't shown in converted mode,
    // so we skip _fetchMetadata here.
    _statuses = widget.allStatuses ?? _statuses;
    if (_statuses.isEmpty) _fetchStatuses();
    _fetchCard(leadId: leadId);
    _fetchStatusHistory(leadId: leadId);
  }

  /// Lead-opened path: if the lead card lists linked students, pick the primary
  /// (first / most recent) one, fetch the student half and flip to `converted`.
  /// Additional linked students stay visible via the existing linked-students
  /// UI. Failures degrade silently back to leadOnly.
  void _resolveStudentCounterpart() {
    if (!mounted) return;
    final linked = _list(_leadCard?['linked_students']);
    if (linked.isEmpty) return;
    final primary = _primaryLinkedStudent(linked);
    final studentId = primary?['id']?.toString();
    if (studentId == null || studentId.isEmpty) return;
    _emitState(() {
      _mode = ClientMode.converted;
      _resolvedStudentId = studentId;
      _loadingStudent = true;
      _studentError = null;
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

  // ── Merged section data (Phase 4) ─────────────────────────────────────────
  // Each merge tags rows with `_origin` (entityType) so converted views can show
  // an origin chip, then de-dups by `id` and sorts desc by date. Single-side
  // modes return just their own half (no behavioural change vs Phase 1/2).

  List<Map<String, dynamic>> _origin(
    List<Map<String, dynamic>> rows,
    String entityType,
  ) => rows.map((r) => {...r, '_origin': entityType}).toList();

  /// Lead tasks (from the lead card) + student tasks, de-duped by id.
  List<Map<String, dynamic>> get _mergedTasks {
    final leadTasks = _mode.hasLeadHalf
        ? _origin(_list(_leadCard?['tasks']), 'lead')
        : const <Map<String, dynamic>>[];
    final studentTasks = _mode.hasStudentHalf
        ? _origin(_studentTasks, 'student')
        : const <Map<String, dynamic>>[];
    return mergeByIdSorted([studentTasks, leadTasks], dateKey: 'created_at');
  }

  /// Lead status history + student timeline, normalised onto a shared shape and
  /// merged/sorted desc. Returns rows with: `_kind` ('status'|'event'),
  /// `_origin`, `_date`, `_title`, `_subtitle`.
  List<Map<String, dynamic>> get _mergedHistory {
    final out = <List<Map<String, dynamic>>>[];
    if (_mode.hasLeadHalf) {
      out.add(
        _statusHistory.map((h) {
          final from = h['old_status']?.toString();
          final to = h['new_status']?.toString();
          final transition = [
            if (from != null && from.isNotEmpty) from else '—',
            '→',
            if (to != null && to.isNotEmpty) to else '—',
          ].join(' ');
          final comment = h['comment']?.toString().trim() ?? '';
          return {
            'id': h['id'],
            '_origin': 'lead',
            '_kind': 'status',
            '_date': h['changed_at'],
            '_title': transition,
            '_subtitle': comment,
          };
        }).toList(),
      );
      // Field edits («кто поменял телефон»). Only the audit rows of the lead
      // timeline: the rest of it (comments, tasks, trials) already has its own
      // sections on the card and would show up twice here.
      out.add(
        _list(
          _leadCard?['timeline'],
        ).where((t) => t['type']?.toString() == 'audit').map((t) {
          return {
            'id': t['id'],
            '_origin': 'lead',
            '_kind': 'event',
            '_date': t['occurred_at'],
            '_title': t['title']?.toString() ?? 'Событие',
            '_subtitle': [
              if ((t['actor_name']?.toString().trim() ?? '').isNotEmpty)
                t['actor_name'].toString().trim(),
              if ((t['body']?.toString().trim() ?? '').isNotEmpty)
                t['body'].toString().trim(),
            ].join('\n'),
          };
        }).toList(),
      );
    }
    if (_mode.hasStudentHalf) {
      out.add(
        _list(_studentCardTimeline).map((t) {
          final body = t['body']?.toString().trim() ?? '';
          final actor = t['actor_name']?.toString().trim() ?? '';
          // For a field edit the author IS the point («кто поменял телефон»);
          // for a comment or lesson the card already shows it elsewhere.
          final isAudit = t['type']?.toString() == 'audit';
          return {
            'id': t['id'],
            '_origin': 'student',
            '_kind': 'event',
            '_date': t['occurred_at'],
            '_title': t['title']?.toString() ?? 'Событие',
            '_subtitle': isAudit && actor.isNotEmpty
                ? [actor, if (body.isNotEmpty) body].join('\n')
                : body,
          };
        }).toList(),
      );
    }
    return mergeByIdSorted(out, dateKey: '_date');
  }

  // The student timeline is part of the student card payload; kept separately so
  // the merged history can fold it in alongside the lead status history.

  // True when the lead card lists at least one linked student — used to hide the
  // «Создать ученика» button even before resolution flips the mode.
  bool get _hasLinkedStudent => _list(_leadCard?['linked_students']).isNotEmpty;

  // Loads the student card in one round-trip (getStudentCard), mirroring
  // student_detail_screen._loadAllData. Per-section failures are isolated: the
  // bulk card load only fails the card if the student record itself is
  // unavailable; family loads independently via [_fetchFamily].
  Future<void> _fetchStudentData({
    String? studentId,
    VoidCallback? then,
  }) async {
    final id = studentId ?? _studentId;
    if (id.isEmpty) return;
    if (mounted) {
      _emitState(() {
        _loadingStudent = true;
        _studentError = null;
      });
    }
    try {
      final crm = ref.read(magicCrmServiceProvider);
      final card = await crm.getStudentCard(id);
      if (!mounted) return;
      final student = card['student'] is Map<String, dynamic>
          ? card['student'] as Map<String, dynamic>
          : <String, dynamic>{};
      _emitState(() {
        _student = student;
        _editorEpoch++;
        _balance = card['balance'] is Map<String, dynamic>
            ? StudentBalance.fromMap(card['balance'] as Map<String, dynamic>)
            : null;
        _subscriptions = _list(
          card['subscriptions'],
        ).map(Subscription.fromMap).toList();
        _payments = _list(card['payments']).map(Payment.fromMap).toList();
        _lessons = _list(card['lessons']).map(Lesson.fromMap).toList();
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
        _loadingStudent = false;
      });
      then?.call();
    } catch (e) {
      debugPrint('Error loading student card: $e');
      if (mounted) {
        _emitState(() {
          _studentError = '$e';
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

  Future<void> _fetchCard({String? leadId, VoidCallback? then}) async {
    final id = leadId ?? _leadId;
    if (id.isEmpty) {
      if (mounted) _emitState(() => _loadingCard = false);
      return;
    }
    try {
      final card = await ref.read(magicCrmServiceProvider).getLeadCard(id);
      if (!mounted) return;
      _emitState(() {
        _leadCard = card;
        if (card['lead'] is Map<String, dynamic>) {
          _leadData = {..._leadData, ...(card['lead'] as Map<String, dynamic>)};
          _editorEpoch++;
          // After merging the lead record, `_leadData['id']` is the lead id —
          // keep `_resolvedLeadId` in sync so lead-side ops target it.
          _resolvedLeadId = _leadData['id']?.toString() ?? id;
        }
        _loadingCard = false;
      });
      then?.call();
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

  Future<void> _fetchMetadata() async {
    final crm = ref.read(magicCrmServiceProvider);
    final settings = ref.read(magicSettingsServiceProvider);
    final results = await Future.wait<dynamic>([
      crm.listBranches(limit: 100),
      settings.getCrmCustomFields(),
      // KVA-234: справочник дисциплин для мультивыбора; сбой не роняет форму.
      crm.listDisciplines().catchError((_) => const <Map<String, dynamic>>[]),
    ]);

    if (mounted) {
      _emitState(() {
        _branches = List<Map<String, dynamic>>.from(results[0] as List);
        _customFieldSchema = results[1] as List<CrmCustomFieldDefinition>;
        _disciplineOptions = List<Map<String, dynamic>>.from(
          results[2] as List,
        );
        _loadingMetadata = false;
      });
    }
  }

  void _scheduleRealtimeRefresh(String entity) {
    if (!mounted || _realtimeRefreshQueued) return;
    if (_edited && (entity == 'lead' || entity == 'student')) return;
    _realtimeRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _realtimeRefreshQueued = false;
      _refreshFromRealtime(entity);
    });
  }

  void _refreshFromRealtime(String entity) {
    switch (entity) {
      case 'homework':
        _emitState(() => _homeworkRefreshKey++);
        break;
      case 'lead':
      case 'student':
      case 'task':
      case 'comment':
      case 'lesson':
      case 'payment':
      case 'subscription':
      case 'group':
      case 'chat_work':
        if (_mode.hasLeadHalf && _leadId.isNotEmpty) {
          _fetchCard();
          _fetchStatusHistory();
        }
        if (_mode.hasStudentHalf && _studentId.isNotEmpty) {
          _fetchStudentData();
        }
        _fetchFamily();
        break;
    }
  }

  Future<void> _save() async {
    _emitState(() => _saving = true);
    try {
      final service = ref.read(magicCrmServiceProvider);
      if (_mode.hasLeadHalf && _leadId.isNotEmpty) {
        final customData = Map<String, dynamic>.from(
          _leadData['custom_data'] as Map? ?? {},
        );
        if (_leadData['branch_id'] != null) {
          customData['branchId'] = _leadData['branch_id'];
        }
        // #2 (контракт 6): statusId уходит только когда он UUID-формата И
        // реально изменился. Легаси-фолбэк 'new' (лид «Без статуса») или имя
        // статуса сервер отверг бы целиком — 400 на весь PATCH; пропущенное
        // поле сервер сохраняет как есть (clearStatus — отдельный явный путь).
        final rawStatus = _leadData['status']?.toString();
        final originalStatus = _leadData['status_id']?.toString();
        final statusId =
            (rawStatus != null &&
                _uuidRe.hasMatch(rawStatus) &&
                rawStatus != originalStatus)
            ? rawStatus
            : null;
        await service.updateLead(
          _leadId,
          firstName: _clientFirstName,
          lastName: _clientLastName,
          phone: _clientPhone,
          email: _clientEmail,
          statusId: statusId,
          assignedTo: _leadData['assigned_to']?.toString(),
          clearAssignedTo:
              _leadResponsibleChanged &&
              (_leadData['assigned_to']?.toString().trim().isEmpty ?? true),
          customDataPatch: customData,
        );
      }

      if (_mode.hasStudentHalf && _studentId.isNotEmpty) {
        final customData = Map<String, dynamic>.from(
          _student?['custom_data'] as Map? ?? {},
        );
        final branchId = _clientBranchId;
        if (branchId != null && branchId.isNotEmpty) {
          customData['branchId'] = branchId;
        }
        await service.updateStudent(
          _studentId,
          firstName: _clientFirstName,
          lastName: _clientLastName,
          phone: _clientPhone,
          email: _clientEmail,
          status: _student?['status']?.toString(),
          clearResponsible:
              _studentResponsibleChanged &&
              !_hasResponsibleInCustomData(customData),
          customDataPatch: customData,
        );
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
      }
    } finally {
      if (mounted) {
        _emitState(() => _saving = false);
      }
    }
  }

  /// «Прикрепить к ученику»: связать лида с уже заведённым учеником.
  ///
  /// Поиск серверный: учеников тысячи, и подгружать их пачкой в клиент значило
  /// бы, что нужного в списке просто не окажется.
  Future<void> _linkExistingStudent() async {
    final crm = ref.read(magicCrmServiceProvider);

    Future<List<SearchableSelectItem>> search(String query) async {
      final response = await crm.searchStudents(q: query, limit: 5);
      final items = response['items'];
      if (items is! List) return const <SearchableSelectItem>[];
      return items.whereType<Map<String, dynamic>>().map((student) {
        final name = [
          student['first_name'] ?? student['firstName'],
          student['last_name'] ?? student['lastName'],
        ].where((v) => (v?.toString().trim() ?? '').isNotEmpty).join(' ');
        return SearchableSelectItem(
          id: student['id'].toString(),
          label: name.isEmpty ? 'Без имени' : name,
          subtitle: student['phone']?.toString(),
        );
      }).toList();
    }

    SearchableSelect.show(
      context: context,
      title: 'Прикрепить к ученику',
      hintText: 'Имя или телефон…',
      items: const [],
      isNullable: false,
      onSearch: search,
      onSelected: (item) async {
        if (item == null) return;
        try {
          await crm.linkStudentToLead(
            leadId: _resolvedLeadId ?? _leadId,
            studentId: item.id,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Лид прикреплён к ученику «${item.label}»')),
          );
          // Перечитываем карточку: у лида появился связанный ученик, и режим
          // карточки должен это увидеть.
          await _fetchCard();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Не удалось прикрепить: $e'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      },
    );
  }

  void _updateCustomDataForEntity(String entity, String key, dynamic value) {
    _emitState(() {
      void put(Map<String, dynamic> target) {
        final cd = Map<String, dynamic>.from(target['custom_data'] ?? {});
        if (value == null || value == '') {
          cd.remove(key);
        } else {
          cd[key] = value;
        }
        target['custom_data'] = cd;
      }

      if (entity == 'students' && _student != null) {
        put(_student!);
        if (_isConverted &&
            _ClientCardState._commonClientCustomFieldKeys.contains(key)) {
          put(_leadData);
        }
      } else {
        put(_leadData);
        if (_isConverted &&
            _student != null &&
            _ClientCardState._commonClientCustomFieldKeys.contains(key)) {
          put(_student!);
        }
      }
      _edited = true;
    });
  }

  Future<void> _attachDuplicateCandidate(Map<String, dynamic> candidate) async {
    final candidateId = candidate['id']?.toString();
    if (candidateId == null || candidateId.isEmpty) return;
    final student = _candidateEntity(candidate, 'student');
    final studentName = student['name']?.toString().trim();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Связать с учеником?'),
        content: Text(
          studentName == null || studentName.isEmpty
              ? 'Лид будет прикреплен к существующей карточке ученика.'
              : 'Лид будет прикреплен к ученику "$studentName".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Связать'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    _emitState(() => _duplicateDecisionId = candidateId);
    try {
      await ref
          .read(magicCrmServiceProvider)
          .decideDuplicateCandidate(
            candidateId,
            status: 'attached',
            notes: 'Связано из карточки лида',
          );
      _dirty = true;
      await Future.wait([_fetchCard(), _fetchDuplicateCandidates()]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лид связан с существующим учеником')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ошибка связи: $e')));
    } finally {
      if (mounted) _emitState(() => _duplicateDecisionId = null);
    }
  }
}
