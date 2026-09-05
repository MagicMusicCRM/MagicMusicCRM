part of 'client_card.dart';

extension _ClientCardAssignmentEditors on _ClientCardState {
  Widget _buildBranchDropdown(ColorScheme cs, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: SearchablePickerField(
        label: label,
        selectedId: _clientBranchId,
        placeholder: 'Выберите филиал',
        hintText: 'Введите название филиала',
        isNullable: false,
        items: _branches
            .map(
              (branch) => SearchableSelectItem(
                id: branch['id'].toString(),
                label: branch['name']?.toString() ?? 'Не указано',
              ),
            )
            .toList(growable: false),
        onSelected: (item) => _updateClientCore('branchId', item?.id),
      ),
    );
  }

  Widget _buildSourceDropdown(ColorScheme cs) {
    final current = _clientSourceId;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: SearchablePickerField(
        key: ValueKey('client-source-$_editorEpoch'),
        label: 'Рекламный источник *',
        selectedId: current,
        placeholder: 'Выберите источник',
        hintText: 'Введите название источника',
        isNullable: false,
        items: _sources
            .where(
              (source) =>
                  source['isActive'] == true ||
                  source['id']?.toString() == current,
            )
            .map((source) {
              final id = source['id']?.toString() ?? '';
              final active = source['isActive'] == true;
              return SearchableSelectItem(
                id: id,
                label:
                    '${active ? '' : 'Архив · '}${source['displayName'] ?? 'Не указано'}',
              );
            })
            .toList(growable: false),
        onSelected: (item) => _updateClientCore('sourceId', item?.id),
      ),
    );
  }

  // ── #7: пикер «Ответственный» ─────────────────────────────────────────────
  // Заменяет свободный текст выбором сотрудника из GET /api/admin/staff.
  // Пишет custom_data.responsible (имя — обратная совместимость с бэкфиллом
  // HolliHop) и custom_data.responsibleUserId (uuid). Показ подхватывает и
  // легаси responsibleName, у которого id нет.

  String? _responsibleDisplayValue(String entity) {
    if (entity == 'leads') {
      final assignedName = _leadData['assigned_name']?.toString().trim();
      if (assignedName != null && assignedName.isNotEmpty) return assignedName;
    }
    final customData = _customDataForEntity(entity);
    for (final key in const ['responsible', 'responsibleName']) {
      final v = customData[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    // Кросс-половинный легаси-фолбэк (responsibleName другой половины или
    // FullName первого assignee из выгрузки HolliHop).
    return _responsibleLabel();
  }

  void _setResponsible(String entity, {String? name, String? userId}) {
    final normalizedId = userId?.trim();
    final isClear = normalizedId == null || normalizedId.isEmpty;
    final mirrorConverted = _mode == ClientMode.converted;
    final updateLead = entity == 'leads' || mirrorConverted;
    final updateStudent = entity == 'students' || mirrorConverted;

    _emitState(() {
      if (updateLead) {
        _leadResponsibleChanged = true;
        if (isClear) {
          _leadData.remove('assigned_to');
          _leadData.remove('assigned_name');
          final customData =
              Map<String, dynamic>.from(_leadData['custom_data'] as Map? ?? {})
                ..removeWhere(
                  (key, _) => const {
                    'responsible',
                    'responsibleUserId',
                    'responsibleName',
                  }.contains(key),
                );
          _leadData['custom_data'] = customData;
        } else {
          _leadData['assigned_to'] = normalizedId;
          _leadData['assigned_name'] = name;
        }
      }

      if (updateStudent) {
        _studentResponsibleChanged = true;
        final student = _student;
        if (student != null) {
          final customData = Map<String, dynamic>.from(
            student['custom_data'] as Map? ?? {},
          );
          if (isClear) {
            customData.remove('responsible');
            customData.remove('responsibleUserId');
            customData.remove('responsibleName');
          } else {
            customData['responsible'] = name;
            customData['responsibleUserId'] = normalizedId;
            customData.remove('responsibleName');
          }
          student['custom_data'] = customData;
        }
      }
      _edited = true;
      if (updateLead) _draft.leadResponsibleEdit = _draft.revision;
      if (updateStudent) _draft.studentResponsibleEdit = _draft.revision;
    });
  }

  Future<void> _pickResponsible(String entity) async {
    final crm = ref.read(magicCrmServiceProvider);

    Future<List<SearchableSelectItem>> search(String query) async {
      final rows = await crm.listResponsibleStaff(search: query);
      return rows.map((row) {
        return SearchableSelectItem(
          id: row['id'].toString(),
          label: row['name']?.toString() ?? 'Без имени',
          subtitle: _staffRoleLabel(row['role']),
        );
      }).toList();
    }

    SearchableSelect.show(
      context: context,
      title: 'Ответственный',
      hintText: 'Имя сотрудника…',
      items: const [],
      isNullable: true,
      onSearch: search,
      onSelected: (item) {
        if (item == null) {
          _setResponsible(entity, name: null, userId: null);
          return;
        }
        _setResponsible(entity, name: item.label, userId: item.id);
      },
    );
  }

  String? _staffRoleLabel(Object? role) {
    return switch (role?.toString()) {
      'admin' => 'Администратор',
      'manager' => 'Управляющий',
      'director' => 'Директор',
      'system_admin' => 'Администратор системы',
      final v when v != null && v.isNotEmpty => v,
      _ => null,
    };
  }

  Widget _buildResponsiblePicker(ColorScheme cs, String entity) {
    final value = _responsibleDisplayValue(entity);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: () => _pickResponsible(entity),
        child: InputDecorator(
          decoration: _inputDecoration(
            cs,
            label: 'Ответственный',
            isDense: true,
            suffixIcon: value == null
                ? const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: AppColor.gold,
                  )
                : IconButton(
                    tooltip: 'Очистить',
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () =>
                        _setResponsible(entity, name: null, userId: null),
                  ),
          ),
          child: Text(
            value ?? 'Не выбран',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: value == null ? TextStyle(color: cs.onSurfaceVariant) : null,
          ),
        ),
      ),
    );
  }
}
