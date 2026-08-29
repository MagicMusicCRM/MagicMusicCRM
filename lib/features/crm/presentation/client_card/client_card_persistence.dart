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

int? _clientVersion(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

extension _ClientCardPersistence on _ClientCardState {
  static const _autoSaveDelay = Duration(milliseconds: 800);

  void _scheduleAutoSave() {
    if (!mounted || _autoSaveConflict) return;
    _autoSaveTimer?.cancel();
    _autoSavePending = true;
    _autoSaveTimer = Timer(_autoSaveDelay, () {
      _autoSaveTimer = null;
      unawaited(_runAutoSave());
    });
  }

  Future<bool> _runAutoSave() async {
    if (!mounted) return false;
    _autoSavePending = false;
    if (_autoSaveConflict) return false;
    if (!_edited) return true;

    final active = _autoSaveInFlight;
    if (active != null) {
      _autoSaveQueued = true;
      return active;
    }

    final revision = _editRevision;
    final save = _persistEdits(editRevision: revision);
    _autoSaveInFlight = save;
    final saved = await save;
    if (_autoSaveInFlight == save) _autoSaveInFlight = null;
    if (!mounted) return saved;

    _emitState(() => _autoSaveFailed = !saved);
    final queued = _autoSaveQueued;
    _autoSaveQueued = false;
    if (queued && _edited && !_autoSaveConflict) return _runAutoSave();
    return saved;
  }

  Future<bool> _flushAutoSave() async {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _autoSavePending = false;
    final active = _autoSaveInFlight;
    if (active != null) await active;
    if (!mounted) return false;
    if (_autoSaveConflict) return false;
    if (!_edited) return true;
    return _runAutoSave();
  }

  Future<void> _retryAutoSave() async {
    if (_saving) return;
    if (_autoSaveConflict) {
      final applyDraft = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Карточка изменилась'),
          content: const Text(
            'Другой сотрудник сохранил изменения. Применить ваши текущие поля поверх последней версии?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('client-autosave-conflict-apply'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Применить'),
            ),
          ],
        ),
      );
      if (applyDraft != true || !mounted) return;
      _autoSaveConflict = false;
      _syncWorkspaceFormDirty();
    }
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _emitState(() {
      _autoSavePending = false;
      _autoSaveFailed = false;
    });
    await _runAutoSave();
  }

  Widget _buildAutoSaveControl(ColorScheme colors, {bool enabled = true}) {
    if (_autoSaveFailed) {
      return FilledButton.icon(
        key: const Key('client-autosave-retry'),
        onPressed: enabled && !_saving
            ? () => unawaited(_retryAutoSave())
            : null,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Повторить'),
      );
    }
    final saving = _saving || _autoSavePending || _edited;
    return Semantics(
      liveRegion: true,
      label: saving ? 'Сохраняем изменения' : 'Изменения сохранены',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            saving ? Icons.sync_rounded : Icons.check_circle_outline_rounded,
            size: 17,
            color: saving ? colors.onSurfaceVariant : AppColor.success,
          ),
          const SizedBox(width: AppSpace.xs),
          Text(
            saving ? 'Сохраняем…' : 'Сохранено',
            style: TextStyle(
              color: saving ? colors.onSurfaceVariant : AppColor.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>>? _serializedTypedCustomFields(
    String entity,
    Map<String, dynamic> customData,
  ) {
    if (!_typedCustomFieldSchemaLoaded) return null;
    return [
      for (final field in _customFieldSchema)
        if (field.entity == entity &&
            field.id != null &&
            !_emptyTypedCustomValue(customData[field.key]))
          {'definitionId': field.id, 'value': customData[field.key]},
    ];
  }

  bool _emptyTypedCustomValue(Object? value) =>
      value == null ||
      (value is String && value.trim().isEmpty) ||
      (value is Iterable && value.isEmpty);

  Set<String> _fieldsThroughRevision(
    Map<String, int> revisions,
    int targetRevision,
  ) => revisions.entries
      .where((entry) => entry.value <= targetRevision)
      .map((entry) => entry.key)
      .toSet();

  Map<String, dynamic> _customPatch(
    Map<String, dynamic> current,
    Set<String> keys,
  ) => {
    for (final key in keys) key: current.containsKey(key) ? current[key] : null,
  };

  void _clearSavedRevisions(Map<String, int> revisions, int targetRevision) {
    revisions.removeWhere((_, revision) => revision <= targetRevision);
  }

  bool _revisionWasSaved(int? revision, int targetRevision) =>
      revision != null && revision <= targetRevision;

  bool _isClientVersionConflict(Object error) {
    if (error is! MagicApiException || error.statusCode != 409) return false;
    final details = error.details;
    return details is Map && details['code'] == 'CLIENT_VERSION_CONFLICT';
  }

  bool _hasTypedCustomEdit(String entity, Set<String> keys) =>
      _typedCustomFieldSchemaLoaded &&
      _customFieldSchema.any(
        (field) => field.entity == entity && keys.contains(field.key),
      );

  /// Persists the current card draft without necessarily closing the card.
  /// Subscription conversion uses the non-closing form so the server receives
  /// the latest lead fields before it snapshots them into the new student.
  Future<bool> _persistEdits({
    bool closeOnSuccess = false,
    int? editRevision,
  }) async {
    _emitState(() => _saving = true);
    try {
      final service = ref.read(magicCrmServiceProvider);
      final targetRevision = editRevision ?? _editRevision;
      final leadCoreFields = _fieldsThroughRevision(
        _leadCoreEditRevisions,
        targetRevision,
      );
      final leadCustomFields = _fieldsThroughRevision(
        _leadCustomEditRevisions,
        targetRevision,
      );
      final saveLeadStatus = _revisionWasSaved(
        _leadStatusEditRevision,
        targetRevision,
      );
      final saveLeadResponsible = _revisionWasSaved(
        _leadResponsibleEditRevision,
        targetRevision,
      );
      final hasLeadChanges =
          leadCoreFields.isNotEmpty ||
          leadCustomFields.isNotEmpty ||
          saveLeadStatus ||
          saveLeadResponsible;
      if (_mode.hasLeadHalf && _leadId.isNotEmpty && hasLeadChanges) {
        if (_clientVersion(_leadData['version']) == null) {
          await _reloadAndRebaseClientDraft();
        }
        final expectedLeadVersion =
            _restoredLeadExpectedVersion ??
            _clientVersion(_leadData['version']);
        if (expectedLeadVersion == null) {
          throw StateError('Не удалось получить версию карточки лида.');
        }
        final customData = Map<String, dynamic>.from(
          _leadData['custom_data'] as Map? ?? {},
        );
        final customDataPatch = _customPatch(customData, leadCustomFields);
        if (leadCoreFields.contains('branchId')) {
          customDataPatch['branchId'] = _leadData['branch_id'];
        }
        // #2 (контракт 6): statusId уходит только когда он UUID-формата И
        // реально изменился. Легаси-фолбэк 'new' (лид «Без статуса») или имя
        // статуса сервер отверг бы целиком — 400 на весь PATCH; пропущенное
        // поле сервер сохраняет как есть (clearStatus — отдельный явный путь).
        final rawStatus = saveLeadStatus
            ? _leadData['status']?.toString()
            : null;
        final originalStatus = _leadData['status_id']?.toString();
        final statusId =
            (rawStatus != null &&
                _uuidRe.hasMatch(rawStatus) &&
                rawStatus != originalStatus)
            ? rawStatus
            : null;
        final updatedLead = await service.updateLead(
          _leadId,
          expectedVersion: expectedLeadVersion,
          firstName: leadCoreFields.contains('firstName')
              ? _clientFirstName
              : null,
          lastName: leadCoreFields.contains('lastName')
              ? _clientLastName
              : null,
          phone: leadCoreFields.contains('phone') ? _clientPhone : null,
          email: leadCoreFields.contains('email') ? _clientEmail : null,
          sourceId: leadCoreFields.contains('sourceId')
              ? _clientSourceId
              : null,
          statusId: statusId,
          assignedTo: saveLeadResponsible
              ? _leadData['assigned_to']?.toString()
              : null,
          clearAssignedTo:
              saveLeadResponsible &&
              _leadResponsibleChanged &&
              (_leadData['assigned_to']?.toString().trim().isEmpty ?? true),
          customDataPatch: customDataPatch.isEmpty ? null : customDataPatch,
          customFields: _hasTypedCustomEdit('leads', leadCustomFields)
              ? _serializedTypedCustomFields('leads', customData)
              : null,
        );
        _leadData['version'] = updatedLead['version'] ?? _leadData['version'];
        _restoredLeadExpectedVersion = null;
        _clearSavedRevisions(_leadCoreEditRevisions, targetRevision);
        _clearSavedRevisions(_leadCustomEditRevisions, targetRevision);
        if (_revisionWasSaved(_leadStatusEditRevision, targetRevision)) {
          _leadStatusEditRevision = null;
        }
        if (_revisionWasSaved(_leadResponsibleEditRevision, targetRevision)) {
          _leadResponsibleEditRevision = null;
          _leadResponsibleChanged = false;
        }
      }

      final studentCoreFields = _fieldsThroughRevision(
        _studentCoreEditRevisions,
        targetRevision,
      );
      final studentCustomFields = _fieldsThroughRevision(
        _studentCustomEditRevisions,
        targetRevision,
      );
      final saveStudentStatus = _revisionWasSaved(
        _studentStatusEditRevision,
        targetRevision,
      );
      final saveStudentResponsible = _revisionWasSaved(
        _studentResponsibleEditRevision,
        targetRevision,
      );
      final hasStudentChanges =
          studentCoreFields.isNotEmpty ||
          studentCustomFields.isNotEmpty ||
          saveStudentStatus ||
          saveStudentResponsible;
      if (_mode.hasStudentHalf && _studentId.isNotEmpty && hasStudentChanges) {
        if (_clientVersion(_student?['version']) == null) {
          await _reloadAndRebaseClientDraft();
        }
        final expectedStudentVersion =
            _restoredStudentExpectedVersion ??
            _clientVersion(_student?['version']);
        if (expectedStudentVersion == null) {
          throw StateError('Не удалось получить версию карточки ученика.');
        }
        final customData = Map<String, dynamic>.from(
          _student?['custom_data'] as Map? ?? {},
        );
        final customDataPatch = _customPatch(customData, studentCustomFields);
        if (saveStudentResponsible && _hasResponsibleInCustomData(customData)) {
          for (final key in const [
            'responsible',
            'responsibleUserId',
            'responsibleName',
          ]) {
            if (customData.containsKey(key)) {
              customDataPatch[key] = customData[key];
            }
          }
        }
        if (studentCoreFields.contains('branchId')) {
          customDataPatch['branchId'] = _clientBranchId;
        }
        final updatedStudent = await service.updateStudent(
          _studentId,
          expectedVersion: expectedStudentVersion,
          firstName: studentCoreFields.contains('firstName')
              ? _clientFirstName
              : null,
          lastName: studentCoreFields.contains('lastName')
              ? _clientLastName
              : null,
          phone: studentCoreFields.contains('phone') ? _clientPhone : null,
          email: studentCoreFields.contains('email') ? _clientEmail : null,
          status: saveStudentStatus ? (_student?['status']?.toString()) : null,
          sourceId: studentCoreFields.contains('sourceId')
              ? _clientSourceId
              : null,
          clearResponsible:
              saveStudentResponsible &&
              _studentResponsibleChanged &&
              !_hasResponsibleInCustomData(customData),
          customDataPatch: customDataPatch.isEmpty ? null : customDataPatch,
          customFields: _hasTypedCustomEdit('students', studentCustomFields)
              ? _serializedTypedCustomFields('students', customData)
              : null,
        );
        if (_student != null) {
          _student!['version'] =
              updatedStudent['version'] ?? _student!['version'];
        }
        _restoredStudentExpectedVersion = null;
        _clearSavedRevisions(_studentCoreEditRevisions, targetRevision);
        _clearSavedRevisions(_studentCustomEditRevisions, targetRevision);
        if (_revisionWasSaved(_studentStatusEditRevision, targetRevision)) {
          _studentStatusEditRevision = null;
        }
        if (_revisionWasSaved(
          _studentResponsibleEditRevision,
          targetRevision,
        )) {
          _studentResponsibleEditRevision = null;
          _studentResponsibleChanged = false;
        }
      }
      // Routed desktop cards live in a separate workspace tab, so their caller
      // cannot reliably receive a dialog result and refresh the board. Drop
      // every cached filter variant here after the successful mutation.
      if (_mode.hasLeadHalf) {
        ref.invalidate(leadBoardProvider);
        ref.invalidate(leadBoardItemsProvider);
      }
      if (_mode.hasStudentHalf) ref.invalidate(studentBoardProvider);
      if (mounted) {
        _markDirty(() {
          _autoSaveConflict = false;
          if (!_hasPendingCardEdits) {
            _edited = false;
          }
        });
        _runDeferredRealtimeRefresh();
      }
      if (mounted && closeOnSuccess) {
        _closeCard(true);
      }
      return true;
    } catch (e) {
      final versionConflict = _isClientVersionConflict(e);
      if (versionConflict) {
        await _reloadAndRebaseClientDraft();
        _restoredLeadExpectedVersion = null;
        _restoredStudentExpectedVersion = null;
        _autoSaveConflict = true;
        _syncWorkspaceFormDirty();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              versionConflict
                  ? 'Карточку изменил другой сотрудник. Ваши поля остались здесь — нажмите «Повторить», чтобы применить их явно.'
                  : userErrorMessage(
                      e,
                      fallback: 'Не удалось сохранить карточку.',
                    ),
            ),
          ),
        );
      }
      return false;
    } finally {
      if (mounted) {
        _emitState(() => _saving = false);
      }
    }
  }

  Future<void> _reloadAndRebaseClientDraft() async {
    try {
      final service = ref.read(magicCrmServiceProvider);
      Map<String, dynamic>? leadCard;
      Map<String, dynamic>? studentCard;
      if (_mode.hasLeadHalf && _leadId.isNotEmpty) {
        leadCard = await service.getLeadCard(_leadId);
      }
      if (_mode.hasStudentHalf && _studentId.isNotEmpty) {
        studentCard = await service.getStudentCard(_studentId);
      }
      if (!mounted) return;
      _emitState(() {
        final latestLead = leadCard?['lead'];
        if (latestLead is Map) {
          final local = Map<String, dynamic>.from(_leadData);
          final rebased = {...local, ...Map<String, dynamic>.from(latestLead)};
          void preserve(String revisionKey, List<String> storageKeys) {
            if (!_leadCoreEditRevisions.containsKey(revisionKey)) return;
            for (final key in storageKeys) {
              if (local.containsKey(key)) {
                rebased[key] = local[key];
              } else {
                rebased.remove(key);
              }
            }
          }

          preserve('firstName', const ['name', 'first_name']);
          preserve('lastName', const ['last_name']);
          preserve('phone', const ['phone']);
          preserve('email', const ['email']);
          preserve('branchId', const ['branch_id']);
          preserve('sourceId', const ['source_id']);
          if (_leadStatusEditRevision != null) {
            rebased['status'] = local['status'];
          }
          if (_leadResponsibleEditRevision != null) {
            for (final key in const ['assigned_to', 'assigned_name']) {
              if (local.containsKey(key)) {
                rebased[key] = local[key];
              } else {
                rebased.remove(key);
              }
            }
          }
          final latestCustom = {
            ...Map<String, dynamic>.from(
              rebased['custom_data'] as Map? ?? const {},
            ),
            ...Map<String, dynamic>.from(
              leadCard?['custom_field_values'] as Map? ?? const {},
            ),
          };
          final localCustom = Map<String, dynamic>.from(
            local['custom_data'] as Map? ?? const {},
          );
          for (final key in _leadCustomEditRevisions.keys) {
            if (localCustom.containsKey(key)) {
              latestCustom[key] = localCustom[key];
            } else {
              latestCustom.remove(key);
            }
          }
          rebased['custom_data'] = latestCustom;
          _leadData = rebased;
          _leadCard = leadCard;
        }

        final latestStudent = studentCard?['student'];
        if (latestStudent is Map && _student != null) {
          final local = Map<String, dynamic>.from(_student!);
          final rebased = {
            ...local,
            ...Map<String, dynamic>.from(latestStudent),
          };
          void preserve(String revisionKey, List<String> storageKeys) {
            if (!_studentCoreEditRevisions.containsKey(revisionKey)) return;
            for (final key in storageKeys) {
              if (local.containsKey(key)) {
                rebased[key] = local[key];
              } else {
                rebased.remove(key);
              }
            }
          }

          preserve('firstName', const ['first_name']);
          preserve('lastName', const ['last_name']);
          preserve('phone', const ['phone']);
          preserve('email', const ['email']);
          preserve('branchId', const ['branch_id']);
          preserve('sourceId', const ['source_id']);
          if (_studentStatusEditRevision != null) {
            rebased['status'] = local['status'];
          }
          final latestCustom = {
            ...Map<String, dynamic>.from(
              rebased['custom_data'] as Map? ?? const {},
            ),
            ...Map<String, dynamic>.from(
              studentCard?['custom_field_values'] as Map? ?? const {},
            ),
          };
          final localCustom = Map<String, dynamic>.from(
            local['custom_data'] as Map? ?? const {},
          );
          final preservedCustomKeys = <String>{
            ..._studentCustomEditRevisions.keys,
            if (_studentResponsibleEditRevision != null) ...const {
              'responsible',
              'responsibleUserId',
              'responsibleName',
            },
          };
          for (final key in preservedCustomKeys) {
            if (localCustom.containsKey(key)) {
              latestCustom[key] = localCustom[key];
            } else {
              latestCustom.remove(key);
            }
          }
          rebased['custom_data'] = latestCustom;
          _student = rebased;
        }
        _editorEpoch++;
      });
      _syncWorkspaceTitle();
    } catch (error) {
      debugPrint('Client conflict rebase failed: $error');
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
              content: Text(
                userErrorMessage(e, fallback: 'Не удалось прикрепить файл.'),
              ),
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
      final revision = _editRevision;
      if (entity == 'students') {
        _studentCustomEditRevisions[key] = revision;
        if (_isConverted &&
            _ClientCardState._commonClientCustomFieldKeys.contains(key)) {
          _leadCustomEditRevisions[key] = revision;
        }
      } else {
        _leadCustomEditRevisions[key] = revision;
        if (_isConverted &&
            _ClientCardState._commonClientCustomFieldKeys.contains(key)) {
          _studentCustomEditRevisions[key] = revision;
        }
      }
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
      _markDirty();
      await Future.wait([_fetchCard(), _fetchDuplicateCandidates()]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Лид связан с существующим учеником')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorMessage(e, fallback: 'Не удалось изменить связь.'),
          ),
        ),
      );
    } finally {
      if (mounted) _emitState(() => _duplicateDecisionId = null);
    }
  }
}
