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

extension _ClientCardPersistence on _ClientCardState {
  Future<void> _save() async {
    await _persistEdits(closeOnSuccess: true);
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

  /// Persists the current card draft without necessarily closing the card.
  /// Subscription conversion uses the non-closing form so the server receives
  /// the latest lead fields before it snapshots them into the new student.
  Future<bool> _persistEdits({bool closeOnSuccess = false}) async {
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
          sourceId: _clientSourceId,
          statusId: statusId,
          assignedTo: _leadData['assigned_to']?.toString(),
          clearAssignedTo:
              _leadResponsibleChanged &&
              (_leadData['assigned_to']?.toString().trim().isEmpty ?? true),
          customDataPatch: customData,
          customFields: _serializedTypedCustomFields('leads', customData),
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
          sourceId: _clientSourceId,
          clearResponsible:
              _studentResponsibleChanged &&
              !_hasResponsibleInCustomData(customData),
          customDataPatch: customData,
          customFields: _serializedTypedCustomFields('students', customData),
        );
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
        _emitState(() {
          _edited = false;
          _dirty = true;
        });
      }
      if (mounted && closeOnSuccess) {
        _closeCard(true);
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userErrorMessage(e, fallback: 'Не удалось сохранить карточку.'),
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
